open Lwt.Infix

type host_os =
  | Macos
  | Ubuntu
  | Freebsd

type request =
  { host_os : host_os
  ; package_name : string
  ; display_name : string
  ; version : string
  ; maintainer : string
  ; description : string
  ; install_root : string
  ; wrapper_dir : string
  ; artifact_dir : string
  ; config_source : string
  ; identifier : string option
  }

type build_result =
  { exit_code : int
  ; artifact_path : string option
  ; transcript : string
  }

let trim = String.trim
let artifact_marker = "ARTIFACT: "

let string_of_host_os = function
  | Macos -> "macos"
  | Ubuntu -> "ubuntu"
  | Freebsd -> "freebsd"
;;

let package_format_label = function
  | Macos -> ".pkg"
  | Ubuntu -> ".deb"
  | Freebsd -> ".pkg"
;;

let default_install_root = function
  | Macos -> "/opt/aegis-lm"
  | Ubuntu -> "/opt/aegis-lm"
  | Freebsd -> "/usr/local/lib/aegis-lm"
;;

let default_wrapper_dir = function
  | Macos -> "/usr/local/bin"
  | Ubuntu -> "/usr/bin"
  | Freebsd -> "/usr/local/bin"
;;

let default_identifier = function
  | Macos -> Some "io.github.louis-ph.aegislm"
  | Ubuntu | Freebsd -> None
;;

let rec contains_substring text needle index =
  let needle_length = String.length needle in
  if needle_length = 0
  then true
  else if index + needle_length > String.length text
  then false
  else if String.sub text index needle_length = needle
  then true
  else contains_substring text needle (index + 1)
;;

let normalize_token raw =
  raw
  |> String.lowercase_ascii
  |> String.to_seq
  |> List.of_seq
  |> List.map (fun ch ->
    if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch = '.' || ch = '-' || ch = '+'
    then ch
    else '-')
  |> List.to_seq
  |> String.of_seq
  |> fun value ->
  if value = "" then Starter_packaging_constants.Defaults.package_name else value
;;

let normalize_version raw =
  let trimmed = trim raw in
  if trimmed = ""
  then "0.1.0"
  else normalize_token trimmed
;;

