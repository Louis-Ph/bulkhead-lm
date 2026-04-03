let ( >>= ) = Result.bind

type message =
  { role : string
  ; content : string
  }

type chat_request =
  { model : string
  ; messages : message list
  ; stream : bool
  ; max_tokens : int option
  }

type chat_message =
  { role : string
  ; content : string
  }

type chat_choice =
  { index : int
  ; message : chat_message
  ; finish_reason : string
  }

type usage =
  { prompt_tokens : int
  ; completion_tokens : int
  ; total_tokens : int
  }

type chat_response =
  { id : string
  ; created : int
  ; model : string
  ; choices : chat_choice list
  ; usage : usage
  }

type embeddings_request =
  { model : string
  ; input : string list
  }

type embedding =
  { index : int
  ; embedding : float list
  }

type embeddings_response =
  { model : string
  ; data : embedding list
  ; usage : usage
  }

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None
;;

let string_field name json =
  match member name json with
  | Some (`String value) -> Ok value
  | _ -> Error name
;;

let int_field name json =
  match member name json with
  | Some (`Int value) -> Ok value
  | Some (`Intlit value) -> Ok (int_of_string value)
  | _ -> Error name
;;

let bool_field_with_default name json ~default =
  match member name json with
  | Some (`Bool value) -> value
  | _ -> default
;;

let int_field_opt name json =
  match member name json with
  | Some (`Int value) -> Some value
  | Some (`Intlit value) -> Some (int_of_string value)
  | _ -> None
;;

let parse_message json =
  string_field "role" json
  >>= fun role ->
  string_field "content" json >>= fun content -> Ok ({ role; content } : message)
;;

let chat_request_of_yojson json =
  string_field "model" json
  >>= fun model ->
  let messages =
    match member "messages" json with
    | Some (`List values) ->
      let rec loop acc = function
        | [] -> Ok (List.rev acc)
        | item :: rest ->
          (match parse_message item with
           | Ok message -> loop (message :: acc) rest
           | Error err -> Error err)
      in
      loop [] values
    | _ -> Error "messages"
  in
  messages
  >>= fun messages ->
  Ok
    { model
    ; messages
    ; stream = bool_field_with_default "stream" json ~default:false
    ; max_tokens = int_field_opt "max_tokens" json
    }
;;

let usage_of_yojson json =
  int_field "prompt_tokens" json
  >>= fun prompt_tokens ->
  int_field "completion_tokens" json
  >>= fun completion_tokens ->
  int_field "total_tokens" json
  >>= fun total_tokens -> Ok { prompt_tokens; completion_tokens; total_tokens }
;;

let parse_chat_choice json =
  let message_json = Option.value (member "message" json) ~default:`Null in
  let finish_reason =
    match member "finish_reason" json with
    | Some (`String value) -> value
    | _ -> "stop"
  in
  int_field "index" json
  >>= fun index ->
  string_field "role" message_json
  >>= fun role ->
  string_field "content" message_json
  >>= fun content ->
  Ok { index; message = ({ role; content } : chat_message); finish_reason }
;;

let chat_response_of_yojson json =
  string_field "id" json
  >>= fun id ->
  int_field "created" json
  >>= fun created ->
  string_field "model" json
  >>= fun model ->
  let usage_json = Option.value (member "usage" json) ~default:`Null in
  usage_of_yojson usage_json
  >>= fun usage ->
  let choices_values =
    match member "choices" json with
    | Some (`List values) -> values
    | _ -> []
  in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
      (match parse_chat_choice item with
       | Ok choice -> loop (choice :: acc) rest
       | Error err -> Error err)
  in
  loop [] choices_values >>= fun choices -> Ok { id; created; model; choices; usage }
;;

let chat_request_to_yojson (request : chat_request) =
  `Assoc
    [ "model", `String request.model
    ; ( "messages"
      , `List
          (List.map
             (fun (message : message) ->
               `Assoc [ "role", `String message.role; "content", `String message.content ])
             request.messages) )
    ; "stream", `Bool request.stream
    ]
  |> fun json ->
  match request.max_tokens with
  | None -> json
  | Some max_tokens ->
    (match json with
     | `Assoc fields -> `Assoc (fields @ [ "max_tokens", `Int max_tokens ])
     | _ -> json)
;;

let chat_response_to_yojson (response : chat_response) =
  `Assoc
    [ "id", `String response.id
    ; "created", `Int response.created
    ; "model", `String response.model
    ; "object", `String "chat.completion"
    ; ( "choices"
      , `List
          (List.map
             (fun (choice : chat_choice) ->
               `Assoc
                 [ "index", `Int choice.index
                 ; "finish_reason", `String choice.finish_reason
                 ; ( "message"
                   , `Assoc
                       [ "role", `String choice.message.role
                       ; "content", `String choice.message.content
                       ] )
                 ])
             response.choices) )
    ; ( "usage"
      , `Assoc
          [ "prompt_tokens", `Int response.usage.prompt_tokens
          ; "completion_tokens", `Int response.usage.completion_tokens
          ; "total_tokens", `Int response.usage.total_tokens
          ] )
    ]
;;

let embeddings_request_of_yojson json =
  string_field "model" json
  >>= fun model ->
  let input =
    match member "input" json with
    | Some (`String value) -> Ok [ value ]
    | Some (`List values) ->
      Ok
        (List.filter_map
           (function
             | `String value -> Some value
             | _ -> None)
           values)
    | _ -> Error "input"
  in
  input >>= fun input -> Ok { model; input }
;;

let embeddings_response_to_yojson (response : embeddings_response) =
  `Assoc
    [ "object", `String "list"
    ; "model", `String response.model
    ; ( "data"
      , `List
          (List.map
             (fun (item : embedding) ->
               `Assoc
                 [ "object", `String "embedding"
                 ; "index", `Int item.index
                 ; ( "embedding"
                   , `List (List.map (fun value -> `Float value) item.embedding) )
                 ])
             response.data) )
    ; ( "usage"
      , `Assoc
          [ "prompt_tokens", `Int response.usage.prompt_tokens
          ; "completion_tokens", `Int response.usage.completion_tokens
          ; "total_tokens", `Int response.usage.total_tokens
          ] )
    ]
;;

let parse_embedding json =
  int_field "index" json
  >>= fun index ->
  let embedding =
    match member "embedding" json with
    | Some (`List values) ->
      Ok
        (List.filter_map (function
           | `Float value -> Some value
           | `Int value -> Some (float_of_int value)
           | _ -> None) values)
    | _ -> Error "embedding"
  in
  embedding >>= fun embedding -> Ok { index; embedding }
;;

let embeddings_response_of_yojson json =
  string_field "model" json
  >>= fun model ->
  let usage_json = Option.value (member "usage" json) ~default:`Null in
  usage_of_yojson usage_json
  >>= fun usage ->
  let data_values =
    match member "data" json with
    | Some (`List values) -> values
    | _ -> []
  in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
      (match parse_embedding item with
       | Ok embedding -> loop (embedding :: acc) rest
       | Error err -> Error err)
  in
  loop [] data_values >>= fun data -> Ok { model; data; usage }
;;
