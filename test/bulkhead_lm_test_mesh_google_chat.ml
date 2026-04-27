open Lwt.Infix
open Bulkhead_lm_test_foundation_security

let google_chat_id_token_verifies_signed_token_test _switch () =
  let auth_config =
    Bulkhead_lm.Config_test_support.google_chat_id_token_auth
      ~audience:"https://example.test/connectors/google-chat/webhook"
      ~certs_url:"https://example.test/certs"
      ()
  in
  let token =
    signed_google_chat_bearer
      ~audience:"https://example.test/connectors/google-chat/webhook"
  in
  let http_get _uri ~headers:_ =
    Lwt.return
      ( Cohttp.Response.make ~status:`OK ()
      , Yojson.Safe.to_string
          (`Assoc [ "test-key", `String test_google_chat_certificate_pem ]) )
  in
  Bulkhead_lm.Google_chat_id_token.verify ~http_get auth_config ("Bearer " ^ token)
  >>= function
  | Error err ->
    Alcotest.failf "expected google chat token verification success: %s" err.message
  | Ok verified ->
    Alcotest.(check (option string))
      "google chat token email"
      (Some "chat@system.gserviceaccount.com")
      verified.email;
    Lwt.return_unit
;;

let google_chat_connector_handles_text_event_test _switch () =
  let captured_request = ref None in
  let invoke_chat _headers _backend (request : Bulkhead_lm.Openai_types.chat_request) =
    captured_request := Some request;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.model
            ~content:"Google Chat reply"
            ()))
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
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "embeddings not used in google chat connector test")))
    }
  in
  let connector =
    Bulkhead_lm.Config_test_support.google_chat_connector
      ~authorization_env:"BULKHEAD_GOOGLE_CHAT_AUTH"
      ~route_model:"gpt-4o-mini"
      ~allowed_space_names:[ "spaces/AAA" ]
      ~allowed_user_names:[ "users/999" ]
      ?id_token_auth:
        (Some
           (Bulkhead_lm.Config_test_support.google_chat_id_token_auth
              ~audience:"https://example.test/connectors/google-chat/webhook"
              ~certs_url:"https://example.test/certs"
              ()))
      ()
  in
  let store =
    Bulkhead_lm.Runtime_state.create
      ~provider_factory:(fun _ -> provider)
      (Bulkhead_lm.Config_test_support.sample_config
         ~user_connectors:
           { Bulkhead_lm.Config.telegram = []
           ; whatsapp = None
           ; messenger = None
           ; instagram = None
           ; line = None
           ; viber = None
           ; wechat = None
           ; discord = None
           ; google_chat = Some connector
           }
         ~routes:
           [ Bulkhead_lm.Config_test_support.route
               ~public_model:"gpt-4o-mini"
               ~backends:
                 [ Bulkhead_lm.Config_test_support.backend
                     ~provider_id:"primary"
                     ~provider_kind:Bulkhead_lm.Config.Openai_compat
                     ~api_base:"https://api.example.test/v1"
                     ~upstream_model:"gpt-4o-mini"
                     ~api_key_env:"OPENAI_API_KEY"
                     ()
                 ]
               ()
           ]
         ())
  in
  let token =
    signed_google_chat_bearer
      ~audience:"https://example.test/connectors/google-chat/webhook"
  in
  let request =
    Cohttp.Request.make
      ~meth:`POST
      ~headers:(Cohttp.Header.of_list [ "authorization", "Bearer " ^ token ])
      (Uri.of_string "http://localhost/connectors/google-chat/webhook")
  in
  let body =
    Cohttp_lwt.Body.of_string
      (Yojson.Safe.to_string
         (`Assoc
           [ "type", `String "MESSAGE"
           ; "space", `Assoc [ "name", `String "spaces/AAA" ]
           ; "thread", `Assoc [ "name", `String "spaces/AAA/threads/BBB" ]
           ; ( "message"
             , `Assoc
                 [ "name", `String "spaces/AAA/messages/123"
                 ; "text", `String "<users/123> Explain the repo"
                 ] )
           ; ( "user"
             , `Assoc [ "name", `String "users/999"; "displayName", `String "Alice" ] )
           ]))
  in
  with_env_overrides
    [ "BULKHEAD_GOOGLE_CHAT_AUTH", "sk-test" ]
    (fun () ->
      let http_get _uri ~headers:_ =
        Lwt.return
          ( Cohttp.Response.make ~status:`OK ()
          , Yojson.Safe.to_string
              (`Assoc [ "test-key", `String test_google_chat_certificate_pem ]) )
      in
      Bulkhead_lm.Google_chat_connector.handle_webhook
        ~http_get
        store
        request
        body
        connector
      >>= fun (response, response_body) ->
      Alcotest.(check int)
        "google chat webhook accepted"
        200
        (response_status_code response);
      response_body_json response_body
      >>= fun response_json ->
      Alcotest.(check (option string))
        "google chat reply text"
        (Some "Google Chat reply")
        (match List.assoc_opt "text" (json_assoc response_json) with
         | Some (`String value) -> Some value
         | _ -> None);
      (match !captured_request with
       | None -> Alcotest.fail "expected routed google chat request"
       | Some routed_request ->
         Alcotest.(check string)
           "google chat connector routes configured model"
           "gpt-4o-mini"
           routed_request.model;
         (match List.rev routed_request.messages with
          | last :: _ ->
            Alcotest.(check string)
              "google chat strips leading mention"
              "Explain the repo"
              last.content
          | [] -> Alcotest.fail "expected google chat routed request messages"));
      let session =
        Bulkhead_lm.Runtime_state.get_user_connector_session
          store
          ~session_key:"google_chat:spaces/AAA:spaces/AAA/threads/BBB"
      in
      Alcotest.(check int)
        "google chat connector remembers one exchange"
        2
        (Bulkhead_lm.Session_memory.stats session).recent_turn_count;
      Lwt.return_unit)
