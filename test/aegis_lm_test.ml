open Lwt.Infix

let secret_redaction_test _switch () =
  let payload =
    `Assoc
      [ "api_key", `String "sk-secret"
      ; "nested", `Assoc [ "authorization", `String "Bearer x"; "safe", `String "ok" ]
      ]
  in
  let redacted =
    Aegis_lm.Secret_redaction.redact_json
      ~sensitive_keys:[ "api_key"; "authorization" ]
      ~replacement:"[REDACTED]"
      payload
  in
  let expected =
    `Assoc
      [ "api_key", `String "[REDACTED]"
      ; "nested", `Assoc [ "authorization", `String "[REDACTED]"; "safe", `String "ok" ]
      ]
  in
  Alcotest.(check string)
    "json redaction"
    (Yojson.Safe.to_string expected)
    (Yojson.Safe.to_string redacted);
  Lwt.return_unit
;;

let auth_rejects_unknown_key_test _switch () =
  let cfg =
    Aegis_lm.Config_test_support.sample_config
      ~virtual_keys:
        [ Aegis_lm.Config_test_support.virtual_key
            ~token_plaintext:"sk-known"
            ~name:"known"
            ()
        ]
      ()
  in
  let store = Aegis_lm.Runtime_state.create cfg in
  let result = Aegis_lm.Auth.authenticate store ~authorization:"Bearer sk-unknown" in
  Alcotest.(check bool)
    "invalid key rejected"
    true
    (match result with
     | Error _ -> true
     | Ok _ -> false);
  Lwt.return_unit
;;

let budget_blocks_after_limit_test _switch () =
  let cfg =
    Aegis_lm.Config_test_support.sample_config
      ~virtual_keys:
        [ Aegis_lm.Config_test_support.virtual_key
            ~token_plaintext:"sk-budget"
            ~name:"budget"
            ~daily_token_budget:5
            ()
        ]
      ()
  in
  let store = Aegis_lm.Runtime_state.create cfg in
  let principal =
    match Aegis_lm.Auth.authenticate store ~authorization:"Bearer sk-budget" with
    | Ok principal -> principal
    | Error _ -> failwith "expected auth success"
  in
  let first = Aegis_lm.Budget_ledger.consume store ~principal ~tokens:3 in
  let second = Aegis_lm.Budget_ledger.consume store ~principal ~tokens:3 in
  Alcotest.(check bool)
    "first allowed"
    true
    (match first with
     | Ok _ -> true
     | Error _ -> false);
  Alcotest.(check bool)
    "second blocked"
    true
    (match second with
     | Error _ -> true
     | Ok _ -> false);
  Lwt.return_unit
;;

let routing_uses_fallback_after_failure_test _switch () =
  let cfg =
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"bad-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Aegis_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
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
    Aegis_lm.Provider_mock.make
      [ "bad-model", Error (Aegis_lm.Domain_error.upstream ~provider_id:"first" "boom")
      ; ( "good-model"
        , Ok
            (Aegis_lm.Provider_mock.sample_chat_response
               ~model:"good-model"
               ~content:"ok"
               ()) )
      ]
  in
  let store = Aegis_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg in
  let request =
    Aegis_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Aegis_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected fallback success but got %s"
      (Aegis_lm.Domain_error.to_string err)
  | Ok response ->
    Alcotest.(check string) "fallback chosen" "good-model" response.model;
    Lwt.return_unit
;;

let routing_falls_back_on_retryable_upstream_status_test _switch () =
  let cfg =
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"rate-limited-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Aegis_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
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
    Aegis_lm.Provider_mock.make
      [ ( "rate-limited-model"
        , Error
            (Aegis_lm.Domain_error.upstream_status
               ~provider_id:"first"
               ~status:429
               "quota hit") )
      ; ( "good-model"
        , Ok
            (Aegis_lm.Provider_mock.sample_chat_response
               ~model:"good-model"
               ~content:"ok"
               ()) )
      ]
  in
  let store = Aegis_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg in
  let request =
    Aegis_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Aegis_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected retryable upstream status fallback but got %s"
      (Aegis_lm.Domain_error.to_string err)
  | Ok response ->
    Alcotest.(check string) "retryable fallback chosen" "good-model" response.model;
    Lwt.return_unit
;;

let routing_stops_on_non_retryable_upstream_status_test _switch () =
  let cfg =
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"auth-failed-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Aegis_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
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
    Aegis_lm.Provider_mock.make
      [ ( "auth-failed-model"
        , Error
            (Aegis_lm.Domain_error.upstream_status
               ~provider_id:"first"
               ~status:401
               "bad upstream key") )
      ; ( "good-model"
        , Ok
            (Aegis_lm.Provider_mock.sample_chat_response
               ~model:"good-model"
               ~content:"should-not-run"
               ()) )
      ]
  in
  let store = Aegis_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg in
  let request =
    Aegis_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Aegis_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Ok response ->
    Alcotest.failf "expected non-retryable stop, got model %s" response.model
  | Error err ->
    Alcotest.(check string) "non-retryable code kept" "upstream_failure" err.code;
    Alcotest.(check int) "non-retryable status kept" 401 err.status;
    Alcotest.(check (option string)) "non-retryable provider kept" (Some "first") err.provider_id;
    Lwt.return_unit
;;

let egress_blocks_localhost_test _switch () =
  let policy = Aegis_lm.Security_policy.default () in
  let denied = Aegis_lm.Egress_policy.ensure_http_allowed policy "http://127.0.0.1:8080/v1" in
  Alcotest.(check bool)
    "localhost blocked"
    true
    (match denied with
     | Error _ -> true
     | Ok () -> false);
  Lwt.return_unit
;;

let request_body_limit_is_enforced_test _switch () =
  let base_config = Aegis_lm.Config_test_support.sample_config () in
  let config =
    { base_config with
      Aegis_lm.Config.security_policy =
        { base_config.security_policy with
          server =
            { base_config.security_policy.server with
              max_request_body_bytes = 24
            }
        }
    }
  in
  let store = Aegis_lm.Runtime_state.create config in
  let oversized_body =
    Cohttp_lwt.Body.of_string "{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\"}]}"
  in
  Aegis_lm.Server.read_request_json store oversized_body
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
    Aegis_lm.Config_test_support.sample_config
      ~virtual_keys:
        [ Aegis_lm.Config_test_support.virtual_key
            ~token_plaintext:"sk-domain"
            ~name:"domain"
            ~daily_token_budget:max_tokens
            ()
        ]
      ()
  in
  let store = Aegis_lm.Runtime_state.create cfg in
  let principal =
    match Aegis_lm.Auth.authenticate store ~authorization:"Bearer sk-domain" with
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
        match Aegis_lm.Budget_ledger.consume store ~principal ~tokens:1 with
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
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"bad-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Aegis_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
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
    match backend.Aegis_lm.Config.upstream_model with
    | "bad-model" -> failwith "provider exploded"
    | "good-model" ->
      Lwt.return
        (Ok
           (Aegis_lm.Provider_mock.sample_chat_response
              ~model:"good-model"
              ~content:"ok"
              ()))
    | _ -> failwith "unexpected model"
  in
  let provider =
    { Aegis_lm.Provider_client.invoke_chat =
        invoke_chat
    ; invoke_chat_stream =
        (fun headers backend request ->
          invoke_chat headers backend request
          >|= Result.map Aegis_lm.Provider_stream.of_chat_response)
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error (Aegis_lm.Domain_error.unsupported_feature "embeddings not used here")))
    }
  in
  let store = Aegis_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg in
  let request =
    Aegis_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Aegis_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected fallback after exception but got %s"
      (Aegis_lm.Domain_error.to_string err)
  | Ok response ->
    Alcotest.(check string) "fallback chosen after exception" "good-model" response.model;
    Lwt.return_unit
;;

let routing_times_out_slow_provider_test _switch () =
  let base_config =
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"slow"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"slow-model"
                  ~api_key_env:"SLOW_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let config =
    { base_config with
      Aegis_lm.Config.security_policy =
        { base_config.security_policy with
          server = { base_config.security_policy.server with request_timeout_ms = 10 }
        }
    }
  in
  let invoke_chat _headers _backend _request =
    Lwt_unix.sleep 0.05
    >|= fun () ->
    Ok
      (Aegis_lm.Provider_mock.sample_chat_response
         ~model:"slow-model"
         ~content:"late"
         ())
  in
  let provider =
    { Aegis_lm.Provider_client.invoke_chat = invoke_chat
    ; invoke_chat_stream =
        (fun headers backend request ->
          invoke_chat headers backend request
          >|= Result.map Aegis_lm.Provider_stream.of_chat_response)
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error (Aegis_lm.Domain_error.unsupported_feature "embeddings not used here")))
    }
  in
  let store = Aegis_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) config in
  let request =
    Aegis_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "gpt-4o-mini"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Aegis_lm.Router.dispatch_chat store ~authorization:"Bearer sk-test" request
  >>= function
  | Ok _ -> Alcotest.fail "expected timeout from slow provider"
  | Error err ->
    Alcotest.(check string) "timeout code" "request_timeout" err.code;
    Alcotest.(check int) "timeout status" 504 err.status;
    Alcotest.(check (option string)) "provider id kept" (Some "slow") err.provider_id;
    Lwt.return_unit
