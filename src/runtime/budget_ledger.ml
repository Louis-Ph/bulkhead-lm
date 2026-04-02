let current_day () =
  let tm = Unix.gmtime (Unix.time ()) in
  Fmt.str "%04d-%02d-%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
;;

let usage_key principal = principal.Runtime_state.name ^ ":" ^ current_day ()

let consume store ~principal ~tokens =
  Runtime_state.with_lock store.Runtime_state.budget_usage_lock (fun () ->
    let key = usage_key principal in
    let consumed =
      Hashtbl.find_opt store.Runtime_state.budget_usage key |> Option.value ~default:0
    in
    if consumed + tokens > principal.Runtime_state.daily_token_budget
    then Error (Domain_error.budget_exceeded ())
    else (
      Hashtbl.replace store.Runtime_state.budget_usage key (consumed + tokens);
      Ok ()))
;;
