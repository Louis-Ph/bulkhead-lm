open Lwt.Infix

type config_source =
  | Example_config
  | Saved_starter_config
  | Build_starter_config

type loaded_store =
  { path : string
  ; store : Runtime_state.t
  }

type stream_outcome =
  | Stream_completed of Openai_types.chat_response
  | Stream_interrupted
  | Stream_failed of Domain_error.t

let print_line message = print_endline message

let terminal_width () =
  match Sys.getenv_opt "COLUMNS" with
  | Some raw ->
    (match int_of_string_opt raw with
     | Some width when width >= 40 -> width
     | _ -> 80)
  | _ -> 80
;;

let wrap_text text =
  let width = terminal_width () in
  let words = String.split_on_char ' ' text |> List.filter (fun word -> word <> "") in
  let rec fold current_length current_line acc = function
    | [] ->
      List.rev
        (if current_line = [] then acc else String.concat " " (List.rev current_line) :: acc)
    | word :: rest ->
      let word_length = String.length word in
      let next_length =
        if current_line = [] then word_length else current_length + 1 + word_length
      in
      if next_length <= width
      then fold next_length (word :: current_line) acc rest
      else if current_line = []
      then fold word_length [ word ] acc rest
      else
        fold
          word_length
          [ word ]
          (String.concat " " (List.rev current_line) :: acc)
          rest
  in
  fold 0 [] [] words
;;

let print_wrapped text =
  if String.trim text = ""
  then print_line ""
  else List.iter print_line (wrap_text text)
;;

let print_wrapped_lines lines = List.iter print_wrapped lines

let prompt ?default label =
  let suffix =
    match default with
    | Some value -> Fmt.str " [%s]" value
    | None -> ""
  in
  try
    let value =
      Starter_terminal.read_line ~prompt:(label ^ suffix ^ ": ") ()
      |> Option.value ~default:""
      |> String.trim
    in
    match value, default with
    | "", Some fallback -> fallback
    | _ -> value
  with
  | End_of_file ->
    (match default with
     | Some fallback -> fallback
     | None -> "")
  | Sys.Break ->
    print_newline ();
    flush stdout;
    (match default with
     | Some fallback -> fallback
     | None -> "")
;;

let rec prompt_yes_no ?(default = true) label =
  let fallback = if default then "Y/n" else "y/N" in
  match String.lowercase_ascii (prompt ~default:fallback label) with
  | "" -> default
  | "y" | "yes" -> true
  | "n" | "no" -> false
  | value when String.equal value fallback -> default
  | _ ->
    print_line "Please answer y or n.";
    prompt_yes_no ~default label
;;

let prompt_int ?default label =
  let default_text = Option.map string_of_int default in
  let rec loop () =
    let raw = prompt ?default:default_text label in
    match int_of_string_opt raw with
    | Some value -> value
    | None ->
      print_line "Please enter a number.";
      loop ()
  in
  loop ()
;;

let rec prompt_choice title items =
  print_line "";
  print_wrapped title;
  List.iteri
    (fun index label -> Printf.printf "  %d. %s\n" (index + 1) label)
    items;
  flush stdout;
  let raw = prompt ~default:"1" "Choose a number" in
  match int_of_string_opt raw with
  | Some value when value >= 1 && value <= List.length items -> value - 1
  | _ ->
    print_line "Please choose one of the listed numbers.";
    prompt_choice title items
;;

let with_hidden_input f =
  if not (Unix.isatty Unix.stdin)
  then f ()
  else
    let fd = Unix.descr_of_in_channel stdin in
    let attrs = Unix.tcgetattr fd in
    let hidden = { attrs with Unix.c_echo = false } in
    Fun.protect
      ~finally:(fun () ->
        Unix.tcsetattr fd Unix.TCSANOW attrs;
        print_newline ();
        flush stdout)
      (fun () ->
        Unix.tcsetattr fd Unix.TCSANOW hidden;
        f ())
;;

let prompt_secret ?default label =
  print_string (label ^ ": ");
  flush stdout;
  let value =
    with_hidden_input (fun () ->
      try read_line () with
      | End_of_file ->
        (match default with
         | Some fallback -> fallback
         | None -> "")
      | Sys.Break ->
        print_newline ();
        flush stdout;
        (match default with
         | Some fallback -> fallback
         | None -> ""))
  in
  match String.trim value, default with
  | "", Some fallback -> fallback
  | trimmed, _ -> trimmed
;;

let load_store path =
  match Config.load path with
  | Error err -> Error ("Configuration error: " ^ err)
  | Ok config ->
    (match Runtime_state.create_result config with
     | Error err -> Error ("Runtime initialization error: " ^ err)
     | Ok store -> Ok { path; store })
;;

