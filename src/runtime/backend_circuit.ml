(* Per-backend circuit breaker.
   Tracks consecutive failures per provider and temporarily skips backends
   that have exceeded the failure threshold, giving them a cooldown period
   before retrying (half-open state).

   States
   ------
   Closed   – healthy; all requests pass through.
   Open t   – tripped; skip until Unix time t, then → Half_open.
   Half_open – one trial request allowed; success → Closed, failure → Open.
*)

type state =
  | Closed
  | Open of float  (* Unix time at which we transition to Half_open *)
  | Half_open

type record = {
  mutable state   : state;
  mutable strikes : int;   (* consecutive failures while Closed *)
}

type t = {
  records        : (string, record) Hashtbl.t;
  lock           : Mutex.t;
  open_threshold : int;    (* consecutive failures required to open *)
  cooldown_s     : float;  (* seconds before a half-open probe is allowed *)
}

let create ~open_threshold ~cooldown_s =
  { records        = Hashtbl.create 16
  ; lock           = Mutex.create ()
  ; open_threshold = max 1 open_threshold
  ; cooldown_s     = max 1.0 cooldown_s
  }
;;

let with_lock t f =
  Mutex.lock t.lock;
  match f () with
  | v              -> Mutex.unlock t.lock; v
  | exception exn  -> Mutex.unlock t.lock; raise exn
;;

let get_or_init t provider_id =
  match Hashtbl.find_opt t.records provider_id with
  | Some r -> r
  | None   ->
    let r = { state = Closed; strikes = 0 } in
    Hashtbl.replace t.records provider_id r;
    r
;;

(* Returns [true] when the circuit is open and the backend should be skipped.
   Transitions Open → Half_open when the cooldown has elapsed. *)
let is_open t provider_id =
  with_lock t (fun () ->
    let r = get_or_init t provider_id in
    match r.state with
    | Closed | Half_open -> false
    | Open reopens_at ->
      let now = Unix.gettimeofday () in
      if now >= reopens_at then begin
        r.state <- Half_open;
        false   (* let this request through as a probe *)
      end else
        true)   (* still in cooldown — skip this backend *)
;;

let record_success t provider_id =
  with_lock t (fun () ->
    let r = get_or_init t provider_id in
    r.state   <- Closed;
    r.strikes <- 0)
;;

let record_failure t provider_id =
  with_lock t (fun () ->
    let r = get_or_init t provider_id in
    r.strikes <- r.strikes + 1;
    match r.state with
    | Half_open ->
      (* Probe failed — re-open with a fresh cooldown *)
      r.state <- Open (Unix.gettimeofday () +. t.cooldown_s)
    | Closed ->
      if r.strikes >= t.open_threshold then
        r.state <- Open (Unix.gettimeofday () +. t.cooldown_s)
    | Open _ -> ())
;;

(* Summary used by the health endpoint. *)
type health_summary =
  { backends_open   : int
  ; backends_closed : int
  }

let health_summary t =
  with_lock t (fun () ->
    let now = Unix.gettimeofday () in
    Hashtbl.fold
      (fun _id r acc ->
        match r.state with
        | Closed | Half_open ->
          { acc with backends_closed = acc.backends_closed + 1 }
        | Open reopens_at when now >= reopens_at ->
          (* Would transition to half-open on next request — count as available *)
          { acc with backends_closed = acc.backends_closed + 1 }
        | Open _ ->
          { acc with backends_open = acc.backends_open + 1 })
      t.records
      { backends_open = 0; backends_closed = 0 })
;;
