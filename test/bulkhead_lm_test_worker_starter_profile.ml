open Lwt.Infix
open Bulkhead_lm_test_foundation_security
open Bulkhead_lm_test_persistence_control_bootstrap

let worker_rejects_malformed_json_lines_test _switch () =
  let store =
    Bulkhead_lm.Runtime_state.create (Bulkhead_lm.Config_test_support.sample_config ())
  in
  Bulkhead_lm.Terminal_worker.run_lines store ~jobs:1 [ "{not-json" ]
  >>= fun outputs ->
  match outputs with
  | [ line ] ->
    let json = Yojson.Safe.from_string line in
    (match json with
     | `Assoc fields ->
       let ok =
         match List.assoc_opt "ok" fields with
         | Some (`Bool value) -> value
         | _ -> true
       in
       let line_number =
         match List.assoc_opt "line" fields with
         | Some (`Int value) -> value
         | _ -> 0
       in
       Alcotest.(check bool) "worker line rejected" false ok;
       Alcotest.(check int) "worker line number preserved" 1 line_number;
       Lwt.return_unit
     | _ -> Alcotest.fail "expected worker output object")
  | _ -> Alcotest.fail "expected exactly one worker output line"
;;

let worker_processes_requests_with_bounded_parallelism_test _switch () =
  let active = ref 0 in
  let max_active = ref 0 in
  let active_lock = Mutex.create () in
  let with_active f =
    Mutex.lock active_lock;
    active := !active + 1;
    if !active > !max_active then max_active := !active;
    Mutex.unlock active_lock;
    Lwt.finalize f (fun () ->
      Mutex.lock active_lock;
      active := !active - 1;
      Mutex.unlock active_lock;
      Lwt.return_unit)
  in
  let provider =
    { Bulkhead_lm.Provider_client.invoke_chat =
        (fun _headers _backend request ->
          with_active (fun () ->
            Lwt_unix.sleep 0.02
            >|= fun () ->
            Ok
              (Bulkhead_lm.Provider_mock.sample_chat_response
                 ~model:request.Bulkhead_lm.Openai_types.model
                 ~content:
                   (request.messages
                    |> List.rev
                    |> List.hd
                    |> fun message -> message.Bulkhead_lm.Openai_types.content)
                 ())))
    ; invoke_chat_stream =
        (fun _headers _backend request ->
          with_active (fun () ->
            Lwt_unix.sleep 0.02
            >|= fun () ->
            Ok
              (Bulkhead_lm.Provider_stream.of_chat_response
                 (Bulkhead_lm.Provider_mock.sample_chat_response
                    ~model:request.Bulkhead_lm.Openai_types.model
                    ~content:"stream"
                    ()))))
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "embeddings not used in worker concurrency test")))
    }
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      ~provider_factory:(fun _ -> provider)
      (Bulkhead_lm.Config_test_support.sample_config
         ~routes:
           [ Bulkhead_lm.Config_test_support.route
               ~public_model:"gpt-4o-mini"
               ~backends:
                 [ Bulkhead_lm.Config_test_support.backend
                     ~provider_id:"worker-primary"
                     ~provider_kind:Bulkhead_lm.Config.Openai_compat
                     ~api_base:"https://api.example.test/v1"
                     ~upstream_model:"worker-model"
                     ~api_key_env:"WORKER_KEY"
                     ()
                 ]
               ()
           ]
         ())
  in
  let lines =
    [ {|{"id":"job-1","request":{"model":"gpt-4o-mini","messages":[{"role":"user","content":"one"}]}}|}
    ; {|{"id":"job-2","request":{"model":"gpt-4o-mini","messages":[{"role":"user","content":"two"}]}}|}
    ; {|{"id":"job-3","request":{"model":"gpt-4o-mini","messages":[{"role":"user","content":"three"}]}}|}
    ]
  in
  Bulkhead_lm.Terminal_worker.run_lines store ~jobs:2 lines
  >>= fun outputs ->
  Alcotest.(check int) "one output per input" 3 (List.length outputs);
  Alcotest.(check bool) "parallelism reached two in flight" true (!max_active >= 2);
  let contains_job id =
    List.exists
      (fun line ->
        let json = Yojson.Safe.from_string line in
        match json with
        | `Assoc fields ->
          (match List.assoc_opt "id" fields with
           | Some (`String value) -> String.equal value id
           | _ -> false)
        | _ -> false)
      outputs
  in
  Alcotest.(check bool) "job-1 kept" true (contains_job "job-1");
  Alcotest.(check bool) "job-2 kept" true (contains_job "job-2");
  Alcotest.(check bool) "job-3 kept" true (contains_job "job-3");
  Lwt.return_unit
;;

let starter_profile_marks_route_ready_from_env_lookup_test _switch () =
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
        ]
      ()
  in
  let statuses =
    Bulkhead_lm.Starter_profile.route_statuses
      ~lookup:(function
        | "ANTHROPIC_API_KEY" -> Some "present"
        | _ -> None)
      config
  in
  match statuses with
  | [ status ] ->
    Alcotest.(check bool) "route ready when env exists" true status.ready;
    Lwt.return_unit
  | _ -> Alcotest.fail "expected one route status"
;;

let starter_profile_writes_portable_config_json_test _switch () =
  let presets =
    Bulkhead_lm.Starter_profile.presets
    |> List.filter (fun (preset : Bulkhead_lm.Starter_profile.provider_preset) ->
      List.mem
        preset.Bulkhead_lm.Starter_profile.public_model
        [ "claude-sonnet"; "qwen-plus" ])
  in
  let json =
    Bulkhead_lm.Starter_profile.config_json
      ~security_policy_file:"../defaults/security_policy.json"
      ~error_catalog_file:"../defaults/error_catalog.json"
      ~providers_schema_file:"../defaults/providers.schema.json"
      ~selected_presets:presets
      ~virtual_key_name:"local-dev"
      ~token_plaintext:"sk-local"
      ~daily_token_budget:50000
      ~requests_per_minute:30
      ~sqlite_path:"../var/bulkhead-lm.sqlite"
      ()
  in
  match json with
  | `Assoc fields ->
    Alcotest.(check (option string))
      "security policy path"
      (Some "../defaults/security_policy.json")
      (match List.assoc_opt "security_policy_file" fields with
       | Some (`String value) -> Some value
       | _ -> None);
    Alcotest.(check (option string))
      "error catalog path"
      (Some "../defaults/error_catalog.json")
      (match List.assoc_opt "error_catalog_file" fields with
       | Some (`String value) -> Some value
       | _ -> None);
    Alcotest.(check (option string))
      "providers schema path"
      (Some "../defaults/providers.schema.json")
      (match List.assoc_opt "providers_schema_file" fields with
       | Some (`String value) -> Some value
       | _ -> None);
    let routes =
      match List.assoc_opt "routes" fields with
      | Some (`List values) -> values
      | _ -> []
    in
    let virtual_keys =
      match List.assoc_opt "virtual_keys" fields with
      | Some (`List values) -> values
      | _ -> []
    in
    Alcotest.(check int) "two routes written" 2 (List.length routes);
    Alcotest.(check int) "one virtual key written" 1 (List.length virtual_keys);
    Lwt.return_unit
  | _ -> Alcotest.fail "expected starter config object"
;;

let starter_saved_config_derives_local_only_catalog_references_test _switch () =
  let references =
    Bulkhead_lm.Starter_saved_config.catalog_references_for_output_path
      ~base_config_path:"config/example.gateway.json"
      "config/local_only/starter.gateway.json"
  in
  Alcotest.(check string)
    "security policy reference"
    "../defaults/security_policy.json"
    references.security_policy_file;
  Alcotest.(check string)
    "error catalog reference"
    "../defaults/error_catalog.json"
    references.error_catalog_file;
  Alcotest.(check string)
    "providers schema reference"
    "../defaults/providers.schema.json"
    references.providers_schema_file;
  Lwt.return_unit
;;

let starter_saved_config_bootstraps_first_run_file_test _switch () =
  let repo = repo_root () in
  let base_config_path = Filename.concat repo "config/example.gateway.json" in
  let output_path =
    Filename.concat repo "config/local_only/starter.bootstrap.test.gateway.json"
  in
  Lwt.finalize
    (fun () ->
      if Sys.file_exists output_path then Sys.remove output_path;
      match
        Bulkhead_lm.Starter_saved_config.ensure ~base_config_path ~output_path
      with
      | Error message ->
        Alcotest.failf "expected starter bootstrap, got error: %s" message
      | Ok Bulkhead_lm.Starter_saved_config.Bootstrapped ->
        let fields = Yojson.Safe.from_file output_path |> json_assoc in
        Alcotest.(check (option string))
          "bootstrapped security policy reference"
          (Some "../defaults/security_policy.json")
          (match List.assoc_opt "security_policy_file" fields with
           | Some (`String value) -> Some value
           | _ -> None);
        Alcotest.(check int)
          "bootstrapped route count"
          (List.length Bulkhead_lm.Starter_profile.presets)
          (match List.assoc_opt "routes" fields with
           | Some (`List values) -> List.length values
           | _ -> 0);
        Lwt.return_unit
      | Ok _ -> Alcotest.fail "expected bootstrapped starter config outcome")
    (fun () ->
      if Sys.file_exists output_path then Sys.remove output_path;
      Lwt.return_unit)
;;

let starter_saved_config_migrates_legacy_catalog_references_test _switch () =
  let repo = repo_root () in
  let base_config_path = Filename.concat repo "config/example.gateway.json" in
  let output_path =
    Filename.concat repo "config/local_only/starter.migrate.test.gateway.json"
  in
  Lwt.finalize
    (fun () ->
      Yojson.Safe.to_file
        output_path
        (`Assoc
          [ "security_policy_file", `String "defaults/security_policy.json"
          ; "error_catalog_file", `String "defaults/error_catalog.json"
          ; "providers_schema_file", `String "defaults/providers.schema.json"
          ; "virtual_keys", `List []
          ; "routes", `List []
          ]);
      match
        Bulkhead_lm.Starter_saved_config.ensure ~base_config_path ~output_path
      with
      | Error message ->
        Alcotest.failf "expected starter migration, got error: %s" message
      | Ok Bulkhead_lm.Starter_saved_config.Migrated ->
        let fields = Yojson.Safe.from_file output_path |> json_assoc in
        Alcotest.(check (option string))
          "migrated security policy reference"
          (Some "../defaults/security_policy.json")
          (match List.assoc_opt "security_policy_file" fields with
           | Some (`String value) -> Some value
           | _ -> None);
        Alcotest.(check (option string))
          "migrated error catalog reference"
          (Some "../defaults/error_catalog.json")
          (match List.assoc_opt "error_catalog_file" fields with
           | Some (`String value) -> Some value
           | _ -> None);
        Lwt.return_unit
      | Ok _ -> Alcotest.fail "expected migrated starter config outcome")
    (fun () ->
      if Sys.file_exists output_path then Sys.remove output_path;
      Lwt.return_unit)
;;

let starter_profile_masks_environment_values_test _switch () =
  let statuses =
    Bulkhead_lm.Starter_profile.env_statuses
      ~lookup:(function
        | "OPENAI_API_KEY" -> Some "sk-test-secret"
        | _ -> None)
      ()
  in
  match
    List.find_opt
      (fun (status : Bulkhead_lm.Starter_profile.env_status) ->
        String.equal status.name "OPENAI_API_KEY")
      statuses
  with
  | Some status ->
    Alcotest.(check bool) "env present" true status.present;
    Alcotest.(check (option string))
      "env masked"
      (Some "sk-t********et")
      status.masked_value;
    Lwt.return_unit
  | None -> Alcotest.fail "expected OPENAI_API_KEY status"
;;

let starter_profile_exposes_multiple_models_per_provider_test _switch () =
  let counts =
    Bulkhead_lm.Starter_profile.presets
    |> List.fold_left
         (fun acc (preset : Bulkhead_lm.Starter_profile.provider_preset) ->
           let current =
             match List.assoc_opt preset.provider_key acc with
             | Some value -> value
             | None -> 0
           in
           (preset.provider_key, current + 1) :: List.remove_assoc preset.provider_key acc)
         []
  in
  let expect provider_key =
    match List.assoc_opt provider_key counts with
    | Some count -> Alcotest.(check bool) provider_key true (count >= 3)
    | None -> Alcotest.failf "missing provider family %s" provider_key
  in
  List.iter
    expect
    [ "anthropic"
    ; "openrouter"
    ; "openai"
    ; "google"
    ; "vertex"
    ; "xai"
    ; "meta"
    ; "mistral"
    ; "alibaba"
    ; "moonshot"
    ];
  Lwt.return_unit
;;

let example_gateway_exposes_multiple_models_per_provider_test _switch () =
  let project_root =
    Filename.dirname (Filename.dirname (Filename.dirname (Sys.getcwd ())))
  in
  let example_path =
    Filename.concat (Filename.concat project_root "config") "example.gateway.json"
  in
  match Bulkhead_lm.Config.load example_path with
  | Error err -> Alcotest.failf "failed to load example config: %s" err
  | Ok config ->
    let counts =
      config.Bulkhead_lm.Config.routes
      |> List.fold_left
           (fun acc (route : Bulkhead_lm.Config.route) ->
             match route.backends with
             | backend :: _ ->
               let key =
                 match backend.provider_kind with
                 | Bulkhead_lm.Config.Anthropic -> "anthropic"
                 | Bulkhead_lm.Config.Openrouter_openai -> "openrouter"
                 | Bulkhead_lm.Config.Openai_compat -> "openai"
                 | Bulkhead_lm.Config.Google_openai -> "google"
                 | Bulkhead_lm.Config.Vertex_openai -> "vertex"
                 | Bulkhead_lm.Config.Mistral_openai -> "mistral"
                 | Bulkhead_lm.Config.Alibaba_openai -> "alibaba"
                 | Bulkhead_lm.Config.Moonshot_openai -> "moonshot"
                 | Bulkhead_lm.Config.Xai_openai -> "xai"
                 | Bulkhead_lm.Config.Meta_openai -> "meta"
                 | _ -> "other"
               in
               let current =
                 match List.assoc_opt key acc with
                 | Some value -> value
                 | None -> 0
               in
               (key, current + 1) :: List.remove_assoc key acc
             | [] -> acc)
           []
    in
    let expect provider_key =
      match List.assoc_opt provider_key counts with
      | Some count -> Alcotest.(check bool) provider_key true (count >= 3)
      | None -> Alcotest.failf "example config missing provider family %s" provider_key
    in
    List.iter
      expect
      [ "anthropic"
      ; "openrouter"
      ; "openai"
      ; "google"
      ; "vertex"
      ; "xai"
      ; "meta"
      ; "mistral"
      ; "alibaba"
      ; "moonshot"
      ];
    Lwt.return_unit
;;

let tests =
  [
    Alcotest_lwt.test_case "worker rejects malformed json lines" `Quick worker_rejects_malformed_json_lines_test
  ; Alcotest_lwt.test_case "worker processes requests with bounded parallelism" `Quick worker_processes_requests_with_bounded_parallelism_test
  ; Alcotest_lwt.test_case "starter profile marks route ready from env lookup" `Quick starter_profile_marks_route_ready_from_env_lookup_test
  ; Alcotest_lwt.test_case "starter profile writes portable config json" `Quick starter_profile_writes_portable_config_json_test
  ; Alcotest_lwt.test_case "starter saved config derives local-only catalog references" `Quick starter_saved_config_derives_local_only_catalog_references_test
  ; Alcotest_lwt.test_case "starter saved config bootstraps first-run file" `Quick starter_saved_config_bootstraps_first_run_file_test
  ; Alcotest_lwt.test_case "starter saved config migrates legacy catalog references" `Quick starter_saved_config_migrates_legacy_catalog_references_test
  ; Alcotest_lwt.test_case "starter profile masks environment values" `Quick starter_profile_masks_environment_values_test
  ; Alcotest_lwt.test_case "starter profile exposes multiple models per provider" `Quick starter_profile_exposes_multiple_models_per_provider_test
  ; Alcotest_lwt.test_case "example gateway exposes multiple models per provider" `Quick example_gateway_exposes_multiple_models_per_provider_test
  ]
;;

let suite = "13.worker/starter-profile", tests
