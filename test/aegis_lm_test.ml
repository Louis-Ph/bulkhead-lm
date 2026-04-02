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
  Alcotest.(check int)
    "successful budget debits"
    max_tokens
    (Atomic.get success_count);
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
  let provider =
    { Aegis_lm.Provider_client.invoke_chat =
        (fun backend _request ->
          match backend.Aegis_lm.Config.upstream_model with
          | "bad-model" -> failwith "provider exploded"
          | "good-model" ->
            Lwt.return
              (Ok
                 (Aegis_lm.Provider_mock.sample_chat_response
                    ~model:"good-model"
                    ~content:"ok"
                    ()))
          | _ -> failwith "unexpected model")
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
  ; Alcotest_lwt.test_case "blocks localhost egress" `Quick egress_blocks_localhost_test
  ; Alcotest_lwt.test_case "budget ledger is domain-safe" `Quick budget_is_domain_safe_test
  ; Alcotest_lwt.test_case
      "falls back after provider exception"
      `Quick
      routing_falls_back_after_provider_exception_test
  ; Alcotest_lwt.test_case
      "responses parses string input"
      `Quick
      responses_request_accepts_string_input_test
  ; Alcotest_lwt.test_case
      "responses wraps chat result"
      `Quick
      responses_wrap_chat_response_test
  ]
;;

let () = Lwt_main.run (Alcotest_lwt.run "aegis-lm" [ "core", tests ])