let choose_config_source ~base_config_path ~starter_output_path =
  let has_saved = Sys.file_exists starter_output_path in
  let labels =
    if has_saved
    then
      [ Fmt.str "Use saved starter config (%s)" starter_output_path
      ; Fmt.str "Use repository example config (%s)" base_config_path
      ; Fmt.str "Build or rebuild starter config (%s)" starter_output_path
      ]
    else
      [ Fmt.str "Use repository example config (%s)" base_config_path
      ; Fmt.str "Build starter config (%s)" starter_output_path
      ]
  in
  match has_saved, prompt_choice "How do you want to start?" labels with
  | true, 0 -> Saved_starter_config
  | true, 1 -> Example_config
  | true, _ -> Build_starter_config
  | false, 0 -> Example_config
  | false, _ -> Build_starter_config
;;

let maybe_capture_session_key env_name =
  if prompt_yes_no ~default:false (Fmt.str "Paste %s now for this session only?" env_name)
  then (
    let value = prompt_secret (Fmt.str "%s value" env_name) in
    if String.trim value <> "" then Unix.putenv env_name value)
;;

let build_starter_config ~output_path =
  print_line "";
  print_wrapped Starter_constants.Text.builder_title;
  print_wrapped_lines Starter_constants.Text.builder_intro_lines;
  let selected_presets =
    Starter_profile.presets
    |> List.filter_map (fun preset ->
      let ready = Starter_profile.preset_is_ready preset in
      let default = ready in
      let label =
        if ready
        then
          Fmt.str
            "Include %s (detected via %s)"
            (Starter_profile.preset_summary preset)
            preset.api_key_env
        else
          Fmt.str
            "Include %s (no %s detected yet)"
            (Starter_profile.preset_summary preset)
            preset.api_key_env
      in
      if prompt_yes_no ~default label
      then (
        let api_key_env =
          if ready
          then preset.api_key_env
          else prompt ~default:preset.api_key_env (Fmt.str "Environment variable for %s" preset.label)
        in
        if not ready then maybe_capture_session_key api_key_env;
        Some (Starter_profile.preset_with_api_key_env preset api_key_env))
      else None)
  in
  if selected_presets = []
  then Error "No provider was selected."
  else (
    let virtual_key_name =
      prompt
        ~default:Starter_constants.Defaults.virtual_key_name
        "Virtual key name"
    in
    let token_plaintext =
      prompt
        ~default:Starter_constants.Defaults.virtual_key_token
        "Virtual key token"
    in
    let daily_token_budget =
      prompt_int
        ~default:Starter_constants.Defaults.daily_token_budget
        "Daily token budget"
    in
    let requests_per_minute =
      prompt_int
        ~default:Starter_constants.Defaults.requests_per_minute
        "Requests per minute"
    in
    let sqlite_path =
      prompt ~default:Starter_constants.Defaults.sqlite_path "SQLite path"
    in
    let config_json =
      Starter_profile.config_json
        ~selected_presets
        ~virtual_key_name
        ~token_plaintext
        ~daily_token_budget
        ~requests_per_minute
        ~sqlite_path
        ()
    in
    Starter_profile.write_config_file output_path config_json;
    Ok output_path)
;;

let route_status_summary status =
  if status.Starter_profile.ready
  then Fmt.str "%s [ready]" status.public_model
  else
    Fmt.str
      "%s [missing %s]"
      status.public_model
      (String.concat ", " status.backend_envs)
;;

let configured_statuses store = Starter_profile.route_statuses store.Runtime_state.config

let ensure_ready_model store requested_model =
  let resolve statuses =
    statuses
    |> List.find_opt (fun (status : Starter_profile.route_status) ->
      String.equal status.public_model requested_model)
  in
  let statuses = configured_statuses store in
  match resolve statuses with
  | None -> Error (Fmt.str "Configured model not found: %s" requested_model)
  | Some status when status.ready -> Ok status.public_model
  | Some status ->
    List.iter
      (fun env_name ->
        if not (Starter_profile.non_empty_env Sys.getenv_opt env_name)
        then maybe_capture_session_key env_name)
      status.backend_envs;
    let refreshed = configured_statuses store in
    (match resolve refreshed with
     | Some status when status.ready -> Ok status.public_model
     | Some status ->
       Error
         (Fmt.str
            "Model %s still has no configured upstream key. Missing: %s"
            status.public_model
            (String.concat ", " status.backend_envs))
     | None -> Error (Fmt.str "Configured model not found: %s" requested_model))
;;

let choose_model store =
  let statuses = configured_statuses store in
  if statuses = []
  then Error "The selected configuration has no routes."
  else (
    let index =
      prompt_choice
        "Which configured model do you want to use now?"
        (List.map route_status_summary statuses)
    in
    let selected = List.nth statuses index in
    ensure_ready_model store selected.public_model)
;;

