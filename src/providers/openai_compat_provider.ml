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

let ollama_reasoning_effort_disabled = "none"

let chat_request_body backend request =
  let request_json =
    Openai_types.chat_request_to_yojson
      { request with model = backend.Config.upstream_model }
  in
  match backend.Config.provider_kind, request_json with
  | Config.Ollama_openai, `Assoc fields ->
    `Assoc (fields @ [ "reasoning_effort", `String ollama_reasoning_effort_disabled ])
  | _, _ -> request_json
;;

let resolve_api_base backend =
  match Config.backend_http_api_base backend with
  | Some api_base -> api_base
  | None ->
    invalid_arg
      ("openai_compat provider requires an HTTP target for " ^ backend.Config.provider_id)
;;

let build_auth_headers ~upstream_context ~api_key =
  merge_headers
    (Cohttp.Header.of_list
       [ "content-type", "application/json"; "authorization", "Bearer " ^ api_key ])
    upstream_context.Provider_client.peer_headers
;;

let invoke_chat upstream_context backend request =
  match api_key_from_env backend with
  | Error err -> Lwt.return (Error err)
  | Ok api_key ->
    let uri = endpoint (resolve_api_base backend) "chat/completions" in
    let headers = build_auth_headers ~upstream_context ~api_key in
    let body = chat_request_body backend request in
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

let invoke_embeddings upstream_context backend request =
  match api_key_from_env backend with
  | Error err -> Lwt.return (Error err)
  | Ok api_key ->
    let uri = endpoint (resolve_api_base backend) "embeddings" in
    let headers = build_auth_headers ~upstream_context ~api_key in
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

let strip_data_prefix line =
  if String.starts_with ~prefix:"data: " line
  then Some (String.sub line 6 (String.length line - 6))
  else if String.starts_with ~prefix:"data:" line
  then Some (String.sub line 5 (String.length line - 5))
  else None
;;

let trim_cr line =
  let len = String.length line in
  if len > 0 && line.[len - 1] = '\r' then String.sub line 0 (len - 1) else line
;;

let events_of_chunk_json json =
  match Openai_types.member "choices" json with
  | Some (`List (choice :: _)) ->
    let delta = Option.value (Openai_types.member "delta" choice) ~default:`Null in
    let reasoning =
      match Openai_types.member "reasoning_content" delta with
      | Some (`String value) when value <> "" ->
        [ Provider_client.Reasoning_delta value ]
      | _ -> []
    in
    let content =
      match Openai_types.member "content" delta with
      | Some (`String value) when value <> "" -> [ Provider_client.Text_delta value ]
      | _ -> []
    in
    reasoning @ content
  | _ -> []
;;

let response_stub_of_chunk backend (first_json : Yojson.Safe.t) : Openai_types.chat_response =
  let id =
    match Openai_types.member "id" first_json with
    | Some (`String value) -> value
    | _ -> "chatcmpl-stream"
  in
  let created =
    match Openai_types.member "created" first_json with
    | Some (`Int value) -> value
    | Some (`Intlit value) -> int_of_string value
    | _ -> int_of_float (Unix.time ())
  in
  let model =
    match Openai_types.member "model" first_json with
    | Some (`String value) -> value
    | _ -> backend.Config.upstream_model
  in
  { id
  ; created
  ; model
  ; choices =
      [ { index = 0
        ; message = { role = "assistant"; content = ""; extra = [] }
        ; finish_reason = "stop"
        }
      ]
  ; usage = { prompt_tokens = 0; completion_tokens = 0; total_tokens = 0 }
  }
;;

let invoke_chat_stream upstream_context backend request =
  match api_key_from_env backend with
  | Error err -> Lwt.return (Error err)
  | Ok api_key ->
    let uri = endpoint (resolve_api_base backend) "chat/completions" in
    let headers = build_auth_headers ~upstream_context ~api_key in
    let body = chat_request_body backend { request with Openai_types.stream = true } in
    Cohttp_lwt_unix.Client.post
      ~headers
      ~body:(Cohttp_lwt.Body.of_string (Yojson.Safe.to_string body))
      uri
    >>= fun (http_response, http_body) ->
    let status =
      Cohttp.Response.status http_response |> Cohttp.Code.code_of_status
    in
    if status < 200 || status >= 300
    then
      Cohttp_lwt.Body.to_string http_body
      >|= fun body_string ->
      Error
        (Domain_error.upstream_status
           ~provider_id:backend.Config.provider_id
           ~status
           (Fmt.str "Upstream status %d: %s" status body_string))
    else (
      let source = Cohttp_lwt.Body.to_stream http_body in
      let json_stream, push = Lwt_stream.create () in
      let buffer = Buffer.create 1024 in
      let closed = ref false in
      let close_once () =
        if not !closed
        then (
          closed := true;
          push None)
      in
      let process_line raw =
        if !closed
        then ()
        else (
          let line = trim_cr raw in
          match strip_data_prefix line with
          | None -> ()
          | Some payload ->
            let trimmed = String.trim payload in
            if trimmed = "[DONE]"
            then close_once ()
            else if trimmed = ""
            then ()
            else (
              match Yojson.Safe.from_string trimmed with
              | json -> push (Some json)
              | exception _ -> ()))
      in
      let flush () =
        let contents = Buffer.contents buffer in
        let rec loop s =
          match String.index_opt s '\n' with
          | None -> s
          | Some idx ->
            let line = String.sub s 0 idx in
            let rest = String.sub s (idx + 1) (String.length s - idx - 1) in
            process_line line;
            loop rest
        in
        let remainder = loop contents in
        Buffer.clear buffer;
        Buffer.add_string buffer remainder
      in
      let rec consume () =
        Lwt_stream.get source
        >>= function
        | None ->
          if Buffer.length buffer > 0 then process_line (Buffer.contents buffer);
          close_once ();
          Lwt.return_unit
        | Some chunk ->
          Buffer.add_string buffer chunk;
          flush ();
          consume ()
      in
      Lwt.async (fun () ->
        Lwt.catch consume (fun _ ->
          close_once ();
          Lwt.return_unit));
      Lwt_stream.get json_stream
      >>= function
      | None ->
        Lwt.return
          (Error
             (Domain_error.upstream
                ~provider_id:backend.Config.provider_id
                "Empty SSE stream from upstream"))
      | Some first_json ->
        let response = response_stub_of_chunk backend first_json in
        let first_events = events_of_chunk_json first_json in
        let rest_events =
          Lwt_stream.map_list events_of_chunk_json json_stream
        in
        let events =
          Lwt_stream.append (Lwt_stream.of_list first_events) rest_events
        in
        let close () =
          close_once ();
          Lwt.return_unit
        in
        Lwt.return (Ok { Provider_client.response; events; close }))
;;

let make () = { Provider_client.invoke_chat; invoke_chat_stream; invoke_embeddings }
