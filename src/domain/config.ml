let ( >>= ) = Result.bind

type provider_kind =
  | Openai_compat
  | Anthropic
  | Openrouter_openai
  | Google_openai
  | Mistral_openai
  | Ollama_openai
  | Alibaba_openai
  | Moonshot_openai
  | Bulkhead_peer
  | Bulkhead_ssh_peer

type ssh_transport =
  { destination : string
  ; host : string
  ; remote_worker_command : string
  ; remote_config_path : string option
  ; remote_switch : string option
  ; remote_jobs : int
  ; options : string list
  }

type backend_target =
  | Http_target of string
  | Ssh_target of ssh_transport

type persistence =
  { sqlite_path : string option
  ; busy_timeout_ms : int
  }

type telegram_connector =
  { webhook_path : string
  ; bot_token_env : string
  ; secret_token_env : string option
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_chat_ids : string list
  }

type whatsapp_connector =
  { webhook_path : string
  ; verify_token_env : string
  ; app_secret_env : string option
  ; access_token_env : string
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_sender_numbers : string list
  ; api_base : string
  }

type messenger_connector =
  { webhook_path : string
  ; verify_token_env : string
  ; app_secret_env : string option
  ; access_token_env : string
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_page_ids : string list
  ; allowed_sender_ids : string list
  ; api_base : string
  }

type instagram_connector =
  { webhook_path : string
  ; verify_token_env : string
  ; app_secret_env : string option
  ; access_token_env : string
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_account_ids : string list
  ; allowed_sender_ids : string list
  ; api_base : string
  }

type line_connector =
  { webhook_path : string
  ; channel_secret_env : string
  ; access_token_env : string
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_user_ids : string list
  ; allowed_group_ids : string list
  ; allowed_room_ids : string list
  ; api_base : string
  }

type viber_connector =
  { webhook_path : string
  ; auth_token_env : string
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_sender_ids : string list
  ; sender_name : string option
  ; sender_avatar : string option
  ; api_base : string
  }

type google_chat_id_token_auth =
  { audience : string
  ; certs_url : string
  }

type google_chat_connector =
  { webhook_path : string
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_space_names : string list
  ; allowed_user_names : string list
  ; id_token_auth : google_chat_id_token_auth option
  }

type user_connectors =
  { telegram : telegram_connector option
  ; whatsapp : whatsapp_connector option
  ; messenger : messenger_connector option
  ; instagram : instagram_connector option
  ; line : line_connector option
  ; viber : viber_connector option
  ; google_chat : google_chat_connector option
  }

type backend =
  { provider_id : string
  ; provider_kind : provider_kind
  ; upstream_model : string
  ; target : backend_target
  ; api_key_env : string
  }

type route =
  { public_model : string
  ; backends : backend list
  }

type virtual_key =
  { name : string
  ; token_plaintext : string option
  ; token_hash : string option
  ; daily_token_budget : int
  ; requests_per_minute : int
  ; allowed_routes : string list
  }

type t =
  { security_policy : Security_policy.t
  ; persistence : persistence
  ; error_catalog : Yojson.Safe.t
  ; providers_schema : Yojson.Safe.t
  ; user_connectors : user_connectors
  ; routes : route list
  ; virtual_keys : virtual_key list
  }

type resolved_paths =
  { gateway_config_path : string
  ; security_policy_path : string option
  ; error_catalog_path : string option
  ; providers_schema_path : string option
  }

let provider_kind_of_string = function
  | "openai_compat" -> Ok Openai_compat
  | "anthropic" -> Ok Anthropic
  | "openrouter_openai" -> Ok Openrouter_openai
  | "google_openai" -> Ok Google_openai
  | "mistral_openai" -> Ok Mistral_openai
  | "ollama_openai" -> Ok Ollama_openai
  | "alibaba_openai" -> Ok Alibaba_openai
  | "moonshot_openai" -> Ok Moonshot_openai
  | "bulkhead_peer" -> Ok Bulkhead_peer
  | "bulkhead_ssh_peer" -> Ok Bulkhead_ssh_peer
  | value -> Error (Fmt.str "Unsupported provider kind: %s" value)
