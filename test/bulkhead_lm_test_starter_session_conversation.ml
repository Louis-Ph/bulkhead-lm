open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let starter_profile_splits_ready_and_missing_routes_test _switch () =
  let config =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"claude-sonnet"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"anthropic-primary"
                  ~provider_kind:Bulkhead_lm.Config.Anthropic
                  ~api_base:"https://api.anthropic.com/v1"
                  ~upstream_model:"claude-sonnet-4-5-20250929"
                  ~api_key_env:"ANTHROPIC_API_KEY"
                  ()
              ]
            ()
        ; Bulkhead_lm.Config_test_support.route
            ~public_model:"gpt-5-mini"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"openai-primary"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.openai.com/v1"
                  ~upstream_model:"gpt-5-mini"
                  ~api_key_env:"OPENAI_API_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let ready, missing =
    Bulkhead_lm.Starter_profile.route_statuses
      ~lookup:(function
        | "ANTHROPIC_API_KEY" -> Some "present"
        | _ -> None)
      config
    |> Bulkhead_lm.Starter_profile.split_route_statuses
  in
  Alcotest.(check int) "one ready route" 1 (List.length ready);
  Alcotest.(check int) "one missing route" 1 (List.length missing);
  Lwt.return_unit
;;

let starter_session_parses_beginner_commands_test _switch () =
  (match Bulkhead_lm.Starter_session.parse_command "/tools" with
   | Bulkhead_lm.Starter_session.Show_tools -> ()
   | _ -> Alcotest.fail "expected /tools command");
  (match Bulkhead_lm.Starter_session.parse_command "/control" with
   | Bulkhead_lm.Starter_session.Show_control_plane -> ()
   | _ -> Alcotest.fail "expected /control command");
  (match
     Bulkhead_lm.Starter_session.parse_command
       "/admin enable local file access in this repo"
   with
   | Bulkhead_lm.Starter_session.Admin_request goal ->
     Alcotest.(check string) "admin goal" "enable local file access in this repo" goal
   | _ -> Alcotest.fail "expected /admin command");
  (match Bulkhead_lm.Starter_session.parse_command "/admin" with
   | Bulkhead_lm.Starter_session.Invalid _ -> ()
   | _ -> Alcotest.fail "expected invalid /admin without argument");
  (match Bulkhead_lm.Starter_session.parse_command "/package" with
   | Bulkhead_lm.Starter_session.Package_request -> ()
   | _ -> Alcotest.fail "expected /package command");
  (match Bulkhead_lm.Starter_session.parse_command "/plan" with
   | Bulkhead_lm.Starter_session.Show_admin_plan -> ()
   | _ -> Alcotest.fail "expected /plan command");
  (match Bulkhead_lm.Starter_session.parse_command "/apply" with
   | Bulkhead_lm.Starter_session.Apply_admin_plan -> ()
   | _ -> Alcotest.fail "expected /apply command");
  (match Bulkhead_lm.Starter_session.parse_command "/discard" with
   | Bulkhead_lm.Starter_session.Discard_admin_plan -> ()
   | _ -> Alcotest.fail "expected /discard command");
  (match Bulkhead_lm.Starter_session.parse_command "/env" with
   | Bulkhead_lm.Starter_session.Show_env -> ()
   | _ -> Alcotest.fail "expected /env command");
  (match Bulkhead_lm.Starter_session.parse_command "/providers" with
   | Bulkhead_lm.Starter_session.Show_providers -> ()
   | _ -> Alcotest.fail "expected /providers command");
  (match Bulkhead_lm.Starter_session.parse_command "/file README.md" with
   | Bulkhead_lm.Starter_session.Attach_file path ->
     Alcotest.(check string) "file path" "README.md" path
   | _ -> Alcotest.fail "expected /file command");
  (match Bulkhead_lm.Starter_session.parse_command "/file" with
   | Bulkhead_lm.Starter_session.Invalid _ -> ()
   | _ -> Alcotest.fail "expected invalid /file without argument");
  (match Bulkhead_lm.Starter_session.parse_command "/files" with
   | Bulkhead_lm.Starter_session.Show_pending_files -> ()
   | _ -> Alcotest.fail "expected /files command");
  (match Bulkhead_lm.Starter_session.parse_command "/clearfiles" with
   | Bulkhead_lm.Starter_session.Clear_pending_files -> ()
   | _ -> Alcotest.fail "expected /clearfiles command");
  (match Bulkhead_lm.Starter_session.parse_command "/explore src" with
   | Bulkhead_lm.Starter_session.Explore_path path ->
     Alcotest.(check string) "explore path" "src" path
   | _ -> Alcotest.fail "expected /explore command");
  (match Bulkhead_lm.Starter_session.parse_command "/explore" with
   | Bulkhead_lm.Starter_session.Explore_path "." -> ()
   | _ -> Alcotest.fail "expected /explore default path");
  (match Bulkhead_lm.Starter_session.parse_command "/open README.md" with
   | Bulkhead_lm.Starter_session.Open_path path ->
     Alcotest.(check string) "open path" "README.md" path
   | _ -> Alcotest.fail "expected /open command");
  (match Bulkhead_lm.Starter_session.parse_command "/run /bin/ls -la" with
   | Bulkhead_lm.Starter_session.Run_command command ->
     Alcotest.(check string) "run command" "/bin/ls -la" command
   | _ -> Alcotest.fail "expected /run command");
  (match Bulkhead_lm.Starter_session.parse_command "/swap claude-sonnet" with
   | Bulkhead_lm.Starter_session.Swap_model model ->
     Alcotest.(check string) "swap target" "claude-sonnet" model
   | _ -> Alcotest.fail "expected /swap command");
  (match Bulkhead_lm.Starter_session.parse_command "/swap" with
   | Bulkhead_lm.Starter_session.Invalid _ -> ()
   | _ -> Alcotest.fail "expected invalid /swap without argument");
  (match Bulkhead_lm.Starter_session.parse_command "/memory" with
   | Bulkhead_lm.Starter_session.Show_memory -> ()
   | _ -> Alcotest.fail "expected /memory command");
  (match
     Bulkhead_lm.Starter_session.parse_command
       "/memory replace Planner memory now starts from the deployment summary."
   with
   | Bulkhead_lm.Starter_session.Replace_memory summary ->
     Alcotest.(check string)
       "memory replacement summary"
       "Planner memory now starts from the deployment summary."
       summary
   | _ -> Alcotest.fail "expected /memory replace command");
  (match Bulkhead_lm.Starter_session.parse_command "/memory replace" with
   | Bulkhead_lm.Starter_session.Invalid _ -> ()
   | _ -> Alcotest.fail "expected invalid /memory replace without summary");
  (match Bulkhead_lm.Starter_session.parse_command "/forget" with
   | Bulkhead_lm.Starter_session.Forget_memory -> ()
   | _ -> Alcotest.fail "expected /forget command");
  (match Bulkhead_lm.Starter_session.parse_command "/thread on" with
   | Bulkhead_lm.Starter_session.Set_thread true -> ()
   | _ -> Alcotest.fail "expected /thread on command");
  (match Bulkhead_lm.Starter_session.parse_command "/thread off" with
   | Bulkhead_lm.Starter_session.Set_thread false -> ()
   | _ -> Alcotest.fail "expected /thread off command");
  (match Bulkhead_lm.Starter_session.parse_command "/thread maybe" with
   | Bulkhead_lm.Starter_session.Invalid _ -> ()
   | _ -> Alcotest.fail "expected invalid /thread argument");
  Lwt.return_unit
