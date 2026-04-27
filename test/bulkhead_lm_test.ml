open Lwt.Infix
open Bulkhead_lm_test_foundation_security
open Bulkhead_lm_test_paths
open Bulkhead_lm_test_persistence_control_bootstrap

let starter_terminal_completes_commands_and_models_test _switch () =
  let context =
    { Bulkhead_lm.Starter_terminal.commands =
        [ "/help"
        ; "/models"
        ; "/memory"
        ; "/swap"
        ; "/thread"
        ; "/quit"
        ; "/tools"
        ; "/control"
        ; "/file"
        ; "/explore"
        ; "/open"
        ; "/run"
        ]
    ; models = [ "claude-sonnet"; "gpt-5-mini" ]
    }
  in
  let slash_candidates =
    Bulkhead_lm.Starter_terminal.completion_candidates ~context "/m"
  in
  Alcotest.(check (list string))
    "slash command completion"
    [ "/memory"; "/models" ]
    slash_candidates;
  let swap_candidates =
    Bulkhead_lm.Starter_terminal.completion_candidates ~context "/swap c"
  in
  Alcotest.(check (list string))
    "model completion after swap"
    [ "/swap claude-sonnet" ]
    swap_candidates;
  let thread_candidates =
    Bulkhead_lm.Starter_terminal.completion_candidates ~context "/thread o"
  in
  Alcotest.(check (list string))
    "thread completion"
    [ "/thread on"; "/thread off" ]
    thread_candidates;
  let memory_candidates =
    Bulkhead_lm.Starter_terminal.completion_candidates ~context "/memory r"
  in
  Alcotest.(check (list string))
    "memory replacement completion"
    [ "/memory replace " ]
    memory_candidates;
  let tool_candidates =
    Bulkhead_lm.Starter_terminal.completion_candidates ~context "/to"
  in
  Alcotest.(check (list string)) "tools command completion" [ "/tools" ] tool_candidates;
  let control_candidates =
    Bulkhead_lm.Starter_terminal.completion_candidates ~context "/co"
  in
  Alcotest.(check (list string))
    "control command completion"
    [ "/control" ]
    control_candidates;
  let run_candidates = Bulkhead_lm.Starter_terminal.completion_candidates ~context "/r" in
  Alcotest.(check (list string)) "run command completion" [ "/run" ] run_candidates;
  Lwt.return_unit
;;

let starter_control_plane_lines_reflect_current_config_test _switch () =
  let enabled_config =
    Bulkhead_lm.Config_test_support.sample_config
      ~security_policy:
        (control_plane_security_policy ~admin_token_env:"BULKHEAD_ADMIN_TOKEN" ())
      ()
  in
  let enabled_text =
    Bulkhead_lm.Starter_wizard.control_plane_lines
      ~lookup_env:(function
        | "BULKHEAD_ADMIN_TOKEN" -> Some "present"
        | _ -> None)
      ~config_path:"/tmp/control gateway.json"
      enabled_config
    |> String.concat "\n"
  in
  Alcotest.(check bool)
    "control intro explains starter role"
    true
    (string_contains enabled_text "This starter is the interactive client.");
  Alcotest.(check bool)
    "enabled control plane is reported"
    true
    (string_contains enabled_text "HTTP control plane: enabled.");
  Alcotest.(check bool)
    "browser url is derived from config"
    true
    (string_contains enabled_text "http://127.0.0.1:4100/_bulkhead/control");
  Alcotest.(check bool)
    "status api url is derived from config"
    true
    (string_contains enabled_text "/_bulkhead/control/api/status");
  Alcotest.(check bool)
    "reload api url is derived from config"
    true
    (string_contains enabled_text "/_bulkhead/control/api/reload");
  Alcotest.(check bool)
    "admin token env is reported without leaking its value"
    true
    (string_contains enabled_text "Admin token env: BULKHEAD_ADMIN_TOKEN (set)");
  Alcotest.(check bool)
    "start command is explicit"
    true
    (string_contains
       enabled_text
       "./scripts/with_local_toolchain.sh dune exec bulkhead-lm -- --config '/tmp/control gateway.json'");
  let disabled_policy =
    let defaults = Bulkhead_lm.Security_policy.default () in
    { defaults with
      control_plane = { defaults.control_plane with enabled = false }
    }
  in
  let disabled_text =
    Bulkhead_lm.Starter_wizard.control_plane_lines
      ~config_path:"config/local_only/starter.gateway.json"
      (Bulkhead_lm.Config_test_support.sample_config
         ~security_policy:disabled_policy
         ())
    |> String.concat "\n"
  in
  Alcotest.(check bool)
    "disabled control plane is reported"
    true
    (string_contains disabled_text "HTTP control plane: disabled in this config.");
  Alcotest.(check bool)
    "disabled control plane suggests an admin request"
    true
    (string_contains
       disabled_text
       "/admin enable the HTTP control plane at /_bulkhead/control");
  Lwt.return_unit
