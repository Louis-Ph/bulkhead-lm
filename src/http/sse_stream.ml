open Lwt.Infix

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

let sse_headers =
  Cohttp.Header.of_list
    [ "content-type", "text/event-stream"
    ; "cache-control", "no-cache"
    ; "connection", "keep-alive"
    ]
;;

let chat_intro_chunk (response : Openai_types.chat_response) =
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
;;

let chat_delta_chunk (response : Openai_types.chat_response) part =
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
    ]
;;

let chat_outro_chunk (response : Openai_types.chat_response) =
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
;;

let chat_completion_chunks (response : Openai_types.chat_response) =
  let text =
    response.choices
    |> List.filter_map (fun (choice : Openai_types.chat_choice) ->
      let content = choice.message.content in
      if content = "" then None else Some content)
    |> String.concat "\n"
  in
  let intro = chat_intro_chunk response in
  let deltas = chunk_text text |> List.map (chat_delta_chunk response) in
  let outro = chat_outro_chunk response in
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

let response_delta_event part =
  ( Some "response.output_text.delta"
  , `Assoc
      [ "type", `String "response.output_text.delta"
      ; "delta", `String part
      ; "output_index", `Int 0
      ; "content_index", `Int 0
      ] )
;;

let respond_encoded_stream ~close feed =
  let stream, push = Lwt_stream.create () in
  let safe_push item =
    try push item with
    | Lwt_stream.Closed -> ()
  in
  let feed_thread =
    Lwt.finalize
      (fun () ->
        Lwt.catch
          (fun () -> feed safe_push)
          (fun _exn ->
            safe_push None;
            Lwt.return_unit))
      (fun () ->
        close () >>= fun () ->
        safe_push None;
        Lwt.return_unit)
  in
  Lwt.async (fun () -> feed_thread);
  Cohttp_lwt_unix.Server.respond
    ~headers:sse_headers
    ~status:`OK
    ~body:(Cohttp_lwt.Body.of_stream stream)
    ()
;;

let respond_chat response =
  let body =
    (chat_completion_chunks response |> List.map (fun json -> encode json)) @ [ done_marker ]
  in
  respond_encoded_stream
    ~close:(fun () -> Lwt.return_unit)
    (fun push ->
      List.iter (fun chunk -> push (Some chunk)) body;
      push None;
      Lwt.return_unit)
;;

let respond_chat_stream (stream : Provider_client.chat_stream) =
  let response = stream.response in
  respond_encoded_stream
    ~close:stream.close
    (fun push ->
      push (Some (encode (chat_intro_chunk response)));
      let rec loop () =
        Lwt_stream.get stream.events
        >>= function
        | None ->
          push (Some (encode (chat_outro_chunk response)));
          push (Some done_marker);
          push None;
          Lwt.return_unit
        | Some (Provider_client.Text_delta part) ->
          push (Some (encode (chat_delta_chunk response part)));
          loop ()
      in
      loop ())
;;

let respond_response response =
  let body =
    response_events response
    |> List.map (fun (event, json) -> encode ?event json)
    |> fun chunks -> chunks @ [ done_marker ]
  in
  respond_encoded_stream
    ~close:(fun () -> Lwt.return_unit)
    (fun push ->
      List.iter (fun chunk -> push (Some chunk)) body;
      push None;
      Lwt.return_unit)
;;

let respond_response_stream ~response (stream : Provider_client.chat_stream) =
  let created =
    `Assoc
      [ "type", `String "response.created"
      ; "response", Responses_api.response_to_yojson response
      ]
  in
  let completed =
    `Assoc
      [ "type", `String "response.completed"
      ; "response", Responses_api.response_to_yojson response
      ]
  in
  respond_encoded_stream
    ~close:stream.close
    (fun push ->
      push (Some (encode created));
      let rec loop () =
        Lwt_stream.get stream.events
        >>= function
        | None ->
          push (Some (encode ~event:"response.completed" completed));
          push (Some done_marker);
          push None;
          Lwt.return_unit
        | Some (Provider_client.Text_delta part) ->
          let event, json = response_delta_event part in
          push (Some (encode ?event json));
          loop ()
      in
      loop ())
;;
