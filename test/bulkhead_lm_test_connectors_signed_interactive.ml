open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let viber_connector_handles_text_webhook_test _switch () =
  let captured_request = ref None in
  let outbound_messages = ref [] in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"Viber reply"
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
                  "embeddings not used in viber connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.viber_connector
      ~auth_token_env:"VIBER_AUTH_TOKEN"
      ~authorization_env:"BULKHEAD_VIBER_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_sender_ids:[ "viber-user-123" ]
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
           ; line = None
           ; viber = Some connector
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
      [ "event", `String "message"
      ; "timestamp", `Int 1457764197
      ; "message_token", `Intlit "4912661846655238145"
      ; ( "sender"
        , `Assoc
            [ "id", `String "viber-user-123"
            ; "name", `String "Alice"
            ; "avatar", `String "https://example.test/alice.png"
            ; "country", `String "UK"
            ; "language", `String "en"
            ; "api_version", `Int 1
            ] )
      ; "message", `Assoc [ "type", `String "text"; "text", `String "Explain the repo" ]
      ]
  in
  let payload_text = Yojson.Safe.to_string payload_json in
  let signature =
    Digestif.SHA256.(to_hex (hmac_string ~key:"viber-token-123" payload_text))
  in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      ~headers:(Cohttp.Header.of_list [ "x-viber-content-signature", signature ])
      (Uri.of_string "http://localhost/connectors/viber/webhook")
  in
  let body = Cohttp_lwt.Body.of_string payload_text in
  with_env_overrides
    [ "VIBER_AUTH_TOKEN", "viber-token-123"; "BULKHEAD_VIBER_AUTH", "sk-test" ]
    (fun () ->
      let http_post uri ~headers:_ payload =
        outbound_messages := (Uri.to_string uri, payload) :: !outbound_messages;
        Lwt.return
          ( Cohttp.Response.make ~status:`OK ()
          , Yojson.Safe.to_string
              (`Assoc
                [ "status", `Int 0
                ; "status_message", `String "ok"
                ; "message_token", `Int 123
                ]) )
      in
      Bulkhead_lm.Viber_connector.handle_webhook ~http_post store request body connector
      >>= fun (response, response_body) ->
      Alcotest.(check int) "viber webhook accepted" 200 (response_status_code response);
      response_body_json response_body
      >>= fun response_json ->
      Alcotest.(check bool)
        "viber webhook acknowledges success"
        true
        (match List.assoc_opt "ok" (json_assoc response_json) with
         | Some (`Bool value) -> value
         | _ -> false);
      (match !captured_request with
       | None -> Alcotest.fail "expected routed viber chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "viber connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "viber user text becomes pending user prompt"
              "Explain the repo"
              last.content
          | [] -> Alcotest.fail "expected viber routed request messages"));
      (match List.rev !outbound_messages with
       | (uri, `Assoc fields) :: _ ->
         Alcotest.(check string)
           "viber uses send_message endpoint"
           "https://chatapi.viber.com/pa/send_message"
           uri;
         Alcotest.(check (option string))
           "viber recipient id"
           (Some "viber-user-123")
           (match List.assoc_opt "receiver" fields with
            | Some (`String value) -> Some value
            | _ -> None);
         Alcotest.(check (option string))
           "viber outbound text"
           (Some "Viber reply")
           (match List.assoc_opt "text" fields with
            | Some (`String value) -> Some value
            | _ -> None)
       | _ :: _ -> Alcotest.fail "expected viber outbound payload object"
       | [] -> Alcotest.fail "expected viber outbound request");
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"viber:viber-user-123"
      in
      Alcotest.(check int)
        "viber connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let wechat_connector_handles_encrypted_verification_test _switch () =
  let encoding_aes_key = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG" in
  let app_id = "wechat-app-id-example" in
  let connector =
    Bulkhead_lm.Config_test_support.wechat_connector
      ~signature_token_env:"WECHAT_SIGNATURE_TOKEN"
      ~encoding_aes_key_env:"WECHAT_ENCODING_AES_KEY"
      ~app_id_env:"WECHAT_APP_ID"
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
  let timestamp = "1714112445" in
  let nonce = "415670741" in
  let echostr =
    match
      Bulkhead_lm.Wechat_connector_crypto.encrypt_payload
        ~random_prefix:"1234567890abcdef"
        ~credentials:
          { Bulkhead_lm.Wechat_connector_crypto.token = "wechat-token-123"
          ; encoding_aes_key
          ; app_id
          }
        ~plaintext:"verified-echo"
        ()
    with
    | Ok value -> value
    | Error err -> Alcotest.failf "expected encrypted echostr: %s" err.message
  in
  let msg_signature =
    wechat_ciphertext_signature
      ~token:"wechat-token-123"
      ~timestamp
      ~nonce
      ~encrypted:echostr
  in
  let request_uri =
    Uri.with_query'
      (Uri.of_string "http://localhost/connectors/wechat/webhook")
      [ "timestamp", timestamp
      ; "nonce", nonce
      ; "echostr", echostr
      ; "encrypt_type", "aes"
      ; "msg_signature", msg_signature
      ]
  in
  let request = Cohttp.Request.make ~meth:`GET request_uri in
  with_env_overrides
    [ "WECHAT_SIGNATURE_TOKEN", "wechat-token-123"
    ; "WECHAT_ENCODING_AES_KEY", encoding_aes_key
    ; "WECHAT_APP_ID", app_id
    ]
    (fun () ->
      Bulkhead_lm.Wechat_connector.handle_webhook
        store
        request
        Cohttp_lwt.Body.empty
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int)
        "wechat encrypted verification accepted"
        200
        (response_status_code response);
      response_body_text response_body
      >|= fun body_text ->
      Alcotest.(check string)
        "wechat encrypted echostr decrypted"
        "verified-echo"
        body_text)
;;

let discord_connector_handles_command_webhook_test _switch () =
  let captured_request = ref None in
  let background_jobs = ref [] in
  let original_response_updates = ref [] in
  let followup_messages = ref [] in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"Discord reply"
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
                  "embeddings not used in discord connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.discord_connector
      ~public_key_env:"DISCORD_PUBLIC_KEY"
      ~authorization_env:"BULKHEAD_DISCORD_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_application_ids:[ "app-123" ]
      ~allowed_user_ids:[ "user-123" ]
      ~allowed_channel_ids:[ "channel-123" ]
      ~allowed_guild_ids:[ "guild-123" ]
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
           ; line = None
           ; viber = None
           ; wechat = None
           ; discord = Some connector
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
  let http_patch uri ~headers:_ payload =
    original_response_updates
    := (Uri.to_string uri, payload) :: !original_response_updates;
    Lwt.return (Cohttp.Response.make ~status:`OK (), {|{"id":"message-123"}|})
  in
  let http_post uri ~headers:_ payload =
    followup_messages := (Uri.to_string uri, payload) :: !followup_messages;
    Lwt.return (Cohttp.Response.make ~status:`OK (), {|{"id":"message-124"}|})
  in
  let payload_text =
    {|{"type":2,"id":"interaction-123","application_id":"app-123","token":"interaction-token-123","channel_id":"channel-123","guild_id":"guild-123","member":{"user":{"id":"user-123","username":"Ava","global_name":"Ava Lane"}},"data":{"id":"command-123","name":"bulkhead","type":1,"options":[{"type":3,"name":"message","value":"Summarize the repo"}]}}|}
  in
  let timestamp = "1712832000" in
  let public_key_hex, signature_hex = signed_discord_request ~timestamp ~payload_text in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      ~headers:
        (Cohttp.Header.of_list
           [ "x-signature-ed25519", signature_hex; "x-signature-timestamp", timestamp ])
      (Uri.of_string "http://localhost/connectors/discord/webhook")
  in
  with_env_overrides
    [ "DISCORD_PUBLIC_KEY", public_key_hex; "BULKHEAD_DISCORD_AUTH", "sk-test" ]
    (fun () ->
      Bulkhead_lm.Discord_connector.handle_webhook
        ~http_post
        ~http_patch
        ~async_runner:(fun job -> background_jobs := job () :: !background_jobs)
        store
        request
        (Cohttp_lwt.Body.of_string payload_text)
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int) "discord webhook accepted" 200 (response_status_code response);
      response_body_json response_body
      >>= fun response_json ->
      Alcotest.(check (option int))
        "discord command deferred"
        (Some 5)
        (match List.assoc_opt "type" (json_assoc response_json) with
         | Some (`Int value) -> Some value
         | _ -> None);
      Alcotest.(check (option int))
        "discord deferred response uses ephemeral flag"
        (Some 64)
        (match List.assoc_opt "data" (json_assoc response_json) with
         | Some (`Assoc data_fields) ->
           (match List.assoc_opt "flags" data_fields with
            | Some (`Int value) -> Some value
            | _ -> None)
         | _ -> None);
      run_background_jobs background_jobs
      >>= fun () ->
      (match !captured_request with
       | None -> Alcotest.fail "expected routed discord chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "discord connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "discord user text becomes pending user prompt"
              "Summarize the repo"
              last.content
          | [] -> Alcotest.fail "expected discord routed request messages"));
      (match List.rev !original_response_updates with
       | (uri, `Assoc fields) :: _ ->
         Alcotest.(check string)
           "discord edits original response"
           "https://discord.com/api/v10/webhooks/app-123/interaction-token-123/messages/@original"
           uri;
         Alcotest.(check (option string))
           "discord original response text"
           (Some "Discord reply")
           (match List.assoc_opt "content" fields with
            | Some (`String value) -> Some value
            | _ -> None)
       | _ :: _ -> Alcotest.fail "expected discord original response payload object"
       | [] -> Alcotest.fail "expected discord original response update");
      Alcotest.(check int)
        "discord does not need followups for short response"
        0
        (List.length !followup_messages);
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"discord:app-123:guild-123:channel-123:user-123"
      in
      Alcotest.(check int)
        "discord connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let tests =
  [
    Alcotest_lwt.test_case "viber connector handles text webhook" `Quick viber_connector_handles_text_webhook_test
  ; Alcotest_lwt.test_case "wechat connector handles encrypted verification" `Quick wechat_connector_handles_encrypted_verification_test
  ; Alcotest_lwt.test_case "discord connector handles command webhook" `Quick discord_connector_handles_command_webhook_test
  ]
;;

let suite = "09.connectors/signed-interactive", tests
