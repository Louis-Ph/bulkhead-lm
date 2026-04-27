open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let wechat_connector_handles_text_webhook_test _switch () =
  let captured_request = ref None in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"WeChat reply"
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
                  "embeddings not used in wechat connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.wechat_connector
      ~signature_token_env:"WECHAT_SIGNATURE_TOKEN"
      ~authorization_env:"BULKHEAD_WECHAT_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_open_ids:[ "openid-123" ]
      ~allowed_account_ids:[ "gh_abc123" ]
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
           ; wechat = Some connector
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
  let timestamp = "1712832000" in
  let nonce = "nonce-123" in
  let payload_text =
    String.concat
      ""
      [ "<xml>"
      ; "<ToUserName><![CDATA[gh_abc123]]></ToUserName>"
      ; "<FromUserName><![CDATA[openid-123]]></FromUserName>"
      ; "<CreateTime>1712832000</CreateTime>"
      ; "<MsgType><![CDATA[text]]></MsgType>"
      ; "<Content><![CDATA[Summarize the repo]]></Content>"
      ; "<MsgId>1234567890123456</MsgId>"
      ; "</xml>"
      ]
  in
  let signature = wechat_signature ~token:"wechat-token-123" ~timestamp ~nonce in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      (Uri.of_string
         (Fmt.str
            "http://localhost/connectors/wechat/webhook?signature=%s&timestamp=%s&nonce=%s"
            signature
            timestamp
            nonce))
  in
  let body = Cohttp_lwt.Body.of_string payload_text in
  with_env_overrides
    [ "WECHAT_SIGNATURE_TOKEN", "wechat-token-123"; "BULKHEAD_WECHAT_AUTH", "sk-test" ]
    (fun () ->
      Bulkhead_lm.Wechat_connector.handle_webhook store request body connector
      >>= fun (response, response_body) ->
      Alcotest.(check int) "wechat webhook accepted" 200 (response_status_code response);
      response_body_text response_body
      >>= fun body_text ->
      Alcotest.(check bool)
        "wechat returns xml reply"
        true
        (string_contains body_text "<xml>");
      Alcotest.(check bool)
        "wechat reply contains assistant text"
        true
        (string_contains body_text "<Content><![CDATA[WeChat reply]]></Content>");
      (match !captured_request with
       | None -> Alcotest.fail "expected routed wechat chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "wechat connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "wechat user text becomes pending user prompt"
              "Summarize the repo"
              last.content
          | [] -> Alcotest.fail "expected wechat routed request messages"));
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"wechat:gh_abc123:openid-123"
      in
      Alcotest.(check int)
        "wechat connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let wechat_connector_handles_encrypted_text_webhook_test _switch () =
  let encoding_aes_key = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG" in
  let app_id = "wechat-app-id-example" in
  let captured_request = ref None in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"WeChat secure reply"
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
                  "embeddings not used in wechat connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.wechat_connector
      ~signature_token_env:"WECHAT_SIGNATURE_TOKEN"
      ~encoding_aes_key_env:"WECHAT_ENCODING_AES_KEY"
      ~app_id_env:"WECHAT_APP_ID"
      ~authorization_env:"BULKHEAD_WECHAT_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_open_ids:[ "openid-123" ]
      ~allowed_account_ids:[ "gh_abc123" ]
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
           ; wechat = Some connector
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
  let timestamp = "1714112445" in
  let nonce = "415670741" in
  let plaintext_xml =
    String.concat
      ""
      [ "<xml>"
      ; "<ToUserName><![CDATA[gh_abc123]]></ToUserName>"
      ; "<FromUserName><![CDATA[openid-123]]></FromUserName>"
      ; "<CreateTime>1714112445</CreateTime>"
      ; "<MsgType><![CDATA[text]]></MsgType>"
      ; "<Content><![CDATA[Summarize the secure repo]]></Content>"
      ; "<MsgId>1234567890123456</MsgId>"
      ; "</xml>"
      ]
  in
  let encrypted_request =
    match
      Bulkhead_lm.Wechat_connector_crypto.encrypt_payload
        ~random_prefix:"1234567890abcdef"
        ~credentials:
          { Bulkhead_lm.Wechat_connector_crypto.token = "wechat-token-123"
          ; encoding_aes_key
          ; app_id
          }
        ~plaintext:plaintext_xml
        ()
    with
    | Ok value -> value
    | Error err -> Alcotest.failf "expected encrypted request body: %s" err.message
  in
  let msg_signature =
    wechat_ciphertext_signature
      ~token:"wechat-token-123"
      ~timestamp
      ~nonce
      ~encrypted:encrypted_request
  in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      (Uri.of_string
         (Fmt.str
            "http://localhost/connectors/wechat/webhook?timestamp=%s&nonce=%s&encrypt_type=aes&msg_signature=%s"
            timestamp
            nonce
            msg_signature))
  in
  let body =
    Cohttp_lwt.Body.of_string
      (String.concat
         ""
         [ "<xml>"
         ; "<ToUserName><![CDATA[gh_abc123]]></ToUserName>"
         ; "<Encrypt><![CDATA["
         ; encrypted_request
         ; "]]></Encrypt>"
         ; "</xml>"
         ])
  in
  with_env_overrides
    [ "WECHAT_SIGNATURE_TOKEN", "wechat-token-123"
    ; "WECHAT_ENCODING_AES_KEY", encoding_aes_key
    ; "WECHAT_APP_ID", app_id
    ; "BULKHEAD_WECHAT_AUTH", "sk-test"
    ]
    (fun () ->
      Bulkhead_lm.Wechat_connector.handle_webhook store request body connector
      >>= fun (response, response_body) ->
      Alcotest.(check int)
        "wechat encrypted webhook accepted"
        200
        (response_status_code response);
      response_body_text response_body
      >>= fun body_text ->
      let encrypted_response =
        match Bulkhead_lm.Wechat_connector_xml.find_tag body_text "Encrypt" with
        | Some value -> value
        | None -> Alcotest.fail "expected encrypted wechat response body"
      in
      let response_timestamp =
        match Bulkhead_lm.Wechat_connector_xml.find_tag body_text "TimeStamp" with
        | Some value -> value
        | None -> Alcotest.fail "expected encrypted wechat response timestamp"
      in
      let response_nonce =
        match Bulkhead_lm.Wechat_connector_xml.find_tag body_text "Nonce" with
        | Some value -> value
        | None -> Alcotest.fail "expected encrypted wechat response nonce"
      in
      let response_signature =
        match Bulkhead_lm.Wechat_connector_xml.find_tag body_text "MsgSignature" with
        | Some value -> value
        | None -> Alcotest.fail "expected encrypted wechat response signature"
      in
      Alcotest.(check string)
        "wechat encrypted response signature matches"
        (wechat_ciphertext_signature
           ~token:"wechat-token-123"
           ~timestamp:response_timestamp
           ~nonce:response_nonce
           ~encrypted:encrypted_response)
        response_signature;
      let decrypted_response =
        match
          Bulkhead_lm.Wechat_connector_crypto.decrypt_payload
            ~credentials:
              { Bulkhead_lm.Wechat_connector_crypto.token = "wechat-token-123"
              ; encoding_aes_key
              ; app_id
              }
            ~encrypted:encrypted_response
        with
        | Ok value -> value
        | Error err ->
          Alcotest.failf "expected encrypted response decryption: %s" err.message
      in
      Alcotest.(check bool)
        "wechat encrypted reply contains assistant text"
        true
        (string_contains
           decrypted_response
           "<Content><![CDATA[WeChat secure reply]]></Content>");
      (match !captured_request with
       | None -> Alcotest.fail "expected routed encrypted wechat chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "wechat encrypted connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "wechat encrypted user text becomes pending user prompt"
              "Summarize the secure repo"
              last.content
          | [] -> Alcotest.fail "expected encrypted wechat routed request messages"));
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"wechat:gh_abc123:openid-123"
      in
      Alcotest.(check int)
        "wechat encrypted connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let discord_connector_handles_ping_test _switch () =
  let connector =
    Bulkhead_lm.Config_test_support.discord_connector
      ~public_key_env:"DISCORD_PUBLIC_KEY"
      ~authorization_env:"BULKHEAD_DISCORD_AUTH"
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
           ; wechat = None
           ; discord = Some connector
           ; google_chat = None
           }
         ())
  in
  let payload_text = {|{"type":1}|} in
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
    [ "DISCORD_PUBLIC_KEY", public_key_hex ]
    (fun () ->
      Bulkhead_lm.Discord_connector.handle_webhook
        store
        request
        (Cohttp_lwt.Body.of_string payload_text)
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int) "discord ping accepted" 200 (response_status_code response);
      response_body_json response_body
      >|= fun response_json ->
      Alcotest.(check (option int))
        "discord ping returns pong"
        (Some 1)
        (match List.assoc_opt "type" (json_assoc response_json) with
         | Some (`Int value) -> Some value
         | _ -> None))
;;

let tests =
  [
    Alcotest_lwt.test_case "wechat connector handles text webhook" `Quick wechat_connector_handles_text_webhook_test
  ; Alcotest_lwt.test_case "wechat connector handles encrypted text webhook" `Quick wechat_connector_handles_encrypted_text_webhook_test
  ; Alcotest_lwt.test_case "discord connector handles ping" `Quick discord_connector_handles_ping_test
  ]
;;

let suite = "08.connectors/wechat-runtime", tests