;;

let is_openai_compatible_kind = function
  | Openai_compat
  | Openrouter_openai
  | Google_openai
  | Mistral_openai
  | Ollama_openai
  | Alibaba_openai
  | Moonshot_openai
  | Bulkhead_peer
  | Bulkhead_ssh_peer -> true
  | Anthropic -> false
;;

let backend_http_api_base = function
  | { target = Http_target api_base; _ } -> Some api_base
  | _ -> None
;;

let backend_ssh_transport = function
  | { target = Ssh_target transport; _ } -> Some transport
  | _ -> None
;;

let backend_target_label backend =
  match backend.target with
  | Http_target api_base -> api_base
  | Ssh_target transport -> "ssh://" ^ transport.host
;;

let resolve_path ~base_dir path =
  if Filename.is_relative path then Filename.concat base_dir path else path
;;

let object_member name = function
  | `Assoc fields -> Option.value (List.assoc_opt name fields) ~default:`Null
  | _ -> `Null
;;

let string_member name json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`String value) -> Ok value
     | _ -> Error name)
  | _ -> Error name
;;

let string_member_with_default name json ~default =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`String value) -> value
     | _ -> default)
  | _ -> default
;;

let int_member_with_default name json ~default =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`Int value) -> value
     | Some (`Intlit value) -> int_of_string value
     | _ -> default)
  | _ -> default
;;

let bool_member_with_default name json ~default =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`Bool value) -> value
     | _ -> default)
  | _ -> default
;;

let list_member name json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt name fields with
     | Some (`List values) -> values
     | _ -> [])
  | _ -> []
;;

let list_of_strings_member name json =
  list_member name json
  |> List.filter_map (function
    | `String value -> Some value
    | _ -> None)
;;

let normalize_http_path path =
  let trimmed = String.trim path in
  if trimmed = ""
  then "/"
  else if String.starts_with ~prefix:"/" trimmed
  then trimmed
  else "/" ^ trimmed
;;

let normalize_http_api_base value =
  let trimmed = String.trim value in
  if trimmed = ""
  then ""
  else if String.ends_with ~suffix:"/" trimmed
  then String.sub trimmed 0 (String.length trimmed - 1)
  else trimmed
;;

let optional_non_empty_string_member name json =
  match object_member name json with
  | `String value ->
    let trimmed = String.trim value in
    if trimmed = "" then None else Some trimmed
  | _ -> None
;;

let string_or_int_list_member name json =
  list_member name json
  |> List.filter_map (function
    | `String value ->
      let trimmed = String.trim value in
      if trimmed = "" then None else Some trimmed
    | `Int value -> Some (string_of_int value)
    | `Intlit value -> Some value
    | _ -> None)
;;

let parse_ssh_host destination json =
  match string_member "host" json with
  | Ok host when String.trim host <> "" -> Ok (String.trim host)
  | _ ->
    let trimmed = String.trim destination in
    let without_scheme =
      if String.starts_with ~prefix:"ssh://" trimmed
      then String.sub trimmed 6 (String.length trimmed - 6)
      else trimmed
    in
    let after_user =
      match List.rev (String.split_on_char '@' without_scheme) with
      | host :: _ -> host
      | [] -> without_scheme
    in
    let host =
      if String.starts_with ~prefix:"[" after_user
      then (
        match String.index_opt after_user ']' with
        | Some index -> String.sub after_user 1 (index - 1)
        | None -> after_user)
      else (
        match String.index_opt after_user ':' with
        | Some index -> String.sub after_user 0 index
        | None -> after_user)
    in
    if String.trim host = ""
    then Error "ssh_transport.host"
    else Ok (String.trim host)
