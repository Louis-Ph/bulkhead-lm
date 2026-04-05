open Lwt.Infix

let upstream_context_for_backend store peer_context backend =
  match backend.Config.provider_kind with
  | Config.Bulkhead_peer | Config.Bulkhead_ssh_peer ->
    { Provider_client.peer_headers =
        Peer_mesh.outbound_headers store.Runtime_state.config.security_policy peer_context
    ; peer_context = Some peer_context
    }
  | _ -> { Provider_client.peer_headers = []; peer_context = None }
;;

let find_route config model =
  List.find_opt (fun route -> route.Config.public_model = model) config.Config.routes
;;

let ensure_route_allowed principal model =
  if principal.Runtime_state.allowed_routes = []
     || List.mem model principal.allowed_routes
  then Ok ()
  else Error (Domain_error.route_forbidden model)
;;

let consume_budget_if_possible store ~principal usage =
  Budget_ledger.consume store ~principal ~tokens:usage.Openai_types.total_tokens
;;

let protect_upstream ~provider_id call =
  Lwt.catch call (fun exn ->
    Lwt.return
      (Error
         (Domain_error.upstream
            ~provider_id
            ("Unhandled provider exception: " ^ Printexc.to_string exn))))
;;

let with_upstream_timeout store ~provider_id worker =
  let timeout_ms = store.Runtime_state.config.security_policy.server.request_timeout_ms in
  Timeout_guard.with_timeout_ms
    ~timeout_ms
    ~on_timeout:(fun () ->
      Error (Domain_error.request_timeout ~provider_id ~timeout_ms ()))
    worker
;;

let final_error_of_failures = function
  | [] -> Domain_error.upstream "No upstream backend configured."
  | [ failure ] -> failure
  | failure_list ->
    let message = failure_list |> List.map Domain_error.to_string |> String.concat " | " in
    Domain_error.upstream message
;;

let rec
  try_backends
    store
    principal
    peer_context
    (request : Openai_types.chat_request)
    failures
  = function
  | [] ->
    Lwt.return (Error (final_error_of_failures (List.rev failures)))
  | backend :: rest ->
    (match
       Egress_policy.ensure_allowed
         store.Runtime_state.config.security_policy
         backend
     with
     | Error err -> try_backends store principal peer_context request (err :: failures) rest
     | Ok () ->
       let provider = store.Runtime_state.provider_factory backend in
       let upstream_context = upstream_context_for_backend store peer_context backend in
       protect_upstream ~provider_id:backend.Config.provider_id (fun () ->
         with_upstream_timeout
           store
           ~provider_id:backend.Config.provider_id
           (provider.Provider_client.invoke_chat
              upstream_context
              backend
              { request with model = backend.Config.upstream_model }))
       >>= (function
       | Ok response ->
          (match
             consume_budget_if_possible store ~principal response.Openai_types.usage
           with
           | Ok () -> Lwt.return (Ok response)
           | Error err -> Lwt.return (Error err))
        | Error err ->
          if Domain_error.is_retryable err
          then try_backends store principal peer_context request (err :: failures) rest
          else Lwt.return (Error err)))
;;

let rec
  try_chat_stream_backends
    store
    principal
    peer_context
    (request : Openai_types.chat_request)
    failures
  = function
  | [] -> Lwt.return (Error (final_error_of_failures (List.rev failures)))
  | backend :: rest ->
    (match
       Egress_policy.ensure_allowed
         store.Runtime_state.config.security_policy
         backend
     with
     | Error err ->
       try_chat_stream_backends store principal peer_context request (err :: failures) rest
     | Ok () ->
       let provider = store.Runtime_state.provider_factory backend in
       let upstream_context = upstream_context_for_backend store peer_context backend in
       protect_upstream ~provider_id:backend.Config.provider_id (fun () ->
         with_upstream_timeout
           store
           ~provider_id:backend.Config.provider_id
           (provider.Provider_client.invoke_chat_stream
              upstream_context
              backend
              { request with model = backend.Config.upstream_model }))
       >>= (function
        | Ok stream ->
          (match consume_budget_if_possible store ~principal stream.Provider_client.response.usage with
           | Ok () -> Lwt.return (Ok stream)
           | Error err -> stream.close () >|= fun () -> Error err)
        | Error err ->
          if Domain_error.is_retryable err
          then
            try_chat_stream_backends
              store
              principal
              peer_context
              request
              (err :: failures)
              rest
          else Lwt.return (Error err)))
;;

