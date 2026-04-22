open Lwt.Infix

let endpoint api_base =
  let base = Uri.of_string api_base in
  let base_path = Uri.path base in
  let normalized_base =
    if base_path = "" || base_path = "/"
    then ""
    else if String.ends_with ~suffix:"/" base_path
    then base_path
    else base_path ^ "/"
  in
  Uri.with_path base (normalized_base ^ "messages")
;;

let api_key_from_env backend =
  match Sys.getenv_opt backend.Config.api_key_env with
  | Some value when String.trim value <> "" -> Ok value
  | _ ->
    Error
      (Domain_error.upstream
         ~provider_id:backend.Config.provider_id
         ("Missing environment variable " ^ backend.Config.api_key_env))
;;

let post_json uri ~headers body =
  Cohttp_lwt_unix.Client.post
    ~headers
    ~body:(Cohttp_lwt.Body.of_string (Yojson.Safe.to_string body))
    uri
  >>= fun (response, body) ->
  Cohttp_lwt.Body.to_string body >|= fun body_string -> response, body_string
;;

let split_system_messages (messages : Openai_types.message list) =
  List.partition
    (fun (message : Openai_types.message) -> message.Openai_types.role = "system")
    messages
;;

let invoke_chat _upstream_context backend request =
  if request.Openai_types.stream
  then Lwt.return (Error (Domain_error.unsupported_feature "anthropic streaming"))
  else (
    match api_key_from_env backend with
    | Error err -> Lwt.return (Error err)
    | Ok api_key ->
      let api_base =
        match Config.backend_http_api_base backend with
        | Some api_base -> api_base
        | None ->
          invalid_arg
            ("anthropic provider requires an HTTP target for " ^ backend.Config.provider_id)
      in
      let uri = endpoint api_base in
      let system_messages, ordinary_messages = split_system_messages request.messages in
      let system =
        system_messages
        |> List.map (fun (message : Openai_types.message) -> message.Openai_types.content)
        |> String.concat "\n"
      in
      let body =
        `Assoc
          [ "model", `String backend.Config.upstream_model
          ; "max_tokens", `Int (Option.value request.max_tokens ~default:1024)
          ; ( "messages"
            , `List
                (List.map
                   (fun (message : Openai_types.message) ->
                     `Assoc
                       [ "role", `String message.role
                       ; "content", `String message.content
                       ])
                   ordinary_messages) )
          ]
        |> fun json ->
        if String.trim system = ""
        then json
        else (
          match json with
          | `Assoc fields -> `Assoc (fields @ [ "system", `String system ])
          | _ -> json)
      in
      let headers =
        Cohttp.Header.of_list
          [ "content-type", "application/json"
          ; "x-api-key", api_key
          ; "anthropic-version", "2023-06-01"
          ]
      in
      post_json uri ~headers body
      >>= fun (response, body_string) ->
      let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
      if status >= 200 && status < 300
      then (
        let json = Yojson.Safe.from_string body_string in
        let content =
          match json with
          | `Assoc fields ->
            (match List.assoc_opt "content" fields with
             | Some (`List parts) ->
               parts
               |> List.filter_map (function
                 | `Assoc part_fields ->
                   (match List.assoc_opt "text" part_fields with
                    | Some (`String text) -> Some text
                    | _ -> None)
                 | _ -> None)
               |> String.concat ""
             | _ -> "")
          | _ -> ""
        in
        let usage =
          match json with
          | `Assoc fields ->
            let usage_json =
              Option.value (List.assoc_opt "usage" fields) ~default:`Null
            in
            let prompt_tokens =
              match usage_json with
              | `Assoc usage_fields ->
                (match List.assoc_opt "input_tokens" usage_fields with
                 | Some (`Int value) -> value
                 | _ -> 0)
              | _ -> 0
            in
            let completion_tokens =
              match usage_json with
              | `Assoc usage_fields ->
                (match List.assoc_opt "output_tokens" usage_fields with
                 | Some (`Int value) -> value
                 | _ -> 0)
              | _ -> 0
            in
            { Openai_types.prompt_tokens
            ; completion_tokens
            ; total_tokens = prompt_tokens + completion_tokens
            }
          | _ -> { prompt_tokens = 0; completion_tokens = 0; total_tokens = 0 }
        in
        Lwt.return
          (Ok
             { Openai_types.id = "chatcmpl-anthropic"
             ; created = int_of_float (Unix.time ())
             ; model = request.model
             ; choices =
                 [ { index = 0
                   ; message = { role = "assistant"; content; extra = [] }
                   ; finish_reason = "stop"
                   }
                 ]
             ; usage
             }))
      else
        Lwt.return
          (Error
             (Domain_error.upstream_status
                ~provider_id:backend.Config.provider_id
                ~status
                (Fmt.str "Upstream status %d: %s" status body_string))))
;;

let invoke_embeddings _upstream_context backend _request =
  Lwt.return
    (Error
       (Domain_error.unsupported_feature
          ("embeddings not available for anthropic provider " ^ backend.Config.provider_id)))
;;

let invoke_chat_stream _upstream_context backend request =
  invoke_chat { Provider_client.peer_headers = []; peer_context = None } backend
    { request with Openai_types.stream = false }
  >|= Result.map Provider_stream.of_chat_response
;;

let make () = { Provider_client.invoke_chat; invoke_chat_stream; invoke_embeddings }
