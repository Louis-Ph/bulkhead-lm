module Ansi = struct
  let reset = "\027[0m"

  let sgr code = "\027[" ^ code ^ "m"
  let wrap code text = sgr code ^ text ^ reset

  let contains_substring text needle =
    let text_length = String.length text in
    let needle_length = String.length needle in
    let rec loop index =
      if needle_length = 0
      then true
      else if index + needle_length > text_length
      then false
      else if String.sub text index needle_length = needle
      then true
      else loop (index + 1)
    in
    loop 0
  ;;

  let supports_extended_palette () =
    match Sys.getenv_opt "TERM", Sys.getenv_opt "COLORTERM" with
    | Some term, _
    | _, Some term ->
      let lowered = String.lowercase_ascii term in
      contains_substring lowered "256color"
      || contains_substring lowered "truecolor"
      || contains_substring lowered "24bit"
      || contains_substring lowered "direct"
    | None, None -> false
  ;;

  let open_cyan = sgr "36"
  let open_green = sgr "32"
  let open_yellow = sgr "33"
  let open_magenta = sgr "35"
  let open_red = sgr "31"

  let open_orange () =
    if supports_extended_palette () then sgr "38;5;208" else open_yellow
  ;;

  let cyan text = wrap "36" text
  let green text = wrap "32" text
  let yellow text = wrap "33" text
  let magenta text = wrap "35" text
  let red text = wrap "31" text
  let orange text = open_orange () ^ text ^ reset
  let dim text = "\027[2m" ^ text ^ "\027[22m" (* 22m resets dim, not everything *)
  let bold text = "\027[1m" ^ text ^ "\027[22m" (* 22m resets bold *)
end

module Assistant_signal = struct
  type level =
    | Normal
    | Green
    | Orange
    | Red

  let directives =
    [ "[[normal]]", Normal
    ; "[[green]]", Green
    ; "[[orange]]", Orange
    ; "[[red]]", Red
    ]
  ;;

  let ansi_open = function
    | Normal -> Ansi.reset
    | Green -> Ansi.open_green
    | Orange -> Ansi.open_orange ()
    | Red -> Ansi.open_red
  ;;

  let usage_lines =
    [ "You may optionally color your reply for terminal context with one control token:"
    ; "[[normal]] for neutral/default terminal color."
    ; "[[green]] for safe, confirmed, successful, or ready states."
    ; "[[orange]] for caution, partial confidence, operator attention, or pending action."
    ; "[[red]] for danger, blockers, destructive risk, or urgent failure."
    ; "Only place these control tokens at the very start of the reply or immediately after a newline."
    ; "Do not mention or explain the control tokens unless the user asks about them."
    ]
  ;;
end

module Command = struct
  let help = "/help"
  let tools = "/tools"
  let admin = "/admin"
  let package = "/package"
  let plan = "/plan"
  let apply = "/apply"
  let discard = "/discard"
  let config = "/config"
  let model = "/model"
  let models = "/models"
  let memory = "/memory"
  let forget = "/forget"
  let providers = "/providers"
  let env = "/env"
  let thread = "/thread"
  let quit = "/quit"
  let swap = "/swap"
  let file = "/file"
  let files = "/files"
  let clearfiles = "/clearfiles"
  let explore = "/explore"
  let open_file = "/open"
  let run = "/run"
end

module Defaults = struct
  let virtual_key_name = "local-dev"
  let virtual_key_token = "sk-bulkhead-lm-dev"
  let daily_token_budget = 50_000
  let requests_per_minute = 30
  let sqlite_path = "../var/bulkhead-lm.sqlite"
  let starter_output = "config/starter.gateway.json"
  let base_config = "config/example.gateway.json"
  let conversation_keep_recent_turns = Session_memory_defaults.keep_recent_turns
  let conversation_compress_threshold_chars = Session_memory_defaults.compress_threshold_chars
  let conversation_turn_excerpt_chars = Session_memory_defaults.turn_excerpt_chars
  let conversation_summary_max_chars = Session_memory_defaults.summary_max_chars
  let attachment_max_bytes = 32_000
  let line_editor_multiline = false
  let local_tool_file_preview_chars = 12_000
  let local_tool_exec_preview_chars = 12_000
end

