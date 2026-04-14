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
        (if current_line = []
         then acc
         else String.concat " " (List.rev current_line) :: acc)
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
        fold word_length [ word ] (String.concat " " (List.rev current_line) :: acc) rest
  in
  fold 0 [] [] words
;;

let print_wrapped text =
  if String.trim text = "" then print_line "" else List.iter print_line (wrap_text text)
;;

let print_wrapped_styled ~style text =
  if String.trim text = ""
  then print_line ""
  else List.iter (fun line -> print_line (style line)) (wrap_text text)
;;

let print_wrapped_lines lines = List.iter print_wrapped lines
let print_styled_lines ~style lines = List.iter (print_wrapped_styled ~style) lines

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
  let hint = if default then "Y/n" else "y/N" in
  let short_label =
    let width = terminal_width () - 10 in
    if String.length label <= width
    then label
    else (
      print_wrapped label;
      "Include?")
  in
  let full_prompt = short_label ^ " [" ^ hint ^ "]: " in
  let raw =
    try
      Starter_terminal.read_line ~prompt:full_prompt ()
      |> Option.value ~default:""
      |> String.trim
    with
    | End_of_file | Sys.Break -> ""
  in
  match String.lowercase_ascii raw with
  | "" -> default
  | "y" | "yes" -> true
  | "n" | "no" -> false
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
  List.iteri (fun index label -> Printf.printf "  %d. %s\n" (index + 1) label) items;
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
  else (
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
        f ()))
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

