open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let persistent_budget_survives_restart_test _switch () =
  let db_path = Filename.temp_file "bulkhead-lm-budget" ".sqlite" in
  let base_config =
    Bulkhead_lm.Config_test_support.sample_config
      ~virtual_keys:
        [ Bulkhead_lm.Config_test_support.virtual_key
            ~token_plaintext:"sk-persist"
            ~name:"persist"
            ~daily_token_budget:5
            ()
        ]
      ()
  in
  let config =
    { base_config with
      Bulkhead_lm.Config.persistence =
        { sqlite_path = Some db_path; busy_timeout_ms = 5000 }
    }
  in
  let store1 = Bulkhead_lm.Runtime_state.create config in
  let principal1 =
    match Bulkhead_lm.Auth.authenticate store1 ~authorization:"Bearer sk-persist" with
    | Ok principal -> principal
    | Error _ -> failwith "expected auth success"
  in
  Alcotest.(check bool)
    "first persisted debit succeeds"
    true
    (match Bulkhead_lm.Budget_ledger.consume store1 ~principal:principal1 ~tokens:3 with
     | Ok () -> true
     | Error _ -> false);
  let store2 = Bulkhead_lm.Runtime_state.create config in
  let principal2 =
    match Bulkhead_lm.Auth.authenticate store2 ~authorization:"Bearer sk-persist" with
    | Ok principal -> principal
    | Error _ -> failwith "expected auth success after reopen"
  in
  Alcotest.(check bool)
    "second persisted debit rejected"
    true
    (match Bulkhead_lm.Budget_ledger.consume store2 ~principal:principal2 ~tokens:3 with
     | Ok () -> false
     | Error _ -> true);
  Lwt.return_unit
;;

let audit_log_is_persisted_test _switch () =
  let db_path = Filename.temp_file "bulkhead-lm-audit" ".sqlite" in
  let base_config = Bulkhead_lm.Config_test_support.sample_config () in
  let config =
    { base_config with
      Bulkhead_lm.Config.persistence =
        { sqlite_path = Some db_path; busy_timeout_ms = 5000 }
    }
  in
  let store = Bulkhead_lm.Runtime_state.create config in
  Bulkhead_lm.Runtime_state.append_audit_event
    store
    { Bulkhead_lm.Persistent_store.event_type = "test.audit"
    ; principal_name = Some "test"
    ; route_model = Some "gpt-5-mini"
    ; provider_id = None
    ; status_code = 200
    ; details = `Assoc [ "result", `String "ok" ]
    };
  let count =
    match store.Bulkhead_lm.Runtime_state.persistent_store with
    | Some persistent_store -> Bulkhead_lm.Persistent_store.audit_count persistent_store
    | None -> failwith "expected persistent store"
  in
  Alcotest.(check int) "one audit row persisted" 1 count;
  Lwt.return_unit
;;

let persistent_connector_session_survives_restart_test _switch () =
  let db_path = Filename.temp_file "bulkhead-lm-session" ".sqlite" in
  let base_config = Bulkhead_lm.Config_test_support.sample_config () in
  let config =
    { base_config with
      Bulkhead_lm.Config.persistence =
        { sqlite_path = Some db_path; busy_timeout_ms = 5000 }
    }
  in
  let session_key = "telegram:chat-42" in
  let conversation : Bulkhead_lm.Session_memory.t =
    { summary = Some "Remember the family trip budget and destination shortlist."
    ; recent_turns =
        [ { Bulkhead_lm.Session_memory.role = Bulkhead_lm.Session_memory.User
          ; content = "We prefer train travel."
          }
        ; { role = Bulkhead_lm.Session_memory.Assistant
          ; content = "Noted: prefer train travel over flights."
          }
        ]
    ; compressed_turn_count = 6
    }
  in
  let store1 = Bulkhead_lm.Runtime_state.create config in
  Bulkhead_lm.Runtime_state.set_user_connector_session
    store1
    ~session_key
    conversation;
  let store2 = Bulkhead_lm.Runtime_state.create config in
  let restored =
    Bulkhead_lm.Runtime_state.get_user_connector_session
      store2
      ~session_key
  in
  Alcotest.(check (option string))
    "summary restored"
    conversation.summary
    restored.summary;
  Alcotest.(check int)
    "two turns restored"
    2
    (List.length restored.recent_turns);
  Alcotest.(check int)
    "compressed count restored"
    conversation.compressed_turn_count
    restored.compressed_turn_count;
  Bulkhead_lm.Runtime_state.clear_user_connector_session
    store2
    ~session_key;
  let store3 = Bulkhead_lm.Runtime_state.create config in
  let cleared =
    Bulkhead_lm.Runtime_state.get_user_connector_session
      store3
      ~session_key
  in
  Alcotest.(check (option string)) "summary cleared" None cleared.summary;
  Alcotest.(check int)
    "no turns after clear"
    0
    (List.length cleared.recent_turns);
  Lwt.return_unit
