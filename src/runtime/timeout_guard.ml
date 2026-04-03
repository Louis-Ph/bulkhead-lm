open Lwt.Infix

let with_timeout_ms ~timeout_ms ~on_timeout worker =
  if timeout_ms <= 0
  then Lwt.return (on_timeout ())
  else (
    let protected_worker = Lwt.protected worker in
    let timeout =
      Lwt_unix.sleep (float_of_int timeout_ms /. 1000.)
      >|= fun () -> `Timed_out
    in
    let resolved_worker = protected_worker >|= fun value -> `Result value in
    Lwt.pick [ resolved_worker; timeout ]
    >>= function
    | `Result value -> Lwt.return value
    | `Timed_out ->
      Lwt.cancel worker;
      Lwt.return (on_timeout ()))
;;
