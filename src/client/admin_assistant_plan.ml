type config_target =
  | Gateway_config
  | Security_policy

type config_op =
  | Set_json of
      { target : config_target
      ; path : string
      ; value : Yojson.Safe.t
      }
  | Delete_json of
      { target : config_target
      ; path : string
      }
  | Append_json of
      { target : config_target
      ; path : string
      ; value : Yojson.Safe.t
      ; unique : bool
      }

type t =
  { kid_summary : string
  ; why : string list
  ; warnings : string list
  ; config_ops : config_op list
  ; system_ops : Terminal_ops.request list
  }

type apply_inputs =
  { gateway_json : Yojson.Safe.t
  ; security_json : Yojson.Safe.t option
  }

type apply_outputs =
  { gateway_json : Yojson.Safe.t
  ; security_json : Yojson.Safe.t option
  }

let ( let* ) = Result.bind

type segment =
  | Key of string
  | Index of int

let trim = String.trim

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None
;;

let string_member name json =
  match member name json with
  | Some (`String value) when trim value <> "" -> Ok (trim value)
  | _ -> Error name
;;

let bool_member_with_default name json ~default =
  match member name json with
  | Some (`Bool value) -> value
  | _ -> default
;;

let list_member name json =
  match member name json with
  | Some (`List values) -> values
  | _ -> []
;;

let target_of_string = function
  | "gateway_config" -> Ok Gateway_config
  | "security_policy" -> Ok Security_policy
  | value -> Error ("target=" ^ value)
;;

let target_to_string = function
  | Gateway_config -> "gateway config"
  | Security_policy -> "security policy"
;;

let config_op_summary = function
  | Set_json { target; path; _ } ->
    Fmt.str "Set %s at %s" (target_to_string target) path
  | Delete_json { target; path } ->
    Fmt.str "Delete %s at %s" (target_to_string target) path
  | Append_json { target; path; unique; _ } ->
    Fmt.str
      "Append%s %s at %s"
      (if unique then " uniquely to" else " to")
      (target_to_string target)
      path
;;

let json_pointer_segments pointer =
  let decode_segment segment =
    segment
    |> String.split_on_char '~'
    |> function
    | [] -> ""
    | first :: rest ->
      List.fold_left
        (fun acc fragment ->
          let replacement, suffix =
            if fragment = ""
            then "~", ""
            else (
              let head = String.get fragment 0 in
              let tail = String.sub fragment 1 (String.length fragment - 1) in
              match head with
              | '0' -> "~", tail
              | '1' -> "/", tail
              | _ -> "~" ^ String.make 1 head, tail)
          in
          acc ^ replacement ^ suffix)
        first
        rest
  in
  if pointer = ""
  then Ok []
  else if String.get pointer 0 <> '/'
  then Error "path"
  else
    pointer
    |> String.split_on_char '/'
    |> List.tl
    |> List.map decode_segment
    |> List.map (fun value ->
      match int_of_string_opt value with
      | Some index when string_of_int index = value -> Index index
      | _ -> Key value)
    |> fun segments -> Ok segments
;;

let upsert_assoc key value fields =
  let rec loop acc = function
    | [] -> List.rev ((key, value) :: acc)
    | (name, current) :: rest ->
      if String.equal name key
      then List.rev_append acc ((key, value) :: rest)
      else loop ((name, current) :: acc) rest
  in
  loop [] fields
;;

let remove_assoc key fields =
  List.filter (fun (name, _) -> not (String.equal name key)) fields
;;

let default_container = function
  | [] -> `Null
  | Key _ :: _ -> `Assoc []
  | Index _ :: _ -> `List []
;;

let rec set_at json segments value =
  match segments with
  | [] -> Ok value
  | Key key :: rest ->
    let fields =
      match json with
      | `Assoc fields -> Ok fields
      | `Null -> Ok []
      | _ -> Error ("Expected object before " ^ key)
    in
    (match fields with
     | Error _ as err -> err
     | Ok fields ->
       let current =
         match List.assoc_opt key fields with
         | Some current -> current
         | None -> default_container rest
       in
       (match set_at current rest value with
        | Error _ as err -> err
        | Ok updated -> Ok (`Assoc (upsert_assoc key updated fields))))
  | Index index :: rest ->
    if index < 0
    then Error "Negative array index"
    else
      let items =
        match json with
        | `List values -> Ok values
        | `Null -> Ok []
        | _ -> Error ("Expected array before index " ^ string_of_int index)
      in
      (match items with
       | Error _ as err -> err
       | Ok items ->
         let rec pad acc current =
           if current >= index
           then List.rev acc
           else pad (`Null :: acc) (current + 1)
         in
         let padded =
           if List.length items <= index
           then items @ pad [] (List.length items)
           else items
         in
         let current =
           if index < List.length padded then List.nth padded index else default_container rest
         in
         (match set_at current rest value with
          | Error _ as err -> err
          | Ok updated ->
            let updated_items =
              padded
              |> List.mapi (fun idx item -> if idx = index then updated else item)
              |> fun values -> if index = List.length values then values @ [ updated ] else values
            in
            Ok (`List updated_items)))
;;

let rec delete_at json segments =
  match segments with
  | [] -> Error "Cannot delete the whole document"
  | [ Key key ] ->
    (match json with
     | `Assoc fields -> Ok (`Assoc (remove_assoc key fields))
     | _ -> Error ("Expected object before " ^ key))
  | [ Index index ] ->
    (match json with
     | `List values ->
       if index < 0 || index >= List.length values
       then Error ("Array index out of bounds: " ^ string_of_int index)
       else
         Ok
           (`List
              (values
               |> List.mapi (fun idx value -> idx, value)
               |> List.filter_map (fun (idx, value) -> if idx = index then None else Some value)))
     | _ -> Error ("Expected array before index " ^ string_of_int index))
  | Key key :: rest ->
    (match json with
     | `Assoc fields ->
       (match List.assoc_opt key fields with
        | None -> Error ("Missing object field: " ^ key)
        | Some current ->
          (match delete_at current rest with
           | Error _ as err -> err
           | Ok updated -> Ok (`Assoc (upsert_assoc key updated fields))))
     | _ -> Error ("Expected object before " ^ key))
  | Index index :: rest ->
    (match json with
     | `List values ->
       if index < 0 || index >= List.length values
       then Error ("Array index out of bounds: " ^ string_of_int index)
       else
         (match delete_at (List.nth values index) rest with
          | Error _ as err -> err
          | Ok updated ->
            Ok (`List (List.mapi (fun idx value -> if idx = index then updated else value) values)))
     | _ -> Error ("Expected array before index " ^ string_of_int index))
;;

let rec get_at json segments =
  match segments with
  | [] -> Ok json
  | Key key :: rest ->
    (match json with
     | `Assoc fields ->
       (match List.assoc_opt key fields with
        | Some value -> get_at value rest
        | None -> Error ("Missing object field: " ^ key))
     | _ -> Error ("Expected object before " ^ key))
  | Index index :: rest ->
    (match json with
     | `List values ->
       if index < 0 || index >= List.length values
       then Error ("Array index out of bounds: " ^ string_of_int index)
       else get_at (List.nth values index) rest
     | _ -> Error ("Expected array before index " ^ string_of_int index))
;;

let append_at json segments value ~unique =
  let existing_array =
    match get_at json segments with
    | Ok (`List items) -> Ok items
    | Ok _ -> Error "Append target must be an array"
    | Error _ -> Ok []
  in
  match existing_array with
  | Error _ as err -> err
  | Ok items ->
    let should_append =
      not unique || not (List.exists (fun current -> Stdlib.compare current value = 0) items)
    in
    if should_append
    then set_at json segments (`List (items @ [ value ]))
    else Ok json
;;

let config_op_of_yojson json =
  let* op = string_member "op" json in
  let* target_raw = string_member "target" json in
  let* target = target_of_string target_raw in
  let* path = string_member "path" json in
  match op with
  | "set_json" ->
    (match member "value" json with
     | Some value -> Ok (Set_json { target; path; value })
     | None -> Error "value")
  | "delete_json" -> Ok (Delete_json { target; path })
  | "append_json" ->
    (match member "value" json with
     | Some value ->
       Ok
         (Append_json
            { target
            ; path
            ; value
            ; unique = bool_member_with_default "unique" json ~default:false
            })
     | None -> Error "value")
  | value -> Error ("op=" ^ value)
;;

let of_yojson json =
  let* kid_summary = string_member "kid_summary" json in
  let why =
    list_member "why" json
    |> List.filter_map (function
      | `String value when trim value <> "" -> Some (trim value)
      | _ -> None)
  in
  let warnings =
    list_member "warnings" json
    |> List.filter_map (function
      | `String value when trim value <> "" -> Some (trim value)
      | _ -> None)
  in
  let rec parse_config_ops acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
      (match config_op_of_yojson item with
       | Ok op -> parse_config_ops (op :: acc) rest
       | Error err -> Error err)
  in
  let rec parse_system_ops acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
      (match Terminal_ops.request_of_yojson item with
       | Ok op -> parse_system_ops (op :: acc) rest
       | Error err -> Error err)
  in
  let* config_ops = parse_config_ops [] (list_member "config_ops" json) in
  let* system_ops = parse_system_ops [] (list_member "system_ops" json) in
  Ok { kid_summary; why; warnings; config_ops; system_ops }
;;

let is_empty plan = plan.config_ops = [] && plan.system_ops = []

let summary_line plan =
  Fmt.str
    "%s (%d config change%s, %d system action%s)"
    plan.kid_summary
    (List.length plan.config_ops)
    (if List.length plan.config_ops = 1 then "" else "s")
    (List.length plan.system_ops)
    (if List.length plan.system_ops = 1 then "" else "s")
;;

let render_lines plan =
  let why_lines = List.map (fun line -> "  - " ^ line) plan.why in
  let warning_lines =
    List.map (fun line -> "  - " ^ line) plan.warnings
  in
  let config_lines =
    List.map (fun op -> "  - " ^ config_op_summary op) plan.config_ops
  in
  let system_lines =
    List.map
      (fun op ->
        "  - "
        ^
        match op with
        | Terminal_ops.List_dir request -> Fmt.str "List directory %s" request.path
        | Terminal_ops.Read_file request -> Fmt.str "Read file %s" request.path
        | Terminal_ops.Write_file request -> Fmt.str "Write file %s" request.path
        | Terminal_ops.Exec request ->
          Fmt.str "Run %s" (String.concat " " (request.command :: request.args)))
      plan.system_ops
  in
  [ "Assistant plan:"
  ; summary_line plan
  ]
  @ (if why_lines = [] then [] else "Why:" :: why_lines)
  @ (if warning_lines = [] then [] else "Warnings:" :: warning_lines)
  @ (if config_lines = [] then [] else "Config changes:" :: config_lines)
  @ (if system_lines = [] then [] else "System actions:" :: system_lines)
;;

let apply_config_op json op =
  let target, path =
    match op with
    | Set_json { target; path; _ }
    | Delete_json { target; path }
    | Append_json { target; path; _ } -> target, path
  in
  match json_pointer_segments path with
  | Error _ -> Error (Fmt.str "Invalid JSON pointer for %s: %s" (target_to_string target) path)
  | Ok segments ->
    (match op with
     | Set_json { value; _ } -> set_at json segments value
     | Delete_json _ -> delete_at json segments
     | Append_json { value; unique; _ } -> append_at json segments value ~unique)
;;

let apply_to_inputs inputs plan =
  let apply_target gateway_json security_json target op =
    match target with
    | Gateway_config ->
      apply_config_op gateway_json op
      |> Result.map (fun gateway_json -> gateway_json, security_json)
    | Security_policy ->
      (match security_json with
       | None -> Error "The active config does not reference a security policy file."
       | Some security_json ->
         apply_config_op security_json op
         |> Result.map (fun updated_security -> gateway_json, Some updated_security))
  in
  let rec loop gateway_json security_json = function
    | [] -> Ok { gateway_json; security_json }
    | op :: rest ->
      let target =
        match op with
        | Set_json { target; _ }
        | Delete_json { target; _ }
        | Append_json { target; _ } -> target
      in
      (match apply_target gateway_json security_json target op with
       | Error _ as err -> err
       | Ok (next_gateway, next_security) -> loop next_gateway next_security rest)
  in
  loop inputs.gateway_json inputs.security_json plan.config_ops
;;