;;

let starter_help_lists_commands_alphabetically_test _switch () =
  let usages =
    Bulkhead_lm.Starter_constants.Text.command_help_entries
    |> List.map (fun ({ usage; _ } : Bulkhead_lm.Starter_constants.Text.command_help_entry) -> usage)
  in
  let sorted_usages = List.sort String.compare usages in
  Alcotest.(check (list string)) "command usages sorted" sorted_usages usages;
  Lwt.return_unit
;;

let starter_attachment_injects_file_content_into_prompt_test _switch () =
  let contains ~sub text =
    let sub_len = String.length sub in
    let text_len = String.length text in
    let rec loop index =
      if index + sub_len > text_len
      then false
      else if String.sub text index sub_len = sub
      then true
      else loop (index + 1)
    in
    loop 0
  in
  let attachment =
    { Bulkhead_lm.Starter_attachment.absolute_path = "/tmp/example.txt"
    ; display_path = "/tmp/example.txt"
    ; content = "alpha\nbeta"
    ; truncated = false
    ; byte_count = 10
    }
  in
  let prompt =
    Bulkhead_lm.Starter_attachment.inject_into_prompt [ attachment ] "summarize this"
  in
  Alcotest.(check bool)
    "mentions file path"
    true
    (contains ~sub:"/tmp/example.txt" prompt);
  Alcotest.(check bool) "mentions file content" true (contains ~sub:"alpha\nbeta" prompt);
  Alcotest.(check bool)
    "mentions user request"
    true
    (contains ~sub:"summarize this" prompt);
  Lwt.return_unit
;;

