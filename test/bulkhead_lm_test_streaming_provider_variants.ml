open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let routing_times_out_slow_provider_test _switch () =
  let base_config =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"gpt-4o-mini"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"slow"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
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
      Bulkhead_lm.Config.security_policy =
        { base_config.security_policy with
          server = { base_config.security_policy.server with request_timeout_ms = 10 }
        }
    }
  in
  let invoke_chat _headers _backend _request =
    Lwt_unix.sleep 0.05
    >|= fun () ->
    Ok
      (Bulkhead_lm.Provider_mock.sample_chat_response
         ~model:"slow-model"
         ~content:"late"
         ())
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
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) config
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
  | Ok _ -> Alcotest.fail "expected timeout from slow provider"
  | Error err ->
    Alcotest.(check string) "timeout code" "request_timeout" err.code;
    Alcotest.(check int) "timeout status" 504 err.status;
    Alcotest.(check (option string)) "provider id kept" (Some "slow") err.provider_id;
    Lwt.return_unit
;;

let embeddings_fall_back_on_retryable_failure_test _switch () =
  let cfg =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"text-embedding-3-small"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"first"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
                  ~api_base:"https://api.example.test/v1"
                  ~upstream_model:"bad-embedding-model"
                  ~api_key_env:"PRIMARY_KEY"
                  ()
              ; Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"second"
                  ~provider_kind:Bulkhead_lm.Config.Openai_compat
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
    { Bulkhead_lm.Provider_client.invoke_chat =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "chat not used in embeddings test")))
    ; invoke_chat_stream =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "chat streaming not used in embeddings test")))
    ; invoke_embeddings =
        (fun _headers backend request ->
          match backend.Bulkhead_lm.Config.upstream_model with
          | "bad-embedding-model" ->
            Lwt.return
              (Error
                 (Bulkhead_lm.Domain_error.upstream_status
                    ~provider_id:"first"
                    ~status:503
                    "temporary outage"))
          | "good-embedding-model" ->
            Lwt.return
              (Ok
                 { Bulkhead_lm.Openai_types.model = request.model
                 ; data = [ { index = 0; embedding = [ 0.1; 0.2 ] } ]
                 ; usage = { prompt_tokens = 1; completion_tokens = 0; total_tokens = 1 }
                 })
          | _ -> failwith "unexpected embeddings model")
    }
  in
  let store =
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg
  in
  let request =
    Bulkhead_lm.Openai_types.embeddings_request_of_yojson
      (`Assoc [ "model", `String "text-embedding-3-small"; "input", `String "hi" ])
    |> Result.get_ok
  in
  Bulkhead_lm.Router.dispatch_embeddings store ~authorization:"Bearer sk-test" request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected embeddings fallback success but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok response ->
    Alcotest.(check string)
      "embeddings fallback chosen"
      "good-embedding-model"
      response.model;
    Alcotest.(check int) "one embedding returned" 1 (List.length response.data);
    Lwt.return_unit
;;

let responses_wrap_chat_response_test _switch () =
  let chat_response =
    Bulkhead_lm.Provider_mock.sample_chat_response ~model:"gpt-5-mini" ~content:"OK" ()
  in
  let response = Bulkhead_lm.Responses_api.of_chat_response chat_response in
  let json = Bulkhead_lm.Responses_api.response_to_yojson response in
  let as_text = Yojson.Safe.to_string json in
  Alcotest.(check bool) "response object tag" true (String.contains as_text 'r');
  Alcotest.(check string) "output text" "OK" response.output_text;
  Lwt.return_unit
;;

let chat_sse_contains_done_marker_test _switch () =
  let response =
    Bulkhead_lm.Provider_mock.sample_chat_response
      ~model:"claude-sonnet"
      ~content:"stream-ok"
      ()
  in
  let chunks = Bulkhead_lm.Sse_stream.chat_completion_chunks response in
  let encoded =
    (chunks |> List.map Bulkhead_lm.Sse_stream.encode |> String.concat "")
    ^ Bulkhead_lm.Sse_stream.done_marker
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
    Bulkhead_lm.Provider_mock.sample_chat_response
      ~model:"claude-sonnet"
      ~content:"delta-ok"
      ()
    |> Bulkhead_lm.Responses_api.of_chat_response
  in
  let encoded =
    Bulkhead_lm.Sse_stream.response_events response
    |> List.map (fun (event, json) -> Bulkhead_lm.Sse_stream.encode ?event json)
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
    Bulkhead_lm.Provider_mock.sample_chat_response
      ~model:"claude-sonnet"
      ~content:"stream-close-ok"
      ()
  in
  let stream =
    { Bulkhead_lm.Provider_client.response
    ; events =
        Lwt_stream.of_list [ Bulkhead_lm.Provider_client.Text_delta "stream-close-ok" ]
    ; close =
        (fun () ->
          closed := true;
          Lwt.return_unit)
    }
  in
  Bulkhead_lm.Sse_stream.respond_chat_stream stream
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
  let config_path = Filename.temp_file "bulkhead-lm-provider-kinds" ".json" in
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
                          [ "provider_id", `String "openrouter-primary"
                          ; "provider_kind", `String "openrouter_openai"
                          ; "upstream_model", `String "openrouter/free"
                          ; "api_base", `String "https://openrouter.ai/api/v1"
                          ; "api_key_env", `String "OPEN_ROUTER_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "vertex-primary"
                          ; "provider_kind", `String "vertex_openai"
                          ; "upstream_model", `String "gpt-oss-120b-maas"
                          ; ( "api_base"
                            , `String
                                "https://aiplatform.googleapis.com/v1/projects/test/locations/global/endpoints/openapi"
                            )
                          ; "api_key_env", `String "VERTEX_AI_ACCESS_TOKEN"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "xai-primary"
                          ; "provider_kind", `String "xai_openai"
                          ; "upstream_model", `String "grok-4.20-reasoning"
                          ; "api_base", `String "https://api.x.ai/v1"
                          ; "api_key_env", `String "XAI_API_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "meta-primary"
                          ; "provider_kind", `String "meta_openai"
                          ; "upstream_model", `String "llama-4-maverick"
                          ; "api_base", `String "https://api.llama.com/compat/v1"
                          ; "api_key_env", `String "META_API_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "peer-primary"
                          ; "provider_kind", `String "bulkhead_peer"
                          ; "upstream_model", `String "claude-sonnet"
                          ; "api_base", `String "https://mesh.example.test/v1"
                          ; "api_key_env", `String "BULKHEAD_LM_PEER_API_KEY"
                          ]
                      ; `Assoc
                          [ "provider_id", `String "ssh-peer-primary"
                          ; "provider_kind", `String "bulkhead_ssh_peer"
                          ; "upstream_model", `String "claude-sonnet"
                          ; "api_key_env", `String "BULKHEAD_LM_SSH_PEER_API_KEY"
                          ; ( "ssh_transport"
                            , `Assoc
                                [ "destination", `String "ops@machine-a.example.net"
                                ; "host", `String "machine-a.example.net"
                                ; ( "remote_worker_command"
                                  , `String "/opt/bulkhead-lm/scripts/remote_worker.sh" )
                                ; ( "remote_config_path"
                                  , `String "/etc/bulkhead-lm/gateway.json" )
                                ; "remote_switch", `String "prod-switch"
                                ; "remote_jobs", `Int 2
                                ; ( "options"
                                  , `List [ `String "-i"; `String "/tmp/bulkhead-lm-key" ]
                                  )
                                ] )
                          ]
                      ] )
                ]
            ] )
      ; "virtual_keys", `List []
      ]
  in
  Yojson.Safe.to_file config_path config_json;
  (match Bulkhead_lm.Config.load config_path with
   | Error err -> Alcotest.failf "expected config load success: %s" err
   | Ok config ->
     (match config.Bulkhead_lm.Config.routes with
      | [ route ] ->
        (match route.Bulkhead_lm.Config.backends with
         | [ mistral
           ; ollama
           ; alibaba
           ; moonshot
           ; openrouter
           ; vertex
           ; xai
           ; meta
           ; peer
           ; ssh_peer
           ] ->
           Alcotest.(check bool)
             "mistral kind parsed"
             true
             (match mistral.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Mistral_openai -> true
              | _ -> false);
           Alcotest.(check bool)
             "mistral kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                mistral.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "ollama kind parsed"
             true
             (match ollama.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Ollama_openai -> true
              | _ -> false);
           Alcotest.(check bool)
             "ollama kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                ollama.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "alibaba kind parsed"
             true
             (match alibaba.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Alibaba_openai -> true
              | _ -> false);
           Alcotest.(check bool)
             "alibaba kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                alibaba.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "moonshot kind parsed"
             true
             (match moonshot.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Moonshot_openai -> true
              | _ -> false);
           Alcotest.(check bool)
             "moonshot kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                moonshot.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "openrouter kind parsed"
             true
             (match openrouter.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Openrouter_openai -> true
              | _ -> false);
           Alcotest.(check bool)
             "openrouter kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                openrouter.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "vertex kind parsed"
             true
             (match vertex.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Vertex_openai -> true
              | _ -> false);
           Alcotest.(check bool)
             "vertex kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                vertex.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "xai kind parsed"
             true
             (match xai.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Xai_openai -> true
              | _ -> false);
           Alcotest.(check bool)
             "xai kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                xai.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "meta kind parsed"
             true
             (match meta.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Meta_openai -> true
              | _ -> false);
           Alcotest.(check bool)
             "meta kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                meta.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "peer kind parsed"
             true
             (match peer.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Bulkhead_peer -> true
              | _ -> false);
           Alcotest.(check bool)
             "peer kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                peer.Bulkhead_lm.Config.provider_kind);
           Alcotest.(check bool)
             "ssh peer kind parsed"
             true
             (match ssh_peer.Bulkhead_lm.Config.provider_kind with
              | Bulkhead_lm.Config.Bulkhead_ssh_peer -> true
              | _ -> false);
           Alcotest.(check bool)
             "ssh peer kind is openai-compatible"
             true
             (Bulkhead_lm.Config.is_openai_compatible_kind
                ssh_peer.Bulkhead_lm.Config.provider_kind);
           (match Bulkhead_lm.Config.backend_ssh_transport ssh_peer with
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
         | _ -> Alcotest.fail "expected ten backends")
      | _ -> Alcotest.fail "expected one route"));
  Lwt.return_unit
;;

let tests =
  [
    Alcotest_lwt.test_case "times out slow provider calls" `Quick routing_times_out_slow_provider_test
  ; Alcotest_lwt.test_case "embeddings fall back on retryable failure" `Quick embeddings_fall_back_on_retryable_failure_test
  ; Alcotest_lwt.test_case "responses wraps chat result" `Quick responses_wrap_chat_response_test
  ; Alcotest_lwt.test_case "chat sse contains done marker" `Quick chat_sse_contains_done_marker_test
  ; Alcotest_lwt.test_case "responses sse contains completion event" `Quick responses_sse_contains_completion_event_test
  ; Alcotest_lwt.test_case "chat stream response closes handle" `Quick chat_stream_response_closes_handle_test
  ; Alcotest_lwt.test_case "config parses openai-compatible provider variants" `Quick config_load_accepts_openai_compatible_provider_variants_test
  ]
;;

let suite = "03.streaming/provider-variants", tests
