open Lwt.Infix

type request =
  { line_no : int
  ; id : string option
  ; kind : Terminal_client.call_kind
  ; authorization : string option
  ; api_key : string option
  ; request_json : Yojson.Safe.t
  }

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None
;;

let string_member_opt name json =
  match member name json with
  | Some (`String value) when String.trim value <> "" -> Some value
  | _ -> None
;;

let request_kind_json kind = `String (Terminal_client.call_kind_to_string kind)

let openai_error_body error =
  match Domain_error.to_openai_json error with
  | `Assoc [ "error", body ] -> body
  | json -> json
;;

let error_json ?id ?kind ?line_no (error : Domain_error.t) =
  let fields =
    [ Some ("ok", `Bool false)
    ; Some ("error", openai_error_body error)
    ; Some ("status", `Int error.status)
    ; Some ("retryable", `Bool (Domain_error.is_retryable error))
    ; Option.map (fun value -> "id", `String value) id
    ; Option.map (fun value -> "kind", request_kind_json value) kind
    ; Option.map (fun value -> "line", `Int value) line_no
    ]
    |> List.filter_map Fun.id
  in
  `Assoc fields
;;

let success_json ~id ~kind ~line_no response =
  `Assoc
    [ "ok", `Bool true
    ; "id", `String id
    ; "kind", request_kind_json kind
    ; "line", `Int line_no
    ; "response", Terminal_client.response_to_yojson response
    ]
;;

let parse_request ~line_no line =
  try
    let json = Yojson.Safe.from_string line in
    let kind =
      match string_member_opt "kind" json with
      | None -> Ok Terminal_client.Chat
      | Some value -> Terminal_client.call_kind_of_string value
    in
    match kind with
    | Error err -> Error (string_member_opt "id" json, None, err)
    | Ok kind ->
      (match member "request" json with
       | Some request_json ->
         Ok
           { line_no
           ; id = string_member_opt "id" json
           ; kind
           ; authorization = string_member_opt "authorization" json
           ; api_key = string_member_opt "api_key" json
           ; request_json
           }
       | None ->
         Error
           ( string_member_opt "id" json
           , Some kind
           , Domain_error.invalid_request
               (Fmt.str "Worker line %d is missing the request object." line_no) ))
  with
  | Yojson.Json_error message ->
    Error
      ( None
      , None
      , Domain_error.invalid_request
          (Fmt.str "Worker line %d is not valid JSON: %s" line_no message) )
;;

let handle_request store ?authorization ?api_key request =
  let authorization =
    match request.authorization with
    | Some value -> Some value
    | None -> authorization
  in
  let api_key =
    match request.api_key with
    | Some value -> Some value
    | None -> api_key
  in
  match Terminal_client.resolve_authorization store ?authorization ?api_key () with
  | Error error ->
    Lwt.return
      (error_json ?id:request.id ~kind:request.kind ~line_no:request.line_no error)
  | Ok authorization ->
    Terminal_client.invoke_json
      store
      ~authorization
      ~kind:request.kind
      request.request_json
    >|= function
    | Ok response ->
      let response_id =
        match request.id with
        | Some value -> value
        | None -> Fmt.str "line-%d" request.line_no
      in
      success_json ~id:response_id ~kind:request.kind ~line_no:request.line_no response
    | Error error ->
      error_json ?id:request.id ~kind:request.kind ~line_no:request.line_no error
;;

let worker_count jobs = max 1 jobs

let rec worker_loop stream emit handle =
  Lwt_stream.get stream
  >>= function
  | None -> Lwt.return_unit
  | Some item ->
    handle item >>= emit >>= fun () -> worker_loop stream emit handle
;;

let run_lines store ?authorization ?api_key ~jobs lines =
  let indexed_lines = List.mapi (fun index line -> index + 1, line) lines in
  let stream = Lwt_stream.of_list indexed_lines in
  let outputs = ref [] in
  let output_lock = Lwt_mutex.create () in
  let emit json =
    Lwt_mutex.with_lock output_lock (fun () ->
      outputs := Yojson.Safe.to_string json :: !outputs;
      Lwt.return_unit)
  in
  let handle (line_no, line) =
    match parse_request ~line_no line with
    | Ok request -> handle_request store ?authorization ?api_key request
    | Error (id, kind, error) -> Lwt.return (error_json ?id ?kind ~line_no error)
  in
  let workers =
    List.init (worker_count jobs) (fun _ -> worker_loop stream emit handle)
  in
  Lwt.join workers >|= fun () -> List.rev !outputs
;;

let run_stdio store ?authorization ?api_key ~jobs () =
  let stream, push = Lwt_stream.create () in
  let output_lock = Lwt_mutex.create () in
  let emit json =
    Lwt_mutex.with_lock output_lock (fun () ->
      Lwt_io.write_line Lwt_io.stdout (Yojson.Safe.to_string json))
  in
  let handle (line_no, line) =
    match parse_request ~line_no line with
    | Ok request -> handle_request store ?authorization ?api_key request
    | Error (id, kind, error) -> Lwt.return (error_json ?id ?kind ~line_no error)
  in
  let rec read_loop line_no =
    Lwt_io.read_line_opt Lwt_io.stdin
    >>= function
    | None ->
      push None;
      Lwt.return_unit
    | Some line ->
      push (Some (line_no, line));
      read_loop (line_no + 1)
  in
  let workers =
    List.init (worker_count jobs) (fun _ -> worker_loop stream emit handle)
  in
  Lwt.join [ read_loop 1; Lwt.join workers ]
;;
