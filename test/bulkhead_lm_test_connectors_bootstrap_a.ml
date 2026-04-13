open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let config_load_parses_telegram_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-telegram-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "telegram"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "telegram/webhook"
                  ; "bot_token_env", `String "TELEGRAM_BOT_TOKEN"
                  ; "secret_token_env", `String "TELEGRAM_WEBHOOK_SECRET"
                  ; "authorization_env", `String "BULKHEAD_TELEGRAM_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Speak plainly."
                  ; "allowed_chat_ids", `List [ `Int 42; `String "-100123456" ]
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err -> Alcotest.failf "expected telegram connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.telegram with
      | None -> Alcotest.fail "expected telegram connector config"
      | Some connector ->
        Alcotest.(check string)
          "telegram webhook path normalized"
          "/telegram/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "telegram token env parsed"
          "TELEGRAM_BOT_TOKEN"
          connector.bot_token_env;
        Alcotest.(check (option string))
          "telegram secret env parsed"
          (Some "TELEGRAM_WEBHOOK_SECRET")
          connector.secret_token_env;
        Alcotest.(check string)
          "telegram authorization env parsed"
          "BULKHEAD_TELEGRAM_AUTH"
          connector.authorization_env;
        Alcotest.(check string)
          "telegram route model parsed"
          "gpt-5-mini"
          connector.route_model;
        Alcotest.(check (option string))
          "telegram system prompt parsed"
          (Some "Speak plainly.")
          connector.system_prompt;
        Alcotest.(check (list string))
          "telegram allowed chat ids parsed"
          [ "42"; "-100123456" ]
          connector.allowed_chat_ids));
  Lwt.return_unit
;;

