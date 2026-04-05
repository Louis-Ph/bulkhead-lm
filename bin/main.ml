open Lwt.Infix

let config_term =
  let doc = "Path to the gateway JSON configuration file." in
  Cmdliner.Arg.(required & opt (some string) None & info [ "config" ] ~docv:"FILE" ~doc)
;;

let port_term =
  let doc = "Override the listen port from configuration." in
  Cmdliner.Arg.(value & opt (some int) None & info [ "port" ] ~docv:"PORT" ~doc)
;;

let override_port (config : Bulkhead_lm.Config.t) port =
  match port with
  | None -> config
  | Some listen_port ->
    { config with
      Bulkhead_lm.Config.security_policy =
        { config.security_policy with
          Bulkhead_lm.Security_policy.server =
            { config.security_policy.server with listen_port }
        }
    }
;;

let run config_path port =
  Logs.set_reporter (Logs_fmt.reporter ());
  Logs.set_level (Some Logs.Info);
  match Bulkhead_lm.Config.load config_path with
  | Error err ->
    prerr_endline ("Configuration error: " ^ err);
    exit 1
  | Ok config ->
    (match Bulkhead_lm.Runtime_state.create_result (override_port config port) with
     | Error err ->
       prerr_endline ("Runtime initialization error: " ^ err);
       exit 1
     | Ok store -> Lwt_main.run (Bulkhead_lm.Server.start store))
;;

let cmd =
  let doc = "Secure OCaml LLM gateway with OpenAI-compatible endpoints" in
  Cmdliner.Cmd.v
    (Cmdliner.Cmd.info "bulkhead-lm" ~doc)
    Cmdliner.Term.(const run $ config_term $ port_term)
;;

let () = exit (Cmdliner.Cmd.eval cmd)
