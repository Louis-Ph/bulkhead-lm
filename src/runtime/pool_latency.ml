(** In-memory latency tracker for pool members.

    Each (pool_name, route_model) pair carries an exponentially-weighted moving
    average of the observed wall-clock latency in milliseconds plus a small
    streak counter of consecutive failures. The selector consumes [score] to
    pick the cheapest healthy member.

    The tracker lives only in process memory: losing the metrics on restart is
    deliberate, the EWMA reconverges within a handful of requests and removes
    the need for an extra SQLite table. Concurrent access is guarded by a
    single mutex; the recorded operations are short and uncontended in
    practice. *)

type sample =
  { ewma_ms : float
  ; failure_streak : int
  ; samples : int (* total observations, including failures *)
  ; updated_at : float (* Unix time of the last update *)
  }

type t =
  { table : (string, sample) Hashtbl.t
  ; lock : Mutex.t
  ; alpha : float
      (** EWMA smoothing factor in (0., 1.); higher values react faster to
          new samples. *)
  ; failure_penalty_ms : float
      (** Latency increment applied per consecutive failure when scoring,
          so a sticky-failing member is deprioritised until it recovers. *)
  }

let key_separator = String.make 1 (Char.chr 0)
let make_key ~pool_name ~route_model = pool_name ^ key_separator ^ route_model

let create ?(alpha = 0.3) ?(failure_penalty_ms = 1000.) () =
  { table = Hashtbl.create 32
  ; lock = Mutex.create ()
  ; alpha
  ; failure_penalty_ms
  }
;;

let with_lock t f =
  Mutex.lock t.lock;
  match f () with
  | result ->
    Mutex.unlock t.lock;
    result
  | exception exn ->
    Mutex.unlock t.lock;
    raise exn
;;

(** Record a successful call's latency in milliseconds. *)
let record_success t ~pool_name ~route_model ~latency_ms =
  with_lock t (fun () ->
    let key = make_key ~pool_name ~route_model in
    let now = Unix.gettimeofday () in
    let updated =
      match Hashtbl.find_opt t.table key with
      | None -> { ewma_ms = latency_ms; failure_streak = 0; samples = 1; updated_at = now }
      | Some prev ->
        let next_ewma =
          (t.alpha *. latency_ms) +. ((1. -. t.alpha) *. prev.ewma_ms)
        in
        { ewma_ms = next_ewma
        ; failure_streak = 0
        ; samples = prev.samples + 1
        ; updated_at = now
        }
    in
    Hashtbl.replace t.table key updated)
;;

(** Record a failed call. Latency is incremented by the failure penalty so the
    member drops in the ranking but is not permanently excluded. *)
let record_failure t ~pool_name ~route_model =
  with_lock t (fun () ->
    let key = make_key ~pool_name ~route_model in
    let now = Unix.gettimeofday () in
    let updated =
      match Hashtbl.find_opt t.table key with
      | None ->
        { ewma_ms = t.failure_penalty_ms
        ; failure_streak = 1
        ; samples = 1
        ; updated_at = now
        }
      | Some prev ->
        { ewma_ms = prev.ewma_ms +. t.failure_penalty_ms
        ; failure_streak = prev.failure_streak + 1
        ; samples = prev.samples + 1
        ; updated_at = now
        }
    in
    Hashtbl.replace t.table key updated)
;;

(** Lookup the current sample, if any. *)
let lookup t ~pool_name ~route_model =
  with_lock t (fun () ->
    Hashtbl.find_opt t.table (make_key ~pool_name ~route_model))
;;

(** Score used by the selector. Lower is better. Members that have never
    been observed return [None] so the selector can give them a chance ahead
    of well-known slow members instead of pinning to a single fast one and
    starving discovery. *)
let score t ~pool_name ~route_model =
  match lookup t ~pool_name ~route_model with
  | None -> None
  | Some sample ->
    Some (sample.ewma_ms +. (float_of_int sample.failure_streak *. t.failure_penalty_ms))
;;

let reset_member t ~pool_name ~route_model =
  with_lock t (fun () ->
    Hashtbl.remove t.table (make_key ~pool_name ~route_model))
;;

let snapshot t =
  with_lock t (fun () ->
    Hashtbl.fold
      (fun key sample acc ->
        match String.split_on_char (Char.chr 0) key with
        | [ pool_name; route_model ] -> (pool_name, route_model, sample) :: acc
        | _ -> acc)
      t.table
      [])
;;
