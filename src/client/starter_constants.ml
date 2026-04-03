module Command = struct
  let help = "/help"
  let config = "/config"
  let model = "/model"
  let models = "/models"
  let providers = "/providers"
  let env = "/env"
  let quit = "/quit"
  let swap = "/swap"
end

module Defaults = struct
  let virtual_key_name = "local-dev"
  let virtual_key_token = "sk-aegis-dev"
  let daily_token_budget = 50_000
  let requests_per_minute = 30
  let sqlite_path = "../var/aegislm.sqlite"
  let starter_output = "config/starter.gateway.json"
  let base_config = "config/example.gateway.json"
end

module Text = struct
  let title = "AegisLM starter"

  let intro_lines =
    [ "This path is for Mac terminal beginners."
    ; "It can reuse the repository example config, or build a personal portable JSON config that only references environment variables."
    ]
  ;;

  let builder_title = "Starter config builder"

  let builder_intro_lines =
    [ "The generated JSON is portable across operating systems: it stores env var names, not upstream secrets."
    ]
  ;;

  let command_help_lines =
    [ "Commands:"
    ; "  /model      choose another configured model"
    ; "  /models     list configured models"
    ; "  /swap NAME  switch directly to a configured model"
    ; "  /providers  show ready and missing providers from the current config"
    ; "  /env        show relevant environment variables in masked form"
    ; "  /config     show the current config path"
    ; "  /help       show this help"
    ; "  /quit       exit the starter"
    ]
  ;;

  let goodbye = "Bye."
  let busy_message = "A response is already in progress. Wait for it to finish or interrupt it with Ctrl+C."
  let interrupted_message = "Interrupted. The starter is ready for another command."
  let swap_usage = "/swap expects a configured public model name, for example: /swap claude-sonnet"
end
