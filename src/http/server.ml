open Lwt.Infix

let read_request_json = Request_body.read_request_json

let authorization_header store req =
  let headers = Cohttp.Request.headers req in
  Cohttp.Header.get
    headers
    (String.lowercase_ascii store.Runtime_state.config.security_policy.auth.header)
  |> Option.value ~default:""
;;

let peer_context_of_request store req =
  Peer_mesh.context_of_headers
    store.Runtime_state.config.security_policy
    (Cohttp.Request.headers req)
;;

let models_json config =
  `Assoc
    [ ( "data"
      , `List
          (List.map
             (fun route ->
               `Assoc
                 [ "id", `String route.Config.public_model; "object", `String "model" ])
             config.Config.routes) )
    ; "object", `String "list"
    ]
;;

let principal_name store authorization =
  match Auth.authenticate store ~authorization with
  | Ok principal -> Some principal.Runtime_state.name
  | Error _ -> None
;;

let record_api_event store ~event_type ~authorization ~route_model ~status_code ~details =
  Runtime_state.append_audit_event
    store
    { event_type
    ; principal_name = principal_name store authorization
    ; route_model
    ; provider_id = None
    ; status_code
    ; details
    }
;;

let respond_error_with_audit
  store
  ~event_type
  ~authorization
  ~route_model
  (error : Domain_error.t)
  =
  record_api_event
    store
    ~event_type
    ~authorization
    ~route_model
    ~status_code:error.status
    ~details:(Domain_error.to_openai_json error);
  Json_response.respond_error error
;;

let callback control _connection req body =
  let store = Runtime_control.current_store control in
  let path = Uri.path (Cohttp.Request.uri req) in
  if Admin_control.matches control path
  then Admin_control.handle control req body
  else
    (match User_connector_router.find store.Runtime_state.config ~path with
     | Some connector -> User_connector_router.handle store req body connector
     | None ->
       match Cohttp.Request.meth req, path with
  | `GET, "/health" -> Json_response.respond_json (`Assoc [ "status", `String "ok" ])
  | `GET, "/v1/models" ->
    Json_response.respond_json (models_json store.Runtime_state.config)
  | `POST, "/v1/chat/completions" ->
    read_request_json store body
    >>= fun body_result ->
    let authorization = authorization_header store req in
    let peer_context_result = peer_context_of_request store req in
    (match body_result, peer_context_result with
     | _, Error error ->
       respond_error_with_audit
         store
         ~event_type:"chat.completions"
         ~authorization
         ~route_model:None
         error
     | Error error, _ ->
       respond_error_with_audit
         store
         ~event_type:"chat.completions"
         ~authorization
         ~route_model:None
         error
     | Ok json, Ok peer_context ->
       let json =
         Secret_redaction.redact_json
           ~sensitive_keys:store.Runtime_state.config.security_policy.redaction.json_keys
           ~replacement:store.Runtime_state.config.security_policy.redaction.replacement
           json
       in
       (* parsing uses the original request shape; redaction only protects later logging hooks *)
       let request_json = json in
       (match Openai_types.chat_request_of_yojson request_json with
        | Error field ->
          respond_error_with_audit
            store
            ~event_type:"chat.completions"
            ~authorization
            ~route_model:None
            (Domain_error.invalid_request ("Invalid chat request field: " ^ field))
        | Ok request ->
          let route_model = Some request.model in
          if request.stream
          then
            Router.dispatch_chat_stream store ~authorization ~peer_context request
            >>= (function
             | Ok stream ->
               record_api_event
                 store
                 ~event_type:"chat.completions"
                 ~authorization
                 ~route_model
                 ~status_code:200
                 ~details:
                   (`Assoc
                     [ "stream", `Bool true
                     ; "result", `String "ok"
                     ; "response_model", `String stream.Provider_client.response.model
                     ]);
               Sse_stream.respond_chat_stream stream
             | Error error ->
               respond_error_with_audit
                 store
                 ~event_type:"chat.completions"
                 ~authorization
                 ~route_model
                 error)
          else
            Router.dispatch_chat store ~authorization ~peer_context request
            >>= (function
             | Ok response ->
               record_api_event
                 store
                 ~event_type:"chat.completions"
                 ~authorization
                 ~route_model
                 ~status_code:200
                 ~details:
                   (`Assoc
                     [ "stream", `Bool false
                     ; "result", `String "ok"
                     ; "response_model", `String response.model
                     ]);
               Json_response.respond_json (Openai_types.chat_response_to_yojson response)
             | Error error ->
               respond_error_with_audit
                 store
                 ~event_type:"chat.completions"
                 ~authorization
                 ~route_model
                 error)))
  | `POST, "/v1/embeddings" ->
    read_request_json store body
    >>= fun body_result ->
    let authorization = authorization_header store req in
    let peer_context_result = peer_context_of_request store req in
    (match body_result, peer_context_result with
     | _, Error error ->
       respond_error_with_audit
         store
         ~event_type:"embeddings"
         ~authorization
         ~route_model:None
         error
     | Error error, _ ->
       respond_error_with_audit
         store
         ~event_type:"embeddings"
         ~authorization
         ~route_model:None
         error
     | Ok json, Ok peer_context ->
       (match Openai_types.embeddings_request_of_yojson json with
        | Error field ->
          respond_error_with_audit
            store
            ~event_type:"embeddings"
            ~authorization
            ~route_model:None
            (Domain_error.invalid_request ("Invalid embeddings request field: " ^ field))
        | Ok request ->
          Router.dispatch_embeddings store ~authorization ~peer_context request
          >>= (function
           | Ok response ->
             record_api_event
               store
               ~event_type:"embeddings"
               ~authorization
               ~route_model:(Some request.model)
               ~status_code:200
               ~details:(`Assoc [ "result", `String "ok" ]);
             Json_response.respond_json (Openai_types.embeddings_response_to_yojson response)
           | Error error ->
             respond_error_with_audit
               store
               ~event_type:"embeddings"
               ~authorization
               ~route_model:(Some request.model)
               error)))
  | `POST, "/v1/responses" ->
    read_request_json store body
    >>= fun body_result ->
    let authorization = authorization_header store req in
    let peer_context_result = peer_context_of_request store req in
    (match body_result, peer_context_result with
     | _, Error error ->
       respond_error_with_audit
         store
         ~event_type:"responses"
         ~authorization
         ~route_model:None
         error
     | Error error, _ ->
       respond_error_with_audit
         store
         ~event_type:"responses"
         ~authorization
         ~route_model:None
         error
     | Ok json, Ok peer_context ->
       (match Responses_api.request_of_yojson json with
        | Error field ->
          respond_error_with_audit
            store
            ~event_type:"responses"
            ~authorization
            ~route_model:None
            (Domain_error.invalid_request ("Invalid responses request field: " ^ field))
        | Ok request ->
          let route_model = Some request.model in
          let chat_request = Responses_api.to_chat_request request in
          if request.stream
          then
            Router.dispatch_chat_stream store ~authorization ~peer_context chat_request
            >>= (function
             | Ok stream ->
               let response = Responses_api.of_chat_response stream.Provider_client.response in
               record_api_event
                 store
                 ~event_type:"responses"
                 ~authorization
                 ~route_model
                 ~status_code:200
                 ~details:
                   (`Assoc
                     [ "stream", `Bool true
                     ; "result", `String "ok"
                     ; "response_model", `String response.model
                     ]);
               Sse_stream.respond_response_stream ~response stream
             | Error error ->
               respond_error_with_audit
                 store
                 ~event_type:"responses"
                 ~authorization
                 ~route_model
                 error)
          else
            Router.dispatch_chat
              store
              ~authorization
              ~peer_context
              { chat_request with stream = false }
            >>= (function
             | Ok response ->
               let response = Responses_api.of_chat_response response in
               record_api_event
                 store
                 ~event_type:"responses"
                 ~authorization
                 ~route_model
                 ~status_code:200
                 ~details:
                   (`Assoc
                     [ "stream", `Bool false
                     ; "result", `String "ok"
                     ; "response_model", `String response.model
                     ]);
               Json_response.respond_json (Responses_api.response_to_yojson response)
             | Error error ->
               respond_error_with_audit
                 store
                 ~event_type:"responses"
                 ~authorization
                 ~route_model
                 error)))
  | _ ->
    Json_response.respond_error
      (Domain_error.route_not_found path))
;;

let start control =
  let store = Runtime_control.current_store control in
  let port = store.Runtime_state.config.security_policy.server.listen_port in
  let mode = `TCP (`Port port) in
  let server = Cohttp_lwt_unix.Server.make ~callback:(callback control) () in
  Logs.app (fun m ->
    m
      "BulkheadLM listening on http://%s:%d"
      store.Runtime_state.config.security_policy.server.listen_host
      port);
  Cohttp_lwt_unix.Server.create ~mode server
;;
