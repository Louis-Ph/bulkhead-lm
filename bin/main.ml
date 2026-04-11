let config_term =
  let doc = "Path to the gateway JSON configuration file." in
  Cmdliner.Arg.(required & opt (some string) None & info [ "config" ] ~docv:"FILE" ~doc)
;;

let port_term =
  let doc = "Override the listen port from configuration." in
  Cmdliner.Arg.(value & opt (some int) None & info [ "port" ] ~docv:"PORT" ~doc)
;;

let run config_path port =
  Logs.set_reporter (Logs_fmt.reporter ());
  Logs.set_level (Some Logs.Info);
  match
    Bulkhead_lm.Runtime_control.create_result
      ~config_path
      ~port_override:port
      ()
  with
  | Error err ->
    prerr_endline ("Runtime initialization error: " ^ err);
    exit 1
  | Ok control -> Lwt_main.run (Bulkhead_lm.Server.start control)
;;

let cmd =
  let doc = "Secure OCaml LLM gateway with OpenAI-compatible endpoints" in
  Cmdliner.Cmd.v
    (Cmdliner.Cmd.info "bulkhead-lm" ~doc)
    Cmdliner.Term.(const run $ config_term $ port_term)
;;

let () = exit (Cmdliner.Cmd.eval cmd)