;;

let parse_ssh_transport json =
  string_member "destination" json
  >>= fun destination ->
  parse_ssh_host destination json
  >>= fun host ->
  string_member "remote_worker_command" json
  >>= fun remote_worker_command ->
  Ok
    { destination = String.trim destination
    ; host
    ; remote_worker_command = String.trim remote_worker_command
    ; remote_config_path =
        (match object_member "remote_config_path" json with
         | `String value when String.trim value <> "" -> Some (String.trim value)
         | _ -> None)
    ; remote_switch =
        (match object_member "remote_switch" json with
         | `String value when String.trim value <> "" -> Some (String.trim value)
         | _ -> None)
    ; remote_jobs = max 1 (int_member_with_default "remote_jobs" json ~default:1)
    ; options = list_of_strings_member "options" json
    }
;;

let parse_backend json =
  string_member "provider_id" json
  >>= fun provider_id ->
  string_member "provider_kind" json
  >>= fun provider_kind_raw ->
  provider_kind_of_string provider_kind_raw
  >>= fun provider_kind ->
  string_member "upstream_model" json
  >>= fun upstream_model ->
  let target_result =
    match provider_kind with
    | Bulkhead_ssh_peer ->
      (match object_member "ssh_transport" json with
       | `Assoc _ as ssh_json ->
         parse_ssh_transport ssh_json |> Result.map (fun transport -> Ssh_target transport)
       | _ -> Error "ssh_transport")
    | _ ->
      string_member "api_base" json |> Result.map (fun api_base -> Http_target api_base)
  in
  target_result
  >>= fun target ->
  string_member "api_key_env" json
  >>= fun api_key_env ->
  Ok { provider_id; provider_kind; upstream_model; target; api_key_env }
;;

let parse_route json =
  string_member "public_model" json
  >>= fun public_model ->
  let backend_values = list_member "backends" json in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
      (match parse_backend item with
       | Ok backend -> loop (backend :: acc) rest
       | Error err -> Error err)
  in
  loop [] backend_values >>= fun backends -> Ok { public_model; backends }
;;

let parse_virtual_key defaults json =
  string_member "name" json
  >>= fun name ->
  let token_plaintext =
    match object_member "token_plaintext" json with
    | `String value -> Some value
    | _ -> None
  in
  let token_hash =
    match object_member "token_hash" json with
    | `String value -> Some value
    | _ -> None
  in
  let allowed_routes =
    list_member "allowed_routes" json
    |> List.filter_map (function
      | `String value -> Some value
      | _ -> None)
  in
  Ok
    { name
    ; token_plaintext
    ; token_hash
    ; daily_token_budget =
        int_member_with_default
          "daily_token_budget"
          json
          ~default:defaults.Security_policy.budget.default_daily_tokens
    ; requests_per_minute =
        int_member_with_default
          "requests_per_minute"
          json
          ~default:defaults.Security_policy.rate_limit.default_requests_per_minute
    ; allowed_routes
    }
;;

let parse_telegram_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    string_member "bot_token_env" json
    >>= fun bot_token_env ->
    string_member "authorization_env" json
    >>= fun authorization_env ->
    string_member "route_model" json
    >>= fun route_model ->
    Ok
      (Some
         { webhook_path =
             normalize_http_path
               (string_member_with_default
                  "webhook_path"
                  json
                  ~default:"/connectors/telegram/webhook")
         ; bot_token_env = String.trim bot_token_env
         ; secret_token_env = optional_non_empty_string_member "secret_token_env" json
         ; authorization_env = String.trim authorization_env
         ; route_model = String.trim route_model
         ; system_prompt = optional_non_empty_string_member "system_prompt" json
         ; allowed_chat_ids = string_or_int_list_member "allowed_chat_ids" json
         })
;;

