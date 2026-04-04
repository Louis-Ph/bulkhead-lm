type exec_plan =
  { command : string
  ; args : string list
  }

type op_kind =
  | File_op
  | Exec_op

let trim = String.trim

let truncation_notice label =
  Fmt.str "%s output was truncated for terminal display." label
;;

let truncate_text ~max_chars text =
  if String.length text <= max_chars
  then text, false
  else String.sub text 0 max_chars ^ "\n...", true
;;

let split_lines text =
  text
  |> String.split_on_char '\n'
  |> List.map trim
  |> List.filter (fun line -> line <> "")
;;

let display_block ~label ~max_chars text =
  let trimmed = trim text in
  if trimmed = ""
  then []
  else
    let shown, truncated = truncate_text ~max_chars trimmed in
    let lines = (label ^ ":") :: split_lines shown in
    if truncated then lines @ [ truncation_notice label ] else lines
;;

let dir_entry_kind_label = function
  | Terminal_ops.File -> "file"
  | Terminal_ops.Directory -> "dir"
  | Terminal_ops.Symlink -> "symlink"
  | Terminal_ops.Other -> "other"
;;

let dir_entry_line (entry : Terminal_ops.dir_entry) =
  match entry.size_bytes with
  | Some size ->
    Fmt.str
      "  [%s] %s (%d bytes)"
      (dir_entry_kind_label entry.kind)
      entry.name
      size
  | None -> Fmt.str "  [%s] %s" (dir_entry_kind_label entry.kind) entry.name
;;

let result_lines_of_response = function
  | Terminal_ops.Listed_dir response ->
    let header =
      Fmt.str "Directory: %s (%d entries)" response.path (List.length response.entries)
    in
    header :: List.map dir_entry_line response.entries
  | Terminal_ops.Read_file_result response ->
    let content, truncated =
      truncate_text
        ~max_chars:Starter_constants.Defaults.local_tool_file_preview_chars
        response.content
    in
    let header = Fmt.str "File: %s (%d bytes)" response.path response.bytes_read in
    let lines = header :: split_lines content in
    if truncated then lines @ [ truncation_notice "File preview" ] else lines
  | Terminal_ops.Write_file_result response ->
    [ Fmt.str "Wrote %d bytes to %s" response.bytes_written response.path ]
  | Terminal_ops.Exec_result response ->
    let command_line =
      match response.args with
      | [] -> response.command
      | args -> String.concat " " (response.command :: args)
    in
    let header =
      [ Fmt.str "Command: %s" command_line
      ; Fmt.str "Working directory: %s" response.cwd
      ; Fmt.str "Exit code: %d" response.exit_code
      ]
    in
    let stdout_lines =
      display_block
        ~label:"stdout"
        ~max_chars:Starter_constants.Defaults.local_tool_exec_preview_chars
        response.stdout
    in
    let stderr_lines =
      display_block
        ~label:"stderr"
        ~max_chars:Starter_constants.Defaults.local_tool_exec_preview_chars
        response.stderr
    in
    let truncation_lines =
      if response.truncated then [ truncation_notice "Command" ] else []
    in
    header @ stdout_lines @ stderr_lines @ truncation_lines
;;

let suggestion_lines kind =
  match kind with
  | File_op ->
    [ "Tip: if file exploration is blocked, try:"
    ; "  /admin enable safe local file access in this repository"
    ]
  | Exec_op ->
    [ "Tip: if command execution is blocked, try:"
    ; "  /admin enable safe local command execution in this repository"
    ]
;;

let result_lines kind = function
  | Ok response -> result_lines_of_response response
  | Error err ->
    let base = [ Domain_error.to_string err ] in
    if err.Domain_error.code = "operation_denied"
       || err.code = "invalid_request"
       || err.code = "resource_not_found"
    then base @ suggestion_lines kind
    else base
;;

let invoke store ~authorization request =
  Lwt_main.run (Terminal_ops.invoke store ~authorization request)
;;

let explore store ~authorization path =
  invoke store ~authorization (Terminal_ops.List_dir { path })
  |> result_lines File_op
;;

let open_file store ~authorization path =
  invoke store ~authorization (Terminal_ops.Read_file { path; encoding = Terminal_ops.Utf8 })
  |> result_lines File_op
;;

let flush_token buffer tokens =
  if Buffer.length buffer = 0
  then tokens
  else
    let token = Buffer.contents buffer in
    Buffer.clear buffer;
    token :: tokens
;;

let parse_exec_words input =
  let buffer = Buffer.create (String.length input) in
  let rec loop index quote escaped tokens =
    if index >= String.length input
    then (
      if escaped then Error "Trailing backslash in /run command."
      else (
        let tokens = flush_token buffer tokens |> List.rev in
        match tokens with
        | [] -> Error Starter_constants.Text.run_usage
        | command :: args -> Ok { command; args }))
    else
      let ch = input.[index] in
      if escaped
      then (
        Buffer.add_char buffer ch;
        loop (index + 1) quote false tokens)
      else
        match quote, ch with
        | _, '\\' -> loop (index + 1) quote true tokens
        | None, ('"' | '\'') -> loop (index + 1) (Some ch) false tokens
        | Some active, ch when ch = active -> loop (index + 1) None false tokens
        | None, (' ' | '\t') ->
          let tokens = flush_token buffer tokens in
          loop (index + 1) None false tokens
        | _ ->
          Buffer.add_char buffer ch;
          loop (index + 1) quote false tokens
  in
  loop 0 None false []
;;

let run_command store ~authorization raw_command =
  match parse_exec_words raw_command with
  | Error message -> [ message ]
  | Ok plan ->
    invoke
      store
      ~authorization
      (Terminal_ops.Exec { command = plan.command; args = plan.args; cwd = None })
    |> result_lines Exec_op
;;