module Text = struct
  let title = "BulkheadLM starter"

  let intro_lines =
    [ "This path is for Mac terminal beginners."
    ; "It can reuse the repository example config, or build a personal portable JSON \
       config that only references environment variables."
    ; "It also includes an administrative assistant for BulkheadLM configuration and \
       safe local operations."
    ]
  ;;

  let builder_title = "Starter config builder"

  let builder_intro_lines =
    [ "The generated JSON is portable across operating systems: it stores env var names, \
       not upstream secrets."
    ; "Selecting one provider includes several curated model routes for that provider \
       key."
    ]
  ;;

  let command_help_lines =
    [ "Commands:"
    ; "  /tools      show the most useful starter actions, including file insertion"
    ; "  /admin TEXT ask the assistant to prepare a safe admin plan"
    ; "  /package    build a distributable package for this operating system"
    ; "  /plan       show the pending admin plan"
    ; "  /apply      apply the pending admin plan"
    ; "  /discard    drop the pending admin plan"
    ; "  /model      choose another configured model"
    ; "  /models     list configured models"
    ; "  /swap NAME  switch directly to a configured model"
    ; "  /memory     show conversation memory status"
    ; "  /forget     clear remembered conversation state"
    ; "  /thread on  enable conversation memory"
    ; "  /thread off disable conversation memory"
    ; "  /providers  show ready and missing providers from the current config"
    ; "  /env        show relevant environment variables in masked form"
    ; "  /file PATH  attach one local text file to the next prompt"
    ; "  /files      list files attached to the next prompt"
    ; "  /clearfiles remove attached files before the next prompt"
    ; "  /explore    list a directory inside the allowed local roots"
    ; "  /open PATH  show one local text file inside the allowed local roots"
    ; "  /run CMD    execute one local command inside the allowed working roots"
    ; "  /config     show the current config path"
    ; "  /help       show this help"
    ; "  /quit       exit the starter"
    ]
  ;;

  let tool_help_lines =
    [ "Simple starter tools:"
    ; "  /file PATH  read one local text file and attach it to the next prompt"
    ; "  /files      show which files are attached right now"
    ; "  /clearfiles clear those attached files"
    ; "  /explore .  list files and folders in the current allowed root"
    ; "  /open PATH  preview one local text file"
    ; "  /run CMD    execute one local command without a shell"
    ; "  /admin ...  ask the assistant to change BulkheadLM or local settings safely"
    ; "  /package    build a distributable package for this operating system"
    ]
  ;;

  let goodbye = "Bye."

  let busy_message =
    "A response is already in progress. Wait for it to finish or interrupt it with \
     Ctrl+C."
  ;;

  let interrupted_message = "Interrupted. The starter is ready for another command."

  let terminal_ready =
    "Line editing is enabled: arrows, history, and tab completion are available in the \
     starter."
  ;;

  let tools_intro = "Use /file PATH to send one local text file with your next question."

  let assistant_capabilities_system_prompt =
    String.concat
      "\n"
      ([ "You are the assistant inside the BulkheadLM starter terminal. You must be \
          proactive and guide the user based on the BulkheadLM documentation, its \
          codebase, and the user's needs. The user can use local starter commands such \
          as /help, /tools, /file PATH, /files, /clearfiles, /explore PATH, /open PATH, \
          /run CMD, /admin TEXT, /package, /model, /models, /swap NAME, /providers, \
          /env, /memory, /thread on, /thread off, and /quit. If the user asks how to \
          send a file, explain /file PATH and /files instead of saying file upload is \
          impossible. If the user asks to inspect local files or run a local command, \
          mention /explore, /open, or /run. Treat OpenRouter as a supported provider \
          family using provider_kind openrouter_openai, api_base \
          https://openrouter.ai/api/v1, and OPEN_ROUTER_KEY by default."
       ]
       @ Assistant_signal.usage_lines)
  ;;

  let swap_usage =
    "/swap expects a configured public model name, for example: /swap claude-sonnet"
  ;;

  let thread_usage = "/thread expects on or off, for example: /thread off"
  let admin_usage = Admin_assistant_constants.Text.usage

  let file_usage =
    "/file expects a readable local file path, for example: /file README.md"
  ;;

  let explore_usage =
    "/explore expects a directory path or defaults to ., for example: /explore src"
  ;;

  let open_usage =
    "/open expects a readable local file path, for example: /open README.md"
  ;;

  let run_usage = "/run expects a command, for example: /run /bin/ls -la"
  let file_attached path = Fmt.str "Attached for the next prompt: %s" path
  let files_cleared = "Attached files were cleared."
  let files_empty = "No file is attached right now."

  let files_will_be_used =
    "The next normal prompt will include the attached file content."
  ;;

  let binary_file_rejected =
    "Binary files are not supported by /file yet. Use /admin if you need a more advanced \
     local workflow."
  ;;

  let package_intro = Starter_packaging_constants.Text.package_intro
  let memory_enabled = "Conversation memory is enabled."

  let memory_disabled =
    "Conversation memory is disabled. New prompts are sent without thread history."
  ;;

  let memory_cleared = "Conversation memory was cleared."

  let compression_notice archived =
    Fmt.str "Conversation memory compressed: %d older turns were summarized." archived
  ;;

  let no_admin_plan = Admin_assistant_constants.Text.no_plan
  let admin_discarded = Admin_assistant_constants.Text.discarded
  let admin_planning = Admin_assistant_constants.Text.planning
  let admin_applying = Admin_assistant_constants.Text.applying
  let admin_empty_plan = Admin_assistant_constants.Text.empty_plan
  let package_failed = Starter_packaging_constants.Text.package_failed
end
