let current_minute_bucket () = int_of_float (Unix.time () /. 60.0)

let minute_bucket_of_key key =
  match String.rindex_opt key ':' with
  | None -> None
  | Some index ->
    let offset = index + 1 in
    let length = String.length key - offset in
    int_of_string_opt (String.sub key offset length)
;;

let prune_expired_windows windows ~current_bucket =
  let expired_keys =
    Hashtbl.fold
      (fun key _ acc ->
        match minute_bucket_of_key key with
        | Some bucket when bucket < current_bucket -> key :: acc
        | _ -> acc)
      windows
      []
  in
  List.iter (Hashtbl.remove windows) expired_keys
;;

let check store ~principal =
  Runtime_state.with_lock store.Runtime_state.request_windows_lock (fun () ->
    let current_bucket = current_minute_bucket () in
    prune_expired_windows store.Runtime_state.request_windows ~current_bucket;
    let key = principal.Runtime_state.name ^ ":" ^ string_of_int current_bucket in
    let count =
      Hashtbl.find_opt store.Runtime_state.request_windows key |> Option.value ~default:0
    in
    if count >= principal.Runtime_state.requests_per_minute
    then Error (Domain_error.rate_limited ())
    else (
      Hashtbl.replace store.Runtime_state.request_windows key (count + 1);
      Ok ()))
;;