;;

let starter_assistant_capabilities_prompt_forbids_invented_admin_commands_test _switch ()
  =
  let prompt = Bulkhead_lm.Starter_constants.Text.assistant_capabilities_system_prompt in
  Alcotest.(check bool)
    "prompt mentions control command"
    true
    (string_contains prompt "/control");
  Alcotest.(check bool)
    "prompt forbids invented starter commands"
    true
    (string_contains prompt "Never invent starter commands");
  Alcotest.(check bool)
    "prompt explicitly blocks admin open hallucination"
    true
    (string_contains prompt "/admin open");
  Alcotest.(check bool)
    "prompt explicitly blocks admin status hallucination"
    true
    (string_contains prompt "/admin status");
  Lwt.return_unit
;;

let starter_response_signal_streams_chunked_directives_test _switch () =
  let module Signal = Bulkhead_lm.Starter_response_signal in
  let state = Signal.initial_state in
  let state, first_events = Signal.feed state "[[gr" in
  let state, second_events = Signal.feed state "een]]ready\n[[red]]stop" in
  let _, tail_events = Signal.finish state in
  let events = first_events @ second_events @ tail_events in
  let render_event = function
    | Signal.Text text -> "T:" ^ text
    | Signal.Set_level Signal.Normal -> "C:normal"
    | Signal.Set_level Signal.Green -> "C:green"
    | Signal.Set_level Signal.Orange -> "C:orange"
    | Signal.Set_level Signal.Red -> "C:red"
  in
  Alcotest.(check (list string))
    "chunked directives change colors without leaking markup"
    [ "C:green"; "T:ready\n"; "C:red"; "T:stop" ]
    (List.map render_event events);
  Alcotest.(check string)
    "markup stripped from remembered assistant text"
    "ready\nstop"
    (Signal.strip_markup "[[green]]ready\n[[red]]stop");
  Lwt.return_unit
;;

let starter_packaging_detects_supported_hosts_test _switch () =
  (match
     Bulkhead_lm.Starter_packaging.host_os_of_values ~uname_s:"Darwin" ~os_release:""
   with
   | Ok Bulkhead_lm.Starter_packaging.Macos -> ()
   | _ -> Alcotest.fail "expected macos host detection");
  (match
     Bulkhead_lm.Starter_packaging.host_os_of_values
       ~uname_s:"Linux"
       ~os_release:"ID=ubuntu\nNAME=Ubuntu\n"
   with
   | Ok Bulkhead_lm.Starter_packaging.Ubuntu -> ()
   | _ -> Alcotest.fail "expected ubuntu host detection");
  (match
     Bulkhead_lm.Starter_packaging.host_os_of_values ~uname_s:"FreeBSD" ~os_release:""
   with
   | Ok Bulkhead_lm.Starter_packaging.Freebsd -> ()
   | _ -> Alcotest.fail "expected freebsd host detection");
  Lwt.return_unit
;;

let starter_packaging_defaults_are_os_specific_test _switch () =
  let mac_request =
    Bulkhead_lm.Starter_packaging.default_request
      ~config_path:"config/example.gateway.json"
      Bulkhead_lm.Starter_packaging.Macos
  in
  let ubuntu_request =
    Bulkhead_lm.Starter_packaging.default_request
      ~config_path:"config/example.gateway.json"
      Bulkhead_lm.Starter_packaging.Ubuntu
  in
  let freebsd_request =
    Bulkhead_lm.Starter_packaging.default_request
      ~config_path:"config/example.gateway.json"
      Bulkhead_lm.Starter_packaging.Freebsd
  in
  Alcotest.(check string) "mac install root" "/opt/bulkhead-lm" mac_request.install_root;
  Alcotest.(check string) "ubuntu wrapper dir" "/usr/bin" ubuntu_request.wrapper_dir;
  Alcotest.(check string)
    "freebsd install root"
    "/usr/local/lib/bulkhead-lm"
    freebsd_request.install_root;
  Alcotest.(check string)
    "freebsd package format"
    ".pkg"
    (Bulkhead_lm.Starter_packaging.package_format_label
       Bulkhead_lm.Starter_packaging.Freebsd);
  Lwt.return_unit
