open Lwt.Infix

type pending_plan =
  { goal : string
  ; plan : Admin_assistant_plan.t
  ; raw_response : string
  }

let trim = String.trim

let non_empty text = trim text <> ""

let normalize_text text =
  text
  |> String.split_on_char '\n'
  |> List.map trim
  |> List.filter non_empty
  |> String.concat "\n"
;;

let truncate_text ~max_chars text =
  if String.length text <= max_chars
  then text
  else String.sub text 0 (max 0 (max_chars - 3)) ^ "..."
;;

let root_dir () = Sys.getcwd ()

let doc_candidates goal =
  let lowered = String.lowercase_ascii goal in
  let contains needle =
    let needle_length = String.length needle in
    let rec loop index =
      if needle_length = 0
      then true
      else if index + needle_length > String.length lowered
      then false
      else if String.sub lowered index needle_length = needle
      then true
      else loop (index + 1)
    in
    loop 0
  in
  if contains "github" || contains "action" || contains "workflow" || contains "release"
  then Admin_assistant_constants.Docs.github_related
  else if contains "ssh" || contains "remote" || contains "peer"
  then Admin_assistant_constants.Docs.ssh_related
  else if contains "provider" || contains "model" || contains "api"
  then Admin_assistant_constants.Docs.provider_related
  else Admin_assistant_constants.Docs.general
;;

let readable_file path =
  Sys.file_exists path
  &&
  try
    let channel = open_in_bin path in
    close_in_noerr channel;
    true
  with
  | Sys_error _ -> false
;;

let read_excerpt path ~max_chars =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      let length = in_channel_length channel in
      really_input_string channel (min length max_chars))
;;

let selected_doc_paths goal =
  doc_candidates goal
  |> List.filter_map (fun relative_path ->
    let absolute_path = Filename.concat (root_dir ()) relative_path in
    if readable_file absolute_path then Some absolute_path else None)
  |> fun paths ->
  let rec take acc count = function
    | [] -> List.rev acc
    | _ when count <= 0 -> List.rev acc
    | path :: rest -> take (path :: acc) (count - 1) rest
  in
  take [] Admin_assistant_constants.Limits.max_docs paths
;;

let doc_excerpt_lines goal =
  selected_doc_paths goal
  |> List.map (fun path ->
    let excerpt =
      read_excerpt path ~max_chars:Admin_assistant_constants.Limits.doc_excerpt_chars
      |> normalize_text
      |> truncate_text ~max_chars:Admin_assistant_constants.Limits.doc_excerpt_chars
    in
    Fmt.str "File: %s\n%s" path excerpt)
;;

let json_file_excerpt path ~max_chars =
  Yojson.Safe.from_file path
  |> Yojson.Safe.pretty_to_string
  |> truncate_text ~max_chars
;;

let provider_summary store =
  Starter_profile.route_statuses store.Runtime_state.config
  |> List.map (fun (status : Starter_profile.route_status) ->
    Fmt.str
      "- %s (%s)"
      status.public_model
      (if status.ready
       then "ready"
       else "missing " ^ String.concat ", " status.backend_envs))
  |> String.concat "\n"
;;

let virtual_key_summary store =
  store.Runtime_state.config.Config.virtual_keys
  |> List.map (fun (key : Config.virtual_key) ->
    Fmt.str
      "- %s: %d req/min, %d daily tokens"
      key.name
      key.requests_per_minute
      key.daily_token_budget)
  |> String.concat "\n"
;;

let system_summary store =
  let files = store.Runtime_state.config.Config.security_policy.Security_policy.client_ops.files in
  let exec = store.Runtime_state.config.Config.security_policy.Security_policy.client_ops.exec in
  String.concat
    "\n"
    [ Fmt.str "OS type: %s" Sys.os_type
    ; Fmt.str "Working directory: %s" (Sys.getcwd ())
    ; Fmt.str "HOME: %s" (Option.value (Sys.getenv_opt "HOME") ~default:"(unknown)")
    ; Fmt.str
        "File ops: enabled=%b read_roots=%s write_roots=%s"
        files.enabled
        (String.concat "," files.read_roots)
        (String.concat "," files.write_roots)
    ; Fmt.str
        "Exec ops: enabled=%b working_roots=%s timeout_ms=%d"
        exec.enabled
        (String.concat "," exec.working_roots)
        exec.timeout_ms
    ]
;;

let plan_user_message store ~config_path ~goal =
  let paths = Config.resolve_related_paths config_path in
  let gateway_json =
    json_file_excerpt
      paths.gateway_config_path
      ~max_chars:Admin_assistant_constants.Limits.gateway_json_chars
  in
  let security_json =
    match paths.security_policy_path with
    | None -> "(no separate security policy file)"
    | Some path ->
      json_file_excerpt
        path
        ~max_chars:Admin_assistant_constants.Limits.security_json_chars
  in
  let docs =
    match doc_excerpt_lines goal with
    | [] -> "(no local docs found)"
    | lines -> String.concat "\n\n---\n\n" lines
  in
  String.concat
    "\n\n"
    [ Fmt.str "User goal:\n%s" goal
    ; "Rules:\n- Prefer config edits.\n- Keep the plan small.\n- Avoid dangerous shell actions."
    ; Fmt.str "Current config path:\n%s" paths.gateway_config_path
    ; Fmt.str
        "Current security policy path:\n%s"
        (Option.value paths.security_policy_path ~default:"(embedded defaults only)")
    ; Fmt.str "Configured routes:\n%s" (provider_summary store)
    ; Fmt.str "Virtual keys:\n%s" (virtual_key_summary store)
    ; Fmt.str "System summary:\n%s" (system_summary store)
    ; Fmt.str "Gateway JSON:\n%s" gateway_json
    ; Fmt.str "Security policy JSON:\n%s" security_json
    ; Fmt.str "Relevant local documentation:\n%s" docs
    ]
