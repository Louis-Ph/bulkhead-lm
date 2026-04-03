open Lwt.Infix

let endpoint api_base suffix =
  let base = Uri.of_string api_base in
  let base_path = Uri.path base in
  let normalized_base =
    if base_path = "" || base_path = "/"
    then ""
    else if String.ends_with ~suffix:"/" base_path
    then base_path
    else base_path ^ "/"
  in
  let suffix =
    if String.starts_with ~prefix:"/" suffix
    then String.sub suffix 1 (String.length suffix - 1)
    else suffix
  in
  Uri.with_path base (normalized_base ^ suffix)
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

let merge_headers base_headers extra_headers =
  List.fold_left
    (fun acc (name, value) -> Cohttp.Header.add acc name value)
    base_headers
    extra_headers
;;

let post_json uri ~headers body =
  Cohttp_lwt_unix.Client.post
    ~headers
    ~body:(Cohttp_lwt.Body.of_string (Yojson.Safe.to_string body))
    uri
  >>= fun (response, body) ->
  Cohttp_lwt.Body.to_string body >|= fun body_string -> response, body_string
;;

let invoke_chat peer_headers backend request =
  match api_key_from_env backend with
  | Error err -> Lwt.return (Error err)
  | Ok api_key ->
    let uri = endpoint backend.Config.api_base "chat/completions" in
    let headers =
      merge_headers
        (Cohttp.Header.of_list
           [ "content-type", "application/json"; "authorization", "Bearer " ^ api_key ])
        peer_headers
    in
    let body =
      Openai_types.chat_request_to_yojson
        { request with model = backend.Config.upstream_model }
    in
    post_json uri ~headers body
    >>= fun (response, body_string) ->
    let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
    if status >= 200 && status < 300
    then (
      match
        Openai_types.chat_response_of_yojson (Yojson.Safe.from_string body_string)
      with
      | Ok value -> Lwt.return (Ok value)
      | Error err ->
        Lwt.return
          (Error
             (Domain_error.upstream
                ~provider_id:backend.provider_id
                ("Unable to parse upstream response: " ^ err))))
    else
      Lwt.return
        (Error
           (Domain_error.upstream_status
              ~provider_id:backend.Config.provider_id
              ~status
              (Fmt.str "Upstream status %d: %s" status body_string)))
;;

let invoke_embeddings peer_headers backend request =
  match api_key_from_env backend with
  | Error err -> Lwt.return (Error err)
  | Ok api_key ->
    let uri = endpoint backend.Config.api_base "embeddings" in
    let headers =
      merge_headers
        (Cohttp.Header.of_list
           [ "content-type", "application/json"; "authorization", "Bearer " ^ api_key ])
        peer_headers
    in
    let body =
      `Assoc
        [ "model", `String backend.Config.upstream_model
        ; "input", `List (List.map (fun item -> `String item) request.Openai_types.input)
        ]
    in
    post_json uri ~headers body
    >>= fun (response, body_string) ->
    let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
    if status >= 200 && status < 300
    then (
      let json = Yojson.Safe.from_string body_string in
      let data =
        match json with
        | `Assoc fields ->
          (match List.assoc_opt "data" fields with
           | Some (`List values) ->
             values
             |> List.mapi (fun index item ->
               let embedding =
                 match item with
                 | `Assoc item_fields ->
                   (match List.assoc_opt "embedding" item_fields with
                    | Some (`List numbers) ->
                      numbers
                      |> List.filter_map (function
                        | `Float value -> Some value
                        | `Int value -> Some (float_of_int value)
                        | _ -> None)
                    | _ -> [])
                 | _ -> []
               in
               { Openai_types.index; embedding })
           | _ -> [])
        | _ -> []
      in
      let usage =
        match json with
        | `Assoc fields ->
          (match List.assoc_opt "usage" fields with
           | Some usage_json ->
             (match Openai_types.usage_of_yojson usage_json with
              | Ok usage -> usage
              | Error _ -> { prompt_tokens = 0; completion_tokens = 0; total_tokens = 0 })
           | None -> { prompt_tokens = 0; completion_tokens = 0; total_tokens = 0 })
        | _ -> { prompt_tokens = 0; completion_tokens = 0; total_tokens = 0 }
      in
      Lwt.return (Ok { Openai_types.model = request.model; data; usage }))
    else
      Lwt.return
        (Error
           (Domain_error.upstream_status
              ~provider_id:backend.Config.provider_id
              ~status
              (Fmt.str "Upstream status %d: %s" status body_string)))
;;

let invoke_chat_stream peer_headers backend request =
  invoke_chat peer_headers backend { request with Openai_types.stream = false }
  >|= Result.map Provider_stream.of_chat_response
;;

let make () = { Provider_client.invoke_chat; invoke_chat_stream; invoke_embeddings }
