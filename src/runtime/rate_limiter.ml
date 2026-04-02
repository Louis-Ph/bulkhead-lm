let current_minute_bucket () = int_of_float (Unix.time () /. 60.0)

let request_key principal =
  principal.Runtime_state.name ^ ":" ^ string_of_int (current_minute_bucket ())
;;

let check store ~principal =
  Runtime_state.with_lock store.Runtime_state.request_windows_lock (fun () ->
    let key = request_key principal in
    let count =
      Hashtbl.find_opt store.Runtime_state.request_windows key |> Option.value ~default:0
    in
    if count >= principal.Runtime_state.requests_per_minute
    then Error (Domain_error.rate_limited ())
    else (
      Hashtbl.replace store.Runtime_state.request_windows key (count + 1);
      Ok ()))
;;