;;

let embeddings_fall_back_on_retryable_failure_test _switch () =
  let cfg =
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"text-embedding-3-small"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"bad-embedding-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Aegis_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"good-embedding-model"
                  ~api_key_env:"SECONDARY_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let provider =
    { Aegis_lm.Provider_client.invoke_chat =
        (fun _headers _backend _request ->
          Lwt.return
            (Error (Aegis_lm.Domain_error.unsupported_feature "chat not used in embeddings test")))
    ; invoke_chat_stream =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Aegis_lm.Domain_error.unsupported_feature
                  "chat streaming not used in embeddings test")))
    ; invoke_embeddings =
        (fun _headers backend request ->
          match backend.Aegis_lm.Config.upstream_model with
          | "bad-embedding-model" ->
            Lwt.return
              (Error
                 (Aegis_lm.Domain_error.upstream_status
                    ~provider_id:"first"
                    ~status:503
                    "temporary outage"))
          | "good-embedding-model" ->
            Lwt.return
              (Ok
                 { Aegis_lm.Openai_types.model = request.model
                 ; data = [ { index = 0; embedding = [ 0.1; 0.2 ] } ]
                 ; usage = { prompt_tokens = 1; completion_tokens = 0; total_tokens = 1 }
                 })
          | _ -> failwith "unexpected embeddings model")
    }
  in
  let store = Aegis_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg in
  let request =
    Aegis_lm.Openai_types.embeddings_request_of_yojson
      (`Assoc
        [ "model", `String "text-embedding-3-small"
        ; "input", `String "hi"
        ])
    |> Result.get_ok
  in
  Aegis_lm.Router.dispatch_embeddings store ~authorization:"Bearer sk-test" request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected embeddings fallback success but got %s"
      (Aegis_lm.Domain_error.to_string err)
  | Ok response ->
    Alcotest.(check string) "embeddings fallback chosen" "good-embedding-model" response.model;
    Alcotest.(check int) "one embedding returned" 1 (List.length response.data);
    Lwt.return_unit
;;

let responses_request_accepts_string_input_test _switch () =
  let request =
    Aegis_lm.Responses_api.request_of_yojson
      (`Assoc
        [ "model", `String "gpt-5-mini"
        ; "input", `String "Reply with OK."
        ; "instructions", `String "Be terse."
        ])
  in
  match request with
  | Error err -> Alcotest.failf "expected responses request parse success: %s" err
  | Ok request ->
    let chat_request = Aegis_lm.Responses_api.to_chat_request request in
    Alcotest.(check string) "model kept" "gpt-5-mini" chat_request.model;
    Alcotest.(check int) "system + user messages" 2 (List.length chat_request.messages);
    Lwt.return_unit
;;

let responses_wrap_chat_response_test _switch () =
  let chat_response =
    Aegis_lm.Provider_mock.sample_chat_response ~model:"gpt-5-mini" ~content:"OK" ()
  in
  let response = Aegis_lm.Responses_api.of_chat_response chat_response in
  let json = Aegis_lm.Responses_api.response_to_yojson response in
  let as_text = Yojson.Safe.to_string json in
  Alcotest.(check bool) "response object tag" true (String.contains as_text 'r');
  Alcotest.(check string) "output text" "OK" response.output_text;
  Lwt.return_unit
;;

let chat_sse_contains_done_marker_test _switch () =
  let response =
    Aegis_lm.Provider_mock.sample_chat_response
      ~model:"claude-sonnet"
      ~content:"stream-ok"
      ()
  in
  let chunks = Aegis_lm.Sse_stream.chat_completion_chunks response in
  let encoded =
    (chunks |> List.map Aegis_lm.Sse_stream.encode |> String.concat "")
    ^ Aegis_lm.Sse_stream.done_marker
  in
  Alcotest.(check bool) "chat sse object tag" true (String.contains encoded '[');
  Alcotest.(check bool)
    "chat sse done marker"
    true
    (String.ends_with ~suffix:"data: [DONE]\n\n" encoded);
  Lwt.return_unit
;;

let responses_sse_contains_completion_event_test _switch () =
  let response =
    Aegis_lm.Provider_mock.sample_chat_response
      ~model:"claude-sonnet"
      ~content:"delta-ok"
      ()
    |> Aegis_lm.Responses_api.of_chat_response
  in
  let encoded =
    Aegis_lm.Sse_stream.response_events response
    |> List.map (fun (event, json) -> Aegis_lm.Sse_stream.encode ?event json)
    |> String.concat ""
  in
  Alcotest.(check bool)
    "response completed event"
    true
    (String.contains encoded 'c' && String.contains encoded 'd');
  Lwt.return_unit
;;

let chat_stream_response_closes_handle_test _switch () =
  let closed = ref false in
  let response =
    Aegis_lm.Provider_mock.sample_chat_response
      ~model:"claude-sonnet"
      ~content:"stream-close-ok"
      ()
  in
  let stream =
    { Aegis_lm.Provider_client.response = response
    ; events = Lwt_stream.of_list [ Aegis_lm.Provider_client.Text_delta "stream-close-ok" ]
    ; close =
        (fun () ->
          closed := true;
          Lwt.return_unit)
    }
  in
  Aegis_lm.Sse_stream.respond_chat_stream stream
  >>= fun (_response, body) ->
  Cohttp_lwt.Body.to_string body
  >>= fun encoded ->
  Lwt.pause ()
  >>= fun () ->
  Alcotest.(check bool)
    "stream body includes done marker"
    true
    (String.ends_with ~suffix:"data: [DONE]\n\n" encoded);
  Alcotest.(check bool) "stream close called" true !closed;
  Lwt.return_unit
;;

let config_load_accepts_openai_compatible_provider_variants_test _switch () =
  let config_path = Filename.temp_file "aegislm-provider-kinds" ".json" in
  let config_json =
    `Assoc
      [ ( "routes"
        , `List
            [ `Assoc
                [ "public_model", `String "asia-multi"
                ; ( "backends"
                  , `List
                      [ `Assoc
                          [ "provider_id", `String "mistral-primary"
                          ; "provider_kind", `String "mistral_openai"
                          ; "upstream_model", `String "mistral-small-latest"
                          ; "api_base", `String "https://api.mistral.ai/v1"
                          ; "api_key_env", `String "MISTRAL_API_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "ollama-primary"
                          ; "provider_kind", `String "ollama_openai"
                          ; "upstream_model", `String "llama3.2"
                          ; "api_base", `String "http://127.0.0.1:11434/v1"
                          ; "api_key_env", `String "OLLAMA_API_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "alibaba-primary"
                          ; "provider_kind", `String "alibaba_openai"
                          ; "upstream_model", `String "qwen-plus"
                          ; ( "api_base"
                            , `String
                                "https://dashscope-intl.aliyuncs.com/compatible-mode/v1" )
                          ; "api_key_env", `String "DASHSCOPE_API_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "moonshot-primary"
                          ; "provider_kind", `String "moonshot_openai"
                          ; "upstream_model", `String "kimi-k2.5"
                          ; "api_base", `String "https://api.moonshot.ai/v1"
                          ; "api_key_env", `String "MOONSHOT_API_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "peer-primary"
                          ; "provider_kind", `String "aegis_peer"
                          ; "upstream_model", `String "claude-sonnet"
                          ; "api_base", `String "https://mesh.example.test/v1"
                          ; "api_key_env", `String "AEGISLM_PEER_API_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "ssh-peer-primary"
                          ; "provider_kind", `String "aegis_ssh_peer"
                          ; "upstream_model", `String "claude-sonnet"
                          ; "api_key_env", `String "AEGISLM_SSH_PEER_API_KEY"
                          ; ( "ssh_transport"
                            , `Assoc
                                [ "destination", `String "ops@machine-a.example.net"
                                ; "host", `String "machine-a.example.net"
                                ; ( "remote_worker_command"
                                  , `String "/opt/aegis-lm/scripts/remote_worker.sh" )
                                ; "remote_config_path", `String "/etc/aegislm/gateway.json"
                                ; "remote_switch", `String "prod-switch"
                                ; "remote_jobs", `Int 2
                                ; "options", `List [ `String "-i"; `String "/tmp/aegis-key" ]
                                ] )
                          ]
                      ] )
                ]
            ] )
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Aegis_lm.Config.load config_path with
   | Error err -> Alcotest.failf "expected config load success: %s" err
   | Ok config ->
     match config.Aegis_lm.Config.routes with
     | [ route ] ->
       (match route.Aegis_lm.Config.backends with
        | [ mistral; ollama; alibaba; moonshot; peer; ssh_peer ] ->
          Alcotest.(check bool)
            "mistral kind parsed"
            true
            (match mistral.Aegis_lm.Config.provider_kind with
             | Aegis_lm.Config.Mistral_openai -> true
             | _ -> false);
          Alcotest.(check bool)
            "mistral kind is openai-compatible"
            true
            (Aegis_lm.Config.is_openai_compatible_kind
               mistral.Aegis_lm.Config.provider_kind);
          Alcotest.(check bool)
            "ollama kind parsed"
            true
            (match ollama.Aegis_lm.Config.provider_kind with
             | Aegis_lm.Config.Ollama_openai -> true
             | _ -> false);
          Alcotest.(check bool)
            "ollama kind is openai-compatible"
            true
            (Aegis_lm.Config.is_openai_compatible_kind
               ollama.Aegis_lm.Config.provider_kind);
          Alcotest.(check bool)
            "alibaba kind parsed"
            true
            (match alibaba.Aegis_lm.Config.provider_kind with
             | Aegis_lm.Config.Alibaba_openai -> true
             | _ -> false);
          Alcotest.(check bool)
            "alibaba kind is openai-compatible"
            true
            (Aegis_lm.Config.is_openai_compatible_kind
               alibaba.Aegis_lm.Config.provider_kind);
          Alcotest.(check bool)
            "moonshot kind parsed"
            true
            (match moonshot.Aegis_lm.Config.provider_kind with
             | Aegis_lm.Config.Moonshot_openai -> true
             | _ -> false);
          Alcotest.(check bool)
            "moonshot kind is openai-compatible"
            true
            (Aegis_lm.Config.is_openai_compatible_kind
               moonshot.Aegis_lm.Config.provider_kind);
          Alcotest.(check bool)
            "peer kind parsed"
            true
            (match peer.Aegis_lm.Config.provider_kind with
             | Aegis_lm.Config.Aegis_peer -> true
             | _ -> false);
          Alcotest.(check bool)
            "peer kind is openai-compatible"
            true
            (Aegis_lm.Config.is_openai_compatible_kind peer.Aegis_lm.Config.provider_kind);
          Alcotest.(check bool)
            "ssh peer kind parsed"
            true
            (match ssh_peer.Aegis_lm.Config.provider_kind with
             | Aegis_lm.Config.Aegis_ssh_peer -> true
             | _ -> false);
          Alcotest.(check bool)
            "ssh peer kind is openai-compatible"
            true
            (Aegis_lm.Config.is_openai_compatible_kind ssh_peer.Aegis_lm.Config.provider_kind);
          (match Aegis_lm.Config.backend_ssh_transport ssh_peer with
           | None -> Alcotest.fail "expected ssh transport"
           | Some transport ->
             Alcotest.(check string)
               "ssh destination parsed"
               "ops@machine-a.example.net"
               transport.destination;
             Alcotest.(check string)
               "ssh host parsed"
               "machine-a.example.net"
               transport.host;
             Alcotest.(check int) "ssh remote jobs parsed" 2 transport.remote_jobs)
        | _ -> Alcotest.fail "expected six backends")
     | _ -> Alcotest.fail "expected one route");
  Lwt.return_unit
;;

let provider_registry_routes_new_openai_compatible_kinds_test _switch () =
  let request =
    { Aegis_lm.Openai_types.model = "ignored"
    ; input = [ "hello" ]
    }
  in
  let assert_openai_compat kind provider_id api_key_env =
    let backend =
      Aegis_lm.Config_test_support.backend
        ~provider_id
        ~provider_kind:kind
        ~api_base:"https://api.example.test/v1"
        ~upstream_model:"example-model"
        ~api_key_env
        ()
    in
    let provider = Aegis_lm.Provider_registry.make backend in
    provider.Aegis_lm.Provider_client.invoke_embeddings
      { Aegis_lm.Provider_client.peer_headers = []; peer_context = None }
      backend
      request
    >>= function
    | Ok _ -> Alcotest.fail "expected missing credential failure"
    | Error err ->
      Alcotest.(check string)
        "new kinds use openai-compatible adapter"
        "upstream_failure"
        err.Aegis_lm.Domain_error.code;
      Alcotest.(check string)
        "missing env reported"
        ("Missing environment variable " ^ api_key_env)
        err.Aegis_lm.Domain_error.message;
      Lwt.return_unit
  in
  assert_openai_compat Aegis_lm.Config.Mistral_openai "mistral-primary" "MISTRAL_TEST_KEY"
  >>= fun () ->
  assert_openai_compat Aegis_lm.Config.Ollama_openai "ollama-primary" "OLLAMA_TEST_KEY"
  >>= fun () ->
  assert_openai_compat Aegis_lm.Config.Alibaba_openai "alibaba-primary" "DASHSCOPE_TEST_KEY"
  >>= fun () ->
  assert_openai_compat
    Aegis_lm.Config.Moonshot_openai
    "moonshot-primary"
    "MOONSHOT_TEST_KEY"
  >>= fun () ->
  assert_openai_compat
    Aegis_lm.Config.Aegis_peer
    "peer-primary"
    "AEGISLM_PEER_TEST_KEY"
  >>= fun () ->
  let ssh_backend =
    Aegis_lm.Config_test_support.backend
      ~provider_id:"ssh-peer-primary"
      ~provider_kind:Aegis_lm.Config.Aegis_ssh_peer
      ~api_base:""
      ~upstream_model:"example-model"
      ~api_key_env:"AEGISLM_SSH_PEER_TEST_KEY"
      ~ssh_transport:
        (Aegis_lm.Config_test_support.ssh_transport
           ~destination:"ops@machine-a.example.net"
           ~host:"machine-a.example.net"
           ~remote_worker_command:"/opt/aegis-lm/scripts/remote_worker.sh"
           ())
      ()
  in
  let ssh_provider = Aegis_lm.Provider_registry.make ssh_backend in
  ssh_provider.Aegis_lm.Provider_client.invoke_embeddings
    { Aegis_lm.Provider_client.peer_headers = []; peer_context = None }
    ssh_backend
    request
  >>= function
  | Ok _ -> Alcotest.fail "expected missing ssh peer credential failure"
  | Error err ->
    Alcotest.(check string)
      "ssh peer reports missing env"
      "Missing environment variable AEGISLM_SSH_PEER_TEST_KEY"
      err.Aegis_lm.Domain_error.message;
    Lwt.return_unit
;;

let ssh_peer_protocol_request_includes_mesh_test _switch () =
  let json =
    Aegis_lm.Ssh_peer_protocol.request_json
      ~request_id:"req-ssh"
      ~kind:Aegis_lm.Ssh_peer_protocol.Chat
      ~peer_context:{ Aegis_lm.Peer_mesh.request_id = "req-peer"; hop_count = 1 }
      (`Assoc [ "model", `String "remote"; "messages", `List [] ])
  in
  match json with
  | `Assoc fields ->
    Alcotest.(check string)
      "kind encoded"
      "chat"
      (match List.assoc_opt "kind" fields with
       | Some (`String value) -> value
       | _ -> "");
    (match List.assoc_opt "mesh" fields with
     | Some mesh_json ->
       (match Aegis_lm.Peer_mesh.of_yojson mesh_json with
        | Ok context ->
          Alcotest.(check string) "mesh request id kept" "req-peer" context.request_id;
          Alcotest.(check int) "mesh hop kept" 1 context.hop_count;
          Lwt.return_unit
        | Error field -> Alcotest.failf "expected valid mesh json, got %s" field)
     | None -> Alcotest.fail "expected mesh object")
  | _ -> Alcotest.fail "expected request object"
;;

let ssh_peer_protocol_surfaces_worker_error_test _switch () =
  let line =
    Yojson.Safe.to_string
      (`Assoc
        [ "ok", `Bool false
        ; "status", `Int 508
        ; "retryable", `Bool false
        ; ( "error"
          , `Assoc
              [ "message", `String "loop detected remotely"
              ; "type", `String "api_error"
              ; "code", `String "loop_detected"
              ] )
        ])
  in
  match Aegis_lm.Ssh_peer_protocol.chat_response_of_line ~provider_id:"ssh-peer" line with
  | Ok _ -> Alcotest.fail "expected remote worker error"
  | Error err ->
    Alcotest.(check string) "remote error code kept" "loop_detected" err.code;
    Alcotest.(check int) "remote error status kept" 508 err.status;
    Lwt.return_unit
;;

let peer_mesh_rejects_excessive_hop_count_test _switch () =
  let headers =
    Cohttp.Header.of_list
      [ "x-aegislm-request-id", "req-overflow"; "x-aegislm-hop-count", "2" ]
  in
  match Aegis_lm.Peer_mesh.context_of_headers (Aegis_lm.Security_policy.default ()) headers with
  | Ok _ -> Alcotest.fail "expected peer mesh hop rejection"
  | Error err ->
    Alcotest.(check string) "loop rejection code" "loop_detected" err.code;
    Alcotest.(check int) "loop rejection status" 508 err.status;
    Lwt.return_unit
;;

let router_adds_peer_mesh_headers_for_aegis_peer_test _switch () =
  let captured_headers : (string * string) list ref = ref [] in
  let cfg =
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"mesh-claude"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"peer-a"
                  ~provider_kind:Aegis_lm.Config.Aegis_peer
                  ~api_base:"https://peer-a.example.test/v1"
                  ~upstream_model:"claude-sonnet"
                  ~api_key_env:"PEER_A_KEY"
                  ()
              ]
            ()
        ]
      ()
  in
  let invoke_chat
    (upstream_context : Aegis_lm.Provider_client.upstream_context)
    _backend
    (request : Aegis_lm.Openai_types.chat_request)
    =
    captured_headers := upstream_context.peer_headers;
    Lwt.return
      (Ok
         (Aegis_lm.Provider_mock.sample_chat_response
            ~model:request.Aegis_lm.Openai_types.model
            ~content:"peer ok"
            ()))
  in
  let provider =
    { Aegis_lm.Provider_client.invoke_chat =
        invoke_chat
    ; invoke_chat_stream =
        (fun upstream_context backend request ->
          invoke_chat upstream_context backend request
          >|= Result.map Aegis_lm.Provider_stream.of_chat_response)
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Aegis_lm.Domain_error.unsupported_feature
                  "embeddings not used in peer mesh header test")))
    }
  in
  let store = Aegis_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg in
  let request =
    Aegis_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "mesh-claude"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Aegis_lm.Router.dispatch_chat
    ~peer_context:
      { Aegis_lm.Peer_mesh.request_id = "req-peer"; Aegis_lm.Peer_mesh.hop_count = 0 }
    store
    ~authorization:"Bearer sk-test"
    request
  >>= function
  | Error err ->
    Alcotest.failf "expected peer route success but got %s" (Aegis_lm.Domain_error.to_string err)
  | Ok _response ->
    let request_id = List.assoc_opt "x-aegislm-request-id" !captured_headers in
    let hop_count = List.assoc_opt "x-aegislm-hop-count" !captured_headers in
    Alcotest.(check (option string))
      "peer request id forwarded"
      (Some "req-peer")
      request_id;
    Alcotest.(check (option string))
      "peer hop incremented"
      (Some "1")
      hop_count;
    Lwt.return_unit