let telegram_connector_handles_text_webhook_test _switch () =
  let captured_request = ref None in
  let outbound_messages = ref [] in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"Telegram reply"
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
                  "embeddings not used in telegram connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.telegram_connector
      ~bot_token_env:"TELEGRAM_BOT_TOKEN"
      ~authorization_env:"BULKHEAD_TELEGRAM_AUTH"
      ~route_model:"gpt-4o-mini"
      ~system_prompt:"Reply in a practical tone."
      ~allowed_chat_ids:[ "42" ]
      ~secret_token_env:"TELEGRAM_WEBHOOK_SECRET"
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      ~provider_factory:(fun _ -> provider)
      (Bulkhead_lm.Config_test_support.sample_config
         ~user_connectors:
           { Bulkhead_lm.Config.telegram = Some connector
           ; whatsapp = None
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
  let request =
    Cohttp.Request.make
      ~meth:`POST
      ~headers:(Cohttp.Header.of_list [ "x-telegram-bot-api-secret-token", "secret-123" ])
      (Uri.of_string "http://localhost/connectors/telegram/webhook")
  in
  let body =
    Cohttp_lwt.Body.of_string
      (Yojson.Safe.to_string
         (`Assoc
           [ "update_id", `Int 777
           ; ( "message"
             , `Assoc
                 [ "message_id", `Int 9
                 ; ( "from"
                   , `Assoc
                       [ "id", `Int 5
                       ; "first_name", `String "Alice"
                       ; "username", `String "alice"
                       ] )
                 ; "text", `String "Summarize the repo"
                 ; "message_thread_id", `Int 17
                 ; "chat", `Assoc [ "id", `Int 42; "type", `String "private" ]
                 ] )
           ]))
  in
  with_env_overrides
    [ "TELEGRAM_BOT_TOKEN", "bot-token"
    ; "BULKHEAD_TELEGRAM_AUTH", "sk-test"
    ; "TELEGRAM_WEBHOOK_SECRET", "secret-123"
    ]
    (fun () ->
      let http_post uri ~headers:_ payload =
        outbound_messages := (Uri.to_string uri, payload) :: !outbound_messages;
        Lwt.return
          ( Cohttp.Response.make ~status:`OK ()
          , Yojson.Safe.to_string (`Assoc [ "ok", `Bool true; "result", `Assoc [] ]) )
      in
      Bulkhead_lm.Telegram_connector.handle_webhook
        ~http_post
        store
        request
        body
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int) "telegram webhook accepted" 200 (response_status_code response);
      response_body_json response_body
      >>= fun response_json ->
      let response_fields = json_assoc response_json in
      Alcotest.(check bool)
        "telegram webhook acknowledges success"
        true
        (match List.assoc_opt "ok" response_fields with
         | Some (`Bool value) -> value
         | _ -> false);
      (match !captured_request with
       | None -> Alcotest.fail "expected routed chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "telegram connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "telegram user text becomes pending user prompt"
              "Summarize the repo"
              last.content
          | [] -> Alcotest.fail "expected routed request messages"));
      (match List.rev !outbound_messages with
       | (_, `Assoc fields) :: _ ->
         Alcotest.(check (option string))
           "telegram sendMessage chat id"
           (Some "42")
           (match List.assoc_opt "chat_id" fields with
            | Some (`String value) -> Some value
            | _ -> None);
         Alcotest.(check (option string))
           "telegram sendMessage text"
           (Some "Telegram reply")
           (match List.assoc_opt "text" fields with
            | Some (`String value) -> Some value
            | _ -> None)
       | _ :: _ -> Alcotest.fail "expected telegram sendMessage payload object"
       | [] -> Alcotest.fail "expected telegram sendMessage request");
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"telegram:42"
      in
      Alcotest.(check int)
        "telegram connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let config_load_parses_whatsapp_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-whatsapp-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "whatsapp"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "whatsapp/webhook"
                  ; "verify_token_env", `String "WHATSAPP_VERIFY_TOKEN"
                  ; "app_secret_env", `String "WHATSAPP_APP_SECRET"
                  ; "access_token_env", `String "WHATSAPP_ACCESS_TOKEN"
                  ; "authorization_env", `String "BULKHEAD_WHATSAPP_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Keep it short."
                  ; "allowed_sender_numbers", `List [ `String "15550001111" ]
                  ; "api_base", `String "https://graph.facebook.com/v23.0/"
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err -> Alcotest.failf "expected whatsapp connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.whatsapp with
      | None -> Alcotest.fail "expected whatsapp connector config"
      | Some connector ->
        Alcotest.(check string)
          "whatsapp webhook path normalized"
          "/whatsapp/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "whatsapp verify token env parsed"
          "WHATSAPP_VERIFY_TOKEN"
          connector.verify_token_env;
        Alcotest.(check (option string))
          "whatsapp app secret env parsed"
          (Some "WHATSAPP_APP_SECRET")
          connector.app_secret_env;
        Alcotest.(check string)
          "whatsapp api base normalized"
          "https://graph.facebook.com/v23.0"
          connector.api_base));
  Lwt.return_unit
;;

let config_load_parses_messenger_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-messenger-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "messenger"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "messenger/webhook"
                  ; "verify_token_env", `String "MESSENGER_VERIFY_TOKEN"
                  ; "app_secret_env", `String "MESSENGER_APP_SECRET"
                  ; "access_token_env", `String "MESSENGER_ACCESS_TOKEN"
                  ; "authorization_env", `String "BULKHEAD_MESSENGER_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Be concise."
                  ; "allowed_page_ids", `List [ `String "page-123" ]
                  ; "allowed_sender_ids", `List [ `String "user-456" ]
                  ; "api_base", `String "https://graph.facebook.com/v23.0/"
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err ->
     Alcotest.failf "expected messenger connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.messenger with
      | None -> Alcotest.fail "expected messenger connector config"
      | Some connector ->
        Alcotest.(check string)
          "messenger webhook path normalized"
          "/messenger/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "messenger verify token env parsed"
          "MESSENGER_VERIFY_TOKEN"
          connector.verify_token_env;
        Alcotest.(check (option string))
          "messenger app secret env parsed"
          (Some "MESSENGER_APP_SECRET")
          connector.app_secret_env;
        Alcotest.(check (list string))
          "messenger allowed page ids parsed"
          [ "page-123" ]
          connector.allowed_page_ids;
        Alcotest.(check (list string))
          "messenger allowed sender ids parsed"
          [ "user-456" ]
          connector.allowed_sender_ids;
        Alcotest.(check string)
          "messenger api base normalized"
          "https://graph.facebook.com/v23.0"
          connector.api_base));
  Lwt.return_unit
