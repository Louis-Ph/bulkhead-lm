open Lwt.Infix

let parse_json_string content =
  if String.trim content = "" then Ok (`Assoc []) else Ok (Yojson.Safe.from_string content)
;;

let read_text_body_limited ~max_bytes body =
  let stream = Cohttp_lwt.Body.to_stream body in
  let buffer = Buffer.create (max 1 (min max_bytes 4096)) in
  let total_bytes = ref 0 in
  let rec loop () =
    Lwt_stream.get stream
    >>= function
    | None ->
      Lwt.catch
        (fun () -> Lwt.return (Ok (Buffer.contents buffer)))
        (fun _exn -> Lwt.return (Error (Domain_error.malformed_json_body ())))
    | Some chunk ->
      total_bytes := !total_bytes + String.length chunk;
      if !total_bytes > max_bytes
      then Lwt.return (Error (Domain_error.request_too_large ~max_bytes))
      else (
        Buffer.add_string buffer chunk;
        loop ())
  in
  loop ()
;;

let read_json_body_limited ~max_bytes body =
  read_text_body_limited ~max_bytes body
  >>= function
  | Error _ as error -> Lwt.return error
  | Ok content ->
    Lwt.catch
      (fun () -> Lwt.return (parse_json_string content))
      (fun _exn -> Lwt.return (Error (Domain_error.malformed_json_body ())))
;;

let read_request_text store body =
  let server_policy = store.Runtime_state.config.security_policy.server in
  Timeout_guard.with_timeout_ms
    ~timeout_ms:server_policy.request_timeout_ms
    ~on_timeout:(fun () ->
      Error (Domain_error.request_timeout ~timeout_ms:server_policy.request_timeout_ms ()))
    (read_text_body_limited ~max_bytes:server_policy.max_request_body_bytes body)
;;

let read_request_json store body =
  let server_policy = store.Runtime_state.config.security_policy.server in
  Timeout_guard.with_timeout_ms
    ~timeout_ms:server_policy.request_timeout_ms
    ~on_timeout:(fun () ->
      Error (Domain_error.request_timeout ~timeout_ms:server_policy.request_timeout_ms ()))
    (read_json_body_limited ~max_bytes:server_policy.max_request_body_bytes body)
;;
