open Lwt.Infix

let ( let* ) = Result.bind

type encoding =
  | Utf8
  | Base64

type list_dir_request = { path : string }
type read_file_request = { path : string; encoding : encoding }

type write_file_request =
  { path : string
  ; content : string
  ; encoding : encoding
  ; overwrite : bool
  ; create_parents : bool
  }

type exec_request =
  { command : string
  ; args : string list
  ; cwd : string option
  }

type request =
  | List_dir of list_dir_request
  | Read_file of read_file_request
  | Write_file of write_file_request
  | Exec of exec_request

type dir_entry_kind =
  | File
  | Directory
  | Symlink
  | Other

type dir_entry =
  { name : string
  ; kind : dir_entry_kind
  ; size_bytes : int option
  }

type list_dir_response =
  { path : string
  ; entries : dir_entry list
  }

type read_file_response =
  { path : string
  ; encoding : encoding
  ; content : string
  ; bytes_read : int
  }

type write_file_response =
  { path : string
  ; bytes_written : int
  ; created : bool
  }

type exec_response =
  { command : string
  ; args : string list
  ; cwd : string
  ; exit_code : int
  ; stdout : string
  ; stderr : string
  ; truncated : bool
  }

type response =
  | Listed_dir of list_dir_response
  | Read_file_result of read_file_response
  | Write_file_result of write_file_response
  | Exec_result of exec_response

type output_budget =
  { remaining : int ref
  ; truncated : bool ref
  ; lock : Lwt_mutex.t
  }

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None
;;

let string_member name = function
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`String value) when String.trim value <> "" -> Ok (String.trim value)
     | _ -> Error name)
  | _ -> Error name
;;

let string_member_opt name json =
  match member name json with
  | Some (`String value) when String.trim value <> "" -> Some (String.trim value)
  | _ -> None
;;