;;

let provider_registry_routes_new_openai_compatible_kinds_test _switch () =
  let request = { Bulkhead_lm.Openai_types.model = "ignored"; input = [ "hello" ] } in
  let assert_openai_compat kind provider_id api_key_env =
    let backend =
      Bulkhead_lm.Config_test_support.backend
        ~provider_id
        ~provider_kind:kind
        ~api_base:"https://api.example.test/v1"
        ~upstream_model:"example-model"
        ~api_key_env
        ()
    in
    let provider = Bulkhead_lm.Provider_registry.make backend in
    provider.Bulkhead_lm.Provider_client.invoke_embeddings
      { Bulkhead_lm.Provider_client.peer_headers = []; peer_context = None }
      backend
      request
    >>= function
    | Ok _ -> Alcotest.fail "expected missing credential failure"
    | Error err ->
      Alcotest.(check string)
        "new kinds use openai-compatible adapter"
        "upstream_failure"
        err.Bulkhead_lm.Domain_error.code;
      Alcotest.(check string)
        "missing env reported"
        ("Missing environment variable " ^ api_key_env)
        err.Bulkhead_lm.Domain_error.message;
      Lwt.return_unit
  in
  assert_openai_compat
    Bulkhead_lm.Config.Mistral_openai
    "mistral-primary"
    "MISTRAL_TEST_KEY"
  >>= fun () ->
  assert_openai_compat Bulkhead_lm.Config.Ollama_openai "ollama-primary" "OLLAMA_TEST_KEY"
  >>= fun () ->
  assert_openai_compat
    Bulkhead_lm.Config.Alibaba_openai
    "alibaba-primary"
    "DASHSCOPE_TEST_KEY"
  >>= fun () ->
  assert_openai_compat
    Bulkhead_lm.Config.Moonshot_openai
    "moonshot-primary"
    "MOONSHOT_TEST_KEY"
  >>= fun () ->
  assert_openai_compat
    Bulkhead_lm.Config.Openrouter_openai
    "openrouter-primary"
    "OPEN_ROUTER_TEST_KEY"
  >>= fun () ->
  assert_openai_compat
    Bulkhead_lm.Config.Bulkhead_peer
    "peer-primary"
    "BULKHEAD_LM_PEER_TEST_KEY"
  >>= fun () ->
  let ssh_backend =
    Bulkhead_lm.Config_test_support.backend
      ~provider_id:"ssh-peer-primary"
      ~provider_kind:Bulkhead_lm.Config.Bulkhead_ssh_peer
      ~api_base:""
      ~upstream_model:"example-model"
      ~api_key_env:"BULKHEAD_LM_SSH_PEER_TEST_KEY"
      ~ssh_transport:
        (Bulkhead_lm.Config_test_support.ssh_transport
           ~destination:"ops@machine-a.example.net"
           ~host:"machine-a.example.net"
           ~remote_worker_command:"/opt/bulkhead-lm/scripts/remote_worker.sh"
           ())
      ()
  in
  let ssh_provider = Bulkhead_lm.Provider_registry.make ssh_backend in
  ssh_provider.Bulkhead_lm.Provider_client.invoke_embeddings
    { Bulkhead_lm.Provider_client.peer_headers = []; peer_context = None }
    ssh_backend
    request
  >>= function
  | Ok _ -> Alcotest.fail "expected missing ssh peer credential failure"
  | Error err ->
    Alcotest.(check string)
      "ssh peer reports missing env"
      "Missing environment variable BULKHEAD_LM_SSH_PEER_TEST_KEY"
      err.Bulkhead_lm.Domain_error.message;
    Lwt.return_unit
;;