let starter_local_tools_parse_exec_words_test _switch () =
  match
    Bulkhead_lm.Starter_local_tools.parse_exec_words
      {|/bin/echo "hello world" 'again two' plain|}
  with
  | Error message -> Alcotest.failf "expected parsed command, got error: %s" message
  | Ok plan ->
    Alcotest.(check string) "command" "/bin/echo" plan.command;
    Alcotest.(check (list string))
      "args"
      [ "hello world"; "again two"; "plain" ]
      plan.args;
    Lwt.return_unit
;;

let starter_session_tracks_streaming_state_test _switch () =
  let state =
      Bulkhead_lm.Starter_session.create
      ~model:"claude-sonnet"
      ~config_path:"config/local_only/starter.gateway.json"
  in
  let streaming_state, effect = Bulkhead_lm.Starter_session.step state "Hello there" in
  (match effect with
   | Bulkhead_lm.Starter_session.Begin_prompt "Hello there" -> ()
   | _ -> Alcotest.fail "expected prompt execution effect");
  (match Bulkhead_lm.Starter_session.current_model streaming_state with
   | Some "claude-sonnet" -> ()
   | _ -> Alcotest.fail "expected streaming model context");
  let busy_state, busy_effect = Bulkhead_lm.Starter_session.step streaming_state "/env" in
  (match busy_effect with
   | Bulkhead_lm.Starter_session.Print_message message ->
     Alcotest.(check string)
       "busy message"
       Bulkhead_lm.Starter_constants.Text.busy_message
       message
   | _ -> Alcotest.fail "expected busy message");
  let resumed_state = Bulkhead_lm.Starter_session.interrupt_stream busy_state in
  (match resumed_state with
   | Bulkhead_lm.Starter_session.Ready _ -> ()
   | _ -> Alcotest.fail "expected ready state after interrupt");
  Lwt.return_unit
;;

let starter_session_toggles_conversation_mode_test _switch () =
  let state =
      Bulkhead_lm.Starter_session.create
      ~model:"claude-sonnet"
      ~config_path:"config/local_only/starter.gateway.json"
  in
  Alcotest.(check bool)
    "conversation starts enabled"
    true
    (Bulkhead_lm.Starter_session.conversation_enabled state);
  let state, effect = Bulkhead_lm.Starter_session.step state "/thread off" in
  (match effect with
   | Bulkhead_lm.Starter_session.Update_thread false -> ()
   | _ -> Alcotest.fail "expected thread update effect");
  Alcotest.(check bool)
    "conversation disabled"
    false
    (Bulkhead_lm.Starter_session.conversation_enabled state);
  let state, effect = Bulkhead_lm.Starter_session.step state "/thread on" in
  (match effect with
   | Bulkhead_lm.Starter_session.Update_thread true -> ()
   | _ -> Alcotest.fail "expected thread update effect");
  Alcotest.(check bool)
    "conversation re-enabled"
    true
    (Bulkhead_lm.Starter_session.conversation_enabled state);
  Lwt.return_unit
;;

let starter_session_replaces_memory_snapshot_test _switch () =
  let state =
      Bulkhead_lm.Starter_session.create
      ~model:"claude-sonnet"
      ~config_path:"config/local_only/starter.gateway.json"
  in
  let state, effect =
    Bulkhead_lm.Starter_session.step
      state
      "/memory replace Deployment is now the top priority."
  in
  (match effect with
   | Bulkhead_lm.Starter_session.Substitute_memory summary ->
     Alcotest.(check string)
       "replacement summary"
       "Deployment is now the top priority."
       summary
   | _ -> Alcotest.fail "expected substitute memory effect");
  (match state with
   | Bulkhead_lm.Starter_session.Ready _ -> ()
   | _ -> Alcotest.fail "expected ready state after memory replacement");
  Lwt.return_unit
;;

let starter_conversation_compresses_old_turns_test _switch () =
  let user_text = String.make 1700 'u' in
  let assistant_text = String.make 1700 'a' in
  let rec loop conversation count last_event =
    if count = 0
    then conversation, last_event
    else (
      let conversation, event =
        Bulkhead_lm.Starter_conversation.commit_exchange
          conversation
          ~user:user_text
          ~assistant:assistant_text
      in
      loop
        conversation
        (count - 1)
        (match event with
         | None -> last_event
         | some -> some))
  in
  let conversation, event = loop Bulkhead_lm.Starter_conversation.empty 4 None in
  let stats = Bulkhead_lm.Starter_conversation.stats conversation in
  Alcotest.(check bool) "compression happened" true (Option.is_some event);
  Alcotest.(check int)
    "keeps latest recent turns"
    Bulkhead_lm.Starter_constants.Defaults.conversation_keep_recent_turns
    stats.recent_turn_count;
  Alcotest.(check bool) "compressed turns tracked" true (stats.compressed_turn_count >= 2);
  Alcotest.(check bool) "summary exists" true (stats.summary_char_count > 0);
  Lwt.return_unit
