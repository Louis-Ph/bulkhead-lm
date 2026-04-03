open Lwt.Infix

let config_term =
  let doc = "Path to the gateway JSON configuration file." in
  Cmdliner.Arg.(required & opt (some string) None & info [ "config" ] ~docv:"FILE" ~doc)
;;

let authorization_term =
  let doc =
    "Client authorization value. Accepts either a full bearer header or a raw token."
  in
  Cmdliner.Arg.(value & opt (some string) None & info [ "authorization" ] ~docv:"VALUE" ~doc)
;;

let api_key_term =
  let doc =
    "Client API key token. Falls back to AEGISLM_API_KEY, AEGISLM_AUTHORIZATION, or a single plaintext token in config."
  in
  Cmdliner.Arg.(value & opt (some string) None & info [ "api-key" ] ~docv:"TOKEN" ~doc)
;;

let model_term =
  let doc = "Public model route to call. Defaults to the first configured route." in
  Cmdliner.Arg.(value & opt (some string) None & info [ "model" ] ~docv:"MODEL" ~doc)
;;

let system_term =
  let doc = "Optional system instruction prepended to the prompt." in
  Cmdliner.Arg.(value & opt (some string) None & info [ "system" ] ~docv:"TEXT" ~doc)
;;

let stream_term =
  let doc = "Print the response incrementally in the terminal." in
  Cmdliner.Arg.(value & flag & info [ "stream" ] ~doc)
;;

let json_term =
  let doc = "Print the final response as JSON instead of plain text." in
  Cmdliner.Arg.(value & flag & info [ "json" ] ~doc)
;;

let max_tokens_term =
  let doc = "Optional max_tokens value forwarded in ask mode." in
  Cmdliner.Arg.(value & opt (some int) None & info [ "max-tokens" ] ~docv:"N" ~doc)
;;

let prompt_term =
  let doc = "Prompt text. If omitted, stdin is read when piped." in
  Cmdliner.Arg.(value & pos 0 (some string) None & info [] ~docv:"PROMPT" ~doc)
;;

let kind_term =
  let kinds =
    [ "chat", Aegis_lm.Terminal_client.Chat
    ; "responses", Aegis_lm.Terminal_client.Responses
    ; "embeddings", Aegis_lm.Terminal_client.Embeddings
    ]
  in
  let doc = "One-shot or worker request kind." in
  Cmdliner.Arg.(
    value
    & opt (enum kinds) Aegis_lm.Terminal_client.Chat
    & info [ "kind" ] ~docv:"KIND" ~doc)
;;

let request_term =
  let doc = "Raw JSON request payload. If omitted, stdin is read when piped." in
  Cmdliner.Arg.(value & opt (some string) None & info [ "request-json" ] ~docv:"JSON" ~doc)
;;

let jobs_term =
  let doc = "Maximum number of in-flight worker requests." in
  Cmdliner.Arg.(value & opt int 4 & info [ "jobs" ] ~docv:"N" ~doc)
;;

let load_store config_path =
  match Aegis_lm.Config.load config_path with
  | Error err -> Error ("Configuration error: " ^ err)
  | Ok config ->
    (match Aegis_lm.Runtime_state.create_result config with
     | Error err -> Error ("Runtime initialization error: " ^ err)
     | Ok store -> Ok store)
;;

let read_all_stdin () = Lwt_io.read Lwt_io.stdin

let require_text_input ?value ~description () =
  match value with
  | Some value when String.trim value <> "" -> Lwt.return (Ok value)
  | _ ->
    if Unix.isatty Unix.stdin
    then Lwt.return (Error description)
    else
      read_all_stdin ()
      >|= fun content ->
      let trimmed = String.trim content in
      if trimmed = "" then Error description else Ok content
;;

let write_error error =
  let json = Aegis_lm.Domain_error.to_openai_json error |> Yojson.Safe.to_string in
  prerr_endline json;
  1
;;

let write_json_error error =
  print_endline (Aegis_lm.Domain_error.to_openai_json error |> Yojson.Safe.to_string);
  1
;;

let resolve_authorization store ?authorization ?api_key () =
  match Aegis_lm.Terminal_client.resolve_authorization store ?authorization ?api_key () with
  | Ok value -> Ok value
  | Error error -> Error error
;;