let parse_whatsapp_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    string_member "verify_token_env" json
    >>= fun verify_token_env ->
    string_member "access_token_env" json
    >>= fun access_token_env ->
    string_member "authorization_env" json
    >>= fun authorization_env ->
    string_member "route_model" json
    >>= fun route_model ->
    Ok
      (Some
         { webhook_path =
             normalize_http_path
               (string_member_with_default
                  "webhook_path"
                  json
                  ~default:"/connectors/whatsapp/webhook")
         ; verify_token_env = String.trim verify_token_env
         ; app_secret_env = optional_non_empty_string_member "app_secret_env" json
         ; access_token_env = String.trim access_token_env
         ; authorization_env = String.trim authorization_env
         ; route_model = String.trim route_model
         ; system_prompt = optional_non_empty_string_member "system_prompt" json
         ; allowed_sender_numbers = string_or_int_list_member "allowed_sender_numbers" json
         ; api_base =
             normalize_http_api_base
               (string_member_with_default
                  "api_base"
                  json
                  ~default:"https://graph.facebook.com/v23.0")
         })
;;

type parsed_meta_connector_base =
  { webhook_path : string
  ; verify_token_env : string
  ; app_secret_env : string option
  ; access_token_env : string
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; api_base : string
  }

let parse_meta_connector_base json ~default_webhook_path ~default_api_base =
  string_member "verify_token_env" json
  >>= fun verify_token_env ->
  string_member "access_token_env" json
  >>= fun access_token_env ->
  string_member "authorization_env" json
  >>= fun authorization_env ->
  string_member "route_model" json
  >>= fun route_model ->
  Ok
    { webhook_path =
        normalize_http_path
          (string_member_with_default "webhook_path" json ~default:default_webhook_path)
    ; verify_token_env = String.trim verify_token_env
    ; app_secret_env = optional_non_empty_string_member "app_secret_env" json
    ; access_token_env = String.trim access_token_env
    ; authorization_env = String.trim authorization_env
    ; route_model = String.trim route_model
    ; system_prompt = optional_non_empty_string_member "system_prompt" json
    ; api_base =
        normalize_http_api_base
          (string_member_with_default "api_base" json ~default:default_api_base)
    }
;;

let parse_messenger_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    parse_meta_connector_base
      json
      ~default_webhook_path:"/connectors/messenger/webhook"
      ~default_api_base:"https://graph.facebook.com/v23.0"
    >>= fun base ->
    Ok
      (Some
         { webhook_path = base.webhook_path
         ; verify_token_env = base.verify_token_env
         ; app_secret_env = base.app_secret_env
         ; access_token_env = base.access_token_env
         ; authorization_env = base.authorization_env
         ; route_model = base.route_model
         ; system_prompt = base.system_prompt
         ; allowed_page_ids = string_or_int_list_member "allowed_page_ids" json
         ; allowed_sender_ids = string_or_int_list_member "allowed_sender_ids" json
         ; api_base = base.api_base
         })
;;

let parse_instagram_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    parse_meta_connector_base
      json
      ~default_webhook_path:"/connectors/instagram/webhook"
      ~default_api_base:"https://graph.instagram.com/v23.0"
    >>= fun base ->
    Ok
      (Some
         { webhook_path = base.webhook_path
         ; verify_token_env = base.verify_token_env
         ; app_secret_env = base.app_secret_env
         ; access_token_env = base.access_token_env
         ; authorization_env = base.authorization_env
         ; route_model = base.route_model
         ; system_prompt = base.system_prompt
         ; allowed_account_ids = string_or_int_list_member "allowed_account_ids" json
         ; allowed_sender_ids = string_or_int_list_member "allowed_sender_ids" json
         ; api_base = base.api_base
         })
;;

