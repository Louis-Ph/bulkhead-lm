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
  let control = "/control"
  let package = "/package"
  let plan = "/plan"
  let apply = "/apply"
  let discard = "/discard"
  let config = "/config"
  let model = "/model"
  let models = "/models"
  let memory = "/memory"
  let memory_replace = memory ^ " replace"
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
  let discover = "/discover"
  let refresh_models = "/refresh-models"

  let all =
    [ help
    ; tools
    ; admin
    ; control
    ; package
    ; plan
    ; apply
    ; discard
    ; config
    ; model
    ; models
    ; memory
    ; forget
    ; providers
    ; env
    ; thread
    ; quit
    ; swap
    ; file
    ; files
    ; clearfiles
    ; explore
    ; open_file
    ; run
    ; discover
    ; refresh_models
    ]
    |> List.sort_uniq String.compare
  ;;
end

module Defaults = struct
  let virtual_key_name = "local-dev"
  let virtual_key_token = "sk-bulkhead-lm-dev"
  let daily_token_budget = 500_000
  let requests_per_minute = 120
  let sqlite_path = "../var/bulkhead-lm.sqlite"
  let starter_output = "config/local_only/starter.gateway.json"
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
    ; "The saved starter config now lives under config/local_only/ and is ignored by Git."
    ]
  ;;

  type command_help_entry =
    { usage : string
    ; description : string
    }

  let command_help_entries =
    [ { usage = Command.tools
      ; description = "show the most useful starter actions, including file insertion"
      }
    ; { usage = Command.admin ^ " TEXT"
      ; description = "ask the assistant to prepare a safe admin plan"
      }
    ; { usage = Command.control
      ; description = "show the real HTTP admin control-plane status for this config"
      }
    ; { usage = Command.package
      ; description = "build a distributable package for this operating system"
      }
    ; { usage = Command.plan
      ; description = "show the pending admin plan"
      }
    ; { usage = Command.apply
      ; description = "apply the pending admin plan"
      }
    ; { usage = Command.discard
      ; description = "drop the pending admin plan"
      }
    ; { usage = Command.model
      ; description = "choose another configured model"
      }
    ; { usage = Command.models
      ; description = "list configured models"
      }
    ; { usage = Command.swap ^ " NAME"
      ; description = "switch directly to a configured model"
      }
    ; { usage = Command.memory
      ; description = "show conversation memory status"
      }
    ; { usage = Command.memory_replace ^ " TEXT"
      ; description = "replace remembered conversation history with one supplied summary"
      }
    ; { usage = Command.forget
      ; description = "clear remembered conversation state"
      }
    ; { usage = Command.thread ^ " on"
      ; description = "enable conversation memory"
      }
    ; { usage = Command.thread ^ " off"
      ; description = "disable conversation memory"
      }
    ; { usage = Command.providers
      ; description = "show ready and missing providers from the current config"
      }
    ; { usage = Command.discover
      ; description = "list every model each provider exposes via its API (uses cached results)"
      }
    ; { usage = Command.refresh_models
      ; description = "force-refresh the cached provider model lists from each API"
      }
    ; { usage = Command.env
      ; description = "show relevant environment variables in masked form"
      }
    ; { usage = Command.file ^ " PATH"
      ; description = "attach one local text file to the next prompt"
      }
    ; { usage = Command.files
      ; description = "list files attached to the next prompt"
      }
    ; { usage = Command.clearfiles
      ; description = "remove attached files before the next prompt"
      }
    ; { usage = Command.explore
      ; description = "list a directory inside the allowed local roots"
      }
    ; { usage = Command.open_file ^ " PATH"
      ; description = "show one local text file inside the allowed local roots"
      }
    ; { usage = Command.run ^ " CMD"
      ; description = "execute one local command inside the allowed working roots"
      }
    ; { usage = Command.config
      ; description = "show the current config path"
      }
    ; { usage = Command.help
      ; description = "show this help"
      }
    ; { usage = Command.quit
      ; description = "exit the starter"
      }
    ]
    |> List.sort (fun left right -> String.compare left.usage right.usage)
  ;;

  let max_command_usage_width =
    List.fold_left
      (fun widest entry -> max widest (String.length entry.usage))
      0
      command_help_entries
  ;;

  let format_command_help_line entry =
    Fmt.str "  %-*s %s" max_command_usage_width entry.usage entry.description
  ;;

  let command_help_lines =
    "Commands:" :: List.map format_command_help_line command_help_entries
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
    ; "  /control    show whether the browser control plane is enabled and where it lives"
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
          /run CMD, /admin TEXT, /control, /package, /model, /models, /swap NAME, \
          /providers, /env, /memory, /memory replace TEXT, /thread on, /thread off, and /quit. If the user \
          asks how to send a file, explain /file PATH and /files instead of saying file \
          upload is impossible. If the user asks to inspect local files or run a local \
          command, mention /explore, /open, or /run. If the user asks how to \
          administer BulkheadLM or how to reach the admin UI, prefer /control for \
          factual status from the current config, and explain that /admin TEXT only \
          prepares a plan. Never invent starter commands, subcommands, URLs, ports, or \
          browser-opening behavior. Do not claim that /admin opens a pane or has \
          subcommands such as /admin open or /admin status. If you do not know whether \
          the HTTP control plane is enabled, tell the user to run /control. Treat \
          OpenRouter as a supported provider family using provider_kind \
          openrouter_openai, api_base https://openrouter.ai/api/v1, and OPEN_ROUTER_KEY \
          by default."
       ]
       @ Assistant_signal.usage_lines)
  ;;

  let swap_usage =
    "/swap expects a configured public model name, for example: /swap claude-sonnet"
  ;;

  let memory_replace_usage =
    "/memory replace expects one replacement summary, for example: /memory replace Project alpha now focuses on deployment."
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

  let memory_replaced summary_char_count =
    Fmt.str
      "Conversation memory was replaced with one supplied summary (%d chars)."
      summary_char_count
  ;;

  let control_plane_intro =
    "This starter is the interactive client. The HTTP control plane belongs to the \
     running gateway server for the current config."
  ;;

  let control_plane_enabled = "HTTP control plane: enabled."
  let control_plane_disabled = "HTTP control plane: disabled in this config."

  let control_plane_terminal_admin_lines =
    [ "Terminal admin flow inside this starter:"
    ; "  /admin TEXT"
    ; "  /plan"
    ; "  /apply"
    ; "  /discard"
    ]
  ;;

  let compression_notice archived =
    Fmt.str "Conversation memory compressed: %d older turns were summarized." archived
  ;;

  let starter_saved_config_bootstrapped path =
    Fmt.str
      "Created a first-run local starter config at %s. It stays out of Git and uses the current curated provider endpoints."
      path
  ;;

  let starter_saved_config_migrated path =
    Fmt.str
      "Updated the saved starter config at %s so its catalog references match the local-only location."
      path
  ;;

  let no_admin_plan = Admin_assistant_constants.Text.no_plan
  let admin_discarded = Admin_assistant_constants.Text.discarded
  let admin_planning = Admin_assistant_constants.Text.planning
  let admin_applying = Admin_assistant_constants.Text.applying
  let admin_empty_plan = Admin_assistant_constants.Text.empty_plan
  let package_failed = Starter_packaging_constants.Text.package_failed
end
