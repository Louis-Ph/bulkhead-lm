(** Runtime mutations for pool definitions.

    Pools live in [Runtime_state.t.pools] (a [ref]) so the wizard can mutate
    them without rebuilding the whole runtime store. Every mutation is
    persisted to SQLite as a JSON snapshot keyed by ['pools'] so the gateway
    can survive a restart without forcing the operator to edit
    [gateway.json]. The snapshot's full pool list overrides whatever the
    config declares; declarative definitions remain the seed, but runtime
    edits win. *)

let with_pools store f =
  Runtime_state.with_lock store.Runtime_state.pools_lock (fun () ->
    let updated = f !(store.Runtime_state.pools) in
    store.Runtime_state.pools := updated;
    updated)
;;

let snapshot store =
  Runtime_state.with_lock store.Runtime_state.pools_lock (fun () ->
    !(store.Runtime_state.pools))
;;

let pool_member_to_yojson (member : Config.pool_member) =
  `Assoc
    [ "route_model", `String member.route_model
    ; "daily_token_budget", `Int member.daily_token_budget
    ]
;;

let pool_to_yojson (pool : Config.pool) =
  `Assoc
    [ "name", `String pool.name
    ; "is_global", `Bool pool.is_global
    ; "members", `List (List.map pool_member_to_yojson pool.members)
    ]
;;

let pool_member_of_yojson = function
  | `Assoc fields ->
    (match List.assoc_opt "route_model" fields with
     | Some (`String route_model) ->
       let daily_token_budget =
         match List.assoc_opt "daily_token_budget" fields with
         | Some (`Int v) -> v
         | _ -> 10_000
       in
       Some { Config.route_model; daily_token_budget }
     | _ -> None)
  | _ -> None
;;

let pool_of_yojson = function
  | `Assoc fields ->
    (match List.assoc_opt "name" fields with
     | Some (`String name) ->
       let is_global =
         match List.assoc_opt "is_global" fields with
         | Some (`Bool v) -> v
         | _ -> false
       in
       let members =
         match List.assoc_opt "members" fields with
         | Some (`List items) -> List.filter_map pool_member_of_yojson items
         | _ -> []
       in
       Some { Config.name; members; is_global }
     | _ -> None)
  | _ -> None
;;

let pools_to_yojson pools = `List (List.map pool_to_yojson pools)

let pools_of_yojson = function
  | `List items -> List.filter_map pool_of_yojson items
  | _ -> []
;;

(* Persist the current pool list to SQLite. Silently no-ops when the store is
   stateless; in that case the runtime mutations live only for the current
   process. *)
let persist store pools =
  match store.Runtime_state.persistent_store with
  | None -> ()
  | Some ps ->
    (try Persistent_store.save_pool_overrides ps (pools_to_yojson pools) with
     | _ ->
       (* SQLite write errors must not prevent the wizard from showing the
          updated state in-memory; the next mutation will retry. *)
       ())
;;

(** Hydrate the in-memory pools field from any persisted overrides. Called
    once at startup, after [Runtime_state.create_result]. *)
let load_overrides_into store =
  match store.Runtime_state.persistent_store with
  | None -> ()
  | Some ps ->
    (match Persistent_store.load_pool_overrides ps with
     | None -> ()
     | Some json ->
       let restored = pools_of_yojson json in
       Runtime_state.with_lock store.pools_lock (fun () ->
         store.pools := restored))
;;

let find_pool pools name =
  List.find_opt (fun (pool : Config.pool) -> String.equal pool.name name) pools
;;

let replace_or_append pools (pool : Config.pool) =
  let exists = find_pool pools pool.name |> Option.is_some in
  if exists
  then
    List.map
      (fun (existing : Config.pool) ->
        if String.equal existing.name pool.name then pool else existing)
      pools
  else pools @ [ pool ]
;;

let create_pool store ~name =
  let trimmed = String.trim name in
  if trimmed = ""
  then Error "pool name cannot be empty"
  else if List.exists
            (fun (route : Config.route) -> String.equal route.public_model trimmed)
            store.Runtime_state.config.Config.routes
  then Error (Fmt.str "pool name %S collides with an existing route" trimmed)
  else (
    let updated =
      with_pools store (fun pools ->
        match find_pool pools trimmed with
        | Some _ -> pools
        | None -> pools @ [ { Config.name = trimmed; members = []; is_global = false } ])
    in
    persist store updated;
    Ok ())
;;

let drop_pool store ~name =
  let updated =
    with_pools store (fun pools ->
      List.filter (fun (pool : Config.pool) -> not (String.equal pool.name name)) pools)
  in
  persist store updated;
  Ok ()
;;

let add_member store ~pool_name ~route_model ~daily_token_budget =
  match
    List.find_opt
      (fun (route : Config.route) -> String.equal route.public_model route_model)
      store.Runtime_state.config.Config.routes
  with
  | None -> Error (Fmt.str "route %S is not configured" route_model)
  | Some _ ->
    let result =
      ref (Error (Fmt.str "pool %S does not exist; create it first" pool_name))
    in
    let updated =
      with_pools store (fun pools ->
        match find_pool pools pool_name with
        | None -> pools
        | Some pool ->
          (* Replace if the route already exists in the pool, else append. *)
          let new_members =
            let already =
              List.exists
                (fun (m : Config.pool_member) -> String.equal m.route_model route_model)
                pool.members
            in
            if already
            then
              List.map
                (fun (m : Config.pool_member) ->
                  if String.equal m.route_model route_model
                  then { m with daily_token_budget }
                  else m)
                pool.members
            else pool.members @ [ { route_model; daily_token_budget } ]
          in
          result := Ok ();
          replace_or_append pools { pool with members = new_members })
    in
    (match !result with
     | Ok () ->
       persist store updated;
       Ok ()
     | err -> err)
;;

let remove_member store ~pool_name ~route_model =
  let updated =
    with_pools store (fun pools ->
      match find_pool pools pool_name with
      | None -> pools
      | Some pool ->
        let new_members =
          List.filter
            (fun (m : Config.pool_member) ->
              not (String.equal m.route_model route_model))
            pool.members
        in
        replace_or_append pools { pool with members = new_members })
  in
  persist store updated;
  Ok ()
;;

let set_global store ~enabled =
  let global_name = "global" in
  let updated =
    with_pools store (fun pools ->
      let without_global =
        List.filter
          (fun (pool : Config.pool) -> not (String.equal pool.name global_name))
          pools
      in
      if enabled
      then
        without_global
        @ [ { Config.name = global_name; members = []; is_global = true } ]
      else without_global)
  in
  persist store updated;
  Ok ()
;;
