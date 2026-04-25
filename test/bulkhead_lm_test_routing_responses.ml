open Lwt.Infix
open Bulkhead_lm_test_foundation_security
open Bulkhead_lm_test_paths

let output_guard_blocks_secret_material_test _switch () =
  let cfg =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"primary"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"unsafe-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let provider =
    Bulkhead_lm.Provider_mock.make
      [ ( "unsafe-model"
        , Ok
            (Bulkhead_lm.Provider_mock.sample_chat_response
               ~model:"unsafe-model"
               ~content:"-----BEGIN PRIVATE KEY-----"
               ()) )
      ]
  in
  let store =
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg
  in
  let request =
    Bulkhead_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Bulkhead_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Ok _ -> Alcotest.fail "expected output guard to block the response"
  | Error err ->
    Alcotest.(check string) "unsafe output code" "unsafe_output_blocked" err.code;
    Alcotest.(check int) "unsafe output status" 403 err.status;
    Lwt.return_unit
;;

let routing_uses_fallback_after_failure_test _switch () =
  let cfg =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"bad-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"good-model"
                  ~api_key_env:"SECONDARY_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let provider =
    Bulkhead_lm.Provider_mock.make
      [ "bad-model", Error (Bulkhead_lm.Domain_error.upstream ~provider_id:"first" "boom")
      ; ( "good-model"
        , Ok
            (Bulkhead_lm.Provider_mock.sample_chat_response
               ~model:"good-model"
               ~content:"ok"
               ()) )
      ]
  in
  let store =
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg
  in
  let request =
    Bulkhead_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Bulkhead_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected fallback success but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok response ->
    Alcotest.(check string) "fallback chosen" "good-model" response.model;
    Lwt.return_unit
;;

let routing_falls_back_on_retryable_upstream_status_test _switch () =
  let cfg =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"rate-limited-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"good-model"
                  ~api_key_env:"SECONDARY_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let provider =
    Bulkhead_lm.Provider_mock.make
      [ ( "rate-limited-model"
        , Error
            (Bulkhead_lm.Domain_error.upstream_status
               ~provider_id:"first"
               ~status:429
               "quota hit") )
      ; ( "good-model"
        , Ok
            (Bulkhead_lm.Provider_mock.sample_chat_response
               ~model:"good-model"
               ~content:"ok"
               ()) )
      ]
  in
  let store =
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg
  in
  let request =
    Bulkhead_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Bulkhead_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected retryable upstream status fallback but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok response ->
    Alcotest.(check string) "retryable fallback chosen" "good-model" response.model;
    Lwt.return_unit
;;

let routing_stops_on_non_retryable_upstream_status_test _switch () =
  let cfg =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"auth-failed-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"good-model"
                  ~api_key_env:"SECONDARY_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let provider =
    Bulkhead_lm.Provider_mock.make
      [ ( "auth-failed-model"
        , Error
            (Bulkhead_lm.Domain_error.upstream_status
               ~provider_id:"first"
               ~status:401
               "bad upstream key") )
      ; ( "good-model"
        , Ok
            (Bulkhead_lm.Provider_mock.sample_chat_response
               ~model:"good-model"
               ~content:"should-not-run"
               ()) )
      ]
  in
  let store =
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg
  in
  let request =
    Bulkhead_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Bulkhead_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Ok response ->
    Alcotest.failf "expected non-retryable stop, got model %s" response.model
  | Error err ->
    Alcotest.(check string) "non-retryable code kept" "upstream_failure" err.code;
    Alcotest.(check int) "non-retryable status kept" 401 err.status;
    Alcotest.(check (option string))
      "non-retryable provider kept"
      (Some "first")
      err.provider_id;
    Lwt.return_unit
;;

let egress_blocks_localhost_test _switch () =
  let policy = Bulkhead_lm.Security_policy.default () in
  let denied =
    Bulkhead_lm.Egress_policy.ensure_http_allowed policy "http://127.0.0.1:8080/v1"
  in
  Alcotest.(check bool)
    "localhost blocked"
    true
    (match denied with
     | Error _ -> true
     | Ok () -> false);
  Lwt.return_unit
;;

let ollama_local_security_overlay_allows_private_egress_test _switch () =
  let policy_path = config_path "config/defaults/security_policy.ollama_local.json" in
  let policy = Bulkhead_lm.Security_policy.load_file policy_path in
  Alcotest.(check bool)
    "overlay allows loopback ollama"
    true
    (match
       Bulkhead_lm.Egress_policy.ensure_http_allowed
         policy
         "http://127.0.0.1:11434/v1"
     with
     | Ok () -> true
     | Error _ -> false);
  Alcotest.(check bool)
    "overlay allows private-range peers"
    true
    (match
       Bulkhead_lm.Egress_policy.ensure_http_allowed
         policy
         "http://192.168.1.40:11434/v1"
     with
     | Ok () -> true
     | Error _ -> false);
  Lwt.return_unit
;;