;;

let terminal_client_resolves_single_plaintext_virtual_key_test _switch () =
  let config =
    Bulkhead_lm.Config_test_support.sample_config
      ~virtual_keys:
        [ Bulkhead_lm.Config_test_support.virtual_key
            ~name:"solo"
            ~token_plaintext:"sk-solo"
            ()
        ]
      ()
  in
  let store = Bulkhead_lm.Runtime_state.create config in
  match Bulkhead_lm.Terminal_client.resolve_authorization store () with
  | Error err ->
    Alcotest.failf
      "expected terminal client auth resolution success but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok authorization ->
    Alcotest.(check string)
      "bearer authorization synthesized"
      "Bearer sk-solo"
      authorization;
    Lwt.return_unit
;;

let terminal_client_infers_first_route_for_ask_test _switch () =
  let config =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"first-route"
            ~backends:[]
            ()
        ; Bulkhead_lm.Config_test_support.route
            ~public_model:"second-route"
            ~backends:[]
            ()
        ]
      ()
  in
  let store = Bulkhead_lm.Runtime_state.create config in
  match Bulkhead_lm.Terminal_client.build_ask_request store "hello" with
  | Error err ->
    Alcotest.failf
      "expected ask request build success but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok request ->
    Alcotest.(check string) "first route selected" "first-route" request.model;
    Lwt.return_unit
;;

let terminal_client_stream_reconstructs_response_text_test _switch () =
  let config =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"kimi-k2.6"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"moonshot-primary"
                  ~provider_kind:Bulkhead_lm.Config.Moonshot_openai
                  ~api_base:"https://api.moonshot.ai/v1"
                  ~upstream_model:"kimi-k2.6"
                  ~api_key_env:"MOONSHOT_API_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let streamed_response : Bulkhead_lm.Openai_types.chat_response =
    { id = "chatcmpl-stream"
    ; created = 1
    ; model = "kimi-k2.6"
    ; choices =
        [ { index = 0
          ; message = { role = "assistant"; content = ""; extra = [] }
          ; finish_reason = "stop"
          }
        ]
    ; usage = { prompt_tokens = 0; completion_tokens = 0; total_tokens = 0 }
    }
  in
  let provider =
    { Bulkhead_lm.Provider_client.invoke_chat =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "non-streaming chat not used here")))
    ; invoke_chat_stream =
        (fun _headers _backend _request ->
          Lwt.return
            (Ok
               { Bulkhead_lm.Provider_client.response = streamed_response
               ; events =
                   Lwt_stream.of_list
                     [ Bulkhead_lm.Provider_client.Reasoning_delta "thinking"
                     ; Bulkhead_lm.Provider_client.Text_delta "Bonjour"
                     ; Bulkhead_lm.Provider_client.Text_delta " monde"
                     ]
               ; close = (fun () -> Lwt.return_unit)
               }))
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "embeddings not used here")))
    }
  in
  let store =
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) config
  in
  match
    Bulkhead_lm.Terminal_client.build_ask_request
      store
      ~model:"kimi-k2.6"
      ~stream:true
      "hello"
  with
  | Error err ->
    Alcotest.failf
      "expected streaming ask request build success but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok request ->
    Bulkhead_lm.Terminal_client.run_ask_stream
      store
      ~authorization:"Bearer sk-test"
      request
      ~on_delta:(fun _chunk -> Lwt.return_unit)
    >>= function
    | Error err ->
      Alcotest.failf
        "expected streaming ask success but got %s"
        (Bulkhead_lm.Domain_error.to_string err)
    | Ok (Bulkhead_lm.Terminal_client.Chat_response response) ->
      Alcotest.(check string)
        "streamed text stitched back into final response"
        "Bonjour monde"
        (Bulkhead_lm.Terminal_client.text_of_chat_response response);
      Lwt.return_unit
    | Ok _ -> Alcotest.fail "expected chat response from streaming ask"
