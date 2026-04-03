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
  let denied = Aegis_lm.Egress_policy.ensure_allowed policy "http://127.0.0.1:8080/v1" in
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
  let invoke_chat backend _request =
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
        (fun backend request ->
          invoke_chat backend request
          >|= Result.map Aegis_lm.Provider_stream.of_chat_response)
    ; invoke_embeddings =
        (fun _backend _request ->
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
  let invoke_chat _backend _request =
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
        (fun backend request ->
          invoke_chat backend request
          >|= Result.map Aegis_lm.Provider_stream.of_chat_response)
    ; invoke_embeddings =
        (fun _backend _request ->
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
        (fun _backend _request ->
          Lwt.return
            (Error (Aegis_lm.Domain_error.unsupported_feature "chat not used in embeddings test")))
    ; invoke_chat_stream =
        (fun _backend _request ->
          Lwt.return
            (Error
               (Aegis_lm.Domain_error.unsupported_feature
                  "chat streaming not used in embeddings test")))
    ; invoke_embeddings =
        (fun backend request ->
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

let config_load_accepts_alibaba_and_moonshot_kinds_test _switch () =
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
        | [ alibaba; moonshot ] ->
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
               moonshot.Aegis_lm.Config.provider_kind)
        | _ -> Alcotest.fail "expected two backends")
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
    provider.Aegis_lm.Provider_client.invoke_embeddings backend request
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
  assert_openai_compat Aegis_lm.Config.Alibaba_openai "alibaba-primary" "DASHSCOPE_TEST_KEY"
  >>= fun () ->
  assert_openai_compat
    Aegis_lm.Config.Moonshot_openai
    "moonshot-primary"
    "MOONSHOT_TEST_KEY"
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
      "config parses alibaba and moonshot kinds"
      `Quick
      config_load_accepts_alibaba_and_moonshot_kinds_test
  ; Alcotest_lwt.test_case
      "provider registry maps new openai-compatible kinds"
      `Quick
      provider_registry_routes_new_openai_compatible_kinds_test
  ; Alcotest_lwt.test_case
      "persistent budget survives restart"
      `Quick
      persistent_budget_survives_restart_test
  ; Alcotest_lwt.test_case "audit log is persisted" `Quick audit_log_is_persisted_test
  ]
;;

let () = Lwt_main.run (Alcotest_lwt.run "aegis-lm" [ "core", tests ])