let request_body_limit_is_enforced_test _switch () =
  let base_config = Bulkhead_lm.Config_test_support.sample_config () in
  let config =
    { base_config with
      Bulkhead_lm.Config.security_policy =
        { base_config.security_policy with
          server = { base_config.security_policy.server with max_request_body_bytes = 24 }
        }
    }
  in
  let store = Bulkhead_lm.Runtime_state.create config in
  let oversized_body =
    Cohttp_lwt.Body.of_string
      "{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\"}]}"
  in
  Bulkhead_lm.Server.read_request_json store oversized_body
  >>= function
  | Ok _ -> Alcotest.fail "expected oversized request body to be rejected"
  | Error err ->
    Alcotest.(check string) "request too large code" "request_too_large" err.code;
    Alcotest.(check int) "request too large status" 413 err.status;
    Lwt.return_unit
;;

let budget_is_domain_safe_test _switch () =
  let max_tokens = 16 in
  let worker_count = 32 in
  let cfg =
    Bulkhead_lm.Config_test_support.sample_config
      ~virtual_keys:
        [ Bulkhead_lm.Config_test_support.virtual_key
            ~token_plaintext:"sk-domain"
            ~name:"domain"
            ~daily_token_budget:max_tokens
            ()
        ]
      ()
  in
  let store = Bulkhead_lm.Runtime_state.create cfg in
  let principal =
    match Bulkhead_lm.Auth.authenticate store ~authorization:"Bearer sk-domain" with
    | Ok principal -> principal
    | Error _ -> failwith "expected auth success"
  in
  let started = Atomic.make false in
  let success_count = Atomic.make 0 in
  let error_count = Atomic.make 0 in
  let workers =
    List.init worker_count (fun _ ->
      Domain.spawn (fun () ->
        while not (Atomic.get started) do
          Domain.cpu_relax ()
        done;
        match Bulkhead_lm.Budget_ledger.consume store ~principal ~tokens:1 with
        | Ok () -> ignore (Atomic.fetch_and_add success_count 1)
        | Error _ -> ignore (Atomic.fetch_and_add error_count 1)))
  in
  Atomic.set started true;
  List.iter Domain.join workers;
  Alcotest.(check int) "successful budget debits" max_tokens (Atomic.get success_count);
  Alcotest.(check int)
    "rejected concurrent debits"
    (worker_count - max_tokens)
    (Atomic.get error_count);
  Lwt.return_unit
;;

let routing_falls_back_after_provider_exception_test _switch () =
  let cfg =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"bad-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"good-model"
                  ~api_key_env:"SECONDARY_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let invoke_chat _headers backend _request =
    match backend.Bulkhead_lm.Config.upstream_model with
    | "bad-model" -> failwith "provider exploded"
    | "good-model" ->
      Lwt.return
        (Ok
           (Bulkhead_lm.Provider_mock.sample_chat_response
              ~model:"good-model"
              ~content:"ok"
              ()))
    | _ -> failwith "unexpected model"
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
               (Bulkhead_lm.Domain_error.unsupported_feature "embeddings not used here")))
    }
  in
  let store =
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg
  in
  let request =
    Bulkhead_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Bulkhead_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected fallback after exception but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok response ->
    Alcotest.(check string) "fallback chosen after exception" "good-model" response.model;
    Lwt.return_unit
;;

let responses_request_accepts_string_input_test _switch () =
  let request =
    Bulkhead_lm.Responses_api.request_of_yojson
      (`Assoc
        [ "model", `String "gpt-5-mini"
        ; "input", `String "Reply with OK."
        ; "instructions", `String "Be terse."
        ])
  in
  match request with
  | Error err -> Alcotest.failf "expected responses request parse success: %s" err
  | Ok request ->
    let chat_request = Bulkhead_lm.Responses_api.to_chat_request request in
    Alcotest.(check string) "model kept" "gpt-5-mini" chat_request.model;
    Alcotest.(check int) "system + user messages" 2 (List.length chat_request.messages);
    Lwt.return_unit
;;

let tests =
  [
    Alcotest_lwt.test_case "output guard blocks secret material" `Quick output_guard_blocks_secret_material_test
  ; Alcotest_lwt.test_case "uses fallback provider" `Quick routing_uses_fallback_after_failure_test
  ; Alcotest_lwt.test_case "falls back on retryable upstream status" `Quick routing_falls_back_on_retryable_upstream_status_test
  ; Alcotest_lwt.test_case "stops on non-retryable upstream status" `Quick routing_stops_on_non_retryable_upstream_status_test
  ; Alcotest_lwt.test_case "blocks localhost egress" `Quick egress_blocks_localhost_test
  ; Alcotest_lwt.test_case "ollama local overlay allows private egress" `Quick ollama_local_security_overlay_allows_private_egress_test
  ; Alcotest_lwt.test_case "enforces request body limit" `Quick request_body_limit_is_enforced_test
  ; Alcotest_lwt.test_case "falls back after provider exception" `Quick routing_falls_back_after_provider_exception_test
  ; Alcotest_lwt.test_case "responses parses string input" `Quick responses_request_accepts_string_input_test
  ]
;;

let suite = "02.routing/responses", tests
