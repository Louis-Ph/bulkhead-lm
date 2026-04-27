(** Tests for multi-bot Telegram personas with shared room memory.

    These tests verify three invariants:

    1. The config parser accepts both legacy single-bot objects and the new
       multi-bot array shape.
    2. With [room_memory_mode = Shared_room], every persona on the same
       chat_id reads and writes the SAME conversation thread.
    3. Assistant turns committed to a shared room are tagged with the
       persona name so other personas can tell who said what. *)

module Config = Bulkhead_lm.Config
module Config_test_support = Bulkhead_lm.Config_test_support

let yojson_to_temp_file ~suffix payload =
  let path = Filename.temp_file "bulkhead-lm-multi-persona" suffix in
  Yojson.Safe.to_file path payload;
  path
;;

(* --- Config parsing accepts both shapes ---------------------------------- *)

let config_accepts_legacy_single_bot_shape_test _switch () =
  let config_path =
    yojson_to_temp_file
      ~suffix:".json"
      (`Assoc
        [ ( "user_connectors"
          , `Assoc
              [ ( "telegram"
                , `Assoc
                    [ "enabled", `Bool true
                    ; "webhook_path", `String "/connectors/telegram/webhook"
                    ; "bot_token_env", `String "TG_TOKEN"
                    ; "authorization_env", `String "BULKHEAD_AUTH"
                    ; "route_model", `String "gpt-4o-mini"
                    ] )
              ] )
        ; "routes", `List []
        ; "virtual_keys", `List []
        ])
  in
  match Bulkhead_lm.Config.load config_path with
  | Error err -> Alcotest.failf "expected legacy single-bot config to load: %s" err
  | Ok config ->
    let entries = config.user_connectors.telegram in
    Alcotest.(check int) "legacy shape produces a one-element list" 1 (List.length entries);
    (match entries with
     | [ entry ] ->
       Alcotest.(check string)
         "default persona name when not specified"
         "default"
         entry.persona_name;
       Alcotest.(check bool)
         "shared room memory by default"
         true
         (entry.room_memory_mode = Config.Shared_room)
     | _ -> Alcotest.fail "expected exactly one entry");
    Lwt.return_unit
;;

