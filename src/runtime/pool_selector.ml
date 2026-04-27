(** Choose the best member to serve a pool request.

    "Best" = the member with the lowest observed latency that
      - has not yet exhausted its daily token budget,
      - has at least one closed-circuit backend on its route, and
      - actually exists in the current route configuration.

    Members that have never been observed (no latency sample yet) sort BEFORE
    well-known slow members so the pool naturally probes new entries instead
    of starving them. The full ordered list of viable members is returned so
    the caller can fall back from one to the next on transient failure. *)

type ranked_member =
  { pool_name : string
  ; member : Config.pool_member
  ; route : Config.route
  ; remaining_tokens : int
      (** [max_int] means "budget effectively unlimited" (e.g. the global
          pool, which delegates budget to virtual keys). *)
  ; latency_score : float option
      (** [None] when the member has never been measured. *)
  }

type unavailable_reason =
  | Route_missing
  | Budget_exhausted
  | All_circuits_open

type rejected_member =
  { route_model : string
  ; reason : unavailable_reason
  }

type ranking =
  { ranked : ranked_member list
  ; rejected : rejected_member list
  }

let current_day () =
  let tm = Unix.gmtime (Unix.time ()) in
  Fmt.str "%04d-%02d-%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
;;

let in_memory_key ~usage_day ~pool_name ~route_model =
  Fmt.str "%s|%s|%s" usage_day pool_name route_model
;;

let consumption store ~usage_day ~pool_name ~route_model =
  match store.Runtime_state.persistent_store with
  | Some ps ->
    Persistent_store.pool_member_consumption ps ~usage_day ~pool_name ~route_model
  | None ->
    Runtime_state.with_lock store.Runtime_state.budget_usage_lock (fun () ->
      Hashtbl.find_opt
        store.in_memory_pool_usage
        (in_memory_key ~usage_day ~pool_name ~route_model)
      |> Option.value ~default:0)
;;

let route_has_open_breaker store (route : Config.route) =
  let circuit = store.Runtime_state.backend_circuit in
  match route.backends with
  | [] -> true (* no backend configured: treat as broken *)
  | backends ->
    List.for_all
      (fun (backend : Config.backend) ->
        Backend_circuit.is_open circuit backend.provider_id)
      backends
;;

(** Build the ranking for a single pool. *)
let rank store (pool : Config.pool) =
  let usage_day = current_day () in
  let members = Config.effective_pool_members store.Runtime_state.config pool in
  let route_lookup = store.Runtime_state.config.Config.routes in
  let evaluate (member : Config.pool_member) =
    match
      List.find_opt
        (fun (route : Config.route) ->
          String.equal route.public_model member.route_model)
        route_lookup
    with
    | None ->
      Error
        { route_model = member.route_model; reason = Route_missing }
    | Some route ->
      let consumed =
        consumption
          store
          ~usage_day
          ~pool_name:pool.name
          ~route_model:member.route_model
      in
      let remaining =
        if member.daily_token_budget = max_int
        then max_int
        else member.daily_token_budget - consumed
      in
      if remaining <= 0
      then
        Error
          { route_model = member.route_model; reason = Budget_exhausted }
      else if route_has_open_breaker store route
      then
        Error
          { route_model = member.route_model; reason = All_circuits_open }
      else (
        let score =
          Pool_latency.score
            store.Runtime_state.pool_latency
            ~pool_name:pool.name
            ~route_model:member.route_model
        in
        Ok
          { pool_name = pool.name
          ; member
          ; route
          ; remaining_tokens = remaining
          ; latency_score = score
          })
  in
  let ranked, rejected =
    List.fold_left
      (fun (ok, ko) member ->
        match evaluate member with
        | Ok value -> value :: ok, ko
        | Error rej -> ok, rej :: ko)
      ([], [])
      members
  in
  (* Sort: members never observed (latency_score = None) come first so we
     give every fresh entry one chance to record a sample. Within each
     "observed" / "unobserved" bucket, lower score wins (faster member). *)
  let comparator a b =
    match a.latency_score, b.latency_score with
    | None, None -> 0
    | None, Some _ -> -1
    | Some _, None -> 1
    | Some sa, Some sb -> Float.compare sa sb
  in
  { ranked = List.sort comparator (List.rev ranked)
  ; rejected = List.rev rejected
  }
;;

(** Empty ranking → user-facing error. The message is intentionally specific
    so the operator knows whether it's a budget issue, a circuit issue, or a
    config issue. *)
let exhaustion_error ~pool_name (ranking : ranking) =
  let reasons =
    ranking.rejected
    |> List.map (fun rej ->
      match rej.reason with
      | Route_missing -> rej.route_model ^ " (route not configured)"
      | Budget_exhausted -> rej.route_model ^ " (daily budget exhausted)"
      | All_circuits_open -> rej.route_model ^ " (all backends circuit-open)")
  in
  let detail =
    if reasons = []
    then "the pool has no members"
    else "every member is unavailable: " ^ String.concat "; " reasons
  in
  Domain_error.upstream
    (Fmt.str "Pool %S has no usable member right now (%s)." pool_name detail)
;;
