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
  let conversation_keep_recent_turns = 6
  let conversation_compress_threshold_chars = 6_000
  let conversation_turn_excerpt_chars = 220
  let conversation_summary_max_chars = 2_200
  let attachment_max_bytes = 32_000
  let line_editor_multiline = false
  let local_tool_file_preview_chars = 12_000
  let local_tool_exec_preview_chars = 12_000
end

module Text = struct
  let title = "BulkheadLM starter"

  let intro_lines =
    [ "This path is for Mac terminal beginners."
    ; "It can reuse the repository example config, or build a personal portable JSON config that only references environment variables."
    ; "It also includes an administrative assistant for BulkheadLM configuration and safe local operations."
    ]
  ;;

  let builder_title = "Starter config builder"

  let builder_intro_lines =
    [ "The generated JSON is portable across operating systems: it stores env var names, not upstream secrets."
    ; "Selecting one provider includes several curated model routes for that provider key."
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
  let busy_message = "A response is already in progress. Wait for it to finish or interrupt it with Ctrl+C."
  let interrupted_message = "Interrupted. The starter is ready for another command."
  let terminal_ready =
    "Line editing is enabled: arrows, history, and tab completion are available in the starter."
  let tools_intro = "Use /file PATH to send one local text file with your next question."
  let assistant_capabilities_system_prompt =
    "You are the assistant inside the BulkheadLM starter terminal. The user can use local starter commands such as /help, /tools, /file PATH, /files, /clearfiles, /explore PATH, /open PATH, /run CMD, /admin TEXT, /package, /model, /models, /swap NAME, /providers, /env, /memory, /thread on, /thread off, and /quit. If the user asks how to send a file, explain /file PATH and /files instead of saying file upload is impossible. If the user asks to inspect local files or run a local command, mention /explore, /open, or /run."
  let swap_usage = "/swap expects a configured public model name, for example: /swap claude-sonnet"
  let thread_usage = "/thread expects on or off, for example: /thread off"
  let admin_usage = Admin_assistant_constants.Text.usage
  let file_usage = "/file expects a readable local file path, for example: /file README.md"
  let explore_usage = "/explore expects a directory path or defaults to ., for example: /explore src"
  let open_usage = "/open expects a readable local file path, for example: /open README.md"
  let run_usage = "/run expects a command, for example: /run /bin/ls -la"
  let file_attached path = Fmt.str "Attached for the next prompt: %s" path
  let files_cleared = "Attached files were cleared."
  let files_empty = "No file is attached right now."
  let files_will_be_used = "The next normal prompt will include the attached file content."
  let binary_file_rejected =
    "Binary files are not supported by /file yet. Use /admin if you need a more advanced local workflow."
  let package_intro = Starter_packaging_constants.Text.package_intro
  let memory_enabled = "Conversation memory is enabled."
  let memory_disabled = "Conversation memory is disabled. New prompts are sent without thread history."
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