let run_ask config_path authorization api_key model system stream as_json max_tokens prompt =
  match load_store config_path with
  | Error err ->
    prerr_endline err;
    1
  | Ok store ->
    Lwt_main.run
      (require_text_input
         ?value:prompt
         ~description:"ask requires a prompt argument or piped stdin."
         ()
       >>= function
       | Error err ->
         Lwt.return
           (write_error (Aegis_lm.Domain_error.invalid_request err))
       | Ok prompt ->
         (match resolve_authorization store ?authorization ?api_key () with
          | Error error -> Lwt.return (write_error error)
          | Ok authorization ->
            (match
               Aegis_lm.Terminal_client.build_ask_request
                 store
                 ?model
                 ?system
                 ?max_tokens
                 ~stream
                 prompt
             with
             | Error error -> Lwt.return (write_error error)
             | Ok request ->
               if stream && as_json
               then
                 Lwt.return
                   (write_error
                      (Aegis_lm.Domain_error.invalid_request
                         "ask does not support combining --stream with --json."))
               else if stream
               then
                 Aegis_lm.Terminal_client.run_ask_stream
                   store
                   ~authorization
                   request
                   ~on_delta:(fun chunk ->
                     print_string chunk;
                     flush stdout;
                     Lwt.return_unit)
                 >|= function
                 | Error error -> write_error error
                 | Ok _ ->
                   print_newline ();
                   0
               else
                 Aegis_lm.Terminal_client.run_ask store ~authorization request
                 >|= function
                 | Error error -> write_error error
                 | Ok response ->
                   if as_json
                   then
                     print_endline
                       (Aegis_lm.Terminal_client.response_to_yojson response
                        |> Yojson.Safe.to_string)
                   else print_endline (Aegis_lm.Terminal_client.text_of_response response);
                   0))))
;;

let run_call config_path authorization api_key kind request_json =
  match load_store config_path with
  | Error err ->
    prerr_endline err;
    1
  | Ok store ->
    Lwt_main.run
      (require_text_input
         ?value:request_json
       ~description:"call requires --request-json or a piped JSON request body."
         ()
       >>= function
       | Error err ->
         Lwt.return
           (write_json_error (Aegis_lm.Domain_error.invalid_request err))
       | Ok request_text ->
         let parsed =
           try Ok (Yojson.Safe.from_string request_text)
           with
           | Yojson.Json_error message ->
             Error
               (Aegis_lm.Domain_error.invalid_request
                  ("Invalid JSON request body: " ^ message))
         in
         (match parsed with
          | Error error -> Lwt.return (write_json_error error)
          | Ok json ->
            (match resolve_authorization store ?authorization ?api_key () with
             | Error error -> Lwt.return (write_json_error error)
             | Ok authorization ->
               Aegis_lm.Terminal_client.invoke_json store ~authorization ~kind json
               >|= function
               | Ok response ->
                 print_endline
                   (Aegis_lm.Terminal_client.response_to_yojson response
                    |> Yojson.Safe.to_string);
                 0
               | Error error ->
                 print_endline
                   (Aegis_lm.Domain_error.to_openai_json error |> Yojson.Safe.to_string);
                 1)))
;;

let run_worker config_path authorization api_key jobs =
  match load_store config_path with
  | Error err ->
    prerr_endline err;
    1
  | Ok store ->
    if jobs < 1
    then (
      prerr_endline "Worker jobs must be greater than or equal to 1.";
      1)
    else (
      Lwt_main.run
        (Aegis_lm.Terminal_worker.run_stdio store ?authorization ?api_key ~jobs () >|= fun () -> 0))
;;

let ask_cmd =
  let doc = "Human-friendly terminal prompt mode with sensible defaults." in
  Cmdliner.Cmd.v
    (Cmdliner.Cmd.info "ask" ~doc)
    Cmdliner.Term.(
      const run_ask
      $ config_term
      $ authorization_term
      $ api_key_term
      $ model_term
      $ system_term
      $ stream_term
      $ json_term
      $ max_tokens_term
      $ prompt_term)
;;

let call_cmd =
  let doc = "One-shot programmable client that accepts a JSON request and prints JSON." in
  Cmdliner.Cmd.v
    (Cmdliner.Cmd.info "call" ~doc)
    Cmdliner.Term.(
      const run_call
      $ config_term
      $ authorization_term
      $ api_key_term
      $ kind_term
      $ request_term)
;;

let worker_cmd =
  let doc = "Long-running JSONL worker for concurrent programmatic use over stdio." in
  Cmdliner.Cmd.v
    (Cmdliner.Cmd.info "worker" ~doc)
    Cmdliner.Term.(
      const run_worker
      $ config_term
      $ authorization_term
      $ api_key_term
      $ jobs_term)
;;

let cmd =
  let doc = "Programmable terminal client and worker for AegisLM" in
  Cmdliner.Cmd.group
    (Cmdliner.Cmd.info "aegislm-client" ~doc)
    [ ask_cmd; call_cmd; worker_cmd ]
;;

let () = exit (Cmdliner.Cmd.eval cmd)