let config_accepts_multi_bot_array_shape_test _switch () =
  let config_path =
    yojson_to_temp_file
      ~suffix:".json"
      (`Assoc
        [ ( "user_connectors"
          , `Assoc
              [ ( "telegram"
                , `List
                    [ `Assoc
                        [ "persona_name", `String "marie"
                        ; "webhook_path", `String "/connectors/telegram/marie"
                        ; "bot_token_env", `String "TG_TOKEN_MARIE"
                        ; "authorization_env", `String "BULKHEAD_AUTH"
                        ; "route_model", `String "claude-opus"
                        ; "room_memory_mode", `String "shared"
                        ]
                    ; `Assoc
                        [ "persona_name", `String "paul"
                        ; "webhook_path", `String "/connectors/telegram/paul"
                        ; "bot_token_env", `String "TG_TOKEN_PAUL"
                        ; "authorization_env", `String "BULKHEAD_AUTH"
                        ; "route_model", `String "pool-cheap"
                        ; "room_memory_mode", `String "isolated"
                        ]
                    ] )
              ] )
        ; "routes", `List []
        ; "virtual_keys", `List []
        ])
  in
  match Bulkhead_lm.Config.load config_path with
  | Error err -> Alcotest.failf "expected multi-bot config to load: %s" err
  | Ok config ->
    let entries = config.user_connectors.telegram in
    Alcotest.(check int) "two personas loaded" 2 (List.length entries);
    (match entries with
     | [ marie; paul ] ->
       Alcotest.(check string) "marie persona" "marie" marie.persona_name;
       Alcotest.(check string) "marie route" "claude-opus" marie.route_model;
       Alcotest.(check bool)
         "marie shared room"
         true
         (marie.room_memory_mode = Config.Shared_room);
       Alcotest.(check string) "paul persona" "paul" paul.persona_name;
       Alcotest.(check bool)
         "paul isolated"
         true
         (paul.room_memory_mode = Config.Isolated_per_persona)
     | _ -> Alcotest.fail "expected exactly two entries");
    Lwt.return_unit
;;

(* --- Shared room session key ---------------------------------------------- *)

let shared_room_session_key_is_persona_independent_test _switch () =
  let marie =
    Config_test_support.telegram_connector
      ~persona_name:"marie"
      ~webhook_path:"/connectors/telegram/marie"
      ~bot_token_env:"TG_MARIE"
      ~authorization_env:"AUTH"
      ~route_model:"claude-opus"
      ~room_memory_mode:Config.Shared_room
      ()
  in
  let paul =
    Config_test_support.telegram_connector
      ~persona_name:"paul"
      ~webhook_path:"/connectors/telegram/paul"
      ~bot_token_env:"TG_PAUL"
      ~authorization_env:"AUTH"
      ~route_model:"pool-cheap"
      ~room_memory_mode:Config.Shared_room
      ()
  in
  let message =
    { Bulkhead_lm.Telegram_connector.update_id = None
    ; chat_id = "42"
    ; chat_type = Some "group"
    ; message_thread_id = None
    ; text = Some "hello"
    ; user_display_name = Some "Alice"
    }
  in
  let marie_key = Bulkhead_lm.Telegram_connector.session_key_for_message marie message in
  let paul_key = Bulkhead_lm.Telegram_connector.session_key_for_message paul message in
  Alcotest.(check string)
    "marie's shared-room key uses room: prefix"
    "telegram:room:42"
    marie_key;
  Alcotest.(check string)
    "paul's shared-room key matches marie's"
    marie_key
    paul_key;
  Lwt.return_unit
;;

let isolated_persona_session_key_is_distinct_test _switch () =
  let marie =
    Config_test_support.telegram_connector
      ~persona_name:"marie"
      ~webhook_path:"/connectors/telegram/marie"
      ~bot_token_env:"TG_MARIE"
      ~authorization_env:"AUTH"
      ~route_model:"claude-opus"
      ~room_memory_mode:Config.Isolated_per_persona
      ()
  in
  let paul =
    Config_test_support.telegram_connector
      ~persona_name:"paul"
      ~webhook_path:"/connectors/telegram/paul"
      ~bot_token_env:"TG_PAUL"
      ~authorization_env:"AUTH"
      ~route_model:"pool-cheap"
      ~room_memory_mode:Config.Isolated_per_persona
      ()
  in
  let message =
    { Bulkhead_lm.Telegram_connector.update_id = None
    ; chat_id = "42"
    ; chat_type = Some "group"
    ; message_thread_id = None
    ; text = Some "hello"
    ; user_display_name = Some "Alice"
    }
  in
  let marie_key = Bulkhead_lm.Telegram_connector.session_key_for_message marie message in
  let paul_key = Bulkhead_lm.Telegram_connector.session_key_for_message paul message in
  Alcotest.(check bool) "isolated keys differ" true (marie_key <> paul_key);
  Alcotest.(check bool)
    "marie's isolated key carries the persona name"
    true
    (String.equal marie_key "telegram:42:marie");
  Lwt.return_unit
;;

(* --- Assistant turns are tagged with the persona name -------------------- *)

let shared_room_tags_assistant_turn_with_persona_test _switch () =
  let marie =
    Config_test_support.telegram_connector
      ~persona_name:"marie"
      ~bot_token_env:"TG_MARIE"
      ~authorization_env:"AUTH"
      ~route_model:"claude-opus"
      ~room_memory_mode:Config.Shared_room
      ()
  in
  let tagged =
    Bulkhead_lm.Telegram_connector.tag_assistant_turn_for_persona
      marie
      "We should ship Tuesday."
  in
  Alcotest.(check string)
    "shared room prefixes the persona name"
    "[marie] We should ship Tuesday."
    tagged;
  Lwt.return_unit
;;

let isolated_persona_does_not_tag_test _switch () =
  let paul =
    Config_test_support.telegram_connector
      ~persona_name:"paul"
      ~bot_token_env:"TG_PAUL"
      ~authorization_env:"AUTH"
      ~route_model:"pool-cheap"
      ~room_memory_mode:Config.Isolated_per_persona
      ()
  in
  let tagged =
    Bulkhead_lm.Telegram_connector.tag_assistant_turn_for_persona
      paul
      "Sounds good."
  in
  Alcotest.(check string)
    "isolated room keeps the assistant turn untagged"
    "Sounds good."
    tagged;
  Lwt.return_unit
;;

let tests =
  [ Alcotest_lwt.test_case
      "config accepts the legacy single-bot object shape"
      `Quick
      config_accepts_legacy_single_bot_shape_test
  ; Alcotest_lwt.test_case
      "config accepts the multi-bot array shape"
      `Quick
      config_accepts_multi_bot_array_shape_test
  ; Alcotest_lwt.test_case
      "shared room memory uses a persona-independent session key"
      `Quick
      shared_room_session_key_is_persona_independent_test
  ; Alcotest_lwt.test_case
      "isolated persona memory uses a distinct session key"
      `Quick
      isolated_persona_session_key_is_distinct_test
  ; Alcotest_lwt.test_case
      "shared room tags assistant turns with the persona name"
      `Quick
      shared_room_tags_assistant_turn_with_persona_test
  ; Alcotest_lwt.test_case
      "isolated persona does not tag assistant turns"
      `Quick
      isolated_persona_does_not_tag_test
  ]
;;

let suite = "18.connectors/multi-persona", tests
