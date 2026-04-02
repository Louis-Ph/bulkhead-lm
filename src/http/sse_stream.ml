let chunk_text ?(size = 16) text =
  let rec loop acc offset =
    if offset >= String.length text
    then List.rev acc
    else (
      let remaining = String.length text - offset in
      let length = min size remaining in
      let part = String.sub text offset length in
      loop (part :: acc) (offset + length))
  in
  if text = "" then [ "" ] else loop [] 0
;;

let encode ?event data =
  let event_prefix =
    match event with
    | None -> ""
    | Some name -> "event: " ^ name ^ "\n"
  in
  event_prefix ^ "data: " ^ Yojson.Safe.to_string data ^ "\n\n"
;;

let done_marker = "data: [DONE]\n\n"

let chat_completion_chunks (response : Openai_types.chat_response) =
  let text =
    response.choices
    |> List.filter_map (fun (choice : Openai_types.chat_choice) ->
      let content = choice.message.content in
      if content = "" then None else Some content)
    |> String.concat "\n"
  in
  let intro =
    `Assoc
      [ "id", `String response.id
      ; "object", `String "chat.completion.chunk"
      ; "created", `Int response.created
      ; "model", `String response.model
      ; ( "choices"
        , `List
            [ `Assoc
                [ "index", `Int 0
                ; "delta", `Assoc [ "role", `String "assistant"; "content", `String "" ]
                ; "finish_reason", `Null
                ]
            ] )
      ]
  in
  let deltas =
    chunk_text text
    |> List.map (fun part ->
      `Assoc
        [ "id", `String response.id
        ; "object", `String "chat.completion.chunk"
        ; "created", `Int response.created
        ; "model", `String response.model
        ; ( "choices"
          , `List
              [ `Assoc
                  [ "index", `Int 0
                  ; "delta", `Assoc [ "content", `String part ]
                  ; "finish_reason", `Null
                  ]
              ] )
        ])
  in
  let outro =
    `Assoc
      [ "id", `String response.id
      ; "object", `String "chat.completion.chunk"
      ; "created", `Int response.created
      ; "model", `String response.model
      ; ( "choices"
        , `List
            [ `Assoc
                [ "index", `Int 0; "delta", `Assoc []; "finish_reason", `String "stop" ]
            ] )
      ]
  in
  (intro :: deltas) @ [ outro ]
;;

let response_events (response : Responses_api.response) =
  let created =
    `Assoc
      [ "type", `String "response.created"
      ; "response", Responses_api.response_to_yojson response
      ]
  in
  let deltas =
    chunk_text response.output_text
    |> List.map (fun part ->
      ( Some "response.output_text.delta"
      , `Assoc
          [ "type", `String "response.output_text.delta"
          ; "delta", `String part
          ; "output_index", `Int 0
          ; "content_index", `Int 0
          ] ))
  in
  let completed =
    `Assoc
      [ "type", `String "response.completed"
      ; "response", Responses_api.response_to_yojson response
      ]
  in
  ((None, created) :: deltas) @ [ Some "response.completed", completed ]
;;

let respond_chat response =
  let headers =
    Cohttp.Header.of_list
      [ "content-type", "text/event-stream"
      ; "cache-control", "no-cache"
      ; "connection", "keep-alive"
      ]
  in
  let body =
    chat_completion_chunks response
    |> List.map (fun json -> encode json)
    |> fun chunks ->
    chunks @ [ done_marker ] |> Lwt_stream.of_list |> Cohttp_lwt.Body.of_stream
  in
  Cohttp_lwt_unix.Server.respond ~headers ~status:`OK ~body ()
;;

let respond_response response =
  let headers =
    Cohttp.Header.of_list
      [ "content-type", "text/event-stream"
      ; "cache-control", "no-cache"
      ; "connection", "keep-alive"
      ]
  in
  let body =
    response_events response
    |> List.map (fun (event, json) -> encode ?event json)
    |> fun chunks ->
    chunks @ [ done_marker ] |> Lwt_stream.of_list |> Cohttp_lwt.Body.of_stream
  in
  Cohttp_lwt_unix.Server.respond ~headers ~status:`OK ~body ()
;;