let bool_member_with_default name json ~default =
  match member name json with
  | Some (`Bool value) -> value
  | _ -> default
;;

let string_list_member name json =
  match member name json with
  | Some (`List values) ->
    Ok
      (values
       |> List.filter_map (function
         | `String value -> Some value
         | _ -> None))
  | Some _ -> Error name
  | None -> Ok []
;;

let encoding_to_string = function
  | Utf8 -> "utf8"
  | Base64 -> "base64"
;;

let encoding_of_string = function
  | "utf8" -> Ok Utf8
  | "base64" -> Ok Base64
  | value -> Error value
;;

let dir_entry_kind_to_string = function
  | File -> "file"
  | Directory -> "directory"
  | Symlink -> "symlink"
  | Other -> "other"
;;

let request_name = function
  | List_dir _ -> "list_dir"
  | Read_file _ -> "read_file"
  | Write_file _ -> "write_file"
  | Exec _ -> "exec"
;;

let string_of_command request =
  match request.args with
  | [] -> request.command
  | args -> String.concat " " (request.command :: args)
;;

let text_of_response = function
  | Listed_dir response ->
    Fmt.str
      "Listed %d entries in %s"
      (List.length response.entries)
      response.path
  | Read_file_result response ->
    Fmt.str "Read %d bytes from %s" response.bytes_read response.path
  | Write_file_result response ->
    Fmt.str "Wrote %d bytes to %s" response.bytes_written response.path
  | Exec_result response ->
    Fmt.str
      "Command exited with %d in %s"
      response.exit_code
      response.cwd
;;

let dir_entry_to_yojson entry =
  `Assoc
    [ "name", `String entry.name
    ; "kind", `String (dir_entry_kind_to_string entry.kind)
    ; ( "size_bytes"
      , match entry.size_bytes with
        | Some value -> `Int value
        | None -> `Null )
    ]
;;

let response_to_yojson = function
  | Listed_dir response ->
    `Assoc
      [ "op", `String "list_dir"
      ; "path", `String response.path
      ; "entries", `List (List.map dir_entry_to_yojson response.entries)
      ]
  | Read_file_result response ->
    `Assoc
      [ "op", `String "read_file"
      ; "path", `String response.path
      ; "encoding", `String (encoding_to_string response.encoding)
      ; "content", `String response.content
      ; "bytes_read", `Int response.bytes_read
      ]
  | Write_file_result response ->
    `Assoc
      [ "op", `String "write_file"
      ; "path", `String response.path
      ; "bytes_written", `Int response.bytes_written
      ; "created", `Bool response.created
      ]
  | Exec_result response ->
    `Assoc
      [ "op", `String "exec"
      ; "command", `String response.command
      ; "args", `List (List.map (fun value -> `String value) response.args)
      ; "cwd", `String response.cwd
      ; "exit_code", `Int response.exit_code
      ; "stdout", `String response.stdout
      ; "stderr", `String response.stderr
      ; "truncated", `Bool response.truncated
      ]
;;

let request_of_yojson json =
  let* op = string_member "op" json in
  match op with
  | "list_dir" ->
    let* path = string_member "path" json in
    Ok (List_dir { path })
  | "read_file" ->
    let* path = string_member "path" json in
    let encoding_raw = Option.value (string_member_opt "encoding" json) ~default:"utf8" in
    encoding_of_string encoding_raw
    |> Result.map_error (fun value -> "encoding=" ^ value)
    |> Result.map (fun encoding -> Read_file { path; encoding })
  | "write_file" ->
    let* path = string_member "path" json in
    let* content = string_member "content" json in
    let encoding_raw = Option.value (string_member_opt "encoding" json) ~default:"utf8" in
    encoding_of_string encoding_raw
    |> Result.map_error (fun value -> "encoding=" ^ value)
    |> Result.map (fun encoding ->
      Write_file
        { path
        ; content
        ; encoding
        ; overwrite = bool_member_with_default "overwrite" json ~default:true
        ; create_parents = bool_member_with_default "create_parents" json ~default:false
        })
  | "exec" ->
    let* command = string_member "command" json in
    let* args = string_list_member "args" json in
    Ok (Exec { command; args; cwd = string_member_opt "cwd" json })
  | value -> Error ("op=" ^ value)
;;

let path_segments path =
  String.split_on_char '/' path |> List.filter (fun segment -> segment <> "")
;;

let join_absolute_segments segments =
  match segments with
  | [] -> "/"
  | _ -> "/" ^ String.concat "/" segments
;;

let normalize_absolute_path path =
  let absolute =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path
  in
  let rec loop acc = function
    | [] -> List.rev acc
    | "" :: rest
    | "." :: rest -> loop acc rest
    | ".." :: rest ->
      (match acc with
       | _ :: tail -> loop tail rest
       | [] -> loop [] rest)
    | segment :: rest -> loop (segment :: acc) rest
  in
  join_absolute_segments (loop [] (String.split_on_char '/' absolute))
;;

let existing_realpath path =
  try Ok (Unix.realpath path) with
  | Unix.Unix_error (Unix.ENOENT, _, _) ->
    Error (Domain_error.resource_not_found ("Path was not found: " ^ path))
  | Unix.Unix_error (err, _, _) ->
    Error
      (Domain_error.invalid_request
         ("Unable to resolve path: " ^ Unix.error_message err))
;;

let canonical_roots roots =
  roots
  |> List.filter_map (fun root ->
    match existing_realpath (normalize_absolute_path root) with
    | Ok value -> Some value
    | Error _ -> None)
  |> List.sort_uniq String.compare
;;

let has_root_prefix ~root path =
  if root = "/"
  then true
  else
    let prefix = root ^ "/" in
    path = root || String.starts_with ~prefix path
;;

let ensure_under_roots roots path =
  if List.exists (fun root -> has_root_prefix ~root path) roots
  then Ok ()
  else
    Error
      (Domain_error.operation_denied
         (Fmt.str "Path is outside the configured allowed roots: %s" path))
;;

let default_base_directory roots =
  match roots with
  | [ root ] -> root
  | _ ->
    (match existing_realpath (Sys.getcwd ()) with
     | Ok cwd -> cwd
     | Error _ -> normalize_absolute_path (Sys.getcwd ()))
;;

let resolve_existing_path ~roots raw_path =
  let base = default_base_directory roots in
  let requested =
    if Filename.is_relative raw_path then Filename.concat base raw_path else raw_path
  in
  let normalized = normalize_absolute_path requested in
  let* real_path = existing_realpath normalized in
  let* () = ensure_under_roots roots real_path in
  Ok real_path
;;

let rec nearest_existing_ancestor path =
  if Sys.file_exists path
  then path
  else
    let parent = Filename.dirname path in
    if parent = path then path else nearest_existing_ancestor parent
;;

let drop_prefix_segments ~prefix segments =
  let rec loop prefix_segments target_segments =
    match prefix_segments, target_segments with
    | [], remaining -> Some remaining
    | prefix_head :: prefix_tail, target_head :: target_tail
      when prefix_head = target_head -> loop prefix_tail target_tail
    | _ -> None
  in
  loop prefix segments
;;

let append_segments base segments =
  List.fold_left Filename.concat base segments
;;

let resolve_write_target ~roots raw_path =
  let base = default_base_directory roots in
  let requested =
    if Filename.is_relative raw_path then Filename.concat base raw_path else raw_path
  in
  let normalized = normalize_absolute_path requested in
  let ancestor = nearest_existing_ancestor normalized |> normalize_absolute_path in
  let* ancestor_real = existing_realpath ancestor in
  let remaining =
    drop_prefix_segments ~prefix:(path_segments ancestor) (path_segments normalized)
    |> Option.value ~default:[]
  in
  let candidate = append_segments ancestor_real remaining in
  let* () = ensure_under_roots roots candidate in
  Ok candidate
;;

let ensure_enabled enabled message =
  if enabled then Ok () else Error (Domain_error.operation_denied message)
;;

let ensure_regular_file path =
  try
    let stats = Unix.stat path in
    if stats.Unix.st_kind = Unix.S_REG
    then Ok stats
    else
      Error
        (Domain_error.invalid_request
           ("Expected a regular file but received: " ^ path))
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) ->
    Error (Domain_error.resource_not_found ("Path was not found: " ^ path))
  | Unix.Unix_error (err, _, _) ->
    Error
      (Domain_error.invalid_request
         ("Unable to inspect file: " ^ Unix.error_message err))
;;

let ensure_directory path =
  try
    let stats = Unix.stat path in
    if stats.Unix.st_kind = Unix.S_DIR
    then Ok ()
    else
      Error
        (Domain_error.invalid_request
           ("Expected a directory but received: " ^ path))
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) ->
    Error (Domain_error.resource_not_found ("Path was not found: " ^ path))
  | Unix.Unix_error (err, _, _) ->
    Error
      (Domain_error.invalid_request
         ("Unable to inspect directory: " ^ Unix.error_message err))
;;

let decode_content encoding content =
  match encoding with
  | Utf8 -> Ok content
  | Base64 ->
    (match Base64.decode content with
     | Ok value -> Ok value
     | Error (`Msg message) ->
       Error
         (Domain_error.invalid_request
            ("Invalid base64 content for write_file: " ^ message)))