let rec
  try_embeddings_backends
    store
    principal
    peer_context
    (request : Openai_types.embeddings_request)
    failures
  = function
  | [] -> Lwt.return (Error (final_error_of_failures (List.rev failures)))
  | backend :: rest ->
    (match
       Egress_policy.ensure_allowed
         store.Runtime_state.config.security_policy
         backend
     with
     | Error err ->
       try_embeddings_backends store principal peer_context request (err :: failures) rest
     | Ok () ->
       let provider = store.Runtime_state.provider_factory backend in
       let upstream_context = upstream_context_for_backend store peer_context backend in
       protect_upstream ~provider_id:backend.Config.provider_id (fun () ->
         with_upstream_timeout
           store
           ~provider_id:backend.Config.provider_id
           (provider.Provider_client.invoke_embeddings
              upstream_context
              backend
              { request with model = backend.Config.upstream_model }))
       >>= (function
        | Ok response ->
          (match consume_budget_if_possible store ~principal response.usage with
           | Ok () -> Lwt.return (Ok response)
           | Error err -> Lwt.return (Error err))
        | Error err ->
          if Domain_error.is_retryable err
          then
            try_embeddings_backends store principal peer_context request (err :: failures) rest
          else Lwt.return (Error err)))
;;

let dispatch_chat ?peer_context store ~authorization (request : Openai_types.chat_request) =
  let peer_context = Option.value peer_context ~default:(Peer_mesh.local_context ()) in
  match Auth.authenticate store ~authorization with
  | Error err -> Lwt.return (Error err)
  | Ok principal ->
    (match ensure_route_allowed principal request.Openai_types.model with
     | Error err -> Lwt.return (Error err)
     | Ok () ->
       (match Rate_limiter.check store ~principal with
        | Error err -> Lwt.return (Error err)
        | Ok () ->
          (match find_route store.Runtime_state.config request.model with
           | None -> Lwt.return (Error (Domain_error.route_not_found request.model))
           | Some route ->
             let limited_backends =
               route.Config.backends
               |> List.mapi (fun index backend -> index, backend)
               |> List.filter_map (fun (index, backend) ->
                 if index
                    <= store.Runtime_state.config.security_policy.routing.max_fallbacks
                 then Some backend
                 else None)
             in
             try_backends store principal peer_context request [] limited_backends)))
;;

let dispatch_chat_stream ?peer_context store ~authorization (request : Openai_types.chat_request) =
  let peer_context = Option.value peer_context ~default:(Peer_mesh.local_context ()) in
  match Auth.authenticate store ~authorization with
  | Error err -> Lwt.return (Error err)
  | Ok principal ->
    (match ensure_route_allowed principal request.Openai_types.model with
     | Error err -> Lwt.return (Error err)
     | Ok () ->
       (match Rate_limiter.check store ~principal with
        | Error err -> Lwt.return (Error err)
        | Ok () ->
          (match find_route store.Runtime_state.config request.model with
           | None -> Lwt.return (Error (Domain_error.route_not_found request.model))
           | Some route ->
             let limited_backends =
               route.Config.backends
               |> List.mapi (fun index backend -> index, backend)
               |> List.filter_map (fun (index, backend) ->
                 if index
                    <= store.Runtime_state.config.security_policy.routing.max_fallbacks
                 then Some backend
                 else None)
             in
             try_chat_stream_backends
               store
               principal
               peer_context
               request
               []
               limited_backends)))
;;

let dispatch_embeddings
  ?peer_context
  store
  ~authorization
  (request : Openai_types.embeddings_request)
  =
  let peer_context = Option.value peer_context ~default:(Peer_mesh.local_context ()) in
  match Auth.authenticate store ~authorization with
  | Error err -> Lwt.return (Error err)
  | Ok principal ->
    (match ensure_route_allowed principal request.Openai_types.model with
     | Error err -> Lwt.return (Error err)
     | Ok () ->
       (match Rate_limiter.check store ~principal with
        | Error err -> Lwt.return (Error err)
        | Ok () ->
          (match find_route store.Runtime_state.config request.model with
           | None -> Lwt.return (Error (Domain_error.route_not_found request.model))
           | Some route ->
             let limited_backends =
               route.Config.backends
               |> List.mapi (fun index backend -> index, backend)
               |> List.filter_map (fun (index, backend) ->
                 if index
                    <= store.Runtime_state.config.security_policy.routing.max_fallbacks
                 then Some backend
                 else None)
             in
             try_embeddings_backends
               store
               principal
               peer_context
               request
               []
               limited_backends)))
;;
