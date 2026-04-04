let ( >>= ) = Result.bind

type provider_kind =
  | Openai_compat
  | Anthropic
  | Google_openai
  | Mistral_openai
  | Ollama_openai
  | Alibaba_openai
  | Moonshot_openai
  | Aegis_peer
  | Aegis_ssh_peer

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
  | "google_openai" -> Ok Google_openai
  | "mistral_openai" -> Ok Mistral_openai
  | "ollama_openai" -> Ok Ollama_openai
  | "alibaba_openai" -> Ok Alibaba_openai
  | "moonshot_openai" -> Ok Moonshot_openai
  | "aegis_peer" -> Ok Aegis_peer
  | "aegis_ssh_peer" -> Ok Aegis_ssh_peer
  | value -> Error (Fmt.str "Unsupported provider kind: %s" value)
;;

let is_openai_compatible_kind = function
  | Openai_compat
  | Google_openai
  | Mistral_openai
  | Ollama_openai
  | Alibaba_openai
  | Moonshot_openai
  | Aegis_peer
  | Aegis_ssh_peer -> true
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
    | Aegis_ssh_peer ->
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
  let security_policy =
    match string_member "security_policy_file" json with
    | Ok security_policy_file ->
      Security_policy.load_file (resolve_path ~base_dir security_policy_file)
    | Error _ -> Security_policy.default ()
  in
  let error_catalog = load_aux_file json ~base_dir ~field:"error_catalog_file" in
  let providers_schema = load_aux_file json ~base_dir ~field:"providers_schema_file" in
  let route_values = list_member "routes" json in
  let virtual_key_values = list_member "virtual_keys" json in
  let rec parse_all parser acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
      (match parser item with
       | Ok value -> parse_all parser (value :: acc) rest
       | Error err -> Error err)
  in
  match parse_all parse_route [] route_values with
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
         ; routes
         ; virtual_keys
         })
;;