;;

let admin_assistant_parses_plan_text_test _switch () =
  let raw_response =
    {|Plan follows:
{"kid_summary":"Open safe local file access for this repository.","why":["BulkheadLM config comes first."],"warnings":["System actions remain bounded by policy."],"config_ops":[{"op":"set_json","target":"security_policy","path":"/client_ops/files/enabled","value":true},{"op":"append_json","target":"security_policy","path":"/client_ops/files/read_roots","value":"/tmp/bulkhead-lm","unique":true}],"system_ops":[{"op":"list_dir","path":"."}]}
|}
  in
  match Bulkhead_lm.Admin_assistant.parse_plan_text raw_response with
  | Error err ->
    Alcotest.failf
      "expected admin plan parse success but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok plan ->
    Alcotest.(check string)
      "kid summary"
      "Open safe local file access for this repository."
      plan.Bulkhead_lm.Admin_assistant_plan.kid_summary;
    Alcotest.(check int)
      "config op count"
      2
      (List.length plan.Bulkhead_lm.Admin_assistant_plan.config_ops);
    Alcotest.(check int)
      "system op count"
      1
      (List.length plan.Bulkhead_lm.Admin_assistant_plan.system_ops);
    Lwt.return_unit
;;

let starter_runtime_tracks_pending_admin_plan_test _switch () =
  let pending_plan =
    { Bulkhead_lm.Admin_assistant.goal = "enable local admin"
    ; plan =
        { Bulkhead_lm.Admin_assistant_plan.kid_summary = "Make the config easier."
        ; why = [ "Because the user asked." ]
        ; warnings = []
        ; config_ops = []
        ; system_ops = []
        }
    ; raw_response = "{}"
    }
  in
  let runtime =
    Bulkhead_lm.Starter_runtime.create ()
    |> fun runtime ->
    Bulkhead_lm.Starter_runtime.set_pending_admin_plan runtime (Some pending_plan)
  in
  Alcotest.(check bool)
    "pending plan stored"
    true
    (Option.is_some runtime.Bulkhead_lm.Starter_runtime.pending_admin_plan);
  let runtime = Bulkhead_lm.Starter_runtime.clear_pending_admin_plan runtime in
  Alcotest.(check bool)
    "pending plan cleared"
    false
    (Option.is_some runtime.Bulkhead_lm.Starter_runtime.pending_admin_plan);
  Lwt.return_unit
;;

let admin_assistant_applies_config_edits_test _switch () =
  with_temp_dir "bulkhead-lm-admin-config" (fun root ->
    let security_path = Filename.concat root "security.json" in
    let gateway_path = Filename.concat root "gateway.json" in
    Yojson.Safe.to_file
      security_path
      (Yojson.Safe.from_file
         (config_path "config/defaults/security_policy.json"));
    Yojson.Safe.to_file
      gateway_path
      (`Assoc
        [ "security_policy_file", `String "security.json"
        ; ( "routes"
          , `List
              [ `Assoc
                  [ "public_model", `String "starter-admin"
                  ; ( "backends"
                    , `List
                        [ `Assoc
                            [ "provider_id", `String "openai-primary"
                            ; "provider_kind", `String "openai_compat"
                            ; "upstream_model", `String "gpt-5-mini"
                            ; "api_base", `String "https://api.example.test/v1"
                            ; "api_key_env", `String "OPENAI_API_KEY"
                            ]
                        ] )
                  ]
              ] )
        ; ( "virtual_keys"
          , `List
              [ `Assoc
                  [ "name", `String "local-dev"
                  ; "token_plaintext", `String "sk-test"
                  ; "daily_token_budget", `Int 1000
                  ; "requests_per_minute", `Int 60
                  ; "allowed_routes", `List [ `String "starter-admin" ]
                  ]
              ] )
        ]);
    let plan =
      { Bulkhead_lm.Admin_assistant_plan.kid_summary =
          "Turn on local file admin only for this temporary directory."
      ; why = [ "The config changes stay local." ]
      ; warnings = []
      ; config_ops =
          [ Bulkhead_lm.Admin_assistant_plan.Set_json
              { target = Bulkhead_lm.Admin_assistant_plan.Security_policy
              ; path = "/client_ops/files/enabled"
              ; value = `Bool true
              }
          ; Bulkhead_lm.Admin_assistant_plan.Append_json
              { target = Bulkhead_lm.Admin_assistant_plan.Security_policy
              ; path = "/client_ops/files/read_roots"
              ; value = `String root
              ; unique = true
              }
          ; Bulkhead_lm.Admin_assistant_plan.Append_json
              { target = Bulkhead_lm.Admin_assistant_plan.Security_policy
              ; path = "/client_ops/files/write_roots"
              ; value = `String root
              ; unique = true
              }
          ; Bulkhead_lm.Admin_assistant_plan.Set_json
              { target = Bulkhead_lm.Admin_assistant_plan.Gateway_config
              ; path = "/routes/0/public_model"
              ; value = `String "starter-admin-ready"
              }
          ]
      ; system_ops = []
      }
    in
    match
      Bulkhead_lm.Admin_assistant.apply_config_edits ~config_path:gateway_path plan
    with
    | Error err ->
      Alcotest.failf
        "expected config edits success but got %s"
        (Bulkhead_lm.Domain_error.to_string err)
    | Ok applied_lines ->
      Alcotest.(check bool) "applied lines reported" true (applied_lines <> []);
      (match Bulkhead_lm.Config.load gateway_path with
       | Error err -> Alcotest.failf "expected reloaded config success: %s" err
       | Ok config ->
         (match config.Bulkhead_lm.Config.routes with
          | route :: _ ->
            Alcotest.(check string)
              "route renamed"
              "starter-admin-ready"
              route.public_model
          | [] -> Alcotest.fail "expected one route");
         Alcotest.(check bool)
           "file ops enabled"
           true
           config.security_policy.client_ops.files.enabled;
         Alcotest.(check bool)
           "read root added"
           true
           (List.mem root config.security_policy.client_ops.files.read_roots);
         Alcotest.(check bool)
           "write root added"
           true
           (List.mem root config.security_policy.client_ops.files.write_roots));
      Lwt.return_unit)
