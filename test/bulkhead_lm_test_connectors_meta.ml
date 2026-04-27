open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let whatsapp_connector_handles_text_webhook_test _switch () =
  let captured_request = ref None in
  let outbound_messages = ref [] in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"WhatsApp reply"
            ()))
  in
  let provider =
    { Bulkhead_lm.Provider_client.invoke_chat
    ; invoke_chat_stream =
        (fun headers backend request ->
          invoke_chat headers backend request
          >|= Result.map Bulkhead_lm.Provider_stream.of_chat_response)
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "embeddings not used in whatsapp connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.whatsapp_connector
      ~verify_token_env:"WHATSAPP_VERIFY_TOKEN"
      ~app_secret_env:"WHATSAPP_APP_SECRET"
      ~access_token_env:"WHATSAPP_ACCESS_TOKEN"
      ~authorization_env:"BULKHEAD_WHATSAPP_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_sender_numbers:[ "15550001111" ]
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      ~provider_factory:(fun _ -> provider)
      (Bulkhead_lm.Config_test_support.sample_config
         ~user_connectors:
           { Bulkhead_lm.Config.telegram = []
           ; whatsapp = Some connector
           ; messenger = None
           ; instagram = None
           ; line = None
           ; viber = None
           ; wechat = None
           ; discord = None
           ; google_chat = None
           }
         ~routes:
           [ Bulkhead_lm.Config_test_support.route
               ~public_model:"gpt-4o-mini"
               ~backends:
                 [ Bulkhead_lm.Config_test_support.backend
                     ~provider_id:"primary"
                     ~provider_kind:Bulkhead_lm.Config.Openai_compat
                     ~api_base:"https://api.example.test/v1"
                     ~upstream_model:"gpt-4o-mini"
                     ~api_key_env:"OPENAI_API_KEY"
                     ()
                 ]
               ()
           ]
         ())
  in
  let payload_json =
    `Assoc
      [ "object", `String "whatsapp_business_account"
      ; ( "entry"
        , `List
            [ `Assoc
                [ "id", `String "waba-1"
                ; ( "changes"
                  , `List
                      [ `Assoc
                          [ "field", `String "messages"
                          ; ( "value"
                            , `Assoc
                                [ ( "metadata"
                                  , `Assoc
                                      [ "phone_number_id", `String "phone-number-123" ] )
                                ; ( "contacts"
                                  , `List
                                      [ `Assoc
                                          [ "wa_id", `String "15550001111"
                                          ; "profile", `Assoc [ "name", `String "Alice" ]
                                          ]
                                      ] )
                                ; ( "messages"
                                  , `List
                                      [ `Assoc
                                          [ "from", `String "15550001111"
                                          ; "id", `String "wamid.123"
                                          ; "type", `String "text"
                                          ; ( "text"
                                            , `Assoc
                                                [ "body", `String "Summarize the repo" ] )
                                          ]
                                      ] )
                                ] )
                          ]
                      ] )
                ]
            ] )
      ]
  in
  let payload_text = Yojson.Safe.to_string payload_json in
  let signature =
    "sha256=" ^ Digestif.SHA256.(to_hex (hmac_string ~key:"app-secret-123" payload_text))
  in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      ~headers:(Cohttp.Header.of_list [ "x-hub-signature-256", signature ])
      (Uri.of_string "http://localhost/connectors/whatsapp/webhook")
  in
  let body = Cohttp_lwt.Body.of_string payload_text in
  with_env_overrides
    [ "WHATSAPP_VERIFY_TOKEN", "verify-123"
    ; "WHATSAPP_APP_SECRET", "app-secret-123"
    ; "WHATSAPP_ACCESS_TOKEN", "access-token"
    ; "BULKHEAD_WHATSAPP_AUTH", "sk-test"
    ]
    (fun () ->
      let http_post uri ~headers:_ payload =
        outbound_messages := (Uri.to_string uri, payload) :: !outbound_messages;
        Lwt.return (Cohttp.Response.make ~status:`OK (), Yojson.Safe.to_string (`Assoc []))
      in
      Bulkhead_lm.Whatsapp_connector.handle_webhook
        ~http_post
        store
        request
        body
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int) "whatsapp webhook accepted" 200 (response_status_code response);
      response_body_json response_body
      >>= fun response_json ->
      Alcotest.(check bool)
        "whatsapp webhook acknowledges success"
        true
        (match List.assoc_opt "ok" (json_assoc response_json) with
         | Some (`Bool value) -> value
         | _ -> false);
      (match !captured_request with
       | None -> Alcotest.fail "expected routed whatsapp chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "whatsapp connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "whatsapp user text becomes pending user prompt"
              "Summarize the repo"
              last.content
          | [] -> Alcotest.fail "expected whatsapp routed request messages"));
      (match List.rev !outbound_messages with
       | (_, `Assoc fields) :: _ ->
         Alcotest.(check (option string))
           "whatsapp recipient number"
           (Some "15550001111")
           (match List.assoc_opt "to" fields with
            | Some (`String value) -> Some value
            | _ -> None)
       | _ :: _ -> Alcotest.fail "expected whatsapp outbound payload object"
       | [] -> Alcotest.fail "expected whatsapp outbound request");
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"whatsapp:15550001111"
      in
      Alcotest.(check int)
        "whatsapp connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let messenger_connector_handles_text_webhook_test _switch () =
  let captured_request = ref None in
  let outbound_messages = ref [] in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"Messenger reply"
            ()))
  in
  let provider =
    { Bulkhead_lm.Provider_client.invoke_chat
    ; invoke_chat_stream =
        (fun headers backend request ->
          invoke_chat headers backend request
          >|= Result.map Bulkhead_lm.Provider_stream.of_chat_response)
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "embeddings not used in messenger connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.messenger_connector
      ~verify_token_env:"MESSENGER_VERIFY_TOKEN"
      ~app_secret_env:"MESSENGER_APP_SECRET"
      ~access_token_env:"MESSENGER_ACCESS_TOKEN"
      ~authorization_env:"BULKHEAD_MESSENGER_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_page_ids:[ "page-123" ]
      ~allowed_sender_ids:[ "user-456" ]
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      ~provider_factory:(fun _ -> provider)
      (Bulkhead_lm.Config_test_support.sample_config
         ~user_connectors:
           { Bulkhead_lm.Config.telegram = []
           ; whatsapp = None
           ; messenger = Some connector
           ; instagram = None
           ; line = None
           ; viber = None
           ; wechat = None
           ; discord = None
           ; google_chat = None
           }
         ~routes:
           [ Bulkhead_lm.Config_test_support.route
               ~public_model:"gpt-4o-mini"
               ~backends:
                 [ Bulkhead_lm.Config_test_support.backend
                     ~provider_id:"primary"
                     ~provider_kind:Bulkhead_lm.Config.Openai_compat
                     ~api_base:"https://api.example.test/v1"
                     ~upstream_model:"gpt-4o-mini"
                     ~api_key_env:"OPENAI_API_KEY"
                     ()
                 ]
               ()
           ]
         ())
  in
  let payload_json =
    `Assoc
      [ "object", `String "page"
      ; ( "entry"
        , `List
            [ `Assoc
                [ "id", `String "page-123"
                ; ( "messaging"
                  , `List
                      [ `Assoc
                          [ "sender", `Assoc [ "id", `String "user-456" ]
                          ; "recipient", `Assoc [ "id", `String "page-123" ]
                          ; "timestamp", `Int 1712832000
                          ; ( "message"
                            , `Assoc
                                [ "mid", `String "mid.1"
                                ; "text", `String "Summarize the repo"
                                ] )
                          ]
                      ] )
                ]
            ] )
      ]
  in
  let payload_text = Yojson.Safe.to_string payload_json in
  let signature =
    "sha256=" ^ Digestif.SHA256.(to_hex (hmac_string ~key:"app-secret-123" payload_text))
  in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      ~headers:(Cohttp.Header.of_list [ "x-hub-signature-256", signature ])
      (Uri.of_string "http://localhost/connectors/messenger/webhook")
  in
  let body = Cohttp_lwt.Body.of_string payload_text in
  with_env_overrides
    [ "MESSENGER_VERIFY_TOKEN", "verify-123"
    ; "MESSENGER_APP_SECRET", "app-secret-123"
    ; "MESSENGER_ACCESS_TOKEN", "access-token"
    ; "BULKHEAD_MESSENGER_AUTH", "sk-test"
    ]
    (fun () ->
      let http_post uri ~headers:_ payload =
        outbound_messages := (Uri.to_string uri, payload) :: !outbound_messages;
        Lwt.return (Cohttp.Response.make ~status:`OK (), Yojson.Safe.to_string (`Assoc []))
      in
      Bulkhead_lm.Messenger_connector.handle_webhook
        ~http_post
        store
        request
        body
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int)
        "messenger webhook accepted"
        200
        (response_status_code response);
      response_body_json response_body
      >>= fun response_json ->
      Alcotest.(check bool)
        "messenger webhook acknowledges success"
        true
        (match List.assoc_opt "ok" (json_assoc response_json) with
         | Some (`Bool value) -> value
         | _ -> false);
      (match !captured_request with
       | None -> Alcotest.fail "expected routed messenger chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "messenger connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "messenger user text becomes pending user prompt"
              "Summarize the repo"
              last.content
          | [] -> Alcotest.fail "expected messenger routed request messages"));
      (match List.rev !outbound_messages with
       | (uri, `Assoc fields) :: _ ->
         Alcotest.(check string)
           "messenger uses page send endpoint"
           "https://graph.facebook.com/v23.0/page-123/messages"
           uri;
         Alcotest.(check (option string))
           "messenger recipient id"
           (Some "user-456")
           (match List.assoc_opt "recipient" fields with
            | Some (`Assoc recipient_fields) ->
              (match List.assoc_opt "id" recipient_fields with
               | Some (`String value) -> Some value
               | _ -> None)
            | _ -> None);
         Alcotest.(check (option string))
           "messenger messaging type"
           (Some "RESPONSE")
           (match List.assoc_opt "messaging_type" fields with
            | Some (`String value) -> Some value
            | _ -> None)
       | _ :: _ -> Alcotest.fail "expected messenger outbound payload object"
       | [] -> Alcotest.fail "expected messenger outbound request");
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"messenger:page-123:user-456"
      in
      Alcotest.(check int)
        "messenger connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let config_load_parses_instagram_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-instagram-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "instagram"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "instagram/webhook"
                  ; "verify_token_env", `String "INSTAGRAM_VERIFY_TOKEN"
                  ; "app_secret_env", `String "INSTAGRAM_APP_SECRET"
                  ; "access_token_env", `String "INSTAGRAM_ACCESS_TOKEN"
                  ; "authorization_env", `String "BULKHEAD_INSTAGRAM_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Be concise."
                  ; "allowed_account_ids", `List [ `String "17841400000000000" ]
                  ; "allowed_sender_ids", `List [ `String "igsid-456" ]
                  ; "api_base", `String "https://graph.instagram.com/v23.0/"
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err ->
     Alcotest.failf "expected instagram connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.instagram with
      | None -> Alcotest.fail "expected instagram connector config"
      | Some connector ->
        Alcotest.(check string)
          "instagram webhook path normalized"
          "/instagram/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "instagram verify token env parsed"
          "INSTAGRAM_VERIFY_TOKEN"
          connector.verify_token_env;
        Alcotest.(check (list string))
          "instagram allowed account ids parsed"
          [ "17841400000000000" ]
          connector.allowed_account_ids;
        Alcotest.(check (list string))
          "instagram allowed sender ids parsed"
          [ "igsid-456" ]
          connector.allowed_sender_ids;
        Alcotest.(check string)
          "instagram api base normalized"
          "https://graph.instagram.com/v23.0"
          connector.api_base));
  Lwt.return_unit
;;

let tests =
  [
    Alcotest_lwt.test_case "whatsapp connector handles text webhook" `Quick whatsapp_connector_handles_text_webhook_test
  ; Alcotest_lwt.test_case "messenger connector handles text webhook" `Quick messenger_connector_handles_text_webhook_test
  ; Alcotest_lwt.test_case "config parses instagram user connector" `Quick config_load_parses_instagram_connector_test
  ]
;;

let suite = "06.connectors/meta", tests
