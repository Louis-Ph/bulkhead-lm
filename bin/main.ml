open Lwt.Infix

let config_term =
  let doc = "Path to the gateway JSON configuration file." in
  Cmdliner.Arg.(required & opt (some string) None & info [ "config" ] ~docv:"FILE" ~doc)
;;

let run config_path =
  Logs.set_reporter (Logs_fmt.reporter ());
  Logs.set_level (Some Logs.Info);
  match Aegis_lm.Config.load config_path with
  | Error err ->
    prerr_endline ("Configuration error: " ^ err);
    exit 1
  | Ok config ->
    let store = Aegis_lm.Runtime_state.create config in
    Lwt_main.run (Aegis_lm.Server.start store)
;;

let cmd =
  let doc = "Secure OCaml LLM gateway with OpenAI-compatible endpoints" in
  Cmdliner.Cmd.v
    (Cmdliner.Cmd.info "aegislm" ~doc)
    Cmdliner.Term.(const run $ config_term)
;;

let () = exit (Cmdliner.Cmd.eval cmd)
