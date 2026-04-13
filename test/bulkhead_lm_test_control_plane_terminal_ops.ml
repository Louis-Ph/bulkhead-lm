open Lwt.Infix
open Bulkhead_lm_test_foundation_security
open Bulkhead_lm_test_persistence_control_bootstrap
let control_plane_reload_swaps_active_runtime_test _switch () =
  with_temp_dir "bulkhead-lm-control-plane-reload" (fun root ->
    let gateway_path = Filename.concat root "gateway.json" in
    let security_policy_path = Filename.concat root "security.json" in
    write_control_plane_security_policy_file ~path:security_policy_path ();
    write_gateway_config_file
      ~path:gateway_path
      ~security_policy_file:security_policy_path
      ~public_model:"gpt-4o-mini";
    with_env_overrides
      [ "BULKHEAD_ADMIN_TOKEN", "bulkhead-admin-token"; "OPENAI_API_KEY", "sk-openai-test" ]
      (fun () ->
        let control =
          match
            Bulkhead_lm.Runtime_control.create_result
              ~config_path:gateway_path
              ~port_override:None
              ()
          with
          | Ok control -> control
          | Error err -> Alcotest.failf "expected control-plane runtime success: %s" err
        in
        write_gateway_config_file
          ~path:gateway_path
          ~security_policy_file:security_policy_path
          ~public_model:"gpt-5-mini";
        let reload_request =
          Cohttp.Request.make
            ~meth:`POST
            ~headers:(Cohttp.Header.of_list [ "authorization", "Bearer bulkhead-admin-token" ])
            (Uri.of_string "http://localhost/_bulkhead/control/api/reload")
        in
        Bulkhead_lm.Server.callback
          control
          ()
          reload_request
          (Cohttp_lwt.Body.of_string "{}")
        >>= fun (reload_response, reload_body) ->
        Alcotest.(check int)
          "control-plane reload accepted"
          200
          (response_status_code reload_response);
        response_body_json reload_body >>= fun reload_json ->
        let reload_fields = json_assoc reload_json in
        Alcotest.(check (option string))
          "reload result named"
          (Some "reloaded")
          (match List.assoc_opt "result" reload_fields with
           | Some (`String value) -> Some value
           | _ -> None);
        let models_request =
          Cohttp.Request.make
            ~meth:`GET
            (Uri.of_string "http://localhost/v1/models")
        in
        Bulkhead_lm.Server.callback
          control
          ()
          models_request
          (Cohttp_lwt.Body.of_string "")
        >>= fun (models_response, models_body) ->
        Alcotest.(check int) "models endpoint stays live" 200 (response_status_code models_response);
        response_body_json models_body >|= fun models_json ->
        let fields = json_assoc models_json in
        let model_ids =
          match List.assoc_opt "data" fields with
          | Some (`List values) ->
            values
            |> List.filter_map (fun item ->
              match List.assoc_opt "id" (json_assoc item) with
              | Some (`String value) -> Some value
              | _ -> None)
          | _ -> []
        in
        Alcotest.(check (list string))
          "models endpoint reflects reloaded config"
          [ "gpt-5-mini" ]
          model_ids)
  )
;;

let control_plane_replaces_and_clears_memory_session_test _switch () =
  with_temp_dir "bulkhead-lm-control-plane-memory" (fun root ->
    let gateway_path = Filename.concat root "gateway.json" in
    let security_policy_path = Filename.concat root "security.json" in
    write_control_plane_security_policy_file ~path:security_policy_path ();
    write_gateway_config_file
      ~path:gateway_path
      ~security_policy_file:security_policy_path
      ~public_model:"gpt-4o-mini";
    with_env_overrides
      [ "BULKHEAD_ADMIN_TOKEN", "bulkhead-admin-token"; "OPENAI_API_KEY", "sk-openai-test" ]
      (fun () ->
        let control =
          match
            Bulkhead_lm.Runtime_control.create_result
              ~config_path:gateway_path
              ~port_override:None
              ()
          with
          | Ok control -> control
          | Error err -> Alcotest.failf "expected control-plane runtime success: %s" err
        in
        let session_key = "agent:planner:demo" in
        let replace_request =
          Cohttp.Request.make
            ~meth:`PUT
            ~headers:(Cohttp.Header.of_list [ "authorization", "Bearer bulkhead-admin-token" ])
            (Uri.of_string "http://localhost/_bulkhead/control/api/memory/session")
        in
        let replace_body =
          Cohttp_lwt.Body.of_string
            (Yojson.Safe.to_string
               (`Assoc
                 [ "session_key", `String session_key
                 ; "summary", `String "Planner memory replaced by external orchestrator."
                 ; "compressed_turn_count", `Int 12
                 ; ( "recent_turns"
                   , `List
                       [ `Assoc
                           [ "role", `String "user"
                           ; "content", `String "Remember the supply constraints."
                           ]
                       ; `Assoc
                           [ "role", `String "assistant"
                           ; "content", `String "Constraints captured in the durable summary."
                           ]
                       ] )
                 ]))
        in
        Bulkhead_lm.Server.callback
          control
          ()
          replace_request
          replace_body
        >>= fun (replace_response, replace_response_body) ->
        Alcotest.(check int)
          "memory replace accepted"
          200
          (response_status_code replace_response);
        response_body_json replace_response_body >>= fun replace_json ->
        let replace_fields = json_assoc replace_json in
        Alcotest.(check (option string))
          "replace echoes summary"
          (Some "Planner memory replaced by external orchestrator.")
          (match List.assoc_opt "summary" replace_fields with
           | Some (`String value) -> Some value
           | _ -> None);
        let store = Bulkhead_lm.Runtime_control.current_store control in
        let session =
          Bulkhead_lm.Runtime_state.get_user_connector_session
            store
            ~session_key
        in
        Alcotest.(check (option string))
          "runtime state summary replaced"
          (Some "Planner memory replaced by external orchestrator.")
          session.summary;
        let get_request =
          Cohttp.Request.make
            ~meth:`GET
            ~headers:(Cohttp.Header.of_list [ "authorization", "Bearer bulkhead-admin-token" ])
            (Uri.of_string
               (Fmt.str
                  "http://localhost/_bulkhead/control/api/memory/session?session_key=%s"
                  (Uri.pct_encode session_key)))
        in
        Bulkhead_lm.Server.callback
          control
          ()
          get_request
          (Cohttp_lwt.Body.of_string "")
        >>= fun (get_response, get_body) ->
        Alcotest.(check int)
          "memory get accepted"
          200
          (response_status_code get_response);
        response_body_json get_body >>= fun get_json ->
        let get_fields = json_assoc get_json in
        Alcotest.(check (option int))
          "memory get returns recent turn count"
          (Some 2)
          (match List.assoc_opt "stats" get_fields with
           | Some (`Assoc stats_fields) ->
             (match List.assoc_opt "recent_turn_count" stats_fields with
              | Some (`Int value) -> Some value
              | _ -> None)
           | _ -> None);
        let delete_request =
          Cohttp.Request.make
            ~meth:`DELETE
            ~headers:(Cohttp.Header.of_list [ "authorization", "Bearer bulkhead-admin-token" ])
            (Uri.of_string
               (Fmt.str
                  "http://localhost/_bulkhead/control/api/memory/session?session_key=%s"
                  (Uri.pct_encode session_key)))
        in
        Bulkhead_lm.Server.callback
          control
          ()
          delete_request
          (Cohttp_lwt.Body.of_string "")
        >>= fun (delete_response, _delete_body) ->
        Alcotest.(check int)
          "memory delete accepted"
          200
          (response_status_code delete_response);
        let cleared =
          Bulkhead_lm.Runtime_state.get_user_connector_session
            store
            ~session_key
        in
        Alcotest.(check (option string)) "memory cleared" None cleared.summary;
        Alcotest.(check int)
          "no recent turns after clear"
          0
          (List.length cleared.recent_turns);
        Lwt.return_unit)
  )
;;

let terminal_ops_lists_directory_within_allowed_root_test _switch () =
  with_temp_dir "bulkhead-lm-ops-list" (fun root ->
    let nested_dir = Filename.concat root "notes" in
    Unix.mkdir nested_dir 0o755;
    write_fixture_file (Filename.concat root "hello.txt") "hello";
    let store =
      Bulkhead_lm.Runtime_state.create
        (Bulkhead_lm.Config_test_support.sample_config
           ~security_policy:
             (client_ops_security_policy ~read_roots:[ root ] ~write_roots:[ root ] ())
           ())
    in
    Bulkhead_lm.Terminal_client.invoke_json
      store
      ~authorization:"Bearer sk-test"
      ~kind:Bulkhead_lm.Terminal_client.Ops
      (`Assoc [ "op", `String "list_dir"; "path", `String "." ])
    >>= function
    | Error err ->
      Alcotest.failf
        "expected list_dir success but got %s"
        (Bulkhead_lm.Domain_error.to_string err)
    | Ok response ->
      let fields =
        Bulkhead_lm.Terminal_client.response_to_yojson response |> json_assoc
      in
      let entries =
        match List.assoc_opt "entries" fields with
        | Some (`List values) -> values
        | _ -> Alcotest.fail "expected entries list"
      in
      let names =
        entries
        |> List.filter_map (function
          | `Assoc entry_fields ->
            (match List.assoc_opt "name" entry_fields with
             | Some (`String value) -> Some value
             | _ -> None)
          | _ -> None)
      in
      Alcotest.(check bool) "file entry present" true (List.mem "hello.txt" names);
      Alcotest.(check bool) "directory entry present" true (List.mem "notes" names);
      Lwt.return_unit)