;;

let persistent_store_allows_virtual_key_token_reuse_test _switch () =
  let db_path = Filename.temp_file "bulkhead-lm-keys" ".sqlite" in
  let make_config name =
    let base_config =
      Bulkhead_lm.Config_test_support.sample_config
        ~virtual_keys:
          [ Bulkhead_lm.Config_test_support.virtual_key
              ~token_plaintext:"sk-shared"
              ~name
              ()
          ]
        ()
    in
    { base_config with
      Bulkhead_lm.Config.persistence =
        { sqlite_path = Some db_path; busy_timeout_ms = 5000 }
    }
  in
  let _store1 = Bulkhead_lm.Runtime_state.create (make_config "starter-alpha") in
  match Bulkhead_lm.Runtime_state.create_result (make_config "starter-beta") with
  | Error err ->
    Alcotest.failf
      "expected persistent store bootstrap success when reusing token hash: %s"
      err
  | Ok store2 ->
    (match Bulkhead_lm.Auth.authenticate store2 ~authorization:"Bearer sk-shared" with
     | Error err ->
       Alcotest.failf
         "expected reused virtual key auth success but got %s"
         (Bulkhead_lm.Domain_error.to_string err)
     | Ok principal ->
       Alcotest.(check string)
         "reused token hash resolves to latest configured principal"
         "starter-beta"
         principal.Bulkhead_lm.Runtime_state.name);
    Lwt.return_unit
;;

let client_ops_security_policy
  ?(file_ops_enabled = true)
  ?(exec_enabled = false)
  ?(read_roots = [])
  ?(write_roots = [])
  ?(working_roots = [])
  ?(max_read_bytes = 1_048_576)
  ?(max_write_bytes = 1_048_576)
  ?(timeout_ms = 10_000)
  ?(max_output_bytes = 65_536)
  ()
  =
  let base = Bulkhead_lm.Security_policy.default () in
  { base with
    Bulkhead_lm.Security_policy.client_ops =
      { files =
          { enabled = file_ops_enabled
          ; read_roots
          ; write_roots
          ; max_read_bytes
          ; max_write_bytes
          }
      ; exec = { enabled = exec_enabled; working_roots; timeout_ms; max_output_bytes }
      }
  }
;;

let control_plane_security_policy
  ?(enabled = true)
  ?(path_prefix = "/_bulkhead/control")
  ?(ui_enabled = true)
  ?(allow_reload = true)
  ?admin_token_env
  ()
  =
  let base = Bulkhead_lm.Security_policy.default () in
  { base with
    Bulkhead_lm.Security_policy.control_plane =
      { enabled; path_prefix; ui_enabled; allow_reload; admin_token_env }
  }
;;

let rec remove_path_recursively path =
  if Sys.file_exists path
  then (
    match Unix.lstat path with
    | { Unix.st_kind = Unix.S_DIR; _ } ->
      Sys.readdir path
      |> Array.iter (fun entry -> remove_path_recursively (Filename.concat path entry));
      Unix.rmdir path
    | _ -> Unix.unlink path)
;;

let with_temp_dir prefix f =
  let path = Filename.temp_file prefix "tmp" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  Lwt.finalize
    (fun () -> f path)
    (fun () ->
      if Sys.file_exists path then remove_path_recursively path;
      Lwt.return_unit)
;;

let write_fixture_file path content =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel content)
;;

let write_gateway_config_file ~path ~security_policy_file ~public_model =
  Yojson.Safe.to_file
    path
    (`Assoc
      [ "security_policy_file", `String security_policy_file
      ; ( "routes"
        , `List
            [ `Assoc
                [ "public_model", `String public_model
                ; ( "backends"
                  , `List
                      [ `Assoc
                          [ "provider_id", `String "primary"
                          ; "provider_kind", `String "openai_compat"
                          ; "upstream_model", `String public_model
                          ; "api_base", `String "https://api.example.test/v1"
                          ; "api_key_env", `String "OPENAI_API_KEY"
                          ]
                      ] )
                ]
            ] )
      ; ( "virtual_keys"
        , `List
            [ `Assoc
                [ "name", `String "test"
                ; "token_plaintext", `String "sk-test"
                ; "daily_token_budget", `Int 1000
                ; "requests_per_minute", `Int 60
                ; "allowed_routes", `List [ `String public_model ]
                ]
            ] )
      ])
;;