let ssh_peer_protocol_request_includes_mesh_test _switch () =
  let json =
    Bulkhead_lm.Ssh_peer_protocol.request_json
      ~request_id:"req-ssh"
      ~kind:Bulkhead_lm.Ssh_peer_protocol.Chat
      ~peer_context:{ Bulkhead_lm.Peer_mesh.request_id = "req-peer"; hop_count = 1 }
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
       (match Bulkhead_lm.Peer_mesh.of_yojson mesh_json with
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
  match
    Bulkhead_lm.Ssh_peer_protocol.chat_response_of_line ~provider_id:"ssh-peer" line
  with
  | Ok _ -> Alcotest.fail "expected remote worker error"
  | Error err ->
    Alcotest.(check string) "remote error code kept" "loop_detected" err.code;
    Alcotest.(check int) "remote error status kept" 508 err.status;
    Lwt.return_unit
;;

let peer_mesh_rejects_excessive_hop_count_test _switch () =
  let headers =
    Cohttp.Header.of_list
      [ "x-bulkhead-lm-request-id", "req-overflow"; "x-bulkhead-lm-hop-count", "2" ]
  in
  match
    Bulkhead_lm.Peer_mesh.context_of_headers
      (Bulkhead_lm.Security_policy.default ())
      headers
  with
  | Ok _ -> Alcotest.fail "expected peer mesh hop rejection"
  | Error err ->
    Alcotest.(check string) "loop rejection code" "loop_detected" err.code;
    Alcotest.(check int) "loop rejection status" 508 err.status;
    Lwt.return_unit
;;

let router_adds_peer_mesh_headers_for_bulkhead_peer_test _switch () =
  let captured_headers : (string * string) list ref = ref [] in
  let cfg =
    Bulkhead_lm.Config_test_support.sample_config
      ~routes:
        [ Bulkhead_lm.Config_test_support.route
            ~public_model:"mesh-claude"
            ~backends:
              [ Bulkhead_lm.Config_test_support.backend
                  ~provider_id:"peer-a"
                  ~provider_kind:Bulkhead_lm.Config.Bulkhead_peer
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
    (upstream_context : Bulkhead_lm.Provider_client.upstream_context)
    _backend
    (request : Bulkhead_lm.Openai_types.chat_request)
    =
    captured_headers := upstream_context.peer_headers;
    Lwt.return
      (Ok
         (Bulkhead_lm.Provider_mock.sample_chat_response
            ~model:request.Bulkhead_lm.Openai_types.model
            ~content:"peer ok"
            ()))
  in
  let provider =
    { Bulkhead_lm.Provider_client.invoke_chat
    ; invoke_chat_stream =
        (fun upstream_context backend request ->
          invoke_chat upstream_context backend request
          >|= Result.map Bulkhead_lm.Provider_stream.of_chat_response)
    ; invoke_embeddings =
        (fun _headers _backend _request ->
          Lwt.return
            (Error
               (Bulkhead_lm.Domain_error.unsupported_feature
                  "embeddings not used in peer mesh header test")))
    }
  in
  let store =
    Bulkhead_lm.Runtime_state.create ~provider_factory:(fun _ -> provider) cfg
  in
  let request =
    Bulkhead_lm.Openai_types.chat_request_of_yojson
      (`Assoc
        [ "model", `String "mesh-claude"
        ; "messages", `List [ `Assoc [ "role", `String "user"; "content", `String "hi" ] ]
        ])
    |> Result.get_ok
  in
  Bulkhead_lm.Router.dispatch_chat
    ~peer_context:
      { Bulkhead_lm.Peer_mesh.request_id = "req-peer"
      ; Bulkhead_lm.Peer_mesh.hop_count = 0
      }
    store
    ~authorization:"Bearer sk-test"
    request
  >>= function
  | Error err ->
    Alcotest.failf
      "expected peer route success but got %s"
      (Bulkhead_lm.Domain_error.to_string err)
  | Ok _response ->
    let request_id = List.assoc_opt "x-bulkhead-lm-request-id" !captured_headers in
    let hop_count = List.assoc_opt "x-bulkhead-lm-hop-count" !captured_headers in
    Alcotest.(check (option string))
      "peer request id forwarded"
      (Some "req-peer")
      request_id;
    Alcotest.(check (option string)) "peer hop incremented" (Some "1") hop_count;
    Lwt.return_unit
;;

let tests =
  [
    Alcotest_lwt.test_case "google chat token verification accepts signed token" `Quick google_chat_id_token_verifies_signed_token_test
  ; Alcotest_lwt.test_case "google chat connector handles text event" `Quick google_chat_connector_handles_text_event_test
  ; Alcotest_lwt.test_case "provider registry maps new openai-compatible kinds" `Quick provider_registry_routes_new_openai_compatible_kinds_test
  ; Alcotest_lwt.test_case "ssh peer protocol request includes mesh" `Quick ssh_peer_protocol_request_includes_mesh_test
  ; Alcotest_lwt.test_case "ssh peer protocol surfaces worker error" `Quick ssh_peer_protocol_surfaces_worker_error_test
  ; Alcotest_lwt.test_case "peer mesh rejects excessive hop count" `Quick peer_mesh_rejects_excessive_hop_count_test
  ; Alcotest_lwt.test_case "router adds peer mesh headers for bulkhead peer backends" `Quick router_adds_peer_mesh_headers_for_bulkhead_peer_test
  ]
;;

let suite = "10.mesh/google-chat", tests