;;

let extract_json_payload text =
  let rec find_last_char text target index result =
    if index >= String.length text
    then result
    else
      let updated =
        if Char.equal (String.get text index) target then Some index else result
      in
      find_last_char text target (index + 1) updated
  in
  match String.index_opt text '{', find_last_char text '}' 0 None with
  | Some start_index, Some end_index when end_index >= start_index ->
    Some (String.sub text start_index (end_index - start_index + 1))
  | _ -> None
;;

let parse_plan_text raw_response =
  match extract_json_payload raw_response with
  | None ->
    Error
      (Domain_error.invalid_request
         "The model did not return a JSON admin plan. Try a shorter request.")
  | Some payload ->
    (try
       let json = Yojson.Safe.from_string payload in
       match Admin_assistant_plan.of_yojson json with
       | Ok plan -> Ok plan
       | Error field ->
         Error
           (Domain_error.invalid_request
              ("The admin plan is missing or invalid at field: " ^ field))
     with
     | Yojson.Json_error message ->
       Error
         (Domain_error.invalid_request
            ("The admin plan JSON could not be parsed: " ^ message)))
;;

let prepare_plan store ~authorization ~model ~config_path goal =
  let messages : Openai_types.message list =
    [ { Openai_types.role = "system"
      ; content = Admin_assistant_constants.Prompt.system_instruction
      }
    ; { Openai_types.role = "user"
      ; content = plan_user_message store ~config_path ~goal
      }
    ]
  in
  match Terminal_client.build_chat_request store ~model messages with
  | Error err -> Lwt.return (Error err)
  | Ok request ->
    Terminal_client.run_ask store ~authorization request
    >|= function
    | Error err -> Error err
    | Ok (Terminal_client.Chat_response response) ->
      let raw_response = Terminal_client.text_of_chat_response response in
      parse_plan_text raw_response
      |> Result.map (fun plan -> { goal; plan; raw_response })
    | Ok _ ->
      Error
        (Domain_error.invalid_request
           "The admin assistant expected a chat response from the target model.")
;;

let render_pending_plan pending_plan =
  let header = Fmt.str "Admin request: %s" pending_plan.goal in
  header :: Admin_assistant_plan.render_lines pending_plan.plan
;;

let write_json_file path json =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> Yojson.Safe.pretty_to_channel channel json)
;;

let validate_runtime path =
  match Config.load path with
  | Error err -> Error err
  | Ok config ->
    (match Runtime_state.create_result config with
     | Ok _ -> Ok ()
     | Error err -> Error err)
;;

let apply_config_edits ~config_path plan =
  if plan.Admin_assistant_plan.config_ops = []
  then Ok []
  else
    let paths = Config.resolve_related_paths config_path in
    let original_gateway = Yojson.Safe.from_file paths.gateway_config_path in
    let original_security =
      match paths.security_policy_path with
      | Some path -> Some (Yojson.Safe.from_file path)
      | None -> None
    in
    match
      Admin_assistant_plan.apply_to_inputs
        { gateway_json = original_gateway; security_json = original_security }
        plan
    with
    | Error err -> Error (Domain_error.invalid_request err)
    | Ok updated ->
      let restore () =
        write_json_file paths.gateway_config_path original_gateway;
        match paths.security_policy_path, original_security with
        | Some path, Some security_json -> write_json_file path security_json
        | _ -> ()
      in
      (try
         write_json_file paths.gateway_config_path updated.gateway_json;
         (match paths.security_policy_path, updated.security_json with
          | Some path, Some security_json -> write_json_file path security_json
          | _ -> ());
         (match validate_runtime paths.gateway_config_path with
          | Ok () ->
            Ok
              (List.map
                 (fun op -> "Applied: " ^ Admin_assistant_plan.config_op_summary op)
                 plan.config_ops)
          | Error err ->
            restore ();
            Error
              (Domain_error.invalid_request
                 ("The proposed configuration is invalid: " ^ err)))
       with
       | Sys_error message ->
         restore ();
         Error
           (Domain_error.invalid_request
              ("Could not write the configuration changes: " ^ message)))
;;

let apply_system_ops store ~authorization plan =
  let rec loop acc = function
    | [] -> Lwt.return (Ok (List.rev acc))
    | request :: rest ->
      Terminal_ops.invoke store ~authorization request
      >>= function
      | Error err -> Lwt.return (Error err)
      | Ok response ->
        loop
          (Fmt.str "Applied system action: %s" (Terminal_ops.text_of_response response) :: acc)
          rest
  in
  loop [] plan.Admin_assistant_plan.system_ops
;;
