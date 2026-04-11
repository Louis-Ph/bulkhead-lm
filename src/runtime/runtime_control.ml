type t =
  { config_path : string
  ; port_override : int option
  ; provider_factory : Runtime_state.provider_factory
  ; swap_lock : Mutex.t
  ; mutable current_store : Runtime_state.t
  ; mutable loaded_at_unix : float
  }

let is_loopback_host host =
  let normalized = String.lowercase_ascii (String.trim host) in
  normalized = "127.0.0.1" || normalized = "::1" || normalized = "localhost"
;;

let override_port (config : Config.t) port_override =
  match port_override with
  | None -> config
  | Some listen_port ->
    { config with
      Config.security_policy =
        { config.security_policy with
          Security_policy.server =
            { config.security_policy.server with listen_port }
        }
    }
;;

let validate_control_plane_runtime (config : Config.t) =
  let control_plane = config.security_policy.Security_policy.control_plane in
  if not control_plane.enabled
  then Ok ()
  else (
    match control_plane.admin_token_env with
    | Some env_name ->
      (match Sys.getenv_opt env_name with
       | Some token when String.trim token <> "" -> Ok ()
       | _ ->
         Error
           (Fmt.str
              "security_policy.control_plane.admin_token_env points to %s, but that environment variable is missing or empty."
              env_name))
    | None ->
      if is_loopback_host config.security_policy.server.listen_host
      then Ok ()
      else
        Error
          "security_policy.control_plane requires admin_token_env when listen_host is not loopback.")
;;

let load_store_result ?provider_factory ~config_path ~port_override () =
  let provider_factory =
    Option.value provider_factory ~default:Provider_registry.make
  in
  match Config.load config_path with
  | Error err -> Error err
  | Ok config ->
    let config = override_port config port_override in
    (match validate_control_plane_runtime config with
     | Error err -> Error err
     | Ok () -> Runtime_state.create_result ~provider_factory config)
;;

let create_result ?provider_factory ~config_path ~port_override () =
  let provider_factory =
    Option.value provider_factory ~default:Provider_registry.make
  in
  match load_store_result ~provider_factory ~config_path ~port_override () with
  | Error err -> Error err
  | Ok current_store ->
    Ok
      { config_path
      ; port_override
      ; provider_factory
      ; swap_lock = Mutex.create ()
      ; current_store
      ; loaded_at_unix = Unix.gettimeofday ()
      }
;;

let create ?provider_factory ~config_path ~port_override () =
  match create_result ?provider_factory ~config_path ~port_override () with
  | Ok control -> control
  | Error err -> failwith err
;;

let current_store control =
  Runtime_state.with_lock control.swap_lock (fun () -> control.current_store)
;;

let loaded_at_unix control =
  Runtime_state.with_lock control.swap_lock (fun () -> control.loaded_at_unix)
;;

let config_path control = control.config_path

let port_override control = control.port_override

let copy_principal_counters previous_store next_store =
  Runtime_state.with_lock previous_store.Runtime_state.budget_usage_lock (fun () ->
    Hashtbl.iter
      (fun token_hash budget_used ->
        if Runtime_state.String_map.mem token_hash next_store.Runtime_state.principals
        then Hashtbl.replace next_store.Runtime_state.budget_usage token_hash budget_used)
      previous_store.Runtime_state.budget_usage);
  Runtime_state.with_lock previous_store.Runtime_state.request_windows_lock (fun () ->
    Hashtbl.iter
      (fun token_hash window_count ->
        if Runtime_state.String_map.mem token_hash next_store.Runtime_state.principals
        then Hashtbl.replace next_store.Runtime_state.request_windows token_hash window_count)
      previous_store.Runtime_state.request_windows)
;;

let copy_user_connector_sessions previous_store next_store =
  Runtime_state.with_lock previous_store.Runtime_state.user_connector_sessions_lock (fun () ->
    Hashtbl.iter
      (fun session_key conversation ->
        Hashtbl.replace
          next_store.Runtime_state.user_connector_sessions
          session_key
          conversation)
      previous_store.Runtime_state.user_connector_sessions)
;;

let validate_reloadable_network_binding previous_store next_store =
  let previous_server = previous_store.Runtime_state.config.Config.security_policy.server in
  let next_server = next_store.Runtime_state.config.Config.security_policy.server in
  if previous_server.listen_host <> next_server.listen_host
  then
    Error
      (Fmt.str
         "Reload requires a restart when security_policy.server.listen_host changes (%s -> %s)."
         previous_server.listen_host
         next_server.listen_host)
  else if previous_server.listen_port <> next_server.listen_port
  then
    Error
      (Fmt.str
         "Reload requires a restart when security_policy.server.listen_port changes (%d -> %d)."
         previous_server.listen_port
         next_server.listen_port)
  else Ok ()
;;

let reload_result control =
  match
    load_store_result
      ~provider_factory:control.provider_factory
      ~config_path:control.config_path
      ~port_override:control.port_override
      ()
  with
  | Error err -> Error err
  | Ok next_store ->
    Runtime_state.with_lock control.swap_lock (fun () ->
      let previous_store = control.current_store in
      match validate_reloadable_network_binding previous_store next_store with
      | Error err -> Error err
      | Ok () ->
        copy_principal_counters previous_store next_store;
        copy_user_connector_sessions previous_store next_store;
        control.current_store <- next_store;
        control.loaded_at_unix <- Unix.gettimeofday ();
        Ok next_store)
;;