let parse_line_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    string_member "channel_secret_env" json
    >>= fun channel_secret_env ->
    string_member "access_token_env" json
    >>= fun access_token_env ->
    string_member "authorization_env" json
    >>= fun authorization_env ->
    string_member "route_model" json
    >>= fun route_model ->
    Ok
      (Some
         { webhook_path =
             normalize_http_path
               (string_member_with_default
                  "webhook_path"
                  json
                  ~default:"/connectors/line/webhook")
         ; channel_secret_env = String.trim channel_secret_env
         ; access_token_env = String.trim access_token_env
         ; authorization_env = String.trim authorization_env
         ; route_model = String.trim route_model
         ; system_prompt = optional_non_empty_string_member "system_prompt" json
         ; allowed_user_ids = string_or_int_list_member "allowed_user_ids" json
         ; allowed_group_ids = string_or_int_list_member "allowed_group_ids" json
         ; allowed_room_ids = string_or_int_list_member "allowed_room_ids" json
         ; api_base =
             normalize_http_api_base
               (string_member_with_default
                  "api_base"
                  json
                  ~default:"https://api.line.me/v2/bot")
         })
;;

let parse_viber_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    string_member "auth_token_env" json
    >>= fun auth_token_env ->
    string_member "authorization_env" json
    >>= fun authorization_env ->
    string_member "route_model" json
    >>= fun route_model ->
    Ok
      (Some
         { webhook_path =
             normalize_http_path
               (string_member_with_default
                  "webhook_path"
                  json
                  ~default:"/connectors/viber/webhook")
         ; auth_token_env = String.trim auth_token_env
         ; authorization_env = String.trim authorization_env
         ; route_model = String.trim route_model
         ; system_prompt = optional_non_empty_string_member "system_prompt" json
         ; allowed_sender_ids = string_or_int_list_member "allowed_sender_ids" json
         ; sender_name = optional_non_empty_string_member "sender_name" json
         ; sender_avatar = optional_non_empty_string_member "sender_avatar" json
         ; api_base =
             normalize_http_api_base
               (string_member_with_default
                  "api_base"
                  json
                  ~default:"https://chatapi.viber.com/pa")
         })
;;

let parse_google_chat_id_token_auth json =
  string_member "audience" json
  >>= fun audience ->
  Ok
    { audience = String.trim audience
    ; certs_url =
        String.trim
          (string_member_with_default
             "certs_url"
             json
             ~default:"https://www.googleapis.com/oauth2/v1/certs")
    }
;;

let parse_google_chat_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    string_member "authorization_env" json
    >>= fun authorization_env ->
    string_member "route_model" json
    >>= fun route_model ->
    let id_token_auth_result =
      match object_member "id_token_auth" json with
      | `Assoc _ as auth_json ->
        (match parse_google_chat_id_token_auth auth_json with
         | Ok auth -> Ok (Some auth)
         | Error err -> Error err)
      | _ -> Ok None
    in
    id_token_auth_result
    >>= fun id_token_auth ->
    Ok
      (Some
         { webhook_path =
             normalize_http_path
               (string_member_with_default
                  "webhook_path"
                  json
                  ~default:"/connectors/google-chat/webhook")
         ; authorization_env = String.trim authorization_env
         ; route_model = String.trim route_model
         ; system_prompt = optional_non_empty_string_member "system_prompt" json
         ; allowed_space_names = string_or_int_list_member "allowed_space_names" json
         ; allowed_user_names = string_or_int_list_member "allowed_user_names" json
         ; id_token_auth
         })
;;

let load_aux_file json ~base_dir ~field =
  match string_member field json with
  | Ok path -> Yojson.Safe.from_file (resolve_path ~base_dir path)
  | Error _ -> `Assoc []
;;

let resolve_related_paths path =
  let json = Yojson.Safe.from_file path in
  let base_dir = Filename.dirname path in
  let resolve_optional field =
    match string_member field json with
    | Ok relative_or_absolute -> Some (resolve_path ~base_dir relative_or_absolute)
    | Error _ -> None
  in
  { gateway_config_path = path
  ; security_policy_path = resolve_optional "security_policy_file"
  ; error_catalog_path = resolve_optional "error_catalog_file"
  ; providers_schema_path = resolve_optional "providers_schema_file"
  }
