(** Glue between the pool selector and the existing router. Translates a
    pool model name into an ordered list of (member, route) candidates the
    router can iterate over, and provides post-call hooks to record latency
    and charge per-member budgets. *)

open Lwt.Infix

type candidate =
  { pool_name : string
  ; member : Config.pool_member
  ; route : Config.route
  }

let lookup_pool store name = Config.find_pool store.Runtime_state.config name

(** Resolve a model name. Returns [None] when the name is not a pool, in
    which case the caller falls through to the existing route lookup. *)
let resolve_candidates store ~model =
  match lookup_pool store model with
  | None -> None
  | Some pool ->
    let ranking = Pool_selector.rank store pool in
    if ranking.ranked = []
    then Some (Error (Pool_selector.exhaustion_error ~pool_name:pool.name ranking))
    else
      Some
        (Ok
           (List.map
              (fun (member : Pool_selector.ranked_member) ->
                { pool_name = member.pool_name
                ; member = member.member
                ; route = member.route
                })
              ranking.ranked))
;;

(** Check that an upcoming charge of [tokens] still fits in the member's
    remaining budget. Atomicity matters under concurrency, so we delegate to
    the SQLite transaction (or to the in-memory map when no DB is configured). *)
let consume_member_budget store (candidate : candidate) ~tokens =
  let usage_day = Pool_selector.current_day () in
  if candidate.member.daily_token_budget = max_int
  then Ok ()
  else (
    match store.Runtime_state.persistent_store with
    | Some ps ->
      Persistent_store.consume_pool_member_budget
        ps
        ~pool_name:candidate.pool_name
        ~route_model:candidate.member.route_model
        ~daily_token_budget:candidate.member.daily_token_budget
        ~usage_day
        ~tokens
    | None ->
      Runtime_state.with_lock store.budget_usage_lock (fun () ->
        let key =
          Pool_selector.in_memory_key
            ~usage_day
            ~pool_name:candidate.pool_name
            ~route_model:candidate.member.route_model
        in
        let consumed =
          Hashtbl.find_opt store.in_memory_pool_usage key
          |> Option.value ~default:0
        in
        if consumed + tokens > candidate.member.daily_token_budget
        then Error (Domain_error.budget_exceeded ())
        else (
          Hashtbl.replace store.in_memory_pool_usage key (consumed + tokens);
          Ok ())))
;;

let record_success store (candidate : candidate) ~latency_ms =
  Pool_latency.record_success
    store.Runtime_state.pool_latency
    ~pool_name:candidate.pool_name
    ~route_model:candidate.member.route_model
    ~latency_ms
;;

let record_failure store (candidate : candidate) =
  Pool_latency.record_failure
    store.Runtime_state.pool_latency
    ~pool_name:candidate.pool_name
    ~route_model:candidate.member.route_model
;;

(** Time a Lwt operation in milliseconds. *)
let timed worker =
  let start = Unix.gettimeofday () in
  worker ()
  >|= fun result ->
  let latency_ms = (Unix.gettimeofday () -. start) *. 1000. in
  result, latency_ms
;;
