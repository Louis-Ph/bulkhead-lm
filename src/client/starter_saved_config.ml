type catalog_references =
  { security_policy_file : string
  ; error_catalog_file : string
  ; providers_schema_file : string
  }

type ensure_outcome =
  | Already_present
  | Bootstrapped
  | Migrated

let path_segments path =
  String.split_on_char '/' path |> List.filter (fun segment -> segment <> "")
;;

let join_absolute_segments segments =
  match segments with
  | [] -> "/"
  | _ -> "/" ^ String.concat "/" segments
;;

let normalize_absolute_path path =
  let absolute =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path
  in
  let rec loop acc = function
    | [] -> List.rev acc
    | "" :: rest
    | "." :: rest -> loop acc rest
    | ".." :: rest ->
      (match acc with
       | _ :: tail -> loop tail rest
       | [] -> loop [] rest)
    | segment :: rest -> loop (segment :: acc) rest
  in
  join_absolute_segments (loop [] (String.split_on_char '/' absolute))
;;

let relative_path ~from_dir ~target =
  let rec drop_common left right =
    match left, right with
    | left_head :: left_tail, right_head :: right_tail
      when String.equal left_head right_head -> drop_common left_tail right_tail
    | _ -> left, right
  in
  let from_segments = path_segments (normalize_absolute_path from_dir) in
  let target_segments = path_segments (normalize_absolute_path target) in
  let remaining_from, remaining_target = drop_common from_segments target_segments in
  match (List.map (fun _ -> "..") remaining_from) @ remaining_target with
  | [] -> "."
  | segments -> String.concat "/" segments
;;

let catalog_references_for_output_path ~base_config_path output_path =
  let output_dir = Filename.dirname output_path in
  let defaults_dir = Filename.concat (Filename.dirname base_config_path) "defaults" in
  { security_policy_file =
      relative_path
        ~from_dir:output_dir
        ~target:(Filename.concat defaults_dir "security_policy.json")
  ; error_catalog_file =
      relative_path
        ~from_dir:output_dir
        ~target:(Filename.concat defaults_dir "error_catalog.json")
  ; providers_schema_file =
      relative_path
        ~from_dir:output_dir
        ~target:(Filename.concat defaults_dir "providers.schema.json")
  }
;;

let default_local_config_json ~base_config_path ~output_path =
  let references = catalog_references_for_output_path ~base_config_path output_path in
  let detected_connectors =
    Starter_profile.connector_families
    |> List.filter (fun (c : Starter_profile.connector_family) ->
      Starter_profile.non_empty_env Sys.getenv_opt c.detection_env)
  in
  Starter_profile.config_json
    ~security_policy_file:references.security_policy_file
    ~error_catalog_file:references.error_catalog_file
    ~providers_schema_file:references.providers_schema_file
    ~enabled_connectors:detected_connectors
    ~selected_presets:Starter_profile.presets
    ~virtual_key_name:Starter_constants.Defaults.virtual_key_name
    ~token_plaintext:Starter_constants.Defaults.virtual_key_token
    ~daily_token_budget:Starter_constants.Defaults.daily_token_budget
    ~requests_per_minute:Starter_constants.Defaults.requests_per_minute
    ~sqlite_path:Starter_constants.Defaults.sqlite_path
    ()
;;

let bootstrap_if_missing ~base_config_path ~output_path =
  if Sys.file_exists output_path
  then Ok false
  else (
    try
      Starter_profile.write_config_file
        output_path
        (default_local_config_json ~base_config_path ~output_path);
      Ok true
    with
    | Sys_error message -> Error message)
;;

let rewrite_assoc_field name value fields =
  let rec loop acc = function
    | [] -> List.rev ((name, `String value) :: acc)
    | (field_name, _) :: rest when String.equal field_name name ->
      List.rev_append acc ((name, `String value) :: rest)
    | field :: rest -> loop (field :: acc) rest
  in
  loop [] fields
;;

let migrate_catalog_references_if_needed ~base_config_path ~output_path =
  if not (Sys.file_exists output_path)
  then Ok false
  else
    try
      let json = Yojson.Safe.from_file output_path in
      let references =
        catalog_references_for_output_path ~base_config_path output_path
      in
      match json with
      | `Assoc fields ->
        let rewrite_if_legacy field_name legacy_value new_value rewritten_fields =
          match List.assoc_opt field_name fields with
          | Some (`String value) when String.equal value legacy_value ->
            rewrite_assoc_field field_name new_value rewritten_fields, true
          | _ -> rewritten_fields, false
        in
        let fields, changed_security =
          rewrite_if_legacy
            "security_policy_file"
            "defaults/security_policy.json"
            references.security_policy_file
            fields
        in
        let fields, changed_error =
          rewrite_if_legacy
            "error_catalog_file"
            "defaults/error_catalog.json"
            references.error_catalog_file
            fields
        in
        let fields, changed_schema =
          rewrite_if_legacy
            "providers_schema_file"
            "defaults/providers.schema.json"
            references.providers_schema_file
            fields
        in
        if changed_security || changed_error || changed_schema
        then (
          Yojson.Safe.to_file output_path (`Assoc fields);
          Ok true)
        else Ok false
      | _ -> Ok false
    with
    | Sys_error message -> Error message
    | Yojson.Json_error message -> Error message
;;

let ensure ~base_config_path ~output_path =
  if Sys.file_exists output_path
  then (
    match migrate_catalog_references_if_needed ~base_config_path ~output_path with
    | Ok true -> Ok Migrated
    | Ok false -> Ok Already_present
    | Error message -> Error message)
  else
    match bootstrap_if_missing ~base_config_path ~output_path with
    | Ok true -> Ok Bootstrapped
    | Ok false -> Ok Already_present
    | Error message -> Error message
;;
