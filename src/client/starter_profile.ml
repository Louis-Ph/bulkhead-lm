type provider_preset =
  { key : string
  ; label : string
  ; public_model : string
  ; provider_id : string
  ; provider_kind : Config.provider_kind
  ; upstream_model : string
  ; api_base : string
  ; api_key_env : string
  }

type route_status =
  { public_model : string
  ; backend_envs : string list
  ; ready : bool
  }

type env_status =
  { name : string
  ; present : bool
  ; masked_value : string option
  }

let provider_kind_to_string = function
  | Config.Openai_compat -> "openai_compat"
  | Config.Anthropic -> "anthropic"
  | Config.Google_openai -> "google_openai"
  | Config.Ollama_openai -> "ollama_openai"
  | Config.Alibaba_openai -> "alibaba_openai"
  | Config.Moonshot_openai -> "moonshot_openai"
  | Config.Aegis_peer -> "aegis_peer"
  | Config.Aegis_ssh_peer -> "aegis_ssh_peer"
;;

let non_empty_env lookup name =
  match lookup name with
  | Some value when String.trim value <> "" -> true
  | _ -> false
;;

let trimmed_env_value lookup name =
  match lookup name with
  | Some value ->
    let trimmed = String.trim value in
    if trimmed = "" then None else Some trimmed
  | None -> None
;;

let presets =
  [ { key = "anthropic"
    ; label = "Anthropic Claude Sonnet"
    ; public_model = "claude-sonnet"
    ; provider_id = "anthropic-primary"
    ; provider_kind = Config.Anthropic
    ; upstream_model = "claude-sonnet-4-5-20250929"
    ; api_base = "https://api.anthropic.com/v1"
    ; api_key_env = "ANTHROPIC_API_KEY"
    }
  ; { key = "openai"
    ; label = "OpenAI GPT-5 mini"
    ; public_model = "gpt-5-mini"
    ; provider_id = "openai-primary"
    ; provider_kind = Config.Openai_compat
    ; upstream_model = "gpt-5-mini"
    ; api_base = "https://api.openai.com/v1"
    ; api_key_env = "OPENAI_API_KEY"
    }
  ; { key = "google"
    ; label = "Google Gemini 2.5 Flash"
    ; public_model = "gemini-2.5-flash"
    ; provider_id = "google-primary"
    ; provider_kind = Config.Google_openai
    ; upstream_model = "gemini-2.5-flash"
    ; api_base = "https://generativelanguage.googleapis.com/v1beta/openai/"
    ; api_key_env = "GOOGLE_API_KEY"
    }
  ; { key = "alibaba"
    ; label = "Alibaba Qwen Plus"
    ; public_model = "qwen-plus"
    ; provider_id = "alibaba-primary"
    ; provider_kind = Config.Alibaba_openai
    ; upstream_model = "qwen-plus"
    ; api_base = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    ; api_key_env = "DASHSCOPE_API_KEY"
    }
  ; { key = "moonshot"
    ; label = "Moonshot Kimi K2.5"
    ; public_model = "kimi-k2.5"
    ; provider_id = "moonshot-primary"
    ; provider_kind = Config.Moonshot_openai
    ; upstream_model = "kimi-k2.5"
    ; api_base = "https://api.moonshot.ai/v1"
    ; api_key_env = "MOONSHOT_API_KEY"
    }
  ]
;;

let preset_is_ready ?(lookup = Sys.getenv_opt) (preset : provider_preset) =
  non_empty_env lookup preset.api_key_env
;;

let preset_summary (preset : provider_preset) = Fmt.str "%s [%s]" preset.label preset.public_model

let preset_with_api_key_env preset api_key_env =
  { preset with api_key_env = String.trim api_key_env }
;;

let route_status ?(lookup = Sys.getenv_opt) (route : Config.route) =
  let backend_envs =
    route.backends
    |> List.map (fun (backend : Config.backend) -> backend.api_key_env)
    |> List.sort_uniq String.compare
  in
  let ready =
    route.backends
    |> List.exists (fun (backend : Config.backend) -> non_empty_env lookup backend.api_key_env)
  in
  { public_model = route.public_model; backend_envs; ready }
;;

let route_statuses ?(lookup = Sys.getenv_opt) (config : Config.t) =
  List.map (route_status ~lookup) config.routes
;;

let split_route_statuses statuses = List.partition (fun (status : route_status) -> status.ready) statuses

let client_env_names = [ "AEGISLM_API_KEY"; "AEGISLM_AUTHORIZATION" ]

let relevant_env_names () =
  client_env_names
  @ (presets |> List.map (fun (preset : provider_preset) -> preset.api_key_env))
  |> List.sort_uniq String.compare
;;

let mask_secret value =
  let length = String.length value in
  if length <= 4
  then String.make length '*'
  else if length <= 10
  then String.sub value 0 2 ^ String.make (length - 2) '*'
  else
    let prefix = String.sub value 0 4 in
    let suffix = String.sub value (length - 2) 2 in
    prefix ^ String.make (length - 6) '*' ^ suffix
;;

let env_statuses ?(lookup = Sys.getenv_opt) () =
  relevant_env_names ()
  |> List.map (fun name ->
    match trimmed_env_value lookup name with
    | None -> { name; present = false; masked_value = None }
    | Some value -> { name; present = true; masked_value = Some (mask_secret value) })
;;

let backend_json (preset : provider_preset) =
  `Assoc
    [ "provider_id", `String preset.provider_id
    ; "provider_kind", `String (provider_kind_to_string preset.provider_kind)
    ; "upstream_model", `String preset.upstream_model
    ; "api_base", `String preset.api_base
    ; "api_key_env", `String preset.api_key_env
    ]
;;

let route_json (preset : provider_preset) =
  `Assoc
    [ "public_model", `String preset.public_model
    ; "backends", `List [ backend_json preset ]
    ]
;;

let config_json
  ~(selected_presets : provider_preset list)
  ~virtual_key_name
  ~token_plaintext
  ~daily_token_budget
  ~requests_per_minute
  ~sqlite_path
  ()
  =
  `Assoc
    [ "security_policy_file", `String "defaults/security_policy.json"
    ; "error_catalog_file", `String "defaults/error_catalog.json"
    ; "providers_schema_file", `String "defaults/providers.schema.json"
    ; ( "persistence"
      , `Assoc
          [ "sqlite_path", `String sqlite_path
          ; "busy_timeout_ms", `Int 5000
          ] )
    ; ( "virtual_keys"
      , `List
          [ `Assoc
              [ "name", `String virtual_key_name
              ; "token_plaintext", `String token_plaintext
              ; "daily_token_budget", `Int daily_token_budget
              ; "requests_per_minute", `Int requests_per_minute
              ; ( "allowed_routes"
                , `List
                    (List.map
                       (fun (preset : provider_preset) -> `String preset.public_model)
                       selected_presets) )
              ]
          ] )
    ; "routes", `List (List.map route_json selected_presets)
    ]
;;

let rec ensure_dir path =
  if path = "" || path = "." || path = "/"
  then ()
  else if Sys.file_exists path
  then ()
  else (
    ensure_dir (Filename.dirname path);
    Unix.mkdir path 0o755)
;;

let write_config_file path json =
  ensure_dir (Filename.dirname path);
  Yojson.Safe.to_file path json
;;
