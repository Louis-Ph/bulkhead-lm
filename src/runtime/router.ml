open Lwt.Infix

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

let rec try_backends store principal (request : Openai_types.chat_request) failures
  = function
  | [] ->
    let message =
      if failures = []
      then "No upstream backend configured."
      else failures |> List.rev_map Domain_error.to_string |> String.concat " | "
    in
    Lwt.return (Error (Domain_error.upstream message))
  | backend :: rest ->
    (match
       Egress_policy.ensure_allowed
         store.Runtime_state.config.security_policy
         backend.Config.api_base
     with
     | Error err -> try_backends store principal request (err :: failures) rest
     | Ok () ->
       let provider = store.Runtime_state.provider_factory backend in
       protect_upstream ~provider_id:backend.Config.provider_id (fun () ->
         provider.Provider_client.invoke_chat
           backend
           { request with model = backend.Config.upstream_model })
       >>= (function
        | Ok response ->
          (match
             consume_budget_if_possible store ~principal response.Openai_types.usage
           with
           | Ok () -> Lwt.return (Ok response)
           | Error err -> Lwt.return (Error err))
        | Error err -> try_backends store principal request (err :: failures) rest))
;;

let dispatch_chat store ~authorization (request : Openai_types.chat_request) =
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
             try_backends store principal request [] limited_backends)))
;;

let dispatch_embeddings store ~authorization (request : Openai_types.embeddings_request) =
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
             (match route.Config.backends with
              | [] -> Lwt.return (Error (Domain_error.route_not_found request.model))
              | backend :: _ ->
                (match
                   Egress_policy.ensure_allowed
                     store.Runtime_state.config.security_policy
                     backend.Config.api_base
                 with
                 | Error err -> Lwt.return (Error err)
                 | Ok () ->
                   let provider = store.Runtime_state.provider_factory backend in
                   protect_upstream ~provider_id:backend.Config.provider_id (fun () ->
                     provider.Provider_client.invoke_embeddings
                       backend
                       { request with model = backend.Config.upstream_model })
                   >>= (function
                    | Ok response ->
                      (match
                         consume_budget_if_possible store ~principal response.usage
                       with
                       | Ok () -> Lwt.return (Ok response)
                       | Error err -> Lwt.return (Error err))
                    | Error err -> Lwt.return (Error err)))))))
;;