let build_starter_config ~base_config_path ~output_path =
  print_line "";
  print_wrapped Starter_constants.Text.builder_title;
  print_wrapped_lines Starter_constants.Text.builder_intro_lines;
  let ready_families, missing_families =
    Starter_profile.provider_families
    |> List.partition (fun (family : Starter_model_catalog.provider_family) ->
      Starter_profile.non_empty_env Sys.getenv_opt family.api_key_env)
  in
  (* Auto-include all providers with detected API keys *)
  let auto_presets =
    if ready_families <> []
    then (
      print_line "";
      print_wrapped "Providers with detected API keys (auto-included):";
      ready_families
      |> List.concat_map (fun (family : Starter_model_catalog.provider_family) ->
        let family_presets = Starter_profile.presets_for_provider_key family.key in
        let route_count = List.length family_presets in
        print_line
          (Fmt.str
             "  %s %s (%d routes, via %s)"
             (Starter_constants.Ansi.green "\xe2\x9c\x93")
             family.label
             route_count
             family.api_key_env);
        family_presets))
    else []
  in
  (* Show skipped providers and offer one batch prompt *)
  let extra_presets =
    if missing_families <> []
    then (
      print_line "";
      print_wrapped "Providers without detected API keys:";
      missing_families
      |> List.iter (fun (family : Starter_model_catalog.provider_family) ->
        let route_count =
          List.length (Starter_profile.presets_for_provider_key family.key)
        in
        print_line
          (Fmt.str
             "  %s %s (%d routes, needs %s)"
             (Starter_constants.Ansi.dim "-")
             family.label
             route_count
             family.api_key_env));
      print_line "";
      if prompt_yes_no ~default:false "Configure additional providers without detected keys?"
      then
        missing_families
        |> List.concat_map (fun (family : Starter_model_catalog.provider_family) ->
          let family_presets = Starter_profile.presets_for_provider_key family.key in
          if prompt_yes_no ~default:false (Fmt.str "Include %s?" family.label)
          then (
            let api_key_env =
              prompt
                ~default:family.api_key_env
                (Fmt.str "Environment variable for %s" family.label)
            in
            maybe_capture_session_key api_key_env;
            family_presets
            |> List.map (fun preset ->
              Starter_profile.preset_with_api_key_env preset api_key_env))
          else [])
      else [])
    else []
  in
  let selected_presets = auto_presets @ extra_presets
  in
  if selected_presets = []
  then Error "No provider was selected."
  else (
    let virtual_key_name =
      prompt ~default:Starter_constants.Defaults.virtual_key_name "Virtual key name"
    in
    let token_plaintext =
      prompt ~default:Starter_constants.Defaults.virtual_key_token "Virtual key token"
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
    let refs =
      Starter_saved_config.catalog_references_for_output_path
        ~base_config_path
        output_path
    in
    let config_json =
      Starter_profile.config_json
        ~security_policy_file:refs.security_policy_file
        ~error_catalog_file:refs.error_catalog_file
        ~providers_schema_file:refs.providers_schema_file
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

let route_identity_label (status : Starter_profile.route_status) =
  match status.catalog_entry with
  | Some (family, model) ->
    Fmt.str "%s %s" family.label (Model_catalog.model_label model)
  | None -> status.public_model
;;

let backend_summary (backend : Starter_profile.route_backend_status) =
  let target =
    match backend.api_base with
    | Some api_base -> api_base
    | None -> "(ssh transport)"
  in
  Fmt.str
    "%s -> %s via %s [%s]"
    (Config.provider_kind_to_string backend.provider_kind)
    backend.upstream_model
    target
    backend.api_key_env
;;

let route_status_summary status =
  let identity = route_identity_label status in
  let backend_hint =
    match status.Starter_profile.backends with
    | backend :: _ -> Fmt.str " -> %s" backend.upstream_model
    | [] -> ""
  in
  if status.Starter_profile.ready
  then Fmt.str "%s [ready] :: %s%s" status.public_model identity backend_hint
  else
    Fmt.str
      "%s [missing %s] :: %s%s"
      status.public_model
      (String.concat ", " status.backend_envs)
      identity
      backend_hint
;;

let configured_statuses store = Starter_profile.route_statuses store.Runtime_state.config

let route_status_detail_lines (status : Starter_profile.route_status) =
  let catalog_lines =
    match status.catalog_entry with
    | Some (family, model) ->
      [ Fmt.str
          "    hierarchy: %s / %s"
          family.label
          (String.concat " / " (Model_catalog.model_hierarchy_parts model))
      ; Fmt.str
          "    lifecycle: %s"
          (Model_catalog.lifecycle_to_string model.lifecycle)
      ; (if model.capabilities = []
         then "    capabilities: (none declared)"
         else
           Fmt.str "    capabilities: %s" (String.concat ", " model.capabilities))
      ]
    | None -> [ "    hierarchy: (custom route not found in built-in catalog)" ]
  in
  let backend_lines =
    status.backends
    |> List.map (fun backend -> "    backend: " ^ backend_summary backend)
  in
  [ "  " ^ route_status_summary status ] @ catalog_lines @ backend_lines
;;

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
  print_wrapped_styled
    ~style:Starter_constants.Ansi.cyan
    (Fmt.str "Current model: %s" current_model);
  print_wrapped_styled
    ~style:Starter_constants.Ansi.cyan
    (Fmt.str "Current config: %s" config_path);
  print_wrapped_styled
    ~style:Starter_constants.Ansi.dim
    (if Starter_session.conversation_enabled state
     then Starter_constants.Text.memory_enabled
     else Starter_constants.Text.memory_disabled);
  print_line "";
  (match Starter_constants.Text.command_help_lines with
   | [] -> ()
   | header :: entries ->
     print_line (Starter_constants.Ansi.bold header);
     List.iter print_line entries)
;;

let print_lines lines = List.iter print_wrapped lines

let print_models store =
  let ready, missing =
    configured_statuses store |> Starter_profile.split_route_statuses
  in
  print_line "";
  print_line "Ready:";
  if ready = []
  then print_line "  (none)"
  else List.iter (fun s -> print_line ("  " ^ route_status_summary s)) ready;
  if missing <> [] then (
    print_line "";
    print_line "Not ready:";
    List.iter (fun s -> print_line ("  " ^ route_status_summary s)) missing)
;;

let control_plane_url ~host ~port ~path =
  Uri.make ~scheme:"http" ~host ~port ~path () |> Uri.to_string
;;

let control_plane_lines ?(lookup_env = Sys.getenv_opt) ~config_path (config : Config.t) =
  let security_policy = config.security_policy in
  let server = security_policy.server in
  let control_plane = security_policy.control_plane in
  let url_for_path path = control_plane_url ~host:server.listen_host ~port:server.listen_port ~path in
  let admin_token_line =
    match control_plane.admin_token_env with
    | None -> "Admin token: not required by current config."
    | Some env_name ->
      let status =
        match lookup_env env_name with
        | Some value when String.trim value <> "" -> "set"
        | _ -> "missing"
      in
      Fmt.str "Admin token env: %s (%s)" env_name status
  in
  let config_lines =
    if String.trim config_path = ""
    then []
    else
      [ Fmt.str "Current config: %s" config_path
      ; Fmt.str
          "Start command: ./scripts/with_local_toolchain.sh dune exec bulkhead-lm -- --config %s"
          (Filename.quote config_path)
      ]
  in
  let status_lines =
    if control_plane.enabled
    then
      [ Starter_constants.Text.control_plane_enabled
      ; (if control_plane.ui_enabled
         then Fmt.str "Browser UI: %s" (url_for_path control_plane.path_prefix)
         else "Browser UI: disabled in this config.")
      ; Fmt.str
          "Status API: %s"
          (url_for_path
             (control_plane.path_prefix ^ Admin_control_constants.Path.status_suffix))
      ; (if control_plane.allow_reload
         then
           Fmt.str
             "Reload API: %s"
             (url_for_path
                (control_plane.path_prefix ^ Admin_control_constants.Path.reload_suffix))
         else "Hot reload: disabled in this config.")
      ; admin_token_line
      ; "The browser control plane appears only when the gateway server is running separately from this starter."
      ]
    else
      [ Starter_constants.Text.control_plane_disabled
      ; "Use terminal administration in this starter, or enable the HTTP control plane in config and run the gateway server separately."
      ; Fmt.str
          "Suggested request: %s enable the HTTP control plane at %s and keep it bound to 127.0.0.1"
          Starter_constants.Command.admin
          control_plane.path_prefix
      ]
  in
  [ Starter_constants.Text.control_plane_intro
  ; Fmt.str "Gateway bind: %s:%d" server.listen_host server.listen_port
  ]
  @ config_lines
  @ status_lines
  @ Starter_constants.Text.control_plane_terminal_admin_lines
;;

let print_control_plane_status store state =
  print_line "";
  control_plane_lines
    ~config_path:(Starter_session.current_config_path state |> Option.value ~default:"")
    store.Runtime_state.config
  |> print_lines
;;

let starter_commands () =
  Starter_constants.Command.all
;;

let update_terminal_context store =
  let models =
    configured_statuses store
    |> List.map (fun (status : Starter_profile.route_status) -> status.public_model)
  in
  Starter_terminal.set_context ~commands:(starter_commands ()) ~models
;;

let print_provider_matrix store =
  let ready, missing =
    configured_statuses store |> Starter_profile.split_route_statuses
  in
  let print_group title statuses =
    print_line "";
    print_line title;
    if statuses = []
    then print_line "  (none)"
    else
      List.iter (fun status -> print_line ("  " ^ route_status_summary status)) statuses
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

let print_tools_help () = print_wrapped_lines Starter_constants.Text.tool_help_lines

let print_pending_files runtime =
  match runtime.Starter_runtime.pending_attachments with
  | [] ->
    print_wrapped_styled
      ~style:Starter_constants.Ansi.dim
      Starter_constants.Text.files_empty
  | attachments ->
    Starter_attachment.render_lines attachments
    |> print_styled_lines ~style:Starter_constants.Ansi.cyan
;;

let attach_local_file runtime path =
  match
    Starter_attachment.load
      ~max_bytes:Starter_constants.Defaults.attachment_max_bytes
      path
  with
  | Ok attachment ->
    let runtime =
      Starter_runtime.set_pending_attachments
        runtime
        (runtime.pending_attachments @ [ attachment ])
    in
    print_wrapped (Starter_constants.Text.file_attached attachment.display_path);
    print_wrapped Starter_constants.Text.files_will_be_used;
    runtime
  | Error message ->
    let lowered = String.lowercase_ascii message in
    if String.starts_with ~prefix:"binary files are not supported" lowered
    then print_wrapped Starter_constants.Text.binary_file_rejected
    else print_wrapped message;
    runtime
;;

let run_local_tool_lines lines =
  match lines with
  | [] -> print_line ""
  | _ -> print_lines lines
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

let print_pending_admin_plan runtime =
  match runtime.Starter_runtime.pending_admin_plan with
  | None -> print_wrapped Starter_constants.Text.no_admin_plan
  | Some pending_plan -> print_lines (Admin_assistant.render_pending_plan pending_plan)
;;

let prompt_non_empty ?default label =
  let rec loop () =
    let value = prompt ?default label |> String.trim in
    if value = ""
    then (
      print_line "Please enter a value.";
      loop ())
    else value
  in
  loop ()
;;

let prompt_package_request config_path =
  match Starter_packaging.detect_host_os () with
  | Error message ->
    print_wrapped message;
    None
  | Ok host_os ->
    print_line "";
    print_wrapped Starter_constants.Text.package_intro;
    let defaults = Starter_packaging.default_request ~config_path host_os in
    let package_name =
      prompt_non_empty ~default:defaults.package_name "System package name"
      |> Starter_packaging.normalize_token
    in
    let display_name = prompt_non_empty ~default:defaults.display_name "Display name" in
    let version =
      prompt_non_empty ~default:defaults.version "Package version"
      |> Starter_packaging.normalize_version
    in
    let maintainer = prompt_non_empty ~default:defaults.maintainer "Maintainer" in
    let description =
      prompt_non_empty ~default:defaults.description "Short description"
    in
    let install_root = prompt_non_empty ~default:defaults.install_root "Install root" in
    let wrapper_dir =
      prompt_non_empty ~default:defaults.wrapper_dir "Wrapper directory"
    in
    let artifact_dir =
      prompt_non_empty ~default:defaults.artifact_dir "Artifact directory"
    in
    let config_source =
      prompt_non_empty ~default:defaults.config_source "Config file to bundle"
    in
    let identifier =
      match defaults.identifier with
      | Some default_identifier ->
        Some (prompt_non_empty ~default:default_identifier "Package identifier")
      | None -> None
    in
    Some
      { Starter_packaging.host_os
      ; package_name
      ; display_name
      ; version
      ; maintainer
      ; description
      ; install_root
      ; wrapper_dir
      ; artifact_dir
      ; config_source
      ; identifier
      }
;;

let run_package_request request =
  let root_dir = Sys.getcwd () in
  let on_output line =
    print_endline line;
    flush stdout;
    Lwt.return_unit
  in
  Lwt_main.run (Starter_packaging.run_build ~root_dir request ~on_output)
;;

let rec run_guided_package_build config_path =
  match prompt_package_request config_path with
  | None -> ()
  | Some request ->
    print_line "";
    print_lines (Starter_packaging.request_summary request);
    if prompt_yes_no ~default:true "Start the package build now?"
    then (
      let result = run_package_request request in
      match result.artifact_path, result.exit_code with
      | Some artifact_path, 0 ->
        print_wrapped (Starter_packaging_constants.Text.package_done artifact_path)
      | _ ->
        print_wrapped Starter_constants.Text.package_failed;
        if prompt_yes_no ~default:true "Adjust the packaging settings and retry now?"
        then run_guided_package_build config_path)
    else ()
;;

let refresh_store config_path =
  match load_store config_path with
  | Error message -> Error message
  | Ok loaded ->
    update_terminal_context loaded.store;
    Ok loaded
;;

let resolve_active_model store state =
  match Starter_session.current_model state with
  | Some model ->
    (match ensure_ready_model store model with
     | Ok ready_model -> Ok ready_model
     | Error _ -> choose_model store)
  | None -> choose_model store
;;

let reload_after_config_apply state config_path =
  match refresh_store config_path with
  | Error message -> Error message
  | Ok loaded ->
    (match resolve_authorization loaded.store with
     | Error err -> Error (Domain_error.to_string err)
     | Ok authorization ->
       (match resolve_active_model loaded.store state with
        | Error message -> Error message
        | Ok model ->
          Ok (loaded.store, authorization, Starter_session.set_model state model)))
;;

let prompt_input model =
  try
    match
      Starter_terminal.read_line
        ~record_history:true
        ~prompt:
          (* linenoise measures prompt width from the raw prompt string, so ANSI
             escapes shift the editing cursor to the right. Keep the input prompt plain. *)
          (Fmt.str "%s> " model)
        ()
    with
    | Some line -> line
    | None -> Starter_constants.Command.quit
  with
  | Sys.Break ->
    print_newline ();
    flush stdout;
    print_wrapped_styled
      ~style:Starter_constants.Ansi.yellow
      Starter_constants.Text.interrupted_message;
    ""
;;

let request_messages state runtime prompt : Openai_types.message list =
  let capability_message : Openai_types.message =
    { Openai_types.role = "system"
    ; content = Starter_constants.Text.assistant_capabilities_system_prompt
    }
  in
  let prompt =
    Starter_attachment.inject_into_prompt
      runtime.Starter_runtime.pending_attachments
      prompt
  in
  if Starter_session.conversation_enabled state
  then
    capability_message
    :: Starter_conversation.request_messages
         runtime.Starter_runtime.conversation
         ~pending_user:prompt
  else
    [ capability_message
    ; ({ Openai_types.role = "user"; content = prompt } : Openai_types.message)
    ]
;;

let render_stream_signal_event = function
  | Starter_response_signal.Text text -> print_string text
  | Starter_response_signal.Set_level level ->
    print_string (Starter_constants.Assistant_signal.ansi_open level)
;;

let run_stream_messages store ~authorization ~model messages =
  match Terminal_client.build_chat_request store ~model ~stream:true messages with
  | Error err -> Stream_failed err
  | Ok request ->
    (try
       let signal_state = ref Starter_response_signal.initial_state in
       let result =
         Lwt_main.run
           (Terminal_client.run_ask_stream
              store
              ~authorization
              request
              ~on_delta:(fun chunk ->
                let next_state, events = Starter_response_signal.feed !signal_state chunk in
                signal_state := next_state;
                List.iter render_stream_signal_event events;
                flush stdout;
                Lwt.return_unit))
       in
       let _, tail_events = Starter_response_signal.finish !signal_state in
       List.iter render_stream_signal_event tail_events;
       print_string Starter_constants.Ansi.reset;
       flush stdout;
       match result with
       | Ok (Terminal_client.Chat_response response) ->
         print_newline ();
         flush stdout;
         Stream_completed response
       | Ok _ ->
         Stream_failed
           (Domain_error.invalid_request "Starter streaming expected a chat response.")
       | Error err -> Stream_failed err
     with
     | Sys.Break ->
       print_string Starter_constants.Ansi.reset;
       print_newline ();
       flush stdout;
       Stream_interrupted)
;;

let remember_exchange state runtime ~user response =
  if not (Starter_session.conversation_enabled state)
  then runtime
  else (
    let assistant =
      response
      |> Terminal_client.text_of_chat_response
      |> Starter_response_signal.strip_markup
    in
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

let plan_admin_request store ~authorization ~model ~config_path goal =
  print_wrapped Starter_constants.Text.admin_planning;
  Lwt_main.run
    (Admin_assistant.prepare_plan store ~authorization ~model ~config_path goal)
;;

let apply_admin_plan store ~authorization ~config_path state runtime =
  match runtime.Starter_runtime.pending_admin_plan with
  | None ->
    print_wrapped Starter_constants.Text.no_admin_plan;
    store, authorization, state, runtime
  | Some pending_plan ->
    print_wrapped Starter_constants.Text.admin_applying;
    (match Admin_assistant.apply_config_edits ~config_path pending_plan.plan with
     | Error err ->
       print_wrapped (Domain_error.to_string err);
       store, authorization, Starter_session.finish_stream state, runtime
     | Ok config_lines ->
       if config_lines <> [] then print_lines config_lines;
       let store, authorization, state =
         if pending_plan.plan.Admin_assistant_plan.config_ops = []
         then store, authorization, Starter_session.finish_stream state
         else (
           match
             reload_after_config_apply (Starter_session.finish_stream state) config_path
           with
           | Ok (store, authorization, state) -> store, authorization, state
           | Error message ->
             print_wrapped message;
             store, authorization, Starter_session.finish_stream state)
       in
       let runtime = Starter_runtime.clear_pending_admin_plan runtime in
       let runtime =
         if pending_plan.plan.Admin_assistant_plan.config_ops = []
            && pending_plan.plan.Admin_assistant_plan.system_ops = []
         then (
           print_wrapped Starter_constants.Text.admin_empty_plan;
           runtime)
         else runtime
       in
       (match
          Lwt_main.run
            (Admin_assistant.apply_system_ops store ~authorization pending_plan.plan)
        with
        | Ok system_lines ->
          if system_lines <> [] then print_lines system_lines;
          store, authorization, state, runtime
        | Error err ->
          print_wrapped (Domain_error.to_string err);
          store, authorization, state, runtime))
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
  | Starter_session.Show_tools_panel ->
    print_tools_help ();
    repl store ~authorization next_state runtime
  | Starter_session.Show_control_plane_status ->
    print_control_plane_status store next_state;
    repl store ~authorization next_state runtime
  | Starter_session.Begin_admin_request goal ->
    let model =
      match Starter_session.current_model next_state with
      | Some model -> model
      | None -> ""
    in
    let resumed_state, runtime =
      match
        plan_admin_request
          store
          ~authorization
          ~model
          ~config_path:
            (Starter_session.current_config_path next_state |> Option.value ~default:"")
          goal
      with
      | Ok pending_plan ->
        print_lines (Admin_assistant.render_pending_plan pending_plan);
        ( Starter_session.finish_stream next_state
        , Starter_runtime.set_pending_admin_plan runtime (Some pending_plan) )
      | Error err ->
        print_wrapped (Domain_error.to_string err);
        Starter_session.finish_stream next_state, runtime
    in
    repl store ~authorization resumed_state runtime
  | Starter_session.Begin_package_request ->
    let resumed_state =
      (match Starter_session.current_config_path next_state with
       | Some config_path -> run_guided_package_build config_path
       | None -> ());
      Starter_session.finish_stream next_state
    in
    repl store ~authorization resumed_state runtime
  | Starter_session.Show_pending_admin_plan ->
    print_pending_admin_plan runtime;
    repl store ~authorization next_state runtime
  | Starter_session.Execute_pending_admin_plan ->
    let store, authorization, state, runtime =
      apply_admin_plan
        store
        ~authorization
        ~config_path:
          (Starter_session.current_config_path next_state |> Option.value ~default:"")
        next_state
        runtime
    in
    repl store ~authorization state runtime
  | Starter_session.Drop_pending_admin_plan ->
    print_wrapped Starter_constants.Text.admin_discarded;
    repl
      store
      ~authorization
      next_state
      (Starter_runtime.clear_pending_admin_plan runtime)
  | Starter_session.Show_config_path path ->
    print_line path;
    repl store ~authorization next_state runtime
  | Starter_session.List_models ->
    print_models store;
    repl store ~authorization next_state runtime
  | Starter_session.Show_memory_status ->
    print_memory_status next_state runtime;
    repl store ~authorization next_state runtime
  | Starter_session.Substitute_memory summary ->
    let conversation =
      Starter_conversation.replace_with_summary ~summary
    in
    let summary_char_count =
      (Starter_conversation.stats conversation).summary_char_count
    in
    print_wrapped (Starter_constants.Text.memory_replaced summary_char_count);
    repl
      store
      ~authorization
      next_state
      (Starter_runtime.replace_conversation runtime conversation)
  | Starter_session.Reset_memory ->
    print_wrapped Starter_constants.Text.memory_cleared;
    repl store ~authorization next_state (Starter_runtime.clear_conversation runtime)
  | Starter_session.List_providers ->
    print_provider_matrix store;
    repl store ~authorization next_state runtime
  | Starter_session.List_env ->
    print_env_statuses ();
    repl store ~authorization next_state runtime
  | Starter_session.Attach_local_file path ->
    let runtime = attach_local_file runtime path in
    repl store ~authorization next_state runtime
  | Starter_session.List_pending_files ->
    print_pending_files runtime;
    repl store ~authorization next_state runtime
  | Starter_session.Reset_pending_files ->
    print_wrapped Starter_constants.Text.files_cleared;
    repl
      store
      ~authorization
      next_state
      (Starter_runtime.clear_pending_attachments runtime)
  | Starter_session.Explore_local_path path ->
    run_local_tool_lines (Starter_local_tools.explore store ~authorization path);
    repl store ~authorization next_state runtime
  | Starter_session.Open_local_path path ->
    run_local_tool_lines (Starter_local_tools.open_file store ~authorization path);
    repl store ~authorization next_state runtime
  | Starter_session.Run_local_command command ->
    run_local_tool_lines (Starter_local_tools.run_command store ~authorization command);
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
        let runtime =
          remember_exchange next_state runtime ~user:prompt response
          |> Starter_runtime.clear_pending_attachments
        in
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
  let banner_text = "BulkheadLM Starter" in
  print_line "";
  print_line (Starter_constants.Ansi.bold (Starter_constants.Ansi.cyan banner_text));
  print_line (Starter_constants.Ansi.cyan (String.make (String.length banner_text) '-'));
  print_line "";
  print_styled_lines ~style:Starter_constants.Ansi.dim Starter_constants.Text.intro_lines;
  print_line "";
  print_wrapped_styled
    ~style:Starter_constants.Ansi.dim
    Starter_constants.Text.terminal_ready;
  (match
     Starter_saved_config.ensure
       ~base_config_path
       ~output_path:starter_output_path
   with
   | Ok Starter_saved_config.Already_present -> ()
   | Ok Starter_saved_config.Bootstrapped ->
     print_line "";
     print_wrapped_styled
       ~style:Starter_constants.Ansi.green
       (Starter_constants.Text.starter_saved_config_bootstrapped starter_output_path)
   | Ok Starter_saved_config.Migrated ->
     print_line "";
     print_wrapped_styled
       ~style:Starter_constants.Ansi.green
       (Starter_constants.Text.starter_saved_config_migrated starter_output_path)
   | Error message ->
     print_line "";
     print_wrapped_styled
       ~style:Starter_constants.Ansi.yellow
       (Fmt.str "Starter local config bootstrap warning: %s" message));
  let selected_path =
    match choose_config_source ~base_config_path ~starter_output_path with
    | Example_config -> Ok base_config_path
    | Saved_starter_config -> Ok starter_output_path
    | Build_starter_config -> build_starter_config ~base_config_path ~output_path:starter_output_path
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
