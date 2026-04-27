open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let instagram_connector_handles_text_webhook_test _switch () =
  let captured_request = ref None in
  let outbound_messages = ref [] in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"Instagram reply"
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
                  "embeddings not used in instagram connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.instagram_connector
      ~verify_token_env:"INSTAGRAM_VERIFY_TOKEN"
      ~app_secret_env:"INSTAGRAM_APP_SECRET"
      ~access_token_env:"INSTAGRAM_ACCESS_TOKEN"
      ~authorization_env:"BULKHEAD_INSTAGRAM_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_account_ids:[ "17841400000000000" ]
      ~allowed_sender_ids:[ "igsid-456" ]
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      ~provider_factory:(fun _ -> provider)
      (Bulkhead_lm.Config_test_support.sample_config
         ~user_connectors:
           { Bulkhead_lm.Config.telegram = []
           ; whatsapp = None
           ; messenger = None
           ; instagram = Some connector
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
      [ "object", `String "instagram"
      ; ( "entry"
        , `List
            [ `Assoc
                [ "id", `String "17841400000000000"
                ; ( "messaging"
                  , `List
                      [ `Assoc
                          [ "sender", `Assoc [ "id", `String "igsid-456" ]
                          ; "recipient", `Assoc [ "id", `String "17841400000000000" ]
                          ; "timestamp", `Int 1712832000
                          ; ( "message"
                            , `Assoc
                                [ "mid", `String "mid.2"
                                ; "text", `String "Explain the repo"
                                ] )
                          ]
                      ] )
                ]
            ] )
      ]
  in
  let payload_text = Yojson.Safe.to_string payload_json in
  let signature =
    "sha256=" ^ Digestif.SHA256.(to_hex (hmac_string ~key:"app-secret-ig" payload_text))
  in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      ~headers:(Cohttp.Header.of_list [ "x-hub-signature-256", signature ])
      (Uri.of_string "http://localhost/connectors/instagram/webhook")
  in
  let body = Cohttp_lwt.Body.of_string payload_text in
  with_env_overrides
    [ "INSTAGRAM_VERIFY_TOKEN", "verify-123"
    ; "INSTAGRAM_APP_SECRET", "app-secret-ig"
    ; "INSTAGRAM_ACCESS_TOKEN", "access-token"
    ; "BULKHEAD_INSTAGRAM_AUTH", "sk-test"
    ]
    (fun () ->
      let http_post uri ~headers:_ payload =
        outbound_messages := (Uri.to_string uri, payload) :: !outbound_messages;
        Lwt.return (Cohttp.Response.make ~status:`OK (), Yojson.Safe.to_string (`Assoc []))
      in
      Bulkhead_lm.Instagram_connector.handle_webhook
        ~http_post
        store
        request
        body
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int)
        "instagram webhook accepted"
        200
        (response_status_code response);
      response_body_json response_body
      >>= fun response_json ->
      Alcotest.(check bool)
        "instagram webhook acknowledges success"
        true
        (match List.assoc_opt "ok" (json_assoc response_json) with
         | Some (`Bool value) -> value
         | _ -> false);
      (match !captured_request with
       | None -> Alcotest.fail "expected routed instagram chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "instagram connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "instagram user text becomes pending user prompt"
              "Explain the repo"
              last.content
          | [] -> Alcotest.fail "expected instagram routed request messages"));
      (match List.rev !outbound_messages with
       | (uri, `Assoc fields) :: _ ->
         Alcotest.(check string)
           "instagram uses me/messages endpoint"
           "https://graph.instagram.com/v23.0/me/messages"
           uri;
         Alcotest.(check (option string))
           "instagram recipient id"
           (Some "igsid-456")
           (match List.assoc_opt "recipient" fields with
            | Some (`Assoc recipient_fields) ->
              (match List.assoc_opt "id" recipient_fields with
               | Some (`String value) -> Some value
               | _ -> None)
            | _ -> None);
         Alcotest.(check bool)
           "instagram does not force messenger messaging_type"
           true
           (not (List.mem_assoc "messaging_type" fields))
       | _ :: _ -> Alcotest.fail "expected instagram outbound payload object"
       | [] -> Alcotest.fail "expected instagram outbound request");
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"instagram:17841400000000000:igsid-456"
      in
      Alcotest.(check int)
        "instagram connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let line_connector_handles_text_webhook_test _switch () =
  let captured_request = ref None in
  let outbound_messages = ref [] in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"LINE reply"
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
                  "embeddings not used in line connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.line_connector
      ~channel_secret_env:"LINE_CHANNEL_SECRET"
      ~access_token_env:"LINE_ACCESS_TOKEN"
      ~authorization_env:"BULKHEAD_LINE_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_user_ids:[ "user-123" ]
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      ~provider_factory:(fun _ -> provider)
      (Bulkhead_lm.Config_test_support.sample_config
         ~user_connectors:
           { Bulkhead_lm.Config.telegram = []
           ; whatsapp = None
           ; messenger = None
           ; instagram = None
           ; line = Some connector
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
      [ ( "events"
        , `List
            [ `Assoc
                [ "type", `String "message"
                ; "replyToken", `String "reply-123"
                ; ( "source"
                  , `Assoc [ "type", `String "user"; "userId", `String "user-123" ] )
                ; ( "message"
                  , `Assoc
                      [ "id", `String "msg-123"
                      ; "type", `String "text"
                      ; "text", `String "Summarize the repo"
                      ] )
                ]
            ] )
      ]
  in
  let payload_text = Yojson.Safe.to_string payload_json in
  let signature =
    Digestif.SHA256.(to_raw_string (hmac_string ~key:"line-secret-123" payload_text))
    |> Base64.encode_exn
  in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      ~headers:(Cohttp.Header.of_list [ "x-line-signature", signature ])
      (Uri.of_string "http://localhost/connectors/line/webhook")
  in
  let body = Cohttp_lwt.Body.of_string payload_text in
  with_env_overrides
    [ "LINE_CHANNEL_SECRET", "line-secret-123"
    ; "LINE_ACCESS_TOKEN", "line-access-token"
    ; "BULKHEAD_LINE_AUTH", "sk-test"
    ]
    (fun () ->
      let http_post uri ~headers:_ payload =
        outbound_messages := (Uri.to_string uri, payload) :: !outbound_messages;
        Lwt.return (Cohttp.Response.make ~status:`OK (), Yojson.Safe.to_string (`Assoc []))
      in
      Bulkhead_lm.Line_connector.handle_webhook ~http_post store request body connector
      >>= fun (response, response_body) ->
      Alcotest.(check int) "line webhook accepted" 200 (response_status_code response);
      response_body_json response_body
      >>= fun response_json ->
      Alcotest.(check bool)
        "line webhook acknowledges success"
        true
        (match List.assoc_opt "ok" (json_assoc response_json) with
         | Some (`Bool value) -> value
         | _ -> false);
      (match !captured_request with
       | None -> Alcotest.fail "expected routed line chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "line connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "line user text becomes pending user prompt"
              "Summarize the repo"
              last.content
          | [] -> Alcotest.fail "expected line routed request messages"));
      (match List.rev !outbound_messages with
       | (uri, `Assoc fields) :: _ ->
         Alcotest.(check string)
           "line uses reply endpoint"
           "https://api.line.me/v2/bot/message/reply"
           uri;
         Alcotest.(check (option string))
           "line reply token"
           (Some "reply-123")
           (match List.assoc_opt "replyToken" fields with
            | Some (`String value) -> Some value
            | _ -> None);
         Alcotest.(check (option string))
           "line outbound text"
           (Some "LINE reply")
           (match List.assoc_opt "messages" fields with
            | Some
                (`List [ `Assoc [ ("type", `String "text"); ("text", `String value) ] ])
              -> Some value
            | Some (`List [ `Assoc message_fields ]) ->
              (match List.assoc_opt "text" message_fields with
               | Some (`String value) -> Some value
               | _ -> None)
            | _ -> None)
       | _ :: _ -> Alcotest.fail "expected line outbound payload object"
       | [] -> Alcotest.fail "expected line outbound request");
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"line:user:user-123"
      in
      Alcotest.(check int)
        "line connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let wechat_connector_handles_verification_test _switch () =
  let connector =
    Bulkhead_lm.Config_test_support.wechat_connector
      ~signature_token_env:"WECHAT_SIGNATURE_TOKEN"
      ~authorization_env:"BULKHEAD_WECHAT_AUTH"
      ~route_model:"gpt-4o-mini"
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      (Bulkhead_lm.Config_test_support.sample_config
         ~user_connectors:
           { Bulkhead_lm.Config.telegram = []
           ; whatsapp = None
           ; messenger = None
           ; instagram = None
           ; line = None
           ; viber = None
           ; wechat = Some connector
           ; discord = None
           ; google_chat = None
           }
         ())
  in
  let timestamp = "1712832000" in
  let nonce = "nonce-123" in
  let signature = wechat_signature ~token:"wechat-token-123" ~timestamp ~nonce in
  let request =
    Cohttp.Request.make
      ~meth:`GET
      (Uri.of_string
         (Fmt.str
            "http://localhost/connectors/wechat/webhook?signature=%s&timestamp=%s&nonce=%s&echostr=%s"
            signature
            timestamp
            nonce
            "echo-123"))
  in
  with_env_overrides
    [ "WECHAT_SIGNATURE_TOKEN", "wechat-token-123" ]
    (fun () ->
      Bulkhead_lm.Wechat_connector.handle_webhook
        store
        request
        Cohttp_lwt.Body.empty
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int)
        "wechat verification accepted"
        200
        (response_status_code response);
      response_body_text response_body
      >|= fun body_text ->
      Alcotest.(check string) "wechat echostr echoed" "echo-123" body_text)
;;

let tests =
  [
    Alcotest_lwt.test_case "instagram connector handles text webhook" `Quick instagram_connector_handles_text_webhook_test
  ; Alcotest_lwt.test_case "line connector handles text webhook" `Quick line_connector_handles_text_webhook_test
  ; Alcotest_lwt.test_case "wechat connector handles verification" `Quick wechat_connector_handles_verification_test
  ]
;;

let suite = "07.connectors/social-text", tests