let resolve_authorization store =
  match Terminal_client.resolve_authorization store () with
  | Ok authorization -> Ok authorization
  | Error _ ->
    let token =
      prompt
        ~default:Starter_constants.Defaults.virtual_key_token
        "Virtual key token to use locally"
    in
    Terminal_client.resolve_authorization store ~api_key:token ()
;;

let print_help state =
  let current_model =
    match Starter_session.current_model state with
    | Some value -> value
    | None -> "(none)"
  in
  let config_path =
    match Starter_session.current_config_path state with
    | Some value -> value
    | None -> "(none)"
  in
  print_line "";
  print_wrapped (Fmt.str "Current model: %s" current_model);
  print_wrapped (Fmt.str "Current config: %s" config_path);
  print_wrapped
    (if Starter_session.conversation_enabled state
     then Starter_constants.Text.memory_enabled
     else Starter_constants.Text.memory_disabled);
  print_wrapped_lines Starter_constants.Text.command_help_lines
;;

let print_models store =
  print_line "";
  print_line "Configured models:";
  configured_statuses store |> List.iter (fun status -> print_line ("  " ^ route_status_summary status))
;;

let starter_commands () =
  [ Starter_constants.Command.help
  ; Starter_constants.Command.config
  ; Starter_constants.Command.model
  ; Starter_constants.Command.models
  ; Starter_constants.Command.memory
  ; Starter_constants.Command.forget
  ; Starter_constants.Command.providers
  ; Starter_constants.Command.env
  ; Starter_constants.Command.thread
  ; Starter_constants.Command.swap
  ; Starter_constants.Command.quit
  ]
;;

let update_terminal_context store =
  let models =
    configured_statuses store
    |> List.map (fun (status : Starter_profile.route_status) -> status.public_model)
  in
  Starter_terminal.set_context ~commands:(starter_commands ()) ~models
;;

let print_provider_matrix store =
  let ready, missing = configured_statuses store |> Starter_profile.split_route_statuses in
  let print_group title statuses =
    print_line "";
    print_line title;
    if statuses = []
    then print_line "  (none)"
    else List.iter (fun status -> print_line ("  " ^ route_status_summary status)) statuses
  in
  print_group "Ready now" ready;
  print_group "Configuration required" missing
;;

let print_env_statuses () =
  let statuses = Starter_profile.env_statuses () in
  print_line "";
  print_line "Relevant environment variables:";
  List.iter
    (fun (status : Starter_profile.env_status) ->
      match status.masked_value with
      | Some value -> print_line (Fmt.str "  %s=%s" status.name value)
      | None -> print_line (Fmt.str "  %s=(not set)" status.name))
    statuses
;;

let print_memory_status state runtime =
  let stats = Starter_conversation.stats runtime.Starter_runtime.conversation in
  print_line "";
  print_wrapped
    (if Starter_session.conversation_enabled state
     then Starter_constants.Text.memory_enabled
     else Starter_constants.Text.memory_disabled);
  print_wrapped (Fmt.str "Recent verbatim turns: %d" stats.recent_turn_count);
  print_wrapped (Fmt.str "Compressed older turns: %d" stats.compressed_turn_count);
  print_wrapped (Fmt.str "Compressed summary chars: %d" stats.summary_char_count);
  print_wrapped
    (Fmt.str "Estimated context chars currently sent: %d" stats.estimated_context_chars)
;;

let prompt_input model =
  try
    (match Starter_terminal.read_line ~record_history:true ~prompt:(Fmt.str "\n%s> " model) () with
    | Some line -> line
    | None -> Starter_constants.Command.quit)
  with
  | Sys.Break ->
    print_newline ();
    flush stdout;
    print_line Starter_constants.Text.interrupted_message;
    ""
;;

let request_messages state runtime prompt : Openai_types.message list =
  if Starter_session.conversation_enabled state
  then Starter_conversation.request_messages runtime.Starter_runtime.conversation ~pending_user:prompt
  else [ ({ Openai_types.role = "user"; content = prompt } : Openai_types.message) ]
;;

let run_stream_messages store ~authorization ~model messages =
  match Terminal_client.build_chat_request store ~model ~stream:true messages with
  | Error err -> Stream_failed err
  | Ok request ->
    (try
       let result =
         Lwt_main.run
           (Terminal_client.run_ask_stream
              store
              ~authorization
              request
              ~on_delta:(fun chunk ->
                print_string chunk;
                flush stdout;
                Lwt.return_unit))
       in
       (match result with
        | Ok (Terminal_client.Chat_response response) ->
          print_newline ();
          flush stdout;
          Stream_completed response
        | Ok _ ->
          Stream_failed
            (Domain_error.invalid_request "Starter streaming expected a chat response.")
        | Error err -> Stream_failed err)
     with
     | Sys.Break ->
       print_newline ();
       flush stdout;
       Stream_interrupted)
