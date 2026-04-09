type provider_preset =
  { provider_key : string
  ; key : string
  ; provider_label : string
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
  | Config.Openrouter_openai -> "openrouter_openai"
  | Config.Google_openai -> "google_openai"
  | Config.Mistral_openai -> "mistral_openai"
  | Config.Ollama_openai -> "ollama_openai"
  | Config.Alibaba_openai -> "alibaba_openai"
  | Config.Moonshot_openai -> "moonshot_openai"
  | Config.Bulkhead_peer -> "bulkhead_peer"
  | Config.Bulkhead_ssh_peer -> "bulkhead_ssh_peer"
;;

let normalize_id_part value =
  let buffer = Buffer.create (String.length value) in
  let push_dash_if_needed () =
    if Buffer.length buffer > 0 && Buffer.nth buffer (Buffer.length buffer - 1) <> '-'
    then Buffer.add_char buffer '-'
  in
  String.iter
    (fun ch ->
      match ch with
      | 'a' .. 'z' | '0' .. '9' -> Buffer.add_char buffer ch
      | 'A' .. 'Z' -> Buffer.add_char buffer (Char.lowercase_ascii ch)
      | _ -> push_dash_if_needed ())
    value;
  let normalized = Buffer.contents buffer in
  let length = String.length normalized in
  let rec left index =
    if index >= length
    then length
    else if normalized.[index] = '-'
    then left (index + 1)
    else index
  in
  let rec right index =
    if index < 0
    then -1
    else if normalized.[index] = '-'
    then right (index - 1)
    else index
  in
  let start = left 0 in
  let stop = right (length - 1) in
  if start > stop then "model" else String.sub normalized start (stop - start + 1)
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

let preset_of_family_model (family : Starter_model_catalog.provider_family) model =
  let normalized_model = normalize_id_part model.Starter_model_catalog.public_model in
  { provider_key = family.key
  ; key = family.key ^ ":" ^ model.key
  ; provider_label = family.label
  ; label = Fmt.str "%s %s" family.label model.label
  ; public_model = model.public_model
  ; provider_id = Fmt.str "%s-%s" family.provider_id_prefix normalized_model
  ; provider_kind = family.provider_kind
  ; upstream_model = model.upstream_model
  ; api_base = family.api_base
  ; api_key_env = family.api_key_env
  }
;;

let provider_families = Starter_model_catalog.provider_families

let presets =
  provider_families
  |> List.concat_map (fun (family : Starter_model_catalog.provider_family) ->
    List.map (preset_of_family_model family) family.models)
;;

let presets_for_provider_key provider_key =
  presets
  |> List.filter (fun (preset : provider_preset) -> String.equal preset.provider_key provider_key)
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

let client_env_names = [ "BULKHEAD_LM_API_KEY"; "BULKHEAD_LM_AUTHORIZATION" ]

let relevant_env_names () =
  client_env_names
  @ (provider_families
    |> List.map (fun (family : Starter_model_catalog.provider_family) -> family.api_key_env))
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
