open Lwt.Infix
open Bulkhead_lm_test_foundation_security
let config_load_parses_line_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-line-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "line"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "line/webhook"
                  ; "channel_secret_env", `String "LINE_CHANNEL_SECRET"
                  ; "access_token_env", `String "LINE_ACCESS_TOKEN"
                  ; "authorization_env", `String "BULKHEAD_LINE_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Reply plainly."
                  ; "allowed_user_ids", `List [ `String "user-123" ]
                  ; "allowed_group_ids", `List [ `String "group-456" ]
                  ; "allowed_room_ids", `List [ `String "room-789" ]
                  ; "api_base", `String "https://api.line.me/v2/bot/"
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err -> Alcotest.failf "expected line connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.line with
      | None -> Alcotest.fail "expected line connector config"
      | Some connector ->
        Alcotest.(check string)
          "line webhook path normalized"
          "/line/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "line channel secret env parsed"
          "LINE_CHANNEL_SECRET"
          connector.channel_secret_env;
        Alcotest.(check (list string))
          "line allowed user ids parsed"
          [ "user-123" ]
          connector.allowed_user_ids;
        Alcotest.(check (list string))
          "line allowed group ids parsed"
          [ "group-456" ]
          connector.allowed_group_ids;
        Alcotest.(check (list string))
          "line allowed room ids parsed"
          [ "room-789" ]
          connector.allowed_room_ids;
        Alcotest.(check string)
          "line api base normalized"
          "https://api.line.me/v2/bot"
          connector.api_base));
  Lwt.return_unit
;;

let config_load_parses_viber_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-viber-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "viber"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "viber/webhook"
                  ; "auth_token_env", `String "VIBER_AUTH_TOKEN"
                  ; "authorization_env", `String "BULKHEAD_VIBER_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Reply plainly."
                  ; "allowed_sender_ids", `List [ `String "viber-user-123" ]
                  ; "sender_name", `String "BulkheadLM"
                  ; "sender_avatar", `String "https://example.test/avatar.png"
                  ; "api_base", `String "https://chatapi.viber.com/pa/"
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err -> Alcotest.failf "expected viber connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.viber with
      | None -> Alcotest.fail "expected viber connector config"
      | Some connector ->
        Alcotest.(check string)
          "viber webhook path normalized"
          "/viber/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "viber auth token env parsed"
          "VIBER_AUTH_TOKEN"
          connector.auth_token_env;
        Alcotest.(check (list string))
          "viber allowed sender ids parsed"
          [ "viber-user-123" ]
          connector.allowed_sender_ids;
        Alcotest.(check (option string))
          "viber sender name parsed"
          (Some "BulkheadLM")
          connector.sender_name;
        Alcotest.(check string)
          "viber api base normalized"
          "https://chatapi.viber.com/pa"
          connector.api_base));
  Lwt.return_unit
;;

let config_load_parses_wechat_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-wechat-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "wechat"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "wechat/webhook"
                  ; "signature_token_env", `String "WECHAT_SIGNATURE_TOKEN"
                  ; "encoding_aes_key_env", `String "WECHAT_ENCODING_AES_KEY"
                  ; "app_id_env", `String "WECHAT_APP_ID"
                  ; "authorization_env", `String "BULKHEAD_WECHAT_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Reply plainly."
                  ; "allowed_open_ids", `List [ `String "openid-123" ]
                  ; "allowed_account_ids", `List [ `String "gh_abc123" ]
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err -> Alcotest.failf "expected wechat connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.wechat with
      | None -> Alcotest.fail "expected wechat connector config"
      | Some connector ->
        Alcotest.(check string)
          "wechat webhook path normalized"
          "/wechat/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "wechat signature token env parsed"
          "WECHAT_SIGNATURE_TOKEN"
          connector.signature_token_env;
        Alcotest.(check (option string))
          "wechat encoding aes key env parsed"
          (Some "WECHAT_ENCODING_AES_KEY")
          connector.encoding_aes_key_env;
        Alcotest.(check (option string))
          "wechat app id env parsed"
          (Some "WECHAT_APP_ID")
          connector.app_id_env;
        Alcotest.(check (list string))
          "wechat allowed open ids parsed"
          [ "openid-123" ]
          connector.allowed_open_ids;
        Alcotest.(check (list string))
          "wechat allowed account ids parsed"
          [ "gh_abc123" ]
          connector.allowed_account_ids));
  Lwt.return_unit
;;

let config_load_parses_discord_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-discord-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "discord"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "discord/webhook"
                  ; "public_key_env", `String "DISCORD_PUBLIC_KEY"
                  ; "authorization_env", `String "BULKHEAD_DISCORD_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Reply plainly."
                  ; "allowed_application_ids", `List [ `String "app-123" ]
                  ; "allowed_user_ids", `List [ `String "user-123" ]
                  ; "allowed_channel_ids", `List [ `String "channel-123" ]
                  ; "allowed_guild_ids", `List [ `String "guild-123" ]
                  ; "ephemeral_by_default", `Bool false
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err -> Alcotest.failf "expected discord connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.discord with
      | None -> Alcotest.fail "expected discord connector config"
      | Some connector ->
        Alcotest.(check string)
          "discord webhook path normalized"
          "/discord/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "discord public key env parsed"
          "DISCORD_PUBLIC_KEY"
          connector.public_key_env;
        Alcotest.(check (list string))
          "discord allowed application ids parsed"
          [ "app-123" ]
          connector.allowed_application_ids;
        Alcotest.(check bool)
          "discord ephemeral default parsed"
          false
          connector.ephemeral_by_default));
  Lwt.return_unit
;;

let config_load_parses_google_chat_connector_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-google-chat-connector" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "google_chat"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "google-chat/webhook"
                  ; "authorization_env", `String "BULKHEAD_GOOGLE_CHAT_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ; "system_prompt", `String "Reply plainly."
                  ; "allowed_space_names", `List [ `String "spaces/AAA" ]
                  ; "allowed_user_names", `List [ `String "users/999" ]
                  ; ( "id_token_auth"
                    , `Assoc
                        [ ( "audience"
                          , `String "https://example.test/connectors/google-chat/webhook"
                          )
                        ; "certs_url", `String "https://example.test/certs"
                        ] )
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err ->
     Alcotest.failf "expected google chat connector config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.user_connectors.google_chat with
      | None -> Alcotest.fail "expected google chat connector config"
      | Some connector ->
        Alcotest.(check string)
          "google chat webhook path normalized"
          "/google-chat/webhook"
          connector.webhook_path;
        Alcotest.(check string)
          "google chat route model parsed"
          "gpt-5-mini"
          connector.route_model;
        Alcotest.(check (option string))
          "google chat auth audience parsed"
          (Some "https://example.test/connectors/google-chat/webhook")
          (match connector.id_token_auth with
           | Some auth -> Some auth.audience
           | None -> None)));
  Lwt.return_unit
;;

let config_load_rejects_duplicate_user_connector_webhook_paths_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-duplicate-webhook-paths" ".json" in
  let config_json =
    `Assoc
      [ ( "user_connectors"
        , `Assoc
            [ ( "telegram"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "/shared/webhook"
                  ; "bot_token_env", `String "TELEGRAM_BOT_TOKEN"
                  ; "authorization_env", `String "BULKHEAD_TELEGRAM_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ] )
            ; ( "google_chat"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "/shared/webhook"
                  ; "authorization_env", `String "BULKHEAD_GOOGLE_CHAT_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Ok _ -> Alcotest.fail "expected duplicate webhook paths to be rejected"
   | Error err ->
     Alcotest.(check bool)
       "duplicate path error is explicit"
       true
       (string_contains
          err
          "Duplicate user connector webhook_path values are not allowed");
     Alcotest.(check bool)
       "duplicate path is named"
       true
       (string_contains err "/shared/webhook");
     Alcotest.(check bool)
       "telegram is named in duplicate path error"
       true
       (string_contains err "telegram");
     Alcotest.(check bool)
       "google chat is named in duplicate path error"
       true
       (string_contains err "google_chat"));
  Lwt.return_unit
;;

let config_load_rejects_control_plane_path_collisions_test _switch () =
  let config_path = Filename.temp_file "bulkhead-lm-control-plane-collision" ".json" in
  let security_policy_path =
    Filename.temp_file "bulkhead-lm-control-plane-security" ".json"
  in
  Yojson.Safe.to_file
    security_policy_path
    (`Assoc
      [ ( "control_plane"
        , `Assoc
            [ "enabled", `Bool true
            ; "path_prefix", `String "/connectors"
            ; "ui_enabled", `Bool true
            ; "allow_reload", `Bool true
            ; "admin_token_env", `String "BULKHEAD_ADMIN_TOKEN"
            ] )
      ]);
  Yojson.Safe.to_file
    config_path
    (`Assoc
      [ "security_policy_file", `String security_policy_path
      ; ( "user_connectors"
        , `Assoc
            [ ( "telegram"
              , `Assoc
                  [ "enabled", `Bool true
                  ; "webhook_path", `String "/connectors/telegram/webhook"
                  ; "bot_token_env", `String "TELEGRAM_BOT_TOKEN"
                  ; "authorization_env", `String "BULKHEAD_TELEGRAM_AUTH"
                  ; "route_model", `String "gpt-5-mini"
                  ] )
            ] )
      ; "routes", `List []
      ; "virtual_keys", `List []
      ]);
  (match Bulkhead_lm.Config.load config_path with
   | Ok _ -> Alcotest.fail "expected control-plane path collision to be rejected"
   | Error err ->
     Alcotest.(check bool)
       "control-plane collision error is explicit"
       true
       (string_contains err "security_policy.control_plane.path_prefix");
     Alcotest.(check bool)
       "colliding webhook path is reported"
       true
       (string_contains err "/connectors/telegram/webhook"));
  Lwt.return_unit
;;

let messenger_connector_handles_verification_test _switch () =
  let connector =
    Bulkhead_lm.Config_test_support.messenger_connector
      ~verify_token_env:"MESSENGER_VERIFY_TOKEN"
      ~access_token_env:"MESSENGER_ACCESS_TOKEN"
      ~authorization_env:"BULKHEAD_MESSENGER_AUTH"
      ~route_model:"gpt-4o-mini"
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
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
         ())
  in
  let request =
    Cohttp.Request.make
      ~meth:`GET
      (Uri.of_string
         "http://localhost/connectors/messenger/webhook?hub.mode=subscribe&hub.verify_token=verify-123&hub.challenge=abc123")
  in
  with_env_overrides
    [ "MESSENGER_VERIFY_TOKEN", "verify-123" ]
    (fun () ->
      Bulkhead_lm.Messenger_connector.handle_webhook
        store
        request
        Cohttp_lwt.Body.empty
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int)
        "messenger verification accepted"
        200
        (response_status_code response);
      response_body_text response_body
      >|= fun body_text ->
      Alcotest.(check string) "messenger challenge echoed" "abc123" body_text)
;;

let tests =
  [
    Alcotest_lwt.test_case "config parses line user connector" `Quick config_load_parses_line_connector_test
  ; Alcotest_lwt.test_case "config parses viber user connector" `Quick config_load_parses_viber_connector_test
  ; Alcotest_lwt.test_case "config parses wechat user connector" `Quick config_load_parses_wechat_connector_test
  ; Alcotest_lwt.test_case "config parses discord user connector" `Quick config_load_parses_discord_connector_test
  ; Alcotest_lwt.test_case "config parses google chat user connector" `Quick config_load_parses_google_chat_connector_test
  ; Alcotest_lwt.test_case "config rejects duplicate user connector webhook paths" `Quick config_load_rejects_duplicate_user_connector_webhook_paths_test
  ; Alcotest_lwt.test_case "config rejects control-plane path collisions" `Quick config_load_rejects_control_plane_path_collisions_test
  ; Alcotest_lwt.test_case "messenger connector handles verification" `Quick messenger_connector_handles_verification_test
  ]
;;

let suite = "05.connectors/bootstrap-b", tests