;;

let remember_exchange state runtime ~user response =
  if not (Starter_session.conversation_enabled state)
  then runtime
  else (
    let assistant = Terminal_client.text_of_chat_response response in
    let conversation, event =
      Starter_conversation.commit_exchange
        runtime.Starter_runtime.conversation
        ~user
        ~assistant
    in
    (match event with
     | None -> ()
     | Some event ->
       print_wrapped (Starter_constants.Text.compression_notice event.archived_turn_count));
    Starter_runtime.update_conversation runtime conversation)
;;

let rec repl store ~authorization state runtime =
  let active_model =
    match Starter_session.current_model state with
    | Some model -> model
    | None -> ""
  in
  let input = prompt_input active_model in
  let next_state, effect = Starter_session.step state input in
  match effect with
  | Starter_session.Noop -> repl store ~authorization next_state runtime
  | Starter_session.Exit ->
    print_line Starter_constants.Text.goodbye;
    0
  | Starter_session.Print_message message ->
    print_wrapped message;
    repl store ~authorization next_state runtime
  | Starter_session.Show_help ->
    print_help next_state;
    repl store ~authorization next_state runtime
  | Starter_session.Show_config_path path ->
    print_line path;
    repl store ~authorization next_state runtime
  | Starter_session.List_models ->
    print_models store;
    repl store ~authorization next_state runtime
  | Starter_session.Show_memory_status ->
    print_memory_status next_state runtime;
    repl store ~authorization next_state runtime
  | Starter_session.Reset_memory ->
    print_wrapped Starter_constants.Text.memory_cleared;
    repl
      store
      ~authorization
      next_state
      (Starter_runtime.clear_conversation runtime)
  | Starter_session.List_providers ->
    print_provider_matrix store;
    repl store ~authorization next_state runtime
  | Starter_session.List_env ->
    print_env_statuses ();
    repl store ~authorization next_state runtime
  | Starter_session.Update_thread enabled ->
    print_wrapped
      (if enabled
       then Starter_constants.Text.memory_enabled
       else Starter_constants.Text.memory_disabled);
    repl store ~authorization next_state runtime
  | Starter_session.Select_model ->
    (match choose_model store with
     | Error message ->
       print_wrapped message;
       repl store ~authorization next_state runtime
     | Ok model ->
       print_line (Fmt.str "Switched to %s" model);
       repl store ~authorization (Starter_session.set_model next_state model) runtime)
  | Starter_session.Attempt_swap requested_model ->
    (match ensure_ready_model store requested_model with
     | Error message ->
       print_wrapped message;
       repl store ~authorization next_state runtime
     | Ok model ->
       print_line (Fmt.str "Switched to %s" model);
       repl store ~authorization (Starter_session.set_model next_state model) runtime)
  | Starter_session.Begin_prompt prompt ->
    let model =
      match Starter_session.current_model next_state with
      | Some model -> model
      | None -> ""
    in
    let messages = request_messages next_state runtime prompt in
    let resumed_state, runtime =
      match run_stream_messages store ~authorization ~model messages with
      | Stream_completed response ->
        let runtime = remember_exchange next_state runtime ~user:prompt response in
        Starter_session.finish_stream next_state, runtime
      | Stream_interrupted ->
        print_line Starter_constants.Text.interrupted_message;
        Starter_session.interrupt_stream next_state, runtime
      | Stream_failed err ->
        print_wrapped (Domain_error.to_string err);
        Starter_session.finish_stream next_state, runtime
    in
    repl store ~authorization resumed_state runtime
;;

let run ~base_config_path ~starter_output_path () =
  Sys.catch_break true;
  print_wrapped Starter_constants.Text.title;
  print_line "";
  print_wrapped_lines Starter_constants.Text.intro_lines;
  print_wrapped Starter_constants.Text.terminal_ready;
  let selected_path =
    match choose_config_source ~base_config_path ~starter_output_path with
    | Example_config -> Ok base_config_path
    | Saved_starter_config -> Ok starter_output_path
    | Build_starter_config -> build_starter_config ~output_path:starter_output_path
  in
  match selected_path with
  | Error message ->
    prerr_endline message;
    1
  | Ok config_path ->
    (match load_store config_path with
     | Error err ->
       prerr_endline err;
       1
     | Ok loaded ->
       (match resolve_authorization loaded.store with
        | Error err ->
          prerr_endline (Domain_error.to_string err);
          1
        | Ok authorization ->
          (match choose_model loaded.store with
           | Error message ->
             prerr_endline message;
             1
           | Ok model ->
             update_terminal_context loaded.store;
             let state = Starter_session.create ~model ~config_path:loaded.path in
             print_help state;
             repl loaded.store ~authorization state (Starter_runtime.create ()))))
;;