;;

let starter_conversation_request_messages_include_summary_test _switch () =
  let conversation =
    [ "first question", "first answer"
    ; "second question", "second answer"
    ; "third question", "third answer"
    ; "fourth question", "fourth answer"
    ]
    |> List.map (fun (user, assistant) ->
      ( String.concat " " [ user; String.make 1600 'x' ]
      , String.concat " " [ assistant; String.make 1600 'y' ] ))
    |> List.fold_left
         (fun conversation (user, assistant) ->
           Bulkhead_lm.Starter_conversation.commit_exchange conversation ~user ~assistant
           |> fst)
         Bulkhead_lm.Starter_conversation.empty
  in
  let messages =
    Bulkhead_lm.Starter_conversation.request_messages
      conversation
      ~pending_user:"next question"
  in
  (match messages with
   | first :: _ ->
     Alcotest.(check string)
       "summary is injected as system"
       "system"
       first.Bulkhead_lm.Openai_types.role
   | [] -> Alcotest.fail "expected messages");
  (match List.rev messages with
   | last :: _ ->
     Alcotest.(check string)
       "pending user kept last"
       "user"
       last.Bulkhead_lm.Openai_types.role;
     Alcotest.(check string) "pending user content" "next question" last.content
  | [] -> Alcotest.fail "expected last message");
  Lwt.return_unit
;;

let starter_conversation_replace_with_summary_test _switch () =
  let conversation =
    Bulkhead_lm.Starter_conversation.replace_with_summary
      ~summary:
        "Deployment phase only. Preserve customer deadline. Ignore earlier exploration."
  in
  let stats = Bulkhead_lm.Starter_conversation.stats conversation in
  Alcotest.(check int) "recent turns cleared" 0 stats.recent_turn_count;
  Alcotest.(check int) "compressed turn count reset" 0 stats.compressed_turn_count;
  Alcotest.(check bool) "summary retained" true (stats.summary_char_count > 0);
  let messages =
    Bulkhead_lm.Starter_conversation.request_messages
      conversation
      ~pending_user:"What is next?"
  in
  match messages with
  | first :: _ ->
    Alcotest.(check string)
      "replacement summary becomes system message"
      "system"
      first.Bulkhead_lm.Openai_types.role;
    Alcotest.(check bool)
      "replacement summary content kept"
      true
      (string_contains first.content "Deployment phase only.");
    Lwt.return_unit
  | [] -> Alcotest.fail "expected replacement summary message"
;;

let starter_terminal_history_file_prefers_override_test _switch () =
  let file =
    Bulkhead_lm.Starter_terminal.history_file
      ~history_env:"/tmp/custom-history.txt"
      ~home:"/Users/example"
      ()
  in
  Alcotest.(check string) "history override wins" "/tmp/custom-history.txt" file;
  let fallback =
    Bulkhead_lm.Starter_terminal.history_file ~history_env:"" ~home:"/Users/example" ()
  in
  Alcotest.(check string)
    "history fallback path"
    "/Users/example/.bulkhead-lm/starter.history"
    fallback;
  Lwt.return_unit
;;

let tests =
  [
    Alcotest_lwt.test_case "starter profile splits ready and missing routes" `Quick starter_profile_splits_ready_and_missing_routes_test
  ; Alcotest_lwt.test_case "starter session parses beginner commands" `Quick starter_session_parses_beginner_commands_test
  ; Alcotest_lwt.test_case "starter help lists commands alphabetically" `Quick starter_help_lists_commands_alphabetically_test
  ; Alcotest_lwt.test_case "starter attachment injects file content into prompt" `Quick starter_attachment_injects_file_content_into_prompt_test
  ; Alcotest_lwt.test_case "starter local tools parse exec words" `Quick starter_local_tools_parse_exec_words_test
  ; Alcotest_lwt.test_case "starter session tracks streaming state" `Quick starter_session_tracks_streaming_state_test
  ; Alcotest_lwt.test_case "starter session toggles conversation mode" `Quick starter_session_toggles_conversation_mode_test
  ; Alcotest_lwt.test_case "starter session replaces memory snapshot" `Quick starter_session_replaces_memory_snapshot_test
  ; Alcotest_lwt.test_case "starter conversation compresses old turns" `Quick starter_conversation_compresses_old_turns_test
  ; Alcotest_lwt.test_case "starter conversation request messages include summary" `Quick starter_conversation_request_messages_include_summary_test
  ; Alcotest_lwt.test_case "starter conversation replace with summary" `Quick starter_conversation_replace_with_summary_test
  ; Alcotest_lwt.test_case "starter terminal history file prefers override" `Quick starter_terminal_history_file_prefers_override_test
  ]
;;

let suite = "14.starter/session-conversation", tests
