type t =
  { absolute_path : string
  ; display_path : string
  ; content : string
  ; truncated : bool
  ; byte_count : int
  }

let expand_home path =
  if String.length path >= 2 && String.sub path 0 2 = "~/"
  then (
    match Sys.getenv_opt "HOME" with
    | Some home when String.trim home <> "" ->
      Filename.concat home (String.sub path 2 (String.length path - 2))
    | _ -> path)
  else path
;;

let absolute_path path =
  let expanded = expand_home path in
  if Filename.is_relative expanded then Filename.concat (Sys.getcwd ()) expanded else expanded
;;

let read_file_prefix ~path ~max_bytes =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      let length = in_channel_length channel in
      let bytes_to_read = min length max_bytes in
      let content = really_input_string channel bytes_to_read in
      content, length > max_bytes)
;;

let contains_nul text =
  let rec loop index =
    if index >= String.length text
    then false
    else if text.[index] = '\000'
    then true
    else loop (index + 1)
  in
  loop 0
;;

let load ~max_bytes raw_path =
  let absolute_path = absolute_path raw_path in
  if not (Sys.file_exists absolute_path)
  then Error (Fmt.str "File not found: %s" absolute_path)
  else if Sys.is_directory absolute_path
  then Error (Fmt.str "Path is a directory, not a file: %s" absolute_path)
  else
    try
      let content, truncated = read_file_prefix ~path:absolute_path ~max_bytes in
      if contains_nul content
      then
        Error
          (Fmt.str
             "Binary files are not supported by /file yet: %s"
             absolute_path)
      else
        Ok
          { absolute_path
          ; display_path = absolute_path
          ; content
          ; truncated
          ; byte_count = String.length content
          }
    with
    | Sys_error message -> Error message
;;

let summary (attachment : t) =
  if attachment.truncated
  then
    Fmt.str
      "%s (%d bytes shown, truncated)"
      attachment.display_path
      attachment.byte_count
  else Fmt.str "%s (%d bytes)" attachment.display_path attachment.byte_count
;;

let render_lines attachments =
  match attachments with
  | [] -> [ "No file is currently attached for the next prompt." ]
  | _ ->
    "Files attached for the next prompt:"
    :: List.map (fun attachment -> "  " ^ summary attachment) attachments
;;

let attachment_block (attachment : t) =
  let truncation_note =
    if attachment.truncated
    then "\nNote: this file was truncated to keep the request bounded."
    else ""
  in
  Fmt.str
    "Attached local file: %s%s\n\n%s"
    attachment.display_path
    truncation_note
    attachment.content
;;

let inject_into_prompt attachments prompt =
  match attachments with
  | [] -> prompt
  | _ ->
    let blocks =
      attachments
      |> List.map attachment_block
      |> String.concat "\n\n-----\n\n"
    in
    Fmt.str
      "Use the attached local file content below when answering.\n\n%s\n\nUser request:\n%s"
      blocks
      prompt
;;
