type input_message =
  { role : string
  ; content : string
  }

type request =
  { model : string
  ; input : input_message list
  ; instructions : string option
  ; stream : bool
  }

type output_text =
  { text : string
  ; annotations : Yojson.Safe.t list
  }

type output_content =
  { content_type : string
  ; text : output_text
  }

type output_message =
  { output_type : string
  ; id : string
  ; status : string
  ; role : string
  ; content : output_content list
  }

type response =
  { id : string
  ; created_at : int
  ; model : string
  ; output : output_message list
  ; output_text : string
  ; prompt_tokens : int
  ; completion_tokens : int
  ; total_tokens : int
  }

let ( >>= ) = Result.bind

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None
;;

let string_field name json =
  match member name json with
  | Some (`String value) -> Ok value
  | _ -> Error name
;;

let bool_field_with_default name json ~default =
  match member name json with
  | Some (`Bool value) -> value
  | _ -> default
;;

let parse_input_message json =
  string_field "role" json
  >>= fun role ->
  string_field "content" json >>= fun content -> Ok ({ role; content } : input_message)
;;

let parse_input json =
  match member "input" json with
  | Some (`String text) -> Ok [ ({ role = "user"; content = text } : input_message) ]
  | Some (`List values) ->
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | item :: rest ->
        (match parse_input_message item with
         | Ok message -> loop (message :: acc) rest
         | Error err -> Error err)
    in
    loop [] values
  | _ -> Error "input"
;;

let request_of_yojson json =
  string_field "model" json
  >>= fun model ->
  parse_input json
  >>= fun input ->
  let instructions =
    match member "instructions" json with
    | Some (`String value) -> Some value
    | _ -> None
  in
  Ok
    { model
    ; input
    ; instructions
    ; stream = bool_field_with_default "stream" json ~default:false
    }
;;

let to_chat_request request =
  let messages =
    match request.instructions with
    | None -> request.input
    | Some instructions -> { role = "system"; content = instructions } :: request.input
  in
  let messages =
    List.map
      (fun (message : input_message) : Openai_types.message ->
        { Openai_types.role = message.role; content = message.content })
      messages
  in
  { Openai_types.model = request.model
  ; messages
  ; stream = request.stream
  ; max_tokens = None
  }
;;

let of_chat_response (chat_response : Openai_types.chat_response) =
  let output_text =
    chat_response.choices
    |> List.filter_map (fun (choice : Openai_types.chat_choice) ->
      let text = String.trim choice.message.content in
      if text = "" then None else Some text)
    |> String.concat "\n"
  in
  { id = "resp_" ^ chat_response.id
  ; created_at = chat_response.created
  ; model = chat_response.model
  ; output =
      [ { output_type = "message"
        ; id = "msg_" ^ chat_response.id
        ; status = "completed"
        ; role = "assistant"
        ; content =
            [ { content_type = "output_text"
              ; text = { text = output_text; annotations = [] }
              }
            ]
        }
      ]
  ; output_text
  ; prompt_tokens = chat_response.usage.prompt_tokens
  ; completion_tokens = chat_response.usage.completion_tokens
  ; total_tokens = chat_response.usage.total_tokens
  }
;;

let response_to_yojson response =
  `Assoc
    [ "id", `String response.id
    ; "object", `String "response"
    ; "created_at", `Int response.created_at
    ; "status", `String "completed"
    ; "model", `String response.model
    ; ( "output"
      , `List
          (List.map
             (fun (message : output_message) ->
               `Assoc
                 [ "type", `String message.output_type
                 ; "id", `String message.id
                 ; "status", `String message.status
                 ; "role", `String message.role
                 ; ( "content"
                   , `List
                       (List.map
                          (fun (content : output_content) ->
                            `Assoc
                              [ "type", `String content.content_type
                              ; ( "text"
                                , `Assoc
                                    [ "value", `String content.text.text
                                    ; "annotations", `List content.text.annotations
                                    ] )
                              ])
                          message.content) )
                 ])
             response.output) )
    ; "output_text", `String response.output_text
    ; ( "usage"
      , `Assoc
          [ "input_tokens", `Int response.prompt_tokens
          ; "output_tokens", `Int response.completion_tokens
          ; "total_tokens", `Int response.total_tokens
          ] )
    ]
;;
