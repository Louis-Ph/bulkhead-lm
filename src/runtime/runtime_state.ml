module String_map = Map.Make (String)

type principal =
  { name : string
  ; token_hash : string
  ; daily_token_budget : int
  ; requests_per_minute : int
  ; allowed_routes : string list
  }

type provider_factory = Config.backend -> Provider_client.t

type t =
  { config : Config.t
  ; principals : principal String_map.t
  ; persistent_store : Persistent_store.t option
  ; budget_usage : (string, int) Hashtbl.t
  ; budget_usage_lock : Mutex.t
  ; request_windows : (string, int) Hashtbl.t
  ; request_windows_lock : Mutex.t
  ; user_connector_sessions : (string, Session_memory.t) Hashtbl.t
  ; user_connector_sessions_lock : Mutex.t
  ; provider_factory : provider_factory
  ; backend_circuit : Backend_circuit.t
  ; inflight : int ref
  ; inflight_lock : Mutex.t
  ; pool_latency : Pool_latency.t
  ; pools : Config.pool list ref
  ; pools_lock : Mutex.t
  ; in_memory_pool_usage : (string, int) Hashtbl.t
      (** Fallback for budget tracking when no SQLite store is configured;
          keyed as ["{usage_day}|{pool_name}|{route_model}"]. *)
  }

let hash_token token = Digestif.SHA256.digest_string token |> Digestif.SHA256.to_hex

let principal_of_virtual_key virtual_key security_policy =
  let token_hash =
    match virtual_key.Config.token_hash, virtual_key.token_plaintext with
    | Some hash, _ -> hash
    | None, Some plaintext ->
      if security_policy.Security_policy.auth.hash_algorithm <> "sha256"
      then invalid_arg "Only sha256 hashing is supported"
      else hash_token plaintext
    | None, None -> invalid_arg "Virtual key requires token_plaintext or token_hash"
  in
  { name = virtual_key.name
  ; token_hash
  ; daily_token_budget = virtual_key.daily_token_budget
  ; requests_per_minute = virtual_key.requests_per_minute
  ; allowed_routes = virtual_key.allowed_routes
  }
;;

let principal_of_stored_principal (stored_principal : Persistent_store.stored_principal) =
  { name = stored_principal.name
  ; token_hash = stored_principal.token_hash
  ; daily_token_budget = stored_principal.daily_token_budget
  ; requests_per_minute = stored_principal.requests_per_minute
  ; allowed_routes = stored_principal.allowed_routes
  }
;;

let with_lock lock f =
  Mutex.lock lock;
  match f () with
  | result ->
    Mutex.unlock lock;
    result
  | exception exn ->
    Mutex.unlock lock;
    raise exn
;;

let find_principal store token_hash = String_map.find_opt token_hash store.principals

let try_inflight store =
  with_lock store.inflight_lock (fun () ->
    let max = store.config.security_policy.routing.max_inflight in
    if !(store.inflight) < max
    then begin
      store.inflight := !(store.inflight) + 1;
      true
    end else
      false)
;;

let release_inflight store =
  with_lock store.inflight_lock (fun () ->
    if !(store.inflight) > 0 then store.inflight := !(store.inflight) - 1)
;;

let current_inflight store =
  with_lock store.inflight_lock (fun () -> !(store.inflight))
;;

let get_user_connector_session store ~session_key =
  with_lock store.user_connector_sessions_lock (fun () ->
    match Hashtbl.find_opt store.user_connector_sessions session_key with
    | Some conversation -> conversation
    | None ->
      let conversation =
        match store.persistent_store with
        | None -> Session_memory.empty
        | Some persistent_store ->
          (match
             Persistent_store.load_connector_session
               persistent_store
               ~session_key
           with
           | None -> Session_memory.empty
           | Some session ->
             { Session_memory.summary = session.summary
             ; recent_turns = session.recent_turns
             ; compressed_turn_count = session.compressed_turn_count
             })
      in
      Hashtbl.replace store.user_connector_sessions session_key conversation;
      conversation)
;;

let set_user_connector_session store ~session_key conversation =
  with_lock store.user_connector_sessions_lock (fun () ->
    Hashtbl.replace store.user_connector_sessions session_key conversation;
    match store.persistent_store with
    | None -> ()
    | Some persistent_store ->
      Persistent_store.upsert_connector_session
        persistent_store
        ~session_key
        conversation)
;;

let clear_user_connector_session store ~session_key =
  with_lock store.user_connector_sessions_lock (fun () ->
    Hashtbl.remove store.user_connector_sessions session_key;
    match store.persistent_store with
    | None -> ()
    | Some persistent_store ->
      Persistent_store.delete_connector_session persistent_store ~session_key)
;;

let append_audit_event store event =
  match store.persistent_store with
  | None -> ()
  | Some persistent_store -> Persistent_store.append_audit_event persistent_store event
;;

let create_result ?provider_factory config =
  let default_provider_factory backend = Provider_registry.make backend in
  let provider_factory =
    Option.value provider_factory ~default:default_provider_factory
  in
  match Persistent_store.open_or_bootstrap config with
  | Error err -> Error err
  | Ok persistent ->
    let persistent_store, principal_list =
      match persistent with
      | None ->
        ( None
        , List.map
            (fun virtual_key ->
              principal_of_virtual_key virtual_key config.Config.security_policy)
            config.Config.virtual_keys )
      | Some (store, principals) ->
        Some store, List.map principal_of_stored_principal principals
    in
    let principals =
      List.fold_left
        (fun acc principal -> String_map.add principal.token_hash principal acc)
        String_map.empty
        principal_list
    in
    Ok
      { config
      ; principals
      ; persistent_store
      ; budget_usage = Hashtbl.create 32
      ; budget_usage_lock = Mutex.create ()
      ; request_windows = Hashtbl.create 32
      ; request_windows_lock = Mutex.create ()
      ; user_connector_sessions = Hashtbl.create 32
      ; user_connector_sessions_lock = Mutex.create ()
      ; provider_factory
      ; backend_circuit =
          Backend_circuit.create
            ~open_threshold:
              config.Config.security_policy.routing.circuit_open_threshold
            ~cooldown_s:config.Config.security_policy.routing.circuit_cooldown_s
      ; inflight = ref 0
      ; inflight_lock = Mutex.create ()
      ; pool_latency = Pool_latency.create ()
      ; pools = ref config.Config.pools
      ; pools_lock = Mutex.create ()
      ; in_memory_pool_usage = Hashtbl.create 32
      }
;;

let create ?provider_factory config =
  match create_result ?provider_factory config with
  | Ok store -> store
  | Error err -> failwith err
;;