;;

let load path =
  let json = Yojson.Safe.from_file path in
  let base_dir = Filename.dirname path in
  let persistence_json = object_member "persistence" json in
  let connector_json = object_member "user_connectors" json in
  let security_policy =
    match string_member "security_policy_file" json with
    | Ok security_policy_file ->
      Security_policy.load_file (resolve_path ~base_dir security_policy_file)
    | Error _ -> Security_policy.default ()
  in
  let error_catalog = load_aux_file json ~base_dir ~field:"error_catalog_file" in
  let providers_schema = load_aux_file json ~base_dir ~field:"providers_schema_file" in
  let user_connectors =
    let telegram_result =
      match object_member "telegram" connector_json with
      | `Assoc _ as telegram_json -> parse_telegram_connector telegram_json
      | _ -> Ok None
    in
    let whatsapp_result =
      match object_member "whatsapp" connector_json with
      | `Assoc _ as whatsapp_json -> parse_whatsapp_connector whatsapp_json
      | _ -> Ok None
    in
    let messenger_result =
      match object_member "messenger" connector_json with
      | `Assoc _ as messenger_json -> parse_messenger_connector messenger_json
      | _ -> Ok None
    in
    let instagram_result =
      match object_member "instagram" connector_json with
      | `Assoc _ as instagram_json -> parse_instagram_connector instagram_json
      | _ -> Ok None
    in
    let line_result =
      match object_member "line" connector_json with
      | `Assoc _ as line_json -> parse_line_connector line_json
      | _ -> Ok None
    in
    let viber_result =
      match object_member "viber" connector_json with
      | `Assoc _ as viber_json -> parse_viber_connector viber_json
      | _ -> Ok None
    in
    let google_chat_result =
      match object_member "google_chat" connector_json with
      | `Assoc _ as google_chat_json -> parse_google_chat_connector google_chat_json
      | _ -> Ok None
    in
    match
      telegram_result,
      whatsapp_result,
      messenger_result,
      instagram_result,
      line_result,
      viber_result,
      google_chat_result
    with
    | Ok telegram, Ok whatsapp, Ok messenger, Ok instagram, Ok line, Ok viber, Ok google_chat ->
      Ok { telegram; whatsapp; messenger; instagram; line; viber; google_chat }
    | Error err, _, _, _, _, _, _
    | _, Error err, _, _, _, _, _
    | _, _, Error err, _, _, _, _
    | _, _, _, Error err, _, _, _
    | _, _, _, _, Error err, _, _
    | _, _, _, _, _, Error err, _
    | _, _, _, _, _, _, Error err -> Error err
  in
  let route_values = list_member "routes" json in
  let virtual_key_values = list_member "virtual_keys" json in
  let rec parse_all parser acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
      (match parser item with
       | Ok value -> parse_all parser (value :: acc) rest
       | Error err -> Error err)
  in
  match user_connectors with
  | Error err -> Error err
  | Ok user_connectors ->
    (match parse_all parse_route [] route_values with
     | Error err -> Error err
     | Ok routes ->
       (match parse_all (parse_virtual_key security_policy) [] virtual_key_values with
        | Error err -> Error err
        | Ok virtual_keys ->
          let sqlite_path =
            match object_member "sqlite_path" persistence_json with
            | `String relative_path -> Some (resolve_path ~base_dir relative_path)
            | _ -> None
          in
          let persistence =
            { sqlite_path
            ; busy_timeout_ms =
                int_member_with_default "busy_timeout_ms" persistence_json ~default:5000
            }
          in
          Ok
            { security_policy
            ; persistence
            ; error_catalog
            ; providers_schema
            ; user_connectors
            ; routes
            ; virtual_keys
            }))
;;
