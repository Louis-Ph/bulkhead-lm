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

let with_inflight store ~on_exceeded work =
  if Runtime_state.try_inflight store
  then Lwt.finalize work (fun () -> Runtime_state.release_inflight store; Lwt.return_unit)
  else on_exceeded ()
;;

let protect_chat_request security_policy request =
  match
    Threat_detector.ensure_chat_request_is_safe
      security_policy.Security_policy.threat_detector
      request
  with
  | Error _ as error -> error
  | Ok () -> Ok (Privacy_filter.filter_chat_request security_policy.privacy_filter request)
;;

let protect_embeddings_request security_policy request =
  match
    Threat_detector.ensure_embeddings_request_is_safe
      security_policy.Security_policy.threat_detector
      request
  with
  | Error _ as error -> error
  | Ok () ->
    Ok (Privacy_filter.filter_embeddings_request security_policy.privacy_filter request)
;;

let protect_chat_response security_policy response =
  let filtered =
    Privacy_filter.filter_chat_response security_policy.Security_policy.privacy_filter response
  in
  match Output_guard.ensure_chat_response_is_safe security_policy.output_guard filtered with
  | Error _ as error -> error
  | Ok () -> Ok filtered
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
       let circuit = store.Runtime_state.backend_circuit in
       let provider_id = backend.Config.provider_id in
       if Backend_circuit.is_open circuit provider_id
       then
         try_backends
           store
           principal
           peer_context
           request
           (Domain_error.circuit_open ~provider_id () :: failures)
           rest
       else
         let provider = store.Runtime_state.provider_factory backend in
         let upstream_context = upstream_context_for_backend store peer_context backend in
         protect_upstream ~provider_id (fun () ->
           with_upstream_timeout
             store
             ~provider_id
             (provider.Provider_client.invoke_chat
                upstream_context
                backend
                { request with model = backend.Config.upstream_model }))
         >>= (function
         | Ok response ->
           Backend_circuit.record_success circuit provider_id;
           (match
              consume_budget_if_possible store ~principal response.Openai_types.usage
            with
            | Ok () ->
              Lwt.return
                (protect_chat_response store.Runtime_state.config.security_policy response)
            | Error err -> Lwt.return (Error err))
          | Error err ->
            if Domain_error.is_retryable err
            then begin
              Backend_circuit.record_failure circuit provider_id;
              try_backends store principal peer_context request (err :: failures) rest
            end else
              Lwt.return (Error err)))
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
       let circuit = store.Runtime_state.backend_circuit in
       let provider_id = backend.Config.provider_id in
       if Backend_circuit.is_open circuit provider_id
       then
         try_chat_stream_backends
           store
           principal
           peer_context
           request
           (Domain_error.circuit_open ~provider_id () :: failures)
           rest
       else
         let provider = store.Runtime_state.provider_factory backend in
         let upstream_context = upstream_context_for_backend store peer_context backend in
         protect_upstream ~provider_id (fun () ->
           with_upstream_timeout
             store
             ~provider_id
             (provider.Provider_client.invoke_chat_stream
                upstream_context
                backend
                { request with model = backend.Config.upstream_model }))
         >>= (function
          | Ok stream ->
            Backend_circuit.record_success circuit provider_id;
            (match consume_budget_if_possible store ~principal stream.Provider_client.response.usage with
             | Ok () ->
               (match
                  protect_chat_response
                    store.Runtime_state.config.security_policy
                    stream.Provider_client.response
                with
                | Error err -> stream.close () >|= fun () -> Error err
                | Ok response ->
                  Lwt.return (Ok { stream with Provider_client.response = response }))
             | Error err -> stream.close () >|= fun () -> Error err)
          | Error err ->
            if Domain_error.is_retryable err
            then begin
              Backend_circuit.record_failure circuit provider_id;
              try_chat_stream_backends
                store
                principal
                peer_context
                request
                (err :: failures)
                rest
            end else Lwt.return (Error err)))
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
       let circuit = store.Runtime_state.backend_circuit in
       let provider_id = backend.Config.provider_id in
       if Backend_circuit.is_open circuit provider_id
       then
         try_embeddings_backends
           store
           principal
           peer_context
           request
           (Domain_error.circuit_open ~provider_id () :: failures)
           rest
       else
         let provider = store.Runtime_state.provider_factory backend in
         let upstream_context = upstream_context_for_backend store peer_context backend in
         protect_upstream ~provider_id (fun () ->
           with_upstream_timeout
             store
             ~provider_id
             (provider.Provider_client.invoke_embeddings
                upstream_context
                backend
                { request with model = backend.Config.upstream_model }))
         >>= (function
          | Ok response ->
            Backend_circuit.record_success circuit provider_id;
            (match consume_budget_if_possible store ~principal response.usage with
             | Ok () -> Lwt.return (Ok response)
             | Error err -> Lwt.return (Error err))
          | Error err ->
            if Domain_error.is_retryable err
            then begin
              Backend_circuit.record_failure circuit provider_id;
              try_embeddings_backends
                store
                principal
                peer_context
                request
                (err :: failures)
                rest
            end else Lwt.return (Error err)))
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
          (match protect_chat_request store.Runtime_state.config.security_policy request with
           | Error err -> Lwt.return (Error err)
           | Ok request ->
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
                with_inflight store
                  ~on_exceeded:(fun () ->
                    Lwt.return (Error (Domain_error.service_unavailable ())))
                  (fun () ->
                    try_backends store principal peer_context request [] limited_backends)))))
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
          (match protect_chat_request store.Runtime_state.config.security_policy request with
           | Error err -> Lwt.return (Error err)
           | Ok request ->
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
                with_inflight store
                  ~on_exceeded:(fun () ->
                    Lwt.return (Error (Domain_error.service_unavailable ())))
                  (fun () ->
                    try_chat_stream_backends
                      store
                      principal
                      peer_context
                      request
                      []
                      limited_backends)))))
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
          (match protect_embeddings_request store.Runtime_state.config.security_policy request with
           | Error err -> Lwt.return (Error err)
           | Ok request ->
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
                with_inflight store
                  ~on_exceeded:(fun () ->
                    Lwt.return (Error (Domain_error.service_unavailable ())))
                  (fun () ->
                    try_embeddings_backends
                      store
                      principal
                      peer_context
                      request
                      []
                      limited_backends)))))
;;

type ha_health =
  { routes_total    : int
  ; backends_open   : int
  ; backends_closed : int
  ; inflight        : int
  }

let ha_health store =
  let circuit = Backend_circuit.health_summary store.Runtime_state.backend_circuit in
  { routes_total    = List.length store.Runtime_state.config.Config.routes
  ; backends_open   = circuit.Backend_circuit.backends_open
  ; backends_closed = circuit.Backend_circuit.backends_closed
  ; inflight        = Runtime_state.current_inflight store
  }
;;
