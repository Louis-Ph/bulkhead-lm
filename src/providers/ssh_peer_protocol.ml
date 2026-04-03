type worker_kind =
  | Chat
  | Embeddings

let worker_kind_to_string = function
  | Chat -> "chat"
  | Embeddings -> "embeddings"
;;

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None
;;

let string_member name json =
  match member name json with
  | Some (`String value) when String.trim value <> "" -> Some (String.trim value)
  | _ -> None
;;

let int_member name json =
  match member name json with
  | Some (`Int value) -> Some value
  | Some (`Intlit value) -> int_of_string_opt value
  | _ -> None
;;

let bool_member name json =
  match member name json with
  | Some (`Bool value) -> Some value
  | _ -> None
;;

let request_json ?peer_context ~request_id ~kind request =
  let fields =
    [ Some ("id", `String request_id)
    ; Some ("kind", `String (worker_kind_to_string kind))
    ; Some ("request", request)
    ; Option.map (fun context -> "mesh", Peer_mesh.to_yojson context) peer_context
    ]
    |> List.filter_map Fun.id
  in
  `Assoc fields
;;

let retry_disposition_of_status status =
  if status = 429 || (status >= 500 && status <= 599 && status <> 508)
  then Domain_error.Retryable
  else Domain_error.Non_retryable
;;

let error_of_worker_json ~provider_id json =
  let status = Option.value (int_member "status" json) ~default:502 in
  let retry_disposition =
    match bool_member "retryable" json with
    | Some true -> Domain_error.Retryable
    | Some false -> Domain_error.Non_retryable
    | None -> retry_disposition_of_status status
  in
  let error_json = Option.value (member "error" json) ~default:`Null in
  let code = Option.value (string_member "code" error_json) ~default:"upstream_failure" in
  let error_type = Option.value (string_member "type" error_json) ~default:"api_error" in
  let message =
    Option.value
      (string_member "message" error_json)
      ~default:"Remote AegisLM SSH worker returned an error."
  in
  Domain_error.make ~provider_id ~retry_disposition ~code ~status ~error_type message
;;

let response_json_of_line ~provider_id line =
  try
    let json = Yojson.Safe.from_string line in
    match bool_member "ok" json with
    | Some false -> Error (error_of_worker_json ~provider_id json)
    | Some true ->
      (match member "response" json with
       | Some response_json -> Ok response_json
       | None ->
         Error
           (Domain_error.upstream
              ~provider_id
              "Remote AegisLM SSH worker response is missing the response object."))
    | None ->
      Error
        (Domain_error.upstream
           ~provider_id
           "Remote AegisLM SSH worker returned an invalid envelope.")
  with
  | Yojson.Json_error message ->
    Error
      (Domain_error.upstream
         ~provider_id
         ("Remote AegisLM SSH worker returned invalid JSON: " ^ message))
;;

let chat_response_of_line ~provider_id line =
  Result.bind
    (response_json_of_line ~provider_id line)
    (fun response_json ->
    match Openai_types.chat_response_of_yojson response_json with
    | Ok response -> Ok response
    | Error field ->
      Error
        (Domain_error.upstream
           ~provider_id
           ("Unable to parse remote chat response field: " ^ field)))
;;

let embeddings_response_of_line ~provider_id line =
  Result.bind
    (response_json_of_line ~provider_id line)
    (fun response_json ->
    match Openai_types.embeddings_response_of_yojson response_json with
    | Ok response -> Ok response
    | Error field ->
      Error
        (Domain_error.upstream
           ~provider_id
           ("Unable to parse remote embeddings response field: " ^ field)))
;;
