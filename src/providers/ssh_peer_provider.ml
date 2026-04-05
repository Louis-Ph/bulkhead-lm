open Lwt.Infix

let api_key_from_env backend =
  match Sys.getenv_opt backend.Config.api_key_env with
  | Some value when String.trim value <> "" -> Ok (String.trim value)
  | _ ->
    Error
      (Domain_error.upstream
         ~provider_id:backend.Config.provider_id
         ("Missing environment variable " ^ backend.Config.api_key_env))
;;

let ssh_binary () =
  match Sys.getenv_opt "BULKHEAD_LM_SSH_BIN" with
  | Some value when String.trim value <> "" -> Some (String.trim value)
  | _ ->
    (match Unix.system "command -v ssh >/dev/null 2>&1" with
     | Unix.WEXITED 0 -> Some "ssh"
     | _ -> None)
;;

let shell_escape value =
  let escaped =
    String.split_on_char '\'' value |> String.concat "'\"'\"'"
  in
  "'" ^ escaped ^ "'"
;;

let remote_worker_command transport ~api_key =
  let base_args =
    [ transport.Config.remote_worker_command
    ; "--jobs"
    ; string_of_int transport.remote_jobs
    ; "--api-key"
    ; api_key
    ]
  in
  let with_config =
    match transport.remote_config_path with
    | Some path -> base_args @ [ "--config"; path ]
    | None -> base_args
  in
  let with_switch =
    match transport.remote_switch with
    | Some switch -> with_config @ [ "--switch"; switch ]
    | None -> with_config
  in
  with_switch |> List.map shell_escape |> String.concat " "
;;

let ssh_command transport ~api_key =
  match ssh_binary () with
  | None -> Error (Domain_error.upstream "ssh executable was not found in PATH.")
  | Some ssh_bin ->
    let remote_command = remote_worker_command transport ~api_key in
    let argv =
      Array.of_list
        ([ ssh_bin; "-T" ] @ transport.options @ [ transport.destination; remote_command ])
    in
    Ok (ssh_bin, argv)
;;

let stderr_summary stderr =
  let trimmed = String.trim stderr in
  if trimmed = "" then "no stderr output" else trimmed
;;

let run_worker transport ~api_key payload =
  match ssh_command transport ~api_key with
  | Error err -> Lwt.return (Error err)
  | Ok command ->
    Lwt.catch
      (fun () ->
        Lwt_process.with_process_full command (fun process ->
          let write_request =
            Lwt_io.write_line process#stdin payload >>= fun () -> Lwt_io.close process#stdin
          in
          write_request
          >>= fun () ->
          Lwt.both (Lwt_io.read_line_opt process#stdout) (Lwt_io.read process#stderr)
          >>= fun (line_opt, stderr) ->
          process#status >|= fun status -> Ok (line_opt, stderr, status)))
      (fun exn ->
        Lwt.return
          (Error (Domain_error.upstream ("SSH peer invocation failed: " ^ Printexc.to_string exn))))
;;

let remote_result ~provider_id line_opt stderr status parse_response =
  match line_opt, status with
  | Some line, Unix.WEXITED 0 -> parse_response ~provider_id line
  | Some line, _ ->
    (match parse_response ~provider_id line with
     | Ok _ as ok -> ok
     | Error _ ->
       Error
         (Domain_error.upstream
            ~provider_id
            (Fmt.str
               "Remote SSH worker exited abnormally and returned stderr: %s"
               (stderr_summary stderr))))
  | None, _ ->
    Error
      (Domain_error.upstream
         ~provider_id
         (Fmt.str
            "Remote SSH worker produced no response line. stderr: %s"
            (stderr_summary stderr)))
;;

let invoke_worker backend upstream_context ~kind request_json parse_response =
  match Config.backend_ssh_transport backend, api_key_from_env backend with
  | None, _ ->
    Lwt.return
      (Error
         (Domain_error.upstream
            ~provider_id:backend.Config.provider_id
            "bulkhead_ssh_peer backend is missing ssh transport settings."))
  | _, Error err -> Lwt.return (Error err)
  | Some transport, Ok api_key ->
    let request_id = Peer_mesh.generate_request_id () in
    let payload =
      Ssh_peer_protocol.request_json
        ?peer_context:upstream_context.Provider_client.peer_context
        ~request_id
        ~kind
        request_json
      |> Yojson.Safe.to_string
    in
    run_worker transport ~api_key payload
    >|= function
    | Error err -> Error err
    | Ok (line_opt, stderr, status) ->
      remote_result ~provider_id:backend.Config.provider_id line_opt stderr status parse_response
;;

let invoke_chat upstream_context backend request =
  let request_json =
    Openai_types.chat_request_to_yojson
      { request with model = backend.Config.upstream_model; stream = false }
  in
  invoke_worker
    backend
    upstream_context
    ~kind:Ssh_peer_protocol.Chat
    request_json
    Ssh_peer_protocol.chat_response_of_line
;;

let invoke_embeddings upstream_context backend request =
  let request_json =
    `Assoc
      [ "model", `String backend.Config.upstream_model
      ; "input", `List (List.map (fun item -> `String item) request.Openai_types.input)
      ]
  in
  invoke_worker
    backend
    upstream_context
    ~kind:Ssh_peer_protocol.Embeddings
    request_json
    Ssh_peer_protocol.embeddings_response_of_line
;;

let invoke_chat_stream upstream_context backend request =
  invoke_chat upstream_context backend { request with Openai_types.stream = false }
  >|= Result.map Provider_stream.of_chat_response
;;

let make () = { Provider_client.invoke_chat; invoke_chat_stream; invoke_embeddings }