;;

let whatsapp_connector_handles_verification_test _switch () =
  let connector =
    Bulkhead_lm.Config_test_support.whatsapp_connector
      ~verify_token_env:"WHATSAPP_VERIFY_TOKEN"
      ~access_token_env:"WHATSAPP_ACCESS_TOKEN"
      ~authorization_env:"BULKHEAD_WHATSAPP_AUTH"
      ~route_model:"gpt-4o-mini"
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      (Bulkhead_lm.Config_test_support.sample_config
         ~user_connectors:
           { Bulkhead_lm.Config.telegram = None
           ; whatsapp = Some connector
           ; messenger = None
           ; instagram = None
           ; line = None
           ; viber = None
           ; wechat = None
           ; discord = None
           ; google_chat = None
           }
         ())
  in
  let request =
    Cohttp.Request.make
      ~meth:`GET
      (Uri.of_string
         "http://localhost/connectors/whatsapp/webhook?hub.mode=subscribe&hub.verify_token=verify-123&hub.challenge=abc123")
  in
  with_env_overrides
    [ "WHATSAPP_VERIFY_TOKEN", "verify-123" ]
    (fun () ->
      Bulkhead_lm.Whatsapp_connector.handle_webhook
        store
        request
        Cohttp_lwt.Body.empty
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int)
        "whatsapp verification accepted"
        200
        (response_status_code response);
      response_body_text response_body
      >|= fun body_text ->
      Alcotest.(check string) "whatsapp challenge echoed" "abc123" body_text)
;;

let user_connector_registry_is_hierarchical_test _switch () =
  let described =
    Bulkhead_lm.User_connector_registry.descriptors
    |> List.map (fun (descriptor : Bulkhead_lm.User_connector_registry.descriptor) ->
      Fmt.str
        "%d:%s:%s"
        descriptor.wave
        descriptor.connector_id
        (Bulkhead_lm.User_connector_registry.runtime_class_label descriptor.runtime_class))
  in
  Alcotest.(check (list string))
    "connector registry order and runtime classes stay explicit"
    [ "1:telegram:webhook-outbound-api-reply"
    ; "1:whatsapp:webhook-outbound-api-reply"
    ; "1:messenger:webhook-outbound-api-reply"
    ; "1:instagram:webhook-outbound-api-reply"
    ; "2:line:webhook-outbound-api-reply"
    ; "2:viber:webhook-outbound-api-reply"
    ; "2:wechat:webhook-inline-reply"
    ; "3:discord:deferred-interaction"
    ; "1:google_chat:webhook-inline-reply"
    ]
    described;
  Lwt.return_unit
;;

let tests =
  [
    Alcotest_lwt.test_case "config parses telegram user connector" `Quick config_load_parses_telegram_connector_test
  ; Alcotest_lwt.test_case "telegram connector handles text webhook" `Quick telegram_connector_handles_text_webhook_test
  ; Alcotest_lwt.test_case "config parses whatsapp user connector" `Quick config_load_parses_whatsapp_connector_test
  ; Alcotest_lwt.test_case "config parses messenger user connector" `Quick config_load_parses_messenger_connector_test
  ; Alcotest_lwt.test_case "whatsapp connector handles verification" `Quick whatsapp_connector_handles_verification_test
  ; Alcotest_lwt.test_case "user connector registry stays hierarchical" `Quick user_connector_registry_is_hierarchical_test
  ]
;;

let suite = "04.connectors/bootstrap-a", tests