let write_control_plane_security_policy_file
  ~path
  ?(path_prefix = "/_bulkhead/control")
  ?(admin_token_env = Some "BULKHEAD_ADMIN_TOKEN")
  ()
  =
  let policy =
    control_plane_security_policy ?admin_token_env ~path_prefix ~enabled:true ()
  in
  Yojson.Safe.to_file
    path
    (`Assoc
      [ ( "server"
        , `Assoc
            [ "listen_host", `String policy.server.listen_host
            ; "listen_port", `Int policy.server.listen_port
            ; "max_request_body_bytes", `Int policy.server.max_request_body_bytes
            ; "request_timeout_ms", `Int policy.server.request_timeout_ms
            ] )
      ; ( "auth"
        , `Assoc
            [ "header", `String policy.auth.header
            ; "bearer_prefix", `String policy.auth.bearer_prefix
            ; "hash_algorithm", `String policy.auth.hash_algorithm
            ; "require_virtual_key", `Bool policy.auth.require_virtual_key
            ] )
      ; ( "control_plane"
        , `Assoc
            [ "enabled", `Bool policy.control_plane.enabled
            ; "path_prefix", `String policy.control_plane.path_prefix
            ; "ui_enabled", `Bool policy.control_plane.ui_enabled
            ; "allow_reload", `Bool policy.control_plane.allow_reload
            ; ( "admin_token_env"
              , match policy.control_plane.admin_token_env with
                | Some env_name -> `String env_name
                | None -> `String "" )
            ] )
      ])
;;

let control_plane_exposes_ui_and_status_test _switch () =
  with_temp_dir "bulkhead-lm-control-plane-ui" (fun root ->
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
        let ui_request =
          Cohttp.Request.make
            ~meth:`GET
            (Uri.of_string "http://localhost/_bulkhead/control")
        in
        Bulkhead_lm.Server.callback
          control
          ()
          ui_request
          (Cohttp_lwt.Body.of_string "")
        >>= fun (ui_response, ui_body) ->
        Alcotest.(check int) "control-plane ui status" 200 (response_status_code ui_response);
        response_body_text ui_body >>= fun ui_text ->
        Alcotest.(check bool)
          "control-plane ui title rendered"
          true
          (string_contains ui_text "BulkheadLM Control Plane");
        let status_request =
          Cohttp.Request.make
            ~meth:`GET
            ~headers:(Cohttp.Header.of_list [ "authorization", "Bearer bulkhead-admin-token" ])
            (Uri.of_string "http://localhost/_bulkhead/control/api/status")
        in
        Bulkhead_lm.Server.callback
          control
          ()
          status_request
          (Cohttp_lwt.Body.of_string "")
        >>= fun (status_response, status_body) ->
        Alcotest.(check int)
          "control-plane status accepted"
          200
          (response_status_code status_response);
        response_body_json status_body >|= fun status_json ->
        let fields = json_assoc status_json in
        Alcotest.(check (option string))
          "status includes config path"
          (Some gateway_path)
          (match List.assoc_opt "config_path" fields with
           | Some (`String value) -> Some value
           | _ -> None);
        Alcotest.(check (option int))
          "status includes route count"
          (Some 1)
          (match List.assoc_opt "routes" fields with
           | Some (`List routes) -> Some (List.length routes)
           | _ -> None))
  )
;;

let tests =
  [
    Alcotest_lwt.test_case "persistent budget survives restart" `Quick persistent_budget_survives_restart_test
  ; Alcotest_lwt.test_case "audit log is persisted" `Quick audit_log_is_persisted_test
  ; Alcotest_lwt.test_case "persistent connector session survives restart" `Quick persistent_connector_session_survives_restart_test
  ; Alcotest_lwt.test_case "terminal client resolves single plaintext virtual key" `Quick terminal_client_resolves_single_plaintext_virtual_key_test
  ; Alcotest_lwt.test_case "terminal client infers first route for ask" `Quick terminal_client_infers_first_route_for_ask_test
  ; Alcotest_lwt.test_case "terminal client reconstructs streamed response text" `Quick terminal_client_stream_reconstructs_response_text_test
  ; Alcotest_lwt.test_case "persistent store allows virtual key token reuse" `Quick persistent_store_allows_virtual_key_token_reuse_test
  ; Alcotest_lwt.test_case "control plane exposes ui and status" `Quick control_plane_exposes_ui_and_status_test
  ]
;;

let suite = "11.persistence/control-bootstrap", tests
