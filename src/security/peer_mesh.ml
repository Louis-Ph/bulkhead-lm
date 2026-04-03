type context =
  { request_id : string
  ; hop_count : int
  }

let uuid_rng = Random.State.make_self_init ()
let generate_uuid = Uuidm.v4_gen uuid_rng

let generate_request_id () = generate_uuid () |> Uuidm.to_string

let local_context () = { request_id = generate_request_id (); hop_count = 0 }

let parse_non_negative_int value =
  match int_of_string_opt (String.trim value) with
  | Some parsed when parsed >= 0 -> Some parsed
  | _ -> None
;;

let context_of_headers policy headers =
  let mesh = policy.Security_policy.mesh in
  let request_id =
    match Cohttp.Header.get headers mesh.request_id_header with
    | Some value when String.trim value <> "" -> String.trim value
    | _ -> generate_request_id ()
  in
  let hop_count_result =
    match Cohttp.Header.get headers mesh.hop_count_header with
    | None -> Ok 0
    | Some value ->
      (match parse_non_negative_int value with
       | Some parsed -> Ok parsed
       | None ->
         Error
           (Domain_error.invalid_request
              (Fmt.str "Invalid %s header value." mesh.hop_count_header)))
  in
  Result.bind hop_count_result (fun hop_count ->
    if not mesh.enabled
    then Ok { request_id; hop_count = 0 }
    else if hop_count > mesh.max_hops
    then
      Error
        (Domain_error.loop_detected ~max_hops:mesh.max_hops ~request_id ~hop_count ())
    else Ok { request_id; hop_count })
;;

let outbound_headers policy (context : context) =
  let mesh = policy.Security_policy.mesh in
  if not mesh.enabled
  then []
  else
    [ mesh.request_id_header, context.request_id
    ; mesh.hop_count_header, string_of_int (context.hop_count + 1)
    ]
;;

let to_yojson (context : context) =
  `Assoc
    [ "request_id", `String context.request_id
    ; "hop_count", `Int context.hop_count
    ]
;;

let of_yojson = function
  | `Assoc fields ->
    (match List.assoc_opt "request_id" fields, List.assoc_opt "hop_count" fields with
     | Some (`String request_id), Some (`Int hop_count) when String.trim request_id <> "" && hop_count >= 0
       ->
       Ok { request_id = String.trim request_id; hop_count }
     | Some (`String request_id), Some (`Intlit hop_count) when String.trim request_id <> "" ->
       (match int_of_string_opt hop_count with
        | Some parsed when parsed >= 0 -> Ok { request_id = String.trim request_id; hop_count = parsed }
        | _ -> Error "hop_count")
     | _ -> Error "mesh")
  | _ -> Error "mesh"
;;
