let ( >>= ) = Result.bind

type provider_kind =
  | Openai_compat
  | Anthropic
  | Openrouter_openai
  | Google_openai
  | Vertex_openai
  | Mistral_openai
  | Ollama_openai
  | Alibaba_openai
  | Moonshot_openai
  | Xai_openai
  | Meta_openai
  | Deepseek_openai
  | Groq_openai
  | Perplexity_openai
  | Together_openai
  | Cerebras_openai
  | Cohere_openai
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

type wechat_connector =
  { webhook_path : string
  ; signature_token_env : string
  ; encoding_aes_key_env : string option
  ; app_id_env : string option
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_open_ids : string list
  ; allowed_account_ids : string list
  }

type discord_connector =
  { webhook_path : string
  ; public_key_env : string
  ; authorization_env : string
  ; route_model : string
  ; system_prompt : string option
  ; allowed_application_ids : string list
  ; allowed_user_ids : string list
  ; allowed_channel_ids : string list
  ; allowed_guild_ids : string list
  ; ephemeral_by_default : bool
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
  ; wechat : wechat_connector option
  ; discord : discord_connector option
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

(* Each pool member references an existing route by [route_model] (the public
   model name) and reserves its own daily token budget. The router picks the
   member with the lowest observed latency that still has budget left and a
   closed circuit; this lets you pile many tightly-budgeted models behind one
   pool name and let the gateway fan-out automatically. *)
type pool_member =
  { route_model : string
  ; daily_token_budget : int
  }

type pool =
  { name : string
  ; members : pool_member list
  ; is_global : bool
      (** When [is_global = true] the [members] field is ignored at lookup time;
          the effective member list is recomputed as every configured route. *)
  }

type t =
  { security_policy : Security_policy.t
  ; persistence : persistence
  ; error_catalog : Yojson.Safe.t
  ; providers_schema : Yojson.Safe.t
  ; user_connectors : user_connectors
  ; routes : route list
  ; pools : pool list
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
  | "vertex_openai" -> Ok Vertex_openai
  | "mistral_openai" -> Ok Mistral_openai
  | "ollama_openai" -> Ok Ollama_openai
  | "alibaba_openai" -> Ok Alibaba_openai
  | "moonshot_openai" -> Ok Moonshot_openai
  | "xai_openai" -> Ok Xai_openai
  | "meta_openai" -> Ok Meta_openai
  | "deepseek_openai" -> Ok Deepseek_openai
  | "groq_openai" -> Ok Groq_openai
  | "perplexity_openai" -> Ok Perplexity_openai
  | "together_openai" -> Ok Together_openai
  | "cerebras_openai" -> Ok Cerebras_openai
  | "cohere_openai" -> Ok Cohere_openai
  | "bulkhead_peer" -> Ok Bulkhead_peer
  | "bulkhead_ssh_peer" -> Ok Bulkhead_ssh_peer
  | value -> Error (Fmt.str "Unsupported provider kind: %s" value)
;;

let provider_kind_to_string = function
  | Openai_compat -> "openai_compat"
  | Anthropic -> "anthropic"
  | Openrouter_openai -> "openrouter_openai"
  | Google_openai -> "google_openai"
  | Vertex_openai -> "vertex_openai"
  | Mistral_openai -> "mistral_openai"
  | Ollama_openai -> "ollama_openai"
  | Alibaba_openai -> "alibaba_openai"
  | Moonshot_openai -> "moonshot_openai"
  | Xai_openai -> "xai_openai"
  | Meta_openai -> "meta_openai"
  | Deepseek_openai -> "deepseek_openai"
  | Groq_openai -> "groq_openai"
  | Perplexity_openai -> "perplexity_openai"
  | Together_openai -> "together_openai"
  | Cerebras_openai -> "cerebras_openai"
  | Cohere_openai -> "cohere_openai"
  | Bulkhead_peer -> "bulkhead_peer"
  | Bulkhead_ssh_peer -> "bulkhead_ssh_peer"
;;

let is_openai_compatible_kind = function
  | Openai_compat
  | Openrouter_openai
  | Google_openai
  | Vertex_openai
  | Mistral_openai
  | Ollama_openai
  | Alibaba_openai
  | Moonshot_openai
  | Xai_openai
  | Meta_openai
  | Deepseek_openai
  | Groq_openai
  | Perplexity_openai
  | Together_openai
  | Cerebras_openai
  | Cohere_openai
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
    if String.trim host = "" then Error "ssh_transport.host" else Ok (String.trim host)
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
  (* Unknown provider kinds fall back to openai_compat for forward compatibility.
     Almost every new HTTP provider uses the OpenAI-compat wire format. *)
  let provider_kind =
    match provider_kind_of_string provider_kind_raw with
    | Ok kind -> kind
    | Error _ -> Openai_compat
  in
  string_member "upstream_model" json
  >>= fun upstream_model ->
  let target_result =
    match provider_kind with
    | Bulkhead_ssh_peer ->
      (match object_member "ssh_transport" json with
       | `Assoc _ as ssh_json ->
         parse_ssh_transport ssh_json
         |> Result.map (fun transport -> Ssh_target transport)
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
  (* Skip individual backends that fail to parse — a bad entry should not
     prevent the remaining backends in the route from being usable. *)
  let backends =
    List.filter_map
      (fun item ->
        match parse_backend item with
        | Ok backend -> Some backend
        | Error _ -> None)
      backend_values
  in
  Ok { public_model; backends }
;;

let parse_pool_member json =
  string_member "route_model" json
  >>= fun route_model ->
  let daily_token_budget =
    int_member_with_default "daily_token_budget" json ~default:10_000
  in
  if daily_token_budget < 0
  then Error (Fmt.str "pool member %s has negative daily_token_budget" route_model)
  else Ok { route_model; daily_token_budget }
;;

let parse_pool json =
  string_member "name" json
  >>= fun name ->
  if String.trim name = ""
  then Error "pool name cannot be empty"
  else (
    let is_global = bool_member_with_default "is_global" json ~default:false in
    let member_values = list_member "members" json in
    let members =
      List.filter_map
        (fun item ->
          match parse_pool_member item with
          | Ok member -> Some member
          | Error _ -> None)
        member_values
    in
    Ok { name; members; is_global })
;;

(* Pool names share the public_model namespace, so a pool that collides with
   an existing route would shadow it ambiguously; we drop the offender (with
   a tolerant log path) rather than refuse to start. *)
let route_models_of (routes : route list) =
  routes |> List.map (fun route -> route.public_model)
;;

let validate_pool ~routes (pool : pool) =
  let route_set = route_models_of routes in
  if List.mem pool.name route_set
  then
    Error
      (Fmt.str
         "pool %S collides with an existing route public_model"
         pool.name)
  else if pool.is_global
  then Ok pool
  else (
    let valid_members =
      pool.members
      |> List.filter (fun (member : pool_member) ->
        List.mem member.route_model route_set)
    in
    Ok { pool with members = valid_members })
;;

let dedupe_pools_by_name pools =
  let seen = Hashtbl.create 8 in
  List.filter
    (fun pool ->
      if Hashtbl.mem seen pool.name
      then false
      else (
        Hashtbl.add seen pool.name ();
        true))
    pools
;;

(** Look up a pool by its [name]; the pool name is what the client sends as
    [model] when calling chat completions. *)
let find_pool config name =
  List.find_opt (fun (pool : pool) -> String.equal pool.name name) config.pools
;;

(** Returns the effective member list for a pool, expanding [is_global = true]
    to all configured routes at call time so that adding a new route makes it
    immediately reachable through the global pool with no reconfiguration. *)
let effective_pool_members config (pool : pool) =
  if pool.is_global
  then
    config.routes
    |> List.map (fun (route : route) ->
      { route_model = route.public_model
      ; daily_token_budget = max_int (* global pool delegates budget to virtual keys *)
      })
  else pool.members
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
         ; allowed_sender_numbers =
             string_or_int_list_member "allowed_sender_numbers" json
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

let parse_wechat_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    string_member "signature_token_env" json
    >>= fun signature_token_env ->
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
                  ~default:"/connectors/wechat/webhook")
         ; signature_token_env = String.trim signature_token_env
         ; encoding_aes_key_env =
             optional_non_empty_string_member "encoding_aes_key_env" json
         ; app_id_env = optional_non_empty_string_member "app_id_env" json
         ; authorization_env = String.trim authorization_env
         ; route_model = String.trim route_model
         ; system_prompt = optional_non_empty_string_member "system_prompt" json
         ; allowed_open_ids = string_or_int_list_member "allowed_open_ids" json
         ; allowed_account_ids = string_or_int_list_member "allowed_account_ids" json
         })
;;

let parse_discord_connector json =
  if not (bool_member_with_default "enabled" json ~default:true)
  then Ok None
  else
    string_member "public_key_env" json
    >>= fun public_key_env ->
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
                  ~default:"/connectors/discord/webhook")
         ; public_key_env = String.trim public_key_env
         ; authorization_env = String.trim authorization_env
         ; route_model = String.trim route_model
         ; system_prompt = optional_non_empty_string_member "system_prompt" json
         ; allowed_application_ids =
             string_or_int_list_member "allowed_application_ids" json
         ; allowed_user_ids = string_or_int_list_member "allowed_user_ids" json
         ; allowed_channel_ids = string_or_int_list_member "allowed_channel_ids" json
         ; allowed_guild_ids = string_or_int_list_member "allowed_guild_ids" json
         ; ephemeral_by_default =
             bool_member_with_default "ephemeral_by_default" json ~default:true
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

let configured_user_connector_webhook_paths (user_connectors : user_connectors) =
  [ Option.map
      (fun (connector : telegram_connector) -> "telegram", connector.webhook_path)
      user_connectors.telegram
  ; Option.map
      (fun (connector : whatsapp_connector) -> "whatsapp", connector.webhook_path)
      user_connectors.whatsapp
  ; Option.map
      (fun (connector : messenger_connector) -> "messenger", connector.webhook_path)
      user_connectors.messenger
  ; Option.map
      (fun (connector : instagram_connector) -> "instagram", connector.webhook_path)
      user_connectors.instagram
  ; Option.map
      (fun (connector : line_connector) -> "line", connector.webhook_path)
      user_connectors.line
  ; Option.map
      (fun (connector : viber_connector) -> "viber", connector.webhook_path)
      user_connectors.viber
  ; Option.map
      (fun (connector : wechat_connector) -> "wechat", connector.webhook_path)
      user_connectors.wechat
  ; Option.map
      (fun (connector : discord_connector) -> "discord", connector.webhook_path)
      user_connectors.discord
  ; Option.map
      (fun (connector : google_chat_connector) -> "google_chat", connector.webhook_path)
      user_connectors.google_chat
  ]
  |> List.filter_map Fun.id
;;

let validate_user_connector_webhook_paths user_connectors =
  let add_binding seen (connector_id, webhook_path) =
    let existing_ids = Option.value (List.assoc_opt webhook_path seen) ~default:[] in
    let updated_ids = List.sort_uniq String.compare (connector_id :: existing_ids) in
    (webhook_path, updated_ids) :: List.remove_assoc webhook_path seen
  in
  let grouped_paths =
    List.fold_left
      add_binding
      []
      (configured_user_connector_webhook_paths user_connectors)
  in
  let duplicates =
    grouped_paths
    |> List.filter_map (fun (webhook_path, connector_ids) ->
      match connector_ids with
      | _ :: _ :: _ ->
        Some (Fmt.str "%s used by %s" webhook_path (String.concat ", " connector_ids))
      | _ -> None)
  in
  match duplicates with
  | [] -> Ok user_connectors
  | _ ->
    Error
      (Fmt.str
         "Duplicate user connector webhook_path values are not allowed: %s."
         (String.concat "; " (List.rev duplicates)))
;;

let path_prefix_matches_request prefix request_path =
  prefix = request_path
  || (prefix <> "/"
      && String.starts_with ~prefix:(prefix ^ "/") request_path)
;;

let validate_control_plane_paths security_policy user_connectors =
  let control_plane = security_policy.Security_policy.control_plane in
  if not control_plane.enabled
  then Ok ()
  else (
    let configured_webhooks =
      configured_user_connector_webhook_paths user_connectors |> List.map snd
    in
    let reserved_paths =
      [ "/health"
      ; "/v1/models"
      ; "/v1/chat/completions"
      ; "/v1/embeddings"
      ; "/v1/responses"
      ]
    in
    if control_plane.path_prefix = "/"
    then
      Error
        "security_policy.control_plane.path_prefix must not be the root path when the control plane is enabled."
    else
      let conflicting_paths =
        reserved_paths @ configured_webhooks
        |> List.filter (path_prefix_matches_request control_plane.path_prefix)
      in
      match conflicting_paths with
      | [] -> Ok ()
      | _ ->
        Error
          (Fmt.str
             "security_policy.control_plane.path_prefix %s conflicts with existing routes: %s."
             control_plane.path_prefix
             (String.concat ", " conflicting_paths)))
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
    let wechat_result =
      match object_member "wechat" connector_json with
      | `Assoc _ as wechat_json -> parse_wechat_connector wechat_json
      | _ -> Ok None
    in
    let discord_result =
      match object_member "discord" connector_json with
      | `Assoc _ as discord_json -> parse_discord_connector discord_json
      | _ -> Ok None
    in
    let google_chat_result =
      match object_member "google_chat" connector_json with
      | `Assoc _ as google_chat_json -> parse_google_chat_connector google_chat_json
      | _ -> Ok None
    in
    match
      ( telegram_result
      , whatsapp_result
      , messenger_result
      , instagram_result
      , line_result
      , viber_result
      , wechat_result
      , discord_result
      , google_chat_result )
    with
    | ( Ok telegram
      , Ok whatsapp
      , Ok messenger
      , Ok instagram
      , Ok line
      , Ok viber
      , Ok wechat
      , Ok discord
      , Ok google_chat ) ->
      validate_user_connector_webhook_paths
        { telegram
        ; whatsapp
        ; messenger
        ; instagram
        ; line
        ; viber
        ; wechat
        ; discord
        ; google_chat
        }
    | Error err, _, _, _, _, _, _, _, _
    | _, Error err, _, _, _, _, _, _, _
    | _, _, Error err, _, _, _, _, _, _
    | _, _, _, Error err, _, _, _, _, _
    | _, _, _, _, Error err, _, _, _, _
    | _, _, _, _, _, Error err, _, _, _
    | _, _, _, _, _, _, Error err, _, _
    | _, _, _, _, _, _, _, Error err, _
    | _, _, _, _, _, _, _, _, Error err -> Error err
  in
  let route_values = list_member "routes" json in
  let virtual_key_values = list_member "virtual_keys" json in
  (* Strict: a bad virtual key entry is a hard error — it means an intended
     principal silently loses access, which is worse than refusing to start. *)
  let rec parse_all_strict parser acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
      (match parser item with
       | Ok value -> parse_all_strict parser (value :: acc) rest
       | Error err -> Error err)
  in
  (* Tolerant: a route that fails to parse is skipped — the gateway starts
     with whatever routes could be loaded rather than refusing to start at all. *)
  let parse_routes_tolerant values =
    List.filter_map
      (fun item ->
        match parse_route item with
        | Ok route -> Some route
        | Error _ -> None)
      values
  in
  match user_connectors with
  | Error err -> Error err
  | Ok user_connectors ->
    (match validate_control_plane_paths security_policy user_connectors with
     | Error err -> Error err
     | Ok () ->
       let routes = parse_routes_tolerant route_values in
       (* Tolerant: a pool that fails to parse or collides with a route is
          dropped silently so the rest of the gateway still starts. *)
       let pool_values = list_member "pools" json in
       let pools =
         pool_values
         |> List.filter_map (fun item ->
           match parse_pool item with
           | Ok pool ->
             (match validate_pool ~routes pool with
              | Ok pool -> Some pool
              | Error _ -> None)
           | Error _ -> None)
         |> dedupe_pools_by_name
       in
       (match parse_all_strict (parse_virtual_key security_policy) [] virtual_key_values with
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
            ; pools
            ; virtual_keys
            }))
;;