;;

let tests =
  [
    Alcotest_lwt.test_case "starter terminal completes commands and models" `Quick starter_terminal_completes_commands_and_models_test
  ; Alcotest_lwt.test_case "starter control plane lines reflect current config" `Quick starter_control_plane_lines_reflect_current_config_test
  ; Alcotest_lwt.test_case "starter assistant capabilities prompt forbids invented admin commands" `Quick starter_assistant_capabilities_prompt_forbids_invented_admin_commands_test
  ; Alcotest_lwt.test_case "starter response signal parses chunked directives" `Quick starter_response_signal_streams_chunked_directives_test
  ; Alcotest_lwt.test_case "starter packaging detects supported hosts" `Quick starter_packaging_detects_supported_hosts_test
  ; Alcotest_lwt.test_case "starter packaging defaults are os specific" `Quick starter_packaging_defaults_are_os_specific_test
  ; Alcotest_lwt.test_case
      "budget ledger is domain-safe"
      `Quick
      Bulkhead_lm_test_routing_responses.budget_is_domain_safe_test
  ; Alcotest_lwt.test_case "admin assistant parses structured plan text" `Quick admin_assistant_parses_plan_text_test
  ; Alcotest_lwt.test_case "starter runtime tracks pending admin plan" `Quick starter_runtime_tracks_pending_admin_plan_test
  ; Alcotest_lwt.test_case "admin assistant applies config edits" `Quick admin_assistant_applies_config_edits_test
  ]
;;

let suite = "15.starter/admin-terminal", tests

let suites =
  [ Bulkhead_lm_test_foundation_security.suite
  ; Bulkhead_lm_test_routing_responses.suite
  ; Bulkhead_lm_test_streaming_provider_variants.suite
  ; Bulkhead_lm_test_connectors_bootstrap_a.suite
  ; Bulkhead_lm_test_connectors_bootstrap_b.suite
  ; Bulkhead_lm_test_connectors_meta.suite
  ; Bulkhead_lm_test_connectors_social_text.suite
  ; Bulkhead_lm_test_connectors_wechat_runtime.suite
  ; Bulkhead_lm_test_connectors_signed_interactive.suite
  ; Bulkhead_lm_test_mesh_google_chat.suite
  ; Bulkhead_lm_test_persistence_control_bootstrap.suite
  ; Bulkhead_lm_test_control_plane_terminal_ops.suite
  ; Bulkhead_lm_test_worker_starter_profile.suite
  ; Bulkhead_lm_test_starter_session_conversation.suite
  ; suite
  ; Bulkhead_lm_test_ollama_reasoning.suite
  ; Bulkhead_lm_test_pools.suite
  ; Bulkhead_lm_test_multi_persona.suite
  ]
;;

let () = Lwt_main.run (Alcotest_lwt.run "bulkhead-lm" suites)