;;

let terminal_ops_rejects_paths_outside_allowed_roots_test _switch () =
  with_temp_dir "bulkhead-lm-ops-deny" (fun root ->
    let store =
      Bulkhead_lm.Runtime_state.create
        (Bulkhead_lm.Config_test_support.sample_config
           ~security_policy:(client_ops_security_policy ~read_roots:[ root ] ())
           ())
    in
    Bulkhead_lm.Terminal_client.invoke_json
      store
      ~authorization:"Bearer sk-test"
      ~kind:Bulkhead_lm.Terminal_client.Ops
      (`Assoc [ "op", `String "read_file"; "path", `String "/etc/hosts" ])
    >>= function
    | Ok _ -> Alcotest.fail "expected read_file outside root to be denied"
    | Error err ->
      Alcotest.(check string) "denied code" "operation_denied" err.code;
      Lwt.return_unit)
;;

let terminal_ops_writes_base64_files_test _switch () =
  with_temp_dir "bulkhead-lm-ops-write" (fun root ->
    let payload = "binary-\000-content" in
    let encoded = Base64.encode_exn payload in
    let store =
      Bulkhead_lm.Runtime_state.create
        (Bulkhead_lm.Config_test_support.sample_config
           ~security_policy:
             (client_ops_security_policy ~read_roots:[ root ] ~write_roots:[ root ] ())
           ())
    in
    Bulkhead_lm.Terminal_client.invoke_json
      store
      ~authorization:"Bearer sk-test"
      ~kind:Bulkhead_lm.Terminal_client.Ops
      (`Assoc
        [ "op", `String "write_file"
        ; "path", `String "artifacts/output.bin"
        ; "encoding", `String "base64"
        ; "content", `String encoded
        ; "create_parents", `Bool true
        ])
    >>= function
    | Error err ->
      Alcotest.failf
        "expected write_file success but got %s"
        (Bulkhead_lm.Domain_error.to_string err)
    | Ok _ ->
      let written_path = Filename.concat root "artifacts/output.bin" in
      let channel = open_in_bin written_path in
      let content =
        Fun.protect
          ~finally:(fun () -> close_in_noerr channel)
          (fun () -> really_input_string channel (in_channel_length channel))
      in
      Alcotest.(check string) "written bytes preserved" payload content;
      Lwt.return_unit)
;;

let terminal_ops_executes_commands_in_allowed_root_test _switch () =
  with_temp_dir "bulkhead-lm-ops-exec" (fun root ->
    let canonical_root = Unix.realpath root in
    write_fixture_file (Filename.concat canonical_root "marker.txt") "root-marker";
    let store =
      Bulkhead_lm.Runtime_state.create
        (Bulkhead_lm.Config_test_support.sample_config
           ~security_policy:
             (client_ops_security_policy
                ~file_ops_enabled:false
                ~exec_enabled:true
                ~working_roots:[ root ]
                ())
           ())
    in
    Bulkhead_lm.Terminal_client.invoke_json
      store
      ~authorization:"Bearer sk-test"
      ~kind:Bulkhead_lm.Terminal_client.Ops
      (`Assoc
        [ "op", `String "exec"
        ; "command", `String "/bin/cat"
        ; "args", `List [ `String (Filename.concat canonical_root "marker.txt") ]
        ; "cwd", `String "."
        ])
    >>= function
    | Error err ->
      Alcotest.failf
        "expected exec success but got %s"
        (Bulkhead_lm.Domain_error.to_string err)
    | Ok response ->
      let fields =
        Bulkhead_lm.Terminal_client.response_to_yojson response |> json_assoc
      in
      let exit_code =
        match List.assoc_opt "exit_code" fields with
        | Some (`Int value) -> value
        | _ -> -1
      in
      let stdout =
        match List.assoc_opt "stdout" fields with
        | Some (`String value) -> String.trim value
        | _ -> Alcotest.fail "expected stdout string"
      in
      let stderr =
        match List.assoc_opt "stderr" fields with
        | Some (`String value) -> String.trim value
        | _ -> ""
      in
      if not (String.equal stdout "root-marker")
      then
        Alcotest.failf
          "unexpected exec output: exit=%d stdout=%S stderr=%S"
          exit_code
          stdout
          stderr;
      Alcotest.(check string)
        "command resolves relative file in allowed cwd"
        "root-marker"
        stdout;
      Lwt.return_unit)
;;

let worker_processes_ops_requests_test _switch () =
  with_temp_dir "bulkhead-lm-ops-worker" (fun root ->
    write_fixture_file (Filename.concat root "worker.txt") "worker-data";
    let store =
      Bulkhead_lm.Runtime_state.create
        (Bulkhead_lm.Config_test_support.sample_config
           ~security_policy:(client_ops_security_policy ~read_roots:[ root ] ())
           ())
    in
    Bulkhead_lm.Terminal_worker.run_lines
      store
      ~jobs:1
      [ {|{"id":"ops-1","kind":"ops","request":{"op":"read_file","path":"worker.txt"}}|} ]
    >>= function
    | [ line ] ->
      let fields = Yojson.Safe.from_string line |> json_assoc in
      let kind =
        match List.assoc_opt "kind" fields with
        | Some (`String value) -> value
        | _ -> Alcotest.fail "expected kind field"
      in
      let response_fields =
        match List.assoc_opt "response" fields with
        | Some json -> json_assoc json
        | None -> Alcotest.fail "expected response field"
      in
      let content =
        match List.assoc_opt "content" response_fields with
        | Some (`String value) -> value
        | _ -> Alcotest.fail "expected content field"
      in
      Alcotest.(check string) "worker kind preserved" "ops" kind;
      Alcotest.(check string) "worker file content returned" "worker-data" content;
      Lwt.return_unit
    | _ -> Alcotest.fail "expected exactly one worker output")
;;

let tests =
  [
    Alcotest_lwt.test_case "control plane reload swaps active runtime" `Quick control_plane_reload_swaps_active_runtime_test
  ; Alcotest_lwt.test_case "control plane replaces and clears memory session" `Quick control_plane_replaces_and_clears_memory_session_test
  ; Alcotest_lwt.test_case "terminal ops lists directory within allowed root" `Quick terminal_ops_lists_directory_within_allowed_root_test
  ; Alcotest_lwt.test_case "terminal ops reject paths outside allowed roots" `Quick terminal_ops_rejects_paths_outside_allowed_roots_test
  ; Alcotest_lwt.test_case "terminal ops write base64 files" `Quick terminal_ops_writes_base64_files_test
  ; Alcotest_lwt.test_case "terminal ops execute commands in allowed root" `Quick terminal_ops_executes_commands_in_allowed_root_test
  ; Alcotest_lwt.test_case "worker processes ops requests" `Quick worker_processes_ops_requests_test
  ]
;;
let suite = "12.control-plane/terminal-ops", tests