;;

let persistent_budget_survives_restart_test _switch () =
  let db_path = Filename.temp_file "aegislm-budget" ".sqlite" in
  let base_config =
    Aegis_lm.Config_test_support.sample_config
      ~virtual_keys:
        [ Aegis_lm.Config_test_support.virtual_key
            ~token_plaintext:"sk-persist"
            ~name:"persist"
            ~daily_token_budget:5
            ()
        ]
      ()
  in
  let config =
    { base_config with
      Aegis_lm.Config.persistence = { sqlite_path = Some db_path; busy_timeout_ms = 5000 }
    }
  in
  let store1 = Aegis_lm.Runtime_state.create config in
  let principal1 =
    match Aegis_lm.Auth.authenticate store1 ~authorization:"Bearer sk-persist" with
    | Ok principal -> principal
    | Error _ -> failwith "expected auth success"
  in
  Alcotest.(check bool)
    "first persisted debit succeeds"
    true
    (match Aegis_lm.Budget_ledger.consume store1 ~principal:principal1 ~tokens:3 with
     | Ok () -> true
     | Error _ -> false);
  let store2 = Aegis_lm.Runtime_state.create config in
  let principal2 =
    match Aegis_lm.Auth.authenticate store2 ~authorization:"Bearer sk-persist" with
    | Ok principal -> principal
    | Error _ -> failwith "expected auth success after reopen"
  in
  Alcotest.(check bool)
    "second persisted debit rejected"
    true
    (match Aegis_lm.Budget_ledger.consume store2 ~principal:principal2 ~tokens:3 with
     | Ok () -> false
     | Error _ -> true);
  Lwt.return_unit
