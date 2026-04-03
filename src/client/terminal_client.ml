open Lwt.Infix

type call_kind =
  | Chat
  | Responses
  | Embeddings

type call_response =
  | Chat_response of Openai_types.chat_response
  | Responses_response of Responses_api.response
  | Embeddings_response of Openai_types.embeddings_response

let call_kind_to_string = function
  | Chat -> "chat"
  | Responses -> "responses"
  | Embeddings -> "embeddings"
;;

let call_kind_of_string = function
  | "chat" -> Ok Chat
  | "responses" -> Ok Responses
  | "embeddings" -> Ok Embeddings
  | value ->
    Error
      (Domain_error.invalid_request
         (Fmt.str
            "Unsupported client request kind: %s. Expected one of chat, responses, embeddings."
            value))
;;

let response_to_yojson = function
  | Chat_response response -> Openai_types.chat_response_to_yojson response
  | Responses_response response -> Responses_api.response_to_yojson response
  | Embeddings_response response -> Openai_types.embeddings_response_to_yojson response
;;

let text_of_chat_response (response : Openai_types.chat_response) =
  response.choices
  |> List.filter_map (fun (choice : Openai_types.chat_choice) ->
    let content = String.trim choice.message.content in
    if content = "" then None else Some content)
  |> String.concat "\n"
;;

let text_of_response = function
  | Chat_response response -> text_of_chat_response response
  | Responses_response response -> response.Responses_api.output_text
  | Embeddings_response _ -> ""
;;

let first_configured_model store =
  match store.Runtime_state.config.Config.routes with
  | route :: _ -> Some route.Config.public_model
  | [] -> None
;;

let sole_plaintext_virtual_key store =
  store.Runtime_state.config.Config.virtual_keys
  |> List.filter_map (fun (virtual_key : Config.virtual_key) -> virtual_key.token_plaintext)
  |> List.sort_uniq String.compare
  |> function
  | [ token ] -> Some token
  | _ -> None
;;

let normalize_authorization store value =
  let prefix =
    store.Runtime_state.config.Config.security_policy.Security_policy.auth.bearer_prefix
  in
  let trimmed = String.trim value in
  if trimmed = ""
  then None
  else if String.starts_with ~prefix trimmed
  then Some trimmed
  else Some (prefix ^ trimmed)
;;

let non_empty_env name =
  match Sys.getenv_opt name with
  | Some value when String.trim value <> "" -> Some value
  | _ -> None
;;

let resolve_authorization store ?authorization ?api_key () =
  let resolved =
    match authorization with
    | Some value -> normalize_authorization store value
    | None ->
      (match api_key with
       | Some value -> normalize_authorization store value
       | None ->
         (match non_empty_env "AEGISLM_AUTHORIZATION" with
          | Some value -> normalize_authorization store value
          | None ->
            (match non_empty_env "AEGISLM_API_KEY" with
             | Some value -> normalize_authorization store value
             | None ->
               (match sole_plaintext_virtual_key store with
                | Some value -> normalize_authorization store value
                | None -> None))))
  in
  match resolved with
  | Some value -> Ok value
  | None ->
    Error
      (Domain_error.invalid_request
         "No client authorization available. Provide --api-key, --authorization, AEGISLM_API_KEY, AEGISLM_AUTHORIZATION, or configure exactly one plaintext virtual key.")
;;

let resolve_model store ?model () =
  match model with
  | Some value when String.trim value <> "" -> Ok (String.trim value)
  | _ ->
    (match first_configured_model store with
     | Some value -> Ok value
     | None ->
       Error
         (Domain_error.invalid_request
            "No public model route is configured. Provide --model or add at least one route."))
;;

let non_streaming_only kind is_streaming =
  if is_streaming
  then
    Error
      (Domain_error.invalid_request
         (Fmt.str
            "Streaming is not supported in %s one-shot or worker mode. Use the ask command for terminal streaming."
            (call_kind_to_string kind)))
  else Ok ()
;;

let invoke_json store ~authorization ~kind json =
  match kind with
  | Chat ->
    (match Openai_types.chat_request_of_yojson json with
     | Error field ->
       Lwt.return
         (Error (Domain_error.invalid_request ("Invalid chat request field: " ^ field)))
     | Ok request ->
       (match non_streaming_only kind request.Openai_types.stream with
        | Error err -> Lwt.return (Error err)
        | Ok () ->
          Router.dispatch_chat store ~authorization request
          >|= Result.map (fun response -> Chat_response response)))
  | Responses ->
    (match Responses_api.request_of_yojson json with
     | Error field ->
       Lwt.return
         (Error (Domain_error.invalid_request ("Invalid responses request field: " ^ field)))
     | Ok request ->
       (match non_streaming_only kind request.Responses_api.stream with
        | Error err -> Lwt.return (Error err)
        | Ok () ->
          Router.dispatch_chat
            store
            ~authorization
            { (Responses_api.to_chat_request request) with stream = false }
          >|= Result.map (fun response -> Responses_response (Responses_api.of_chat_response response))))
  | Embeddings ->
    (match Openai_types.embeddings_request_of_yojson json with
     | Error field ->
       Lwt.return
         (Error (Domain_error.invalid_request ("Invalid embeddings request field: " ^ field)))
     | Ok request ->
       Router.dispatch_embeddings store ~authorization request
       >|= Result.map (fun response -> Embeddings_response response))
;;

let build_ask_request store ?model ?system ?max_tokens ?(stream = false) prompt =
  resolve_model store ?model ()
  |> Result.map (fun resolved_model ->
    let base_messages : Openai_types.message list =
      [ { Openai_types.role = "user"; content = prompt } ]
    in
    let messages =
      match system with
      | Some content when String.trim content <> "" ->
        ({ Openai_types.role = "system"; content } : Openai_types.message) :: base_messages
      | _ -> base_messages
    in
    { Openai_types.model = resolved_model
    ; messages
    ; stream
    ; max_tokens
    })
;;

let run_ask store ~authorization request =
  Router.dispatch_chat store ~authorization { request with Openai_types.stream = false }
  >|= Result.map (fun response -> Chat_response response)
;;

let run_ask_stream store ~authorization request ~on_delta =
  Router.dispatch_chat_stream store ~authorization { request with Openai_types.stream = true }
  >>= function
  | Error err -> Lwt.return (Error err)
  | Ok stream ->
    Lwt.finalize
      (fun () ->
        let rec drain () =
          Lwt_stream.get stream.Provider_client.events
          >>= function
          | None -> Lwt.return (Ok (Chat_response stream.response))
          | Some (Provider_client.Text_delta text) -> on_delta text >>= drain
        in
        drain ())
      stream.close
;;