;;

let encode_content encoding content =
  match encoding with
  | Utf8 -> content
  | Base64 -> Base64.encode_exn content
;;

let ensure_directory_tree path =
  let rec loop current =
    if current = "" || current = "." || current = "/"
    then Ok ()
    else if Sys.file_exists current
    then ensure_directory current
    else (
      let* () = loop (Filename.dirname current) in
      try
        Unix.mkdir current 0o755;
        Ok ()
      with
      | Unix.Unix_error (err, _, _) ->
        Error
          (Domain_error.invalid_request
             ("Unable to create directory: " ^ Unix.error_message err)))
  in
  loop path
;;

let dir_entry_kind_of_stats stats =
  match stats.Unix.st_kind with
  | Unix.S_REG -> File
  | Unix.S_DIR -> Directory
  | Unix.S_LNK -> Symlink
  | _ -> Other
;;

let list_directory_entries path =
  try
    Sys.readdir path
    |> Array.to_list
    |> List.sort String.compare
    |> List.map (fun name ->
      let entry_path = Filename.concat path name in
      let stats_opt =
        try Some (Unix.lstat entry_path) with
        | Unix.Unix_error _ -> None
      in
      let kind, size_bytes =
        match stats_opt with
        | Some stats -> dir_entry_kind_of_stats stats, Some stats.Unix.st_size
        | None -> Other, None
      in
      { name; kind; size_bytes })
    |> fun entries -> Ok entries
  with
  | Sys_error message ->
    Error (Domain_error.invalid_request ("Unable to list directory: " ^ message))
;;

let write_all fd content =
  let rec loop offset =
    if offset >= String.length content
    then Ok ()
    else
      try
        let written =
          Unix.single_write_substring
            fd
            content
            offset
            (String.length content - offset)
        in
        if written <= 0
        then Error (Domain_error.invalid_request "Unable to write file content.")
        else loop (offset + written)
      with
      | Unix.Unix_error (err, _, _) ->
        Error
          (Domain_error.invalid_request
             ("Unable to write file content: " ^ Unix.error_message err))
  in
  loop 0
;;

let exit_code_of_status = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal -> 128 + signal
  | Unix.WSTOPPED signal -> 128 + signal
;;

let create_output_budget max_output_bytes =
  { remaining = ref (max 0 max_output_bytes)
  ; truncated = ref false
  ; lock = Lwt_mutex.create ()
  }
;;

let capture_chunk budget chunk =
  Lwt_mutex.with_lock budget.lock (fun () ->
    if chunk = ""
    then Lwt.return ""
    else if !(budget.remaining) <= 0
    then (
      budget.truncated := true;
      Lwt.return "")
    else
      let keep = min (String.length chunk) !(budget.remaining) in
      budget.remaining := !(budget.remaining) - keep;
      if keep < String.length chunk then budget.truncated := true;
      if keep = 0 then Lwt.return "" else Lwt.return (String.sub chunk 0 keep))