;;

let audit_log_is_persisted_test _switch () =
  let db_path = Filename.temp_file "aegislm-audit" ".sqlite" in
  let base_config = Aegis_lm.Config_test_support.sample_config () in
  let config =
    { base_config with
      Aegis_lm.Config.persistence = { sqlite_path = Some db_path; busy_timeout_ms = 5000 }
    }
  in
  let store = Aegis_lm.Runtime_state.create config in
  Aegis_lm.Runtime_state.append_audit_event
    store
    { Aegis_lm.Persistent_store.event_type = "test.audit"
    ; principal_name = Some "test"
    ; route_model = Some "gpt-5-mini"
    ; provider_id = None
    ; status_code = 200
    ; details = `Assoc [ "result", `String "ok" ]
    };
  let count =
    match store.Aegis_lm.Runtime_state.persistent_store with
    | Some persistent_store -> Aegis_lm.Persistent_store.audit_count persistent_store
    | None -> failwith "expected persistent store"
  in
  Alcotest.(check int) "one audit row persisted" 1 count;
  Lwt.return_unit
;;

let terminal_client_resolves_single_plaintext_virtual_key_test _switch () =
  let config =
    Aegis_lm.Config_test_support.sample_config
      ~virtual_keys:
        [ Aegis_lm.Config_test_support.virtual_key
            ~name:"solo"
            ~token_plaintext:"sk-solo"
            ()
        ]
      ()
  in
  let store = Aegis_lm.Runtime_state.create config in
  match Aegis_lm.Terminal_client.resolve_authorization store () with
  | Error err ->
    Alcotest.failf
      "expected terminal client auth resolution success but got %s"
      (Aegis_lm.Domain_error.to_string err)
  | Ok authorization ->
    Alcotest.(check string) "bearer authorization synthesized" "Bearer sk-solo" authorization;
    Lwt.return_unit
;;

let terminal_client_infers_first_route_for_ask_test _switch () =
  let config =
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route ~public_model:"first-route" ~backends:[] ()
        ; Aegis_lm.Config_test_support.route ~public_model:"second-route" ~backends:[] ()
        ]
      ()
  in
  let store = Aegis_lm.Runtime_state.create config in
  match Aegis_lm.Terminal_client.build_ask_request store "hello" with
  | Error err ->
    Alcotest.failf
      "expected ask request build success but got %s"
      (Aegis_lm.Domain_error.to_string err)
  | Ok request ->
    Alcotest.(check string) "first route selected" "first-route" request.model;
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
  let base = Aegis_lm.Security_policy.default () in
  { base with
    Aegis_lm.Security_policy.client_ops =
      { files =
          { enabled = file_ops_enabled
          ; read_roots
          ; write_roots
          ; max_read_bytes
          ; max_write_bytes
          }
      ; exec =
          { enabled = exec_enabled
          ; working_roots
          ; timeout_ms
          ; max_output_bytes
          }
      }
  }
;;

let rec remove_path_recursively path =
  if Sys.file_exists path
  then
    match Unix.lstat path with
    | { Unix.st_kind = Unix.S_DIR; _ } ->
      Sys.readdir path
      |> Array.iter (fun entry ->
        remove_path_recursively (Filename.concat path entry));
      Unix.rmdir path
    | _ -> Unix.unlink path
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

let repo_root () =
  Sys.getcwd ()
  |> Filename.dirname
  |> Filename.dirname
  |> Filename.dirname
;;

let write_fixture_file path content =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel content)
;;

let json_assoc = function
  | `Assoc fields -> fields
  | _ -> Alcotest.fail "expected JSON object"
;;

let terminal_ops_lists_directory_within_allowed_root_test _switch () =
  with_temp_dir "aegislm-ops-list" (fun root ->
    let nested_dir = Filename.concat root "notes" in
    Unix.mkdir nested_dir 0o755;
    write_fixture_file (Filename.concat root "hello.txt") "hello";
    let store =
      Aegis_lm.Runtime_state.create
        (Aegis_lm.Config_test_support.sample_config
           ~security_policy:
             (client_ops_security_policy ~read_roots:[ root ] ~write_roots:[ root ] ())
           ())
    in
    Aegis_lm.Terminal_client.invoke_json
      store
      ~authorization:"Bearer sk-test"
      ~kind:Aegis_lm.Terminal_client.Ops
      (`Assoc [ "op", `String "list_dir"; "path", `String "." ])
    >>= function
    | Error err ->
      Alcotest.failf
        "expected list_dir success but got %s"
        (Aegis_lm.Domain_error.to_string err)
    | Ok response ->
      let fields =
        Aegis_lm.Terminal_client.response_to_yojson response |> json_assoc
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
      Alcotest.(check bool)
        "file entry present"
        true
        (List.mem "hello.txt" names);
      Alcotest.(check bool)
        "directory entry present"
        true
        (List.mem "notes" names);
      Lwt.return_unit)
;;

