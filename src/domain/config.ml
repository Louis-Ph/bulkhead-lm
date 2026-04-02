let ( >>= ) = Result.bind

type provider_kind =
  | Openai_compat
  | Anthropic

type backend =
  { provider_id : string
  ; provider_kind : provider_kind
  ; upstream_model : string
  ; api_base : string
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
  ; error_catalog : Yojson.Safe.t
  ; providers_schema : Yojson.Safe.t
  ; routes : route list
  ; virtual_keys : virtual_key list
  }

let provider_kind_of_string = function
  | "openai_compat" -> Ok Openai_compat
  | "anthropic" -> Ok Anthropic
  | value -> Error (Fmt.str "Unsupported provider kind: %s" value)
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

let parse_backend json =
  string_member "provider_id" json
  >>= fun provider_id ->
  string_member "provider_kind" json
  >>= fun provider_kind_raw ->
  provider_kind_of_string provider_kind_raw
  >>= fun provider_kind ->
  string_member "upstream_model" json
  >>= fun upstream_model ->
  string_member "api_base" json
  >>= fun api_base ->
  string_member "api_key_env" json
  >>= fun api_key_env ->
  Ok { provider_id; provider_kind; upstream_model; api_base; api_key_env }
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

let load path =
  let json = Yojson.Safe.from_file path in
  let base_dir = Filename.dirname path in
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
       Ok { security_policy; error_catalog; providers_schema; routes; virtual_keys })
;;
