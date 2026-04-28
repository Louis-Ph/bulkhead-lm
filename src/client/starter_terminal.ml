type completion_context =
  { commands : string list
  ; models : string list
  }

let history_max_entries = 200
let initialized = ref false
let history_loaded = ref false
let context = ref { commands = []; models = [] }

let trim text = String.trim text

let rec ensure_dir path =
  if path = "" || path = "." || path = "/"
  then ()
  else if Sys.file_exists path
  then ()
  else (
    ensure_dir (Filename.dirname path);
    Unix.mkdir path 0o755)
;;

let history_file ?history_env ~home () =
  match history_env with
  | Some path when trim path <> "" -> path
  | _ -> Filename.concat home ".bulkhead-lm/starter.history"
;;

let default_history_file () =
  match Sys.getenv_opt "BULKHEAD_LM_STARTER_HISTORY_FILE", Sys.getenv_opt "HOME" with
  | Some path, _ when trim path <> "" -> Some path
  | _, Some home when trim home <> "" -> Some (history_file ~home ())
  | _ -> None
;;

let history_load_once () =
  if !history_loaded
  then ()
  else (
    history_loaded := true;
    ignore (LNoise.history_set ~max_length:history_max_entries);
    match default_history_file () with
    | None -> ()
    | Some filename ->
      ensure_dir (Filename.dirname filename);
      if Sys.file_exists filename then ignore (LNoise.history_load ~filename))
;;

let save_history_entry ?(sanitize = Fun.id) line =
  let history_line = sanitize line in
  if trim history_line = ""
  then ()
  else (
    ignore (LNoise.history_add history_line);
    match default_history_file () with
    | None -> ()
    | Some filename ->
      ensure_dir (Filename.dirname filename);
      ignore (LNoise.history_save ~filename))
;;

let prefix_matches ~prefix value =
  let prefix_length = String.length prefix in
  String.length value >= prefix_length && String.sub value 0 prefix_length = prefix
;;

let slash_command_variants input commands =
  commands
  |> List.filter (prefix_matches ~prefix:input)
  |> List.sort_uniq String.compare
;;

let swap_variants input models =
  let prefix = Starter_constants.Command.swap ^ " " in
  models
  |> List.map (fun model -> prefix ^ model)
  |> List.filter (prefix_matches ~prefix:input)
  |> List.sort_uniq String.compare
;;

let thread_variants input =
  [ Starter_constants.Command.thread ^ " on"; Starter_constants.Command.thread ^ " off" ]
  |> List.filter (prefix_matches ~prefix:input)
;;

let memory_variants input =
  [ Starter_constants.Command.memory_replace ^ " " ]
  |> List.filter (prefix_matches ~prefix:input)
;;

let completion_candidates ~context input =
  if input = ""
  then []
  else if prefix_matches ~prefix:(Starter_constants.Command.swap ^ " ") input
  then swap_variants input context.models
  else if prefix_matches ~prefix:(Starter_constants.Command.memory ^ " ") input
  then memory_variants input
  else if prefix_matches ~prefix:(Starter_constants.Command.thread ^ " ") input
  then thread_variants input
  else if prefix_matches ~prefix:"/" input
  then slash_command_variants input context.commands
  else []
;;

let hint_for_input input =
  if input = ""
  then Some (" Type /help for commands", LNoise.Cyan, false)
  else if prefix_matches ~prefix:Starter_constants.Command.file input
  then Some (" <path-to-local-text-file>", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.explore input
  then Some (" <directory-path>", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.open_file input
  then Some (" <file-path>", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.run input
  then Some (" <command and args>", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.admin input
  then Some (" <plain-language admin request>", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.control input
  then Some (" show the real admin control-plane status", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.package input
  then Some (" build a local distributable package", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.swap input
  then Some (" <model>", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.memory_replace input
  then Some (" <replacement summary>", LNoise.Yellow, false)
  else if prefix_matches ~prefix:Starter_constants.Command.thread input
  then Some (" <on|off>", LNoise.Yellow, false)
  else None
;;

let initialize () =
  if not !initialized
  then (
    initialized := true;
    LNoise.catch_break true;
    LNoise.set_multiline Starter_constants.Defaults.line_editor_multiline;
    LNoise.set_completion_callback (fun line completions ->
      completion_candidates ~context:!context line
      |> List.iter (LNoise.add_completion completions));
    LNoise.set_hints_callback hint_for_input)
;;

let set_context ~commands ~models =
  initialize ();
  context :=
    { commands = List.sort_uniq String.compare commands
    ; models = List.sort_uniq String.compare models
    }
;;

let read_line ?(record_history = false) ?(history_sanitizer = Fun.id) ~prompt () =
  initialize ();
  history_load_once ();
  match LNoise.linenoise prompt with
  | None -> None
  | Some line ->
    if record_history then save_history_entry ~sanitize:history_sanitizer line;
    Some line
;;