let terminal_ops_rejects_paths_outside_allowed_roots_test _switch () =
  with_temp_dir "aegislm-ops-deny" (fun root ->
    let store =
      Aegis_lm.Runtime_state.create
        (Aegis_lm.Config_test_support.sample_config
           ~security_policy:(client_ops_security_policy ~read_roots:[ root ] ())
           ())
    in
    Aegis_lm.Terminal_client.invoke_json
      store
      ~authorization:"Bearer sk-test"
      ~kind:Aegis_lm.Terminal_client.Ops
      (`Assoc [ "op", `String "read_file"; "path", `String "/etc/hosts" ])
    >>= function
    | Ok _ -> Alcotest.fail "expected read_file outside root to be denied"
    | Error err ->
      Alcotest.(check string) "denied code" "operation_denied" err.code;
      Lwt.return_unit)
;;

let terminal_ops_writes_base64_files_test _switch () =
  with_temp_dir "aegislm-ops-write" (fun root ->
    let payload = "binary-\000-content" in
    let encoded = Base64.encode_exn payload in
    let store =
      Aegis_lm.Runtime_state.create
        (Aegis_lm.Config_test_support.sample_config
           ~security_policy:
             (client_ops_security_policy ~read_roots:[ root ] ~write_roots:[ root ] ())
           ())
    in
    Aegis_lm.Terminal_client.invoke_json
      store
      ~authorization:"Bearer sk-test"
      ~kind:Aegis_lm.Terminal_client.Ops
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
        (Aegis_lm.Domain_error.to_string err)
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
  with_temp_dir "aegislm-ops-exec" (fun root ->
    let canonical_root = Unix.realpath root in
    write_fixture_file (Filename.concat canonical_root "marker.txt") "root-marker";
    let store =
      Aegis_lm.Runtime_state.create
        (Aegis_lm.Config_test_support.sample_config
           ~security_policy:
             (client_ops_security_policy
                ~file_ops_enabled:false
                ~exec_enabled:true
                ~working_roots:[ root ]
                ())
           ())
    in
    Aegis_lm.Terminal_client.invoke_json
      store
      ~authorization:"Bearer sk-test"
      ~kind:Aegis_lm.Terminal_client.Ops
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
        (Aegis_lm.Domain_error.to_string err)
    | Ok response ->
      let fields =
        Aegis_lm.Terminal_client.response_to_yojson response |> json_assoc
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
      Alcotest.(check string) "command resolves relative file in allowed cwd" "root-marker" stdout;
      Lwt.return_unit)
;;

let worker_processes_ops_requests_test _switch () =
  with_temp_dir "aegislm-ops-worker" (fun root ->
    write_fixture_file (Filename.concat root "worker.txt") "worker-data";
    let store =
      Aegis_lm.Runtime_state.create
        (Aegis_lm.Config_test_support.sample_config
           ~security_policy:(client_ops_security_policy ~read_roots:[ root ] ())
           ())
    in
    Aegis_lm.Terminal_worker.run_lines
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

let worker_rejects_malformed_json_lines_test _switch () =
  let store = Aegis_lm.Runtime_state.create (Aegis_lm.Config_test_support.sample_config ()) in
  Aegis_lm.Terminal_worker.run_lines store ~jobs:1 [ "{not-json" ]
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
    Lwt.finalize
      f
      (fun () ->
        Mutex.lock active_lock;
        active := !active - 1;
        Mutex.unlock active_lock;
        Lwt.return_unit)
  in
  let provider =
    { Aegis_lm.Provider_client.invoke_chat =
        (fun _headers _backend request ->
          with_active (fun () ->
            Lwt_unix.sleep 0.02
            >|= fun () ->
            Ok
              (Aegis_lm.Provider_mock.sample_chat_response
                 ~model:request.Aegis_lm.Openai_types.model
                 ~content:
                   (request.messages
                    |> List.rev
                    |> List.hd
                    |> fun message -> message.Aegis_lm.Openai_types.content)
                 ())))
    ; invoke_chat_stream =
        (fun _headers _backend request ->
          with_active (fun () ->
            Lwt_unix.sleep 0.02
            >|= fun () ->
            Ok
              (Aegis_lm.Provider_stream.of_chat_response
                 (Aegis_lm.Provider_mock.sample_chat_response
                    ~model:request.Aegis_lm.Openai_types.model
                    ~content:"stream"
                    ()))))
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Aegis_lm.Domain_error.unsupported_feature
                  "embeddings not used in worker concurrency test")))
    }
  in
  let store =
    Aegis_lm.Runtime_state.create
      ~provider_factory:(fun _ -> provider)
      (Aegis_lm.Config_test_support.sample_config
         ~routes:
           [ Aegis_lm.Config_test_support.route
               ~public_model:"gpt-4o-mini"
               ~backends:
                 [ Aegis_lm.Config_test_support.backend
                     ~provider_id:"worker-primary"
                     ~provider_kind:Aegis_lm.Config.Openai_compat
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
  Aegis_lm.Terminal_worker.run_lines store ~jobs:2 lines
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
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"claude-sonnet"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"anthropic-primary"
                  ~provider_kind:Aegis_lm.Config.Anthropic
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
    Aegis_lm.Starter_profile.route_statuses
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
    Aegis_lm.Starter_profile.presets
    |> List.filter (fun (preset : Aegis_lm.Starter_profile.provider_preset) ->
      List.mem preset.Aegis_lm.Starter_profile.public_model [ "claude-sonnet"; "qwen-plus" ])
  in
  let json =
    Aegis_lm.Starter_profile.config_json
      ~selected_presets:presets
      ~virtual_key_name:"local-dev"
      ~token_plaintext:"sk-local"
      ~daily_token_budget:50000
      ~requests_per_minute:30
      ~sqlite_path:"../var/aegislm.sqlite"
      ()
  in
  match json with
  | `Assoc fields ->
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

let starter_profile_masks_environment_values_test _switch () =
  let statuses =
    Aegis_lm.Starter_profile.env_statuses
      ~lookup:(function
        | "OPENAI_API_KEY" -> Some "sk-test-secret"
        | _ -> None)
      ()
  in
  match
    List.find_opt
      (fun (status : Aegis_lm.Starter_profile.env_status) ->
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
    Aegis_lm.Starter_profile.presets
    |> List.fold_left
         (fun acc (preset : Aegis_lm.Starter_profile.provider_preset) ->
           let current =
             match List.assoc_opt preset.provider_key acc with
             | Some value -> value
             | None -> 0
           in
           (preset.provider_key, current + 1)
           :: List.remove_assoc preset.provider_key acc)
         []
  in
  let expect provider_key =
    match List.assoc_opt provider_key counts with
    | Some count -> Alcotest.(check bool) provider_key true (count >= 3)
    | None -> Alcotest.failf "missing provider family %s" provider_key
  in
  List.iter expect [ "anthropic"; "openai"; "google"; "mistral"; "alibaba"; "moonshot" ];
  Lwt.return_unit
;;

let example_gateway_exposes_multiple_models_per_provider_test _switch () =
  let project_root = Filename.dirname (Filename.dirname (Filename.dirname (Sys.getcwd ()))) in
  let example_path =
    Filename.concat (Filename.concat project_root "config") "example.gateway.json"
  in
  match Aegis_lm.Config.load example_path with
  | Error err -> Alcotest.failf "failed to load example config: %s" err
  | Ok config ->
    let counts =
      config.Aegis_lm.Config.routes
      |> List.fold_left
           (fun acc (route : Aegis_lm.Config.route) ->
             match route.backends with
             | backend :: _ ->
               let key =
                 match backend.provider_kind with
                 | Aegis_lm.Config.Anthropic -> "anthropic"
                 | Aegis_lm.Config.Openai_compat -> "openai"
                 | Aegis_lm.Config.Google_openai -> "google"
                 | Aegis_lm.Config.Mistral_openai -> "mistral"
                 | Aegis_lm.Config.Alibaba_openai -> "alibaba"
                 | Aegis_lm.Config.Moonshot_openai -> "moonshot"
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
    List.iter expect [ "anthropic"; "openai"; "google"; "mistral"; "alibaba"; "moonshot" ];
    Lwt.return_unit
;;

let starter_profile_splits_ready_and_missing_routes_test _switch () =
  let config =
    Aegis_lm.Config_test_support.sample_config
      ~routes:
        [ Aegis_lm.Config_test_support.route
            ~public_model:"claude-sonnet"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"anthropic-primary"
                  ~provider_kind:Aegis_lm.Config.Anthropic
                  ~api_base:"https://api.anthropic.com/v1"
                  ~upstream_model:"claude-sonnet-4-5-20250929"
                  ~api_key_env:"ANTHROPIC_API_KEY"
                  ()
              ]
            ()
        ; Aegis_lm.Config_test_support.route
            ~public_model:"gpt-5-mini"
            ~backends:
              [ Aegis_lm.Config_test_support.backend
                  ~provider_id:"openai-primary"
                  ~provider_kind:Aegis_lm.Config.Openai_compat
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
    Aegis_lm.Starter_profile.route_statuses
      ~lookup:(function
        | "ANTHROPIC_API_KEY" -> Some "present"
        | _ -> None)
      config
    |> Aegis_lm.Starter_profile.split_route_statuses
  in
  Alcotest.(check int) "one ready route" 1 (List.length ready);
  Alcotest.(check int) "one missing route" 1 (List.length missing);
  Lwt.return_unit
;;

let starter_session_parses_beginner_commands_test _switch () =
  (match Aegis_lm.Starter_session.parse_command "/tools" with
   | Aegis_lm.Starter_session.Show_tools -> ()
   | _ -> Alcotest.fail "expected /tools command");
  (match Aegis_lm.Starter_session.parse_command "/admin enable local file access in this repo" with
   | Aegis_lm.Starter_session.Admin_request goal ->
     Alcotest.(check string)
       "admin goal"
       "enable local file access in this repo"
       goal
   | _ -> Alcotest.fail "expected /admin command");
  (match Aegis_lm.Starter_session.parse_command "/admin" with
   | Aegis_lm.Starter_session.Invalid _ -> ()
   | _ -> Alcotest.fail "expected invalid /admin without argument");
  (match Aegis_lm.Starter_session.parse_command "/package" with
   | Aegis_lm.Starter_session.Package_request -> ()
   | _ -> Alcotest.fail "expected /package command");
  (match Aegis_lm.Starter_session.parse_command "/plan" with
   | Aegis_lm.Starter_session.Show_admin_plan -> ()
   | _ -> Alcotest.fail "expected /plan command");
  (match Aegis_lm.Starter_session.parse_command "/apply" with
   | Aegis_lm.Starter_session.Apply_admin_plan -> ()
   | _ -> Alcotest.fail "expected /apply command");
  (match Aegis_lm.Starter_session.parse_command "/discard" with
   | Aegis_lm.Starter_session.Discard_admin_plan -> ()
   | _ -> Alcotest.fail "expected /discard command");
  (match Aegis_lm.Starter_session.parse_command "/env" with
   | Aegis_lm.Starter_session.Show_env -> ()
   | _ -> Alcotest.fail "expected /env command");
  (match Aegis_lm.Starter_session.parse_command "/providers" with
   | Aegis_lm.Starter_session.Show_providers -> ()
   | _ -> Alcotest.fail "expected /providers command");
  (match Aegis_lm.Starter_session.parse_command "/file README.md" with
   | Aegis_lm.Starter_session.Attach_file path ->
     Alcotest.(check string) "file path" "README.md" path
   | _ -> Alcotest.fail "expected /file command");
  (match Aegis_lm.Starter_session.parse_command "/file" with
   | Aegis_lm.Starter_session.Invalid _ -> ()
   | _ -> Alcotest.fail "expected invalid /file without argument");
  (match Aegis_lm.Starter_session.parse_command "/files" with
   | Aegis_lm.Starter_session.Show_pending_files -> ()
   | _ -> Alcotest.fail "expected /files command");
  (match Aegis_lm.Starter_session.parse_command "/clearfiles" with
   | Aegis_lm.Starter_session.Clear_pending_files -> ()
   | _ -> Alcotest.fail "expected /clearfiles command");
  (match Aegis_lm.Starter_session.parse_command "/swap claude-sonnet" with
   | Aegis_lm.Starter_session.Swap_model model ->
     Alcotest.(check string) "swap target" "claude-sonnet" model
   | _ -> Alcotest.fail "expected /swap command");
  (match Aegis_lm.Starter_session.parse_command "/swap" with
   | Aegis_lm.Starter_session.Invalid _ -> ()
   | _ -> Alcotest.fail "expected invalid /swap without argument");
  (match Aegis_lm.Starter_session.parse_command "/memory" with
   | Aegis_lm.Starter_session.Show_memory -> ()
   | _ -> Alcotest.fail "expected /memory command");
  (match Aegis_lm.Starter_session.parse_command "/forget" with
   | Aegis_lm.Starter_session.Forget_memory -> ()
   | _ -> Alcotest.fail "expected /forget command");
  (match Aegis_lm.Starter_session.parse_command "/thread on" with
   | Aegis_lm.Starter_session.Set_thread true -> ()
   | _ -> Alcotest.fail "expected /thread on command");
  (match Aegis_lm.Starter_session.parse_command "/thread off" with
   | Aegis_lm.Starter_session.Set_thread false -> ()
   | _ -> Alcotest.fail "expected /thread off command");
  (match Aegis_lm.Starter_session.parse_command "/thread maybe" with
   | Aegis_lm.Starter_session.Invalid _ -> ()
  | _ -> Alcotest.fail "expected invalid /thread argument");
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
    { Aegis_lm.Starter_attachment.absolute_path = "/tmp/example.txt"
    ; display_path = "/tmp/example.txt"
    ; content = "alpha\nbeta"
    ; truncated = false
    ; byte_count = 10
    }
  in
  let prompt =
    Aegis_lm.Starter_attachment.inject_into_prompt [ attachment ] "summarize this"
  in
  Alcotest.(check bool) "mentions file path" true (contains ~sub:"/tmp/example.txt" prompt);
  Alcotest.(check bool) "mentions file content" true (contains ~sub:"alpha\nbeta" prompt);
  Alcotest.(check bool) "mentions user request" true (contains ~sub:"summarize this" prompt);
  Lwt.return_unit
;;

let starter_session_tracks_streaming_state_test _switch () =
  let state =
    Aegis_lm.Starter_session.create
      ~model:"claude-sonnet"
      ~config_path:"config/starter.gateway.json"
  in
  let streaming_state, effect = Aegis_lm.Starter_session.step state "Hello there" in
  (match effect with
   | Aegis_lm.Starter_session.Begin_prompt "Hello there" -> ()
   | _ -> Alcotest.fail "expected prompt execution effect");
  (match Aegis_lm.Starter_session.current_model streaming_state with
   | Some "claude-sonnet" -> ()
   | _ -> Alcotest.fail "expected streaming model context");
  let busy_state, busy_effect = Aegis_lm.Starter_session.step streaming_state "/env" in
  (match busy_effect with
   | Aegis_lm.Starter_session.Print_message message ->
     Alcotest.(check string)
       "busy message"
       Aegis_lm.Starter_constants.Text.busy_message
       message
   | _ -> Alcotest.fail "expected busy message");
  let resumed_state = Aegis_lm.Starter_session.interrupt_stream busy_state in
  (match resumed_state with
   | Aegis_lm.Starter_session.Ready _ -> ()
   | _ -> Alcotest.fail "expected ready state after interrupt");
  Lwt.return_unit
;;

let starter_session_toggles_conversation_mode_test _switch () =
  let state =
    Aegis_lm.Starter_session.create
      ~model:"claude-sonnet"
      ~config_path:"config/starter.gateway.json"
  in
  Alcotest.(check bool)
    "conversation starts enabled"
    true
    (Aegis_lm.Starter_session.conversation_enabled state);
  let state, effect = Aegis_lm.Starter_session.step state "/thread off" in
  (match effect with
   | Aegis_lm.Starter_session.Update_thread false -> ()
   | _ -> Alcotest.fail "expected thread update effect");
  Alcotest.(check bool)
    "conversation disabled"
    false
    (Aegis_lm.Starter_session.conversation_enabled state);
  let state, effect = Aegis_lm.Starter_session.step state "/thread on" in
  (match effect with
   | Aegis_lm.Starter_session.Update_thread true -> ()
   | _ -> Alcotest.fail "expected thread update effect");
  Alcotest.(check bool)
    "conversation re-enabled"
    true
    (Aegis_lm.Starter_session.conversation_enabled state);
  Lwt.return_unit
;;

let starter_conversation_compresses_old_turns_test _switch () =
  let user_text = String.make 1700 'u' in
  let assistant_text = String.make 1700 'a' in
  let rec loop conversation count last_event =
    if count = 0
    then conversation, last_event
    else
      let conversation, event =
        Aegis_lm.Starter_conversation.commit_exchange
          conversation
          ~user:user_text
          ~assistant:assistant_text
      in
      loop conversation (count - 1) (match event with None -> last_event | some -> some)
  in
  let conversation, event = loop Aegis_lm.Starter_conversation.empty 4 None in
  let stats = Aegis_lm.Starter_conversation.stats conversation in
  Alcotest.(check bool) "compression happened" true (Option.is_some event);
  Alcotest.(check int)
    "keeps latest recent turns"
    Aegis_lm.Starter_constants.Defaults.conversation_keep_recent_turns
    stats.recent_turn_count;
  Alcotest.(check bool) "compressed turns tracked" true (stats.compressed_turn_count >= 2);
  Alcotest.(check bool) "summary exists" true (stats.summary_char_count > 0);
  Lwt.return_unit
;;

let starter_conversation_request_messages_include_summary_test _switch () =
  let conversation =
    [ ("first question", "first answer")
    ; ("second question", "second answer")
    ; ("third question", "third answer")
    ; ("fourth question", "fourth answer")
    ]
    |> List.map (fun (user, assistant) ->
      String.concat " " [ user; String.make 1600 'x' ],
      String.concat " " [ assistant; String.make 1600 'y' ])
    |> List.fold_left
         (fun conversation (user, assistant) ->
           Aegis_lm.Starter_conversation.commit_exchange conversation ~user ~assistant
           |> fst)
         Aegis_lm.Starter_conversation.empty
  in
  let messages =
    Aegis_lm.Starter_conversation.request_messages conversation ~pending_user:"next question"
  in
  (match messages with
   | first :: _ ->
     Alcotest.(check string) "summary is injected as system" "system" first.Aegis_lm.Openai_types.role
   | [] -> Alcotest.fail "expected messages");
  (match List.rev messages with
   | last :: _ ->
     Alcotest.(check string) "pending user kept last" "user" last.Aegis_lm.Openai_types.role;
     Alcotest.(check string) "pending user content" "next question" last.content
  | [] -> Alcotest.fail "expected last message");
  Lwt.return_unit
;;

let starter_terminal_completes_commands_and_models_test _switch () =
  let context =
    { Aegis_lm.Starter_terminal.commands =
        [ "/help"; "/models"; "/memory"; "/swap"; "/thread"; "/quit"; "/tools"; "/file" ]
    ; models = [ "claude-sonnet"; "gpt-5-mini" ]
    }
  in
  let slash_candidates =
    Aegis_lm.Starter_terminal.completion_candidates ~context "/m"
  in
  Alcotest.(check (list string))
    "slash command completion"
    [ "/memory"; "/models" ]
    slash_candidates;
  let swap_candidates =
    Aegis_lm.Starter_terminal.completion_candidates ~context "/swap c"
  in
  Alcotest.(check (list string))
    "model completion after swap"
    [ "/swap claude-sonnet" ]
    swap_candidates;
  let thread_candidates =
    Aegis_lm.Starter_terminal.completion_candidates ~context "/thread o"
  in
  Alcotest.(check (list string))
    "thread completion"
    [ "/thread on"; "/thread off" ]
    thread_candidates;
  let tool_candidates =
    Aegis_lm.Starter_terminal.completion_candidates ~context "/to"
  in
  Alcotest.(check (list string))
    "tools command completion"
    [ "/tools" ]
    tool_candidates;
  Lwt.return_unit
;;

let starter_terminal_history_file_prefers_override_test _switch () =
  let file =
    Aegis_lm.Starter_terminal.history_file
      ~history_env:"/tmp/custom-history.txt"
      ~home:"/Users/example"
      ()
  in
  Alcotest.(check string) "history override wins" "/tmp/custom-history.txt" file;
  let fallback =
    Aegis_lm.Starter_terminal.history_file
      ~history_env:""
      ~home:"/Users/example"
      ()
  in
  Alcotest.(check string)
    "history fallback path"
    "/Users/example/.aegislm/starter.history"
    fallback;
  Lwt.return_unit
;;

let starter_packaging_detects_supported_hosts_test _switch () =
  (match
     Aegis_lm.Starter_packaging.host_os_of_values
       ~uname_s:"Darwin"
       ~os_release:""
   with
   | Ok Aegis_lm.Starter_packaging.Macos -> ()
   | _ -> Alcotest.fail "expected macos host detection");
  (match
     Aegis_lm.Starter_packaging.host_os_of_values
       ~uname_s:"Linux"
       ~os_release:"ID=ubuntu\nNAME=Ubuntu\n"
   with
   | Ok Aegis_lm.Starter_packaging.Ubuntu -> ()
   | _ -> Alcotest.fail "expected ubuntu host detection");
  (match
     Aegis_lm.Starter_packaging.host_os_of_values
       ~uname_s:"FreeBSD"
       ~os_release:""
   with
   | Ok Aegis_lm.Starter_packaging.Freebsd -> ()
   | _ -> Alcotest.fail "expected freebsd host detection");
  Lwt.return_unit
;;

let starter_packaging_defaults_are_os_specific_test _switch () =
  let mac_request =
    Aegis_lm.Starter_packaging.default_request
      ~config_path:"config/example.gateway.json"
      Aegis_lm.Starter_packaging.Macos
  in
  let ubuntu_request =
    Aegis_lm.Starter_packaging.default_request
      ~config_path:"config/example.gateway.json"
      Aegis_lm.Starter_packaging.Ubuntu
  in
  let freebsd_request =
    Aegis_lm.Starter_packaging.default_request
      ~config_path:"config/example.gateway.json"
      Aegis_lm.Starter_packaging.Freebsd
  in
  Alcotest.(check string) "mac install root" "/opt/aegis-lm" mac_request.install_root;
  Alcotest.(check string) "ubuntu wrapper dir" "/usr/bin" ubuntu_request.wrapper_dir;
  Alcotest.(check string)
    "freebsd install root"
    "/usr/local/lib/aegis-lm"
    freebsd_request.install_root;
  Alcotest.(check string)
    "freebsd package format"
    ".pkg"
    (Aegis_lm.Starter_packaging.package_format_label Aegis_lm.Starter_packaging.Freebsd);
  Lwt.return_unit
;;

let admin_assistant_parses_plan_text_test _switch () =
  let raw_response =
    {|Plan follows:
{"kid_summary":"Open safe local file access for this repository.","why":["AegisLM config comes first."],"warnings":["System actions remain bounded by policy."],"config_ops":[{"op":"set_json","target":"security_policy","path":"/client_ops/files/enabled","value":true},{"op":"append_json","target":"security_policy","path":"/client_ops/files/read_roots","value":"/tmp/aegis","unique":true}],"system_ops":[{"op":"list_dir","path":"."}]}
|}
  in
  match Aegis_lm.Admin_assistant.parse_plan_text raw_response with
  | Error err ->
    Alcotest.failf
      "expected admin plan parse success but got %s"
      (Aegis_lm.Domain_error.to_string err)
  | Ok plan ->
    Alcotest.(check string)
      "kid summary"
      "Open safe local file access for this repository."
      plan.Aegis_lm.Admin_assistant_plan.kid_summary;
    Alcotest.(check int)
      "config op count"
      2
      (List.length plan.Aegis_lm.Admin_assistant_plan.config_ops);
    Alcotest.(check int)
      "system op count"
      1
      (List.length plan.Aegis_lm.Admin_assistant_plan.system_ops);
    Lwt.return_unit
;;

let starter_runtime_tracks_pending_admin_plan_test _switch () =
  let pending_plan =
    { Aegis_lm.Admin_assistant.goal = "enable local admin"
    ; plan =
        { Aegis_lm.Admin_assistant_plan.kid_summary = "Make the config easier."
        ; why = [ "Because the user asked." ]
        ; warnings = []
        ; config_ops = []
        ; system_ops = []
        }
    ; raw_response = "{}"
    }
  in
  let runtime =
    Aegis_lm.Starter_runtime.create ()
    |> fun runtime -> Aegis_lm.Starter_runtime.set_pending_admin_plan runtime (Some pending_plan)
  in
  Alcotest.(check bool)
    "pending plan stored"
    true
    (Option.is_some runtime.Aegis_lm.Starter_runtime.pending_admin_plan);
  let runtime = Aegis_lm.Starter_runtime.clear_pending_admin_plan runtime in
  Alcotest.(check bool)
    "pending plan cleared"
    false
    (Option.is_some runtime.Aegis_lm.Starter_runtime.pending_admin_plan);
  Lwt.return_unit
;;

let admin_assistant_applies_config_edits_test _switch () =
  with_temp_dir "aegislm-admin-config" (fun root ->
    let security_path = Filename.concat root "security.json" in
    let gateway_path = Filename.concat root "gateway.json" in
    Yojson.Safe.to_file
      security_path
      (Yojson.Safe.from_file
         (Filename.concat (repo_root ()) "config/defaults/security_policy.json"));
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
                            ] ] )
                  ] ] )
        ; ( "virtual_keys"
          , `List
              [ `Assoc
                  [ "name", `String "local-dev"
                  ; "token_plaintext", `String "sk-test"
                  ; "daily_token_budget", `Int 1000
                  ; "requests_per_minute", `Int 60
                  ; "allowed_routes", `List [ `String "starter-admin" ]
                  ] ] )
        ] );
    let plan =
      { Aegis_lm.Admin_assistant_plan.kid_summary =
          "Turn on local file admin only for this temporary directory."
      ; why = [ "The config changes stay local." ]
      ; warnings = []
      ; config_ops =
          [ Aegis_lm.Admin_assistant_plan.Set_json
              { target = Aegis_lm.Admin_assistant_plan.Security_policy
              ; path = "/client_ops/files/enabled"
              ; value = `Bool true
              }
          ; Aegis_lm.Admin_assistant_plan.Append_json
              { target = Aegis_lm.Admin_assistant_plan.Security_policy
              ; path = "/client_ops/files/read_roots"
              ; value = `String root
              ; unique = true
              }
          ; Aegis_lm.Admin_assistant_plan.Append_json
              { target = Aegis_lm.Admin_assistant_plan.Security_policy
              ; path = "/client_ops/files/write_roots"
              ; value = `String root
              ; unique = true
              }
          ; Aegis_lm.Admin_assistant_plan.Set_json
              { target = Aegis_lm.Admin_assistant_plan.Gateway_config
              ; path = "/routes/0/public_model"
              ; value = `String "starter-admin-ready"
              }
          ]
      ; system_ops = []
      }
    in
    match Aegis_lm.Admin_assistant.apply_config_edits ~config_path:gateway_path plan with
    | Error err ->
      Alcotest.failf
        "expected config edits success but got %s"
        (Aegis_lm.Domain_error.to_string err)
    | Ok applied_lines ->
      Alcotest.(check bool) "applied lines reported" true (applied_lines <> []);
      (match Aegis_lm.Config.load gateway_path with
       | Error err -> Alcotest.failf "expected reloaded config success: %s" err
       | Ok config ->
         (match config.Aegis_lm.Config.routes with
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
  [ Alcotest_lwt.test_case "redacts secrets recursively" `Quick secret_redaction_test
  ; Alcotest_lwt.test_case
      "rejects unknown virtual key"
      `Quick
      auth_rejects_unknown_key_test
  ; Alcotest_lwt.test_case "enforces daily budget" `Quick budget_blocks_after_limit_test
  ; Alcotest_lwt.test_case
      "uses fallback provider"
      `Quick
      routing_uses_fallback_after_failure_test
  ; Alcotest_lwt.test_case
      "falls back on retryable upstream status"
      `Quick
      routing_falls_back_on_retryable_upstream_status_test
  ; Alcotest_lwt.test_case
      "stops on non-retryable upstream status"
      `Quick
      routing_stops_on_non_retryable_upstream_status_test
  ; Alcotest_lwt.test_case "blocks localhost egress" `Quick egress_blocks_localhost_test
  ; Alcotest_lwt.test_case
      "enforces request body limit"
      `Quick
      request_body_limit_is_enforced_test
  ; Alcotest_lwt.test_case
      "terminal ops lists directory within allowed root"
      `Quick
      terminal_ops_lists_directory_within_allowed_root_test
  ; Alcotest_lwt.test_case
      "terminal ops reject paths outside allowed roots"
      `Quick
      terminal_ops_rejects_paths_outside_allowed_roots_test
  ; Alcotest_lwt.test_case
      "terminal ops write base64 files"
      `Quick
      terminal_ops_writes_base64_files_test
  ; Alcotest_lwt.test_case
      "terminal ops execute commands in allowed root"
      `Quick
      terminal_ops_executes_commands_in_allowed_root_test
  ; Alcotest_lwt.test_case
      "budget ledger is domain-safe"
      `Quick
      budget_is_domain_safe_test
  ; Alcotest_lwt.test_case
      "falls back after provider exception"
      `Quick
      routing_falls_back_after_provider_exception_test
  ; Alcotest_lwt.test_case
      "times out slow provider calls"
      `Quick
      routing_times_out_slow_provider_test
  ; Alcotest_lwt.test_case
      "embeddings fall back on retryable failure"
      `Quick
      embeddings_fall_back_on_retryable_failure_test
  ; Alcotest_lwt.test_case
      "responses parses string input"
      `Quick
      responses_request_accepts_string_input_test
  ; Alcotest_lwt.test_case
      "responses wraps chat result"
      `Quick
      responses_wrap_chat_response_test
  ; Alcotest_lwt.test_case
      "chat sse contains done marker"
      `Quick
      chat_sse_contains_done_marker_test
  ; Alcotest_lwt.test_case
      "responses sse contains completion event"
      `Quick
      responses_sse_contains_completion_event_test
  ; Alcotest_lwt.test_case
      "chat stream response closes handle"
      `Quick
      chat_stream_response_closes_handle_test
  ; Alcotest_lwt.test_case
      "config parses openai-compatible provider variants"
      `Quick
      config_load_accepts_openai_compatible_provider_variants_test
  ; Alcotest_lwt.test_case
      "provider registry maps new openai-compatible kinds"
      `Quick
      provider_registry_routes_new_openai_compatible_kinds_test
  ; Alcotest_lwt.test_case
      "ssh peer protocol request includes mesh"
      `Quick
      ssh_peer_protocol_request_includes_mesh_test
  ; Alcotest_lwt.test_case
      "ssh peer protocol surfaces worker error"
      `Quick
      ssh_peer_protocol_surfaces_worker_error_test
  ; Alcotest_lwt.test_case
      "peer mesh rejects excessive hop count"
      `Quick
      peer_mesh_rejects_excessive_hop_count_test
  ; Alcotest_lwt.test_case
      "router adds peer mesh headers for aegis peer backends"
      `Quick
      router_adds_peer_mesh_headers_for_aegis_peer_test
  ; Alcotest_lwt.test_case
      "persistent budget survives restart"
      `Quick
      persistent_budget_survives_restart_test
  ; Alcotest_lwt.test_case "audit log is persisted" `Quick audit_log_is_persisted_test
  ; Alcotest_lwt.test_case
      "terminal client resolves single plaintext virtual key"
      `Quick
      terminal_client_resolves_single_plaintext_virtual_key_test
  ; Alcotest_lwt.test_case
      "terminal client infers first route for ask"
      `Quick
      terminal_client_infers_first_route_for_ask_test
  ; Alcotest_lwt.test_case
      "worker processes ops requests"
      `Quick
      worker_processes_ops_requests_test
  ; Alcotest_lwt.test_case
      "worker rejects malformed json lines"
      `Quick
      worker_rejects_malformed_json_lines_test
  ; Alcotest_lwt.test_case
      "worker processes requests with bounded parallelism"
      `Quick
      worker_processes_requests_with_bounded_parallelism_test
  ; Alcotest_lwt.test_case
      "starter profile marks route ready from env lookup"
      `Quick
      starter_profile_marks_route_ready_from_env_lookup_test
  ; Alcotest_lwt.test_case
      "starter profile writes portable config json"
      `Quick
      starter_profile_writes_portable_config_json_test
  ; Alcotest_lwt.test_case
      "starter profile masks environment values"
      `Quick
      starter_profile_masks_environment_values_test
  ; Alcotest_lwt.test_case
      "starter profile exposes multiple models per provider"
      `Quick
      starter_profile_exposes_multiple_models_per_provider_test
  ; Alcotest_lwt.test_case
      "example gateway exposes multiple models per provider"
      `Quick
      example_gateway_exposes_multiple_models_per_provider_test
  ; Alcotest_lwt.test_case
      "starter profile splits ready and missing routes"
      `Quick
      starter_profile_splits_ready_and_missing_routes_test
  ; Alcotest_lwt.test_case
      "starter session parses beginner commands"
      `Quick
      starter_session_parses_beginner_commands_test
  ; Alcotest_lwt.test_case
      "starter attachment injects file content into prompt"
      `Quick
      starter_attachment_injects_file_content_into_prompt_test
  ; Alcotest_lwt.test_case
      "admin assistant parses structured plan text"
      `Quick
      admin_assistant_parses_plan_text_test
  ; Alcotest_lwt.test_case
      "starter runtime tracks pending admin plan"
      `Quick
      starter_runtime_tracks_pending_admin_plan_test
  ; Alcotest_lwt.test_case
      "admin assistant applies config edits"
      `Quick
      admin_assistant_applies_config_edits_test
  ; Alcotest_lwt.test_case
      "starter session tracks streaming state"
      `Quick
      starter_session_tracks_streaming_state_test
  ; Alcotest_lwt.test_case
      "starter session toggles conversation mode"
      `Quick
      starter_session_toggles_conversation_mode_test
  ; Alcotest_lwt.test_case
      "starter conversation compresses old turns"
      `Quick
      starter_conversation_compresses_old_turns_test
  ; Alcotest_lwt.test_case
      "starter conversation request messages include summary"
      `Quick
      starter_conversation_request_messages_include_summary_test
  ; Alcotest_lwt.test_case
      "starter terminal completes commands and models"
      `Quick
      starter_terminal_completes_commands_and_models_test
  ; Alcotest_lwt.test_case
      "starter terminal history file prefers override"
      `Quick
      starter_terminal_history_file_prefers_override_test
  ; Alcotest_lwt.test_case
      "starter packaging detects supported hosts"
      `Quick
      starter_packaging_detects_supported_hosts_test
  ; Alcotest_lwt.test_case
      "starter packaging defaults are os specific"
      `Quick
      starter_packaging_defaults_are_os_specific_test
  ]
;;

let () = Lwt_main.run (Alcotest_lwt.run "aegis-lm" [ "core", tests ])