let suggested_version () =
  let from_git command =
    try
      let channel = Unix.open_process_in command in
      Fun.protect
        ~finally:(fun () -> ignore (Unix.close_process_in channel))
        (fun () ->
          let value = input_line channel |> trim in
          if value = "" then None else Some (normalize_version value))
    with
    | _ -> None
  in
  match from_git "git describe --tags --always --dirty 2>/dev/null" with
  | Some value -> value
  | None ->
    let tm = Unix.localtime (Unix.time ()) in
    Fmt.str "0.1.0-%04d%02d%02d" (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
;;

let suggested_maintainer () =
  let from_env =
    match Sys.getenv_opt "GIT_AUTHOR_NAME", Sys.getenv_opt "USER" with
    | Some value, _ when trim value <> "" -> Some (trim value)
    | _, Some value when trim value <> "" -> Some (trim value)
    | _ -> None
  in
  match from_env with
  | Some value -> value
  | None ->
    try
      let channel = Unix.open_process_in "git config user.name 2>/dev/null" in
      Fun.protect
        ~finally:(fun () -> ignore (Unix.close_process_in channel))
        (fun () ->
          let value = input_line channel |> trim in
          if value = "" then "AegisLM" else value)
    with
    | _ -> "AegisLM"
;;

let request_summary request =
  [ Fmt.str "Host OS: %s" (string_of_host_os request.host_os)
  ; Fmt.str "Package name: %s" request.package_name
  ; Fmt.str "Display name: %s" request.display_name
  ; Fmt.str "Version: %s" request.version
  ; Fmt.str "Maintainer: %s" request.maintainer
  ; Fmt.str "Description: %s" request.description
  ; Fmt.str "Install root: %s" request.install_root
  ; Fmt.str "Wrapper directory: %s" request.wrapper_dir
  ; Fmt.str "Artifact directory: %s" request.artifact_dir
  ; Fmt.str "Bundled config: %s" request.config_source
  ]
  @ (match request.identifier with
     | Some identifier -> [ Fmt.str "Identifier: %s" identifier ]
     | None -> [])
;;

let default_request ~config_path host_os =
  { host_os
  ; package_name = Starter_packaging_constants.Defaults.package_name
  ; display_name = Starter_packaging_constants.Defaults.display_name
  ; version = suggested_version ()
  ; maintainer = suggested_maintainer ()
  ; description = Starter_packaging_constants.Defaults.description
  ; install_root = default_install_root host_os
  ; wrapper_dir = default_wrapper_dir host_os
  ; artifact_dir = Starter_packaging_constants.Defaults.artifact_dir
  ; config_source = config_path
  ; identifier = default_identifier host_os
  }
;;

let host_os_of_values ~uname_s ~os_release =
  match String.lowercase_ascii (trim uname_s) with
  | "darwin" -> Ok Macos
  | "freebsd" -> Ok Freebsd
  | "linux" ->
    let lowered = String.lowercase_ascii os_release in
    if contains_substring lowered "id=ubuntu" 0
       || contains_substring lowered "id_like=ubuntu" 0
       || contains_substring lowered "id_like=\"ubuntu" 0
       || contains_substring lowered "ubuntu" 0
    then Ok Ubuntu
    else Error Starter_packaging_constants.Text.unsupported_os
  | _ -> Error Starter_packaging_constants.Text.unsupported_os
;;

let detect_host_os () =
  let uname_s =
    try
      let channel = Unix.open_process_in "uname -s 2>/dev/null" in
      Fun.protect
        ~finally:(fun () -> ignore (Unix.close_process_in channel))
        (fun () -> input_line channel)
    with
    | _ -> ""
  in
  let os_release =
    if Sys.file_exists "/etc/os-release"
    then (
      let channel = open_in_bin "/etc/os-release" in
      Fun.protect
        ~finally:(fun () -> close_in_noerr channel)
        (fun () -> really_input_string channel (in_channel_length channel)))
    else ""
  in
  host_os_of_values ~uname_s ~os_release
;;

let build_script_path root_dir =
  Filename.concat root_dir "scripts/build_dist_package.sh"
;;

let build_argv root_dir request =
  let base =
    [ "/bin/sh"
    ; build_script_path root_dir
    ; "--os"
    ; string_of_host_os request.host_os
    ; "--package-name"
    ; request.package_name
    ; "--display-name"
    ; request.display_name
    ; "--version"
    ; request.version
    ; "--maintainer"
    ; request.maintainer
    ; "--description"
    ; request.description
    ; "--install-root"
    ; request.install_root
    ; "--wrapper-dir"
    ; request.wrapper_dir
    ; "--artifact-dir"
    ; request.artifact_dir
    ; "--config-source"
    ; request.config_source
    ]
  in
  let base =
    match request.identifier with
    | Some identifier -> base @ [ "--identifier"; identifier ]
    | None -> base
  in
  Array.of_list base
;;

let append_line buffer line =
  Buffer.add_string buffer line;
  Buffer.add_char buffer '\n'
;;

let read_lines channel buffer on_line =
  let rec loop () =
    Lwt_io.read_line_opt channel
    >>= function
    | None -> Lwt.return_unit
    | Some line ->
      append_line buffer line;
      on_line line >>= loop
  in
  loop ()
;;

let parse_artifact_path transcript =
  transcript
  |> String.split_on_char '\n'
  |> List.find_opt (fun line -> String.starts_with ~prefix:artifact_marker line)
  |> Option.map (fun line ->
    let length = String.length line - String.length artifact_marker in
    String.sub line (String.length artifact_marker) length |> trim)
;;

let run_build ~root_dir request ~on_output =
  let argv = build_argv root_dir request in
  let process = Lwt_process.open_process_full (argv.(0), argv) in
  let stdout_buffer = Buffer.create 512 in
  let stderr_buffer = Buffer.create 512 in
  Lwt.finalize
    (fun () ->
      Lwt.both
        (read_lines process#stdout stdout_buffer on_output)
        (read_lines process#stderr stderr_buffer (fun line -> on_output ("[stderr] " ^ line)))
      >>= fun (_stdout_done, _stderr_done) ->
      process#status
      >|= fun status ->
      let exit_code =
        match status with
        | Unix.WEXITED code -> code
        | Unix.WSIGNALED signal -> 128 + signal
        | Unix.WSTOPPED signal -> 128 + signal
      in
      let transcript = Buffer.contents stdout_buffer ^ Buffer.contents stderr_buffer in
      { exit_code
      ; artifact_path = parse_artifact_path transcript
      ; transcript
      })
    (fun () -> Lwt.catch (fun () -> process#close >|= fun _ -> ()) (fun _ -> Lwt.return_unit))
;;