;;

let drain_channel channel budget =
  let buffer = Buffer.create 256 in
  let rec loop () =
    Lwt_io.read ~count:4096 channel
    >>= fun chunk ->
    if chunk = ""
    then Lwt.return (Buffer.contents buffer)
    else
      capture_chunk budget chunk
      >>= fun kept ->
      if kept <> "" then Buffer.add_string buffer kept;
      loop ()
  in
  loop ()
;;

let close_process process =
  Lwt.catch
    (fun () -> process#close >|= fun _ -> ())
    (fun _ -> Lwt.return_unit)
;;

let kill_process process =
  try process#kill Sys.sigkill with
  | _ -> ()
;;

let perform_exec (policy : Security_policy.client_exec) (request : exec_request) =
  let roots = canonical_roots policy.Security_policy.working_roots in
  match
    ensure_enabled
      policy.enabled
      "Client command execution is disabled by security policy."
  with
  | Error err -> Lwt.return (Error err)
  | Ok () ->
    if roots = []
    then
      Lwt.return
        (Error
           (Domain_error.operation_denied
              "No client exec working_roots are configured in security policy."))
    else
      let cwd_raw = Option.value request.cwd ~default:(default_base_directory roots) in
      let cwd_result = resolve_existing_path ~roots cwd_raw in
      (match cwd_result with
       | Error err -> Lwt.return (Error err)
       | Ok cwd ->
         (match ensure_directory cwd with
          | Error err -> Lwt.return (Error err)
          | Ok () ->
            try
              let argv = Array.of_list (request.command :: request.args) in
              let process =
                Lwt_process.open_process_full ~cwd (request.command, argv)
              in
              let budget = create_output_budget policy.max_output_bytes in
              let run =
                Lwt.both
                  (drain_channel process#stdout budget)
                  (drain_channel process#stderr budget)
                >>= fun (stdout, stderr) ->
                process#status
                >|= fun status ->
                Ok
                  (Exec_result
                     { command = request.command
                     ; args = request.args
                     ; cwd
                     ; exit_code = exit_code_of_status status
                     ; stdout
                     ; stderr
                     ; truncated = !(budget.truncated)
                     })
              in
              Lwt.finalize
                (fun () ->
                  Timeout_guard.with_timeout_ms
                    ~timeout_ms:policy.timeout_ms
                    ~on_timeout:(fun () ->
                      kill_process process;
                      Error (Domain_error.command_timeout ~timeout_ms:policy.timeout_ms ()))
                    run)
                (fun () -> close_process process)
            with
            | Unix.Unix_error (err, _, _) ->
              Lwt.return
                (Error
                   (Domain_error.invalid_request
                      ("Unable to start command: " ^ Unix.error_message err)))
            | Failure message ->
              Lwt.return
                (Error
                   (Domain_error.invalid_request
                      ("Unable to start command: " ^ message)))))
;;

let principal_name_json principal = `String principal.Runtime_state.name

let record_event store ~principal request outcome =
  let details =
    let request_fields =
      match request with
      | List_dir data ->
        [ "op", `String "list_dir"; "path", `String data.path ]
      | Read_file data ->
        [ "op", `String "read_file"
        ; "path", `String data.path
        ; "encoding", `String (encoding_to_string data.encoding)
        ]
      | Write_file data ->
        [ "op", `String "write_file"
        ; "path", `String data.path
        ; "encoding", `String (encoding_to_string data.encoding)
        ; "overwrite", `Bool data.overwrite
        ; "create_parents", `Bool data.create_parents
        ]
      | Exec data ->
        [ "op", `String "exec"
        ; "command", `String data.command
        ; "args", `List (List.map (fun value -> `String value) data.args)
        ; ( "cwd"
          , match data.cwd with
            | Some value -> `String value
            | None -> `Null )
        ]
    in
    let outcome_fields =
      match outcome with
      | Ok response ->
        [ "ok", `Bool true
        ; "response", response_to_yojson response
        ; "principal", principal_name_json principal
        ]
      | Error err ->
        [ "ok", `Bool false
        ; "error", Domain_error.to_openai_json err
        ; "principal", principal_name_json principal
        ]
    in
    `Assoc (request_fields @ outcome_fields)
  in
  let status_code =
    match outcome with
    | Ok _ -> 200
    | Error err -> err.Domain_error.status
  in
  Runtime_state.append_audit_event
    store
    { Persistent_store.event_type = "client.ops"
    ; principal_name = Some principal.Runtime_state.name
    ; route_model = None
    ; provider_id = None
    ; status_code
    ; details
    }
;;

let authorize store ~authorization =
  match Auth.authenticate store ~authorization with
  | Error err -> Error err
  | Ok principal ->
    (match Rate_limiter.check store ~principal with
     | Error err -> Error err
     | Ok () -> Ok principal)
;;

let perform_file_request (policy : Security_policy.client_files) request =
  let read_roots = canonical_roots policy.Security_policy.read_roots in
  let write_roots = canonical_roots policy.write_roots in
  match
    ensure_enabled policy.enabled "Client filesystem operations are disabled by security policy."
  with
  | Error err -> Error err
  | Ok () ->
    (match request with
     | List_dir data ->
       if read_roots = []
       then
         Error
           (Domain_error.operation_denied
              "No client file read_roots are configured in security policy.")
       else
         let* path = resolve_existing_path ~roots:read_roots data.path in
         let* () = ensure_directory path in
         list_directory_entries path |> Result.map (fun entries -> Listed_dir { path; entries })
     | Read_file data ->
       if read_roots = []
       then
         Error
           (Domain_error.operation_denied
              "No client file read_roots are configured in security policy.")
       else
         let* path = resolve_existing_path ~roots:read_roots data.path in
         let* stats = ensure_regular_file path in
         if stats.Unix.st_size > policy.max_read_bytes
         then
           Error
             (Domain_error.operation_too_large
                ~subject:"File read"
                ~max_bytes:policy.max_read_bytes)
         else
           let channel = open_in_bin path in
           Fun.protect
             ~finally:(fun () -> close_in_noerr channel)
             (fun () ->
                let bytes_read = in_channel_length channel in
                let content = really_input_string channel bytes_read in
                Ok
                  (Read_file_result
                     { path
                     ; encoding = data.encoding
                     ; content = encode_content data.encoding content
                     ; bytes_read
                     }))
     | Write_file data ->
       if write_roots = []
       then
         Error
           (Domain_error.operation_denied
              "No client file write_roots are configured in security policy.")
       else
         let* decoded = decode_content data.encoding data.content in
         if String.length decoded > policy.max_write_bytes
         then
           Error
             (Domain_error.operation_too_large
                ~subject:"File write"
                ~max_bytes:policy.max_write_bytes)
         else
           let* path = resolve_write_target ~roots:write_roots data.path in
           let parent = Filename.dirname path in
           let* () =
             if data.create_parents then ensure_directory_tree parent else ensure_directory parent
           in
           let created = not (Sys.file_exists path) in
           if not data.overwrite && not created
           then
             Error
               (Domain_error.resource_conflict
                  ("File already exists and overwrite=false: " ^ path))
           else
             let* () =
               if Sys.file_exists path
               then
                 match Unix.lstat path with
                 | { Unix.st_kind = Unix.S_REG; _ } -> Ok ()
                 | _ ->
                   Error
                     (Domain_error.invalid_request
                        ("Refusing to overwrite a non-regular file: " ^ path))
               else Ok ()
             in
             let flags =
               [ Unix.O_WRONLY; Unix.O_CREAT ]
               @ if data.overwrite then [ Unix.O_TRUNC ] else [ Unix.O_EXCL ]
             in
             (try
                let fd = Unix.openfile path flags 0o644 in
                Fun.protect
                  ~finally:(fun () -> Unix.close fd)
                  (fun () ->
                     let* () = write_all fd decoded in
                     let* real_path = existing_realpath path in
                     let* () = ensure_under_roots write_roots real_path in
                     Ok
                       (Write_file_result
                          { path = real_path
                          ; bytes_written = String.length decoded
                          ; created
                          }))
              with
              | Unix.Unix_error (err, _, _) ->
                Error
                  (Domain_error.invalid_request
                     ("Unable to open file for writing: " ^ Unix.error_message err)))
     | Exec _ -> Error (Domain_error.invalid_request "Expected a filesystem operation request."))
;;

let invoke store ~authorization request =
  match authorize store ~authorization with
  | Error err -> Lwt.return (Error err)
  | Ok principal ->
    let worker =
      match request with
      | List_dir _ | Read_file _ | Write_file _ ->
        perform_file_request
          store.Runtime_state.config.Config.security_policy.Security_policy.client_ops.files
          request
        |> Lwt.return
      | Exec exec_request ->
        perform_exec
          store.Runtime_state.config.Config.security_policy.Security_policy.client_ops.exec
          exec_request
    in
    worker
    >|= fun outcome ->
    record_event store ~principal request outcome;
    outcome
;;
