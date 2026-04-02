open Lwt.Infix

let read_json_body body =
  Cohttp_lwt.Body.to_string body
  >|= fun content ->
  if String.trim content = "" then `Assoc [] else Yojson.Safe.from_string content
;;

let authorization_header store req =
  let headers = Cohttp.Request.headers req in
  Cohttp.Header.get
    headers
    (String.lowercase_ascii store.Runtime_state.config.security_policy.auth.header)
  |> Option.value ~default:""
;;

let models_json config =
  `Assoc
    [ ( "data"
      , `List
          (List.map
             (fun route ->
               `Assoc
                 [ "id", `String route.Config.public_model; "object", `String "model" ])
             config.Config.routes) )
    ; "object", `String "list"
    ]
;;

let callback store _connection req body =
  match Cohttp.Request.meth req, Uri.path (Cohttp.Request.uri req) with
  | `GET, "/health" -> Json_response.respond_json (`Assoc [ "status", `String "ok" ])
  | `GET, "/v1/models" ->
    Json_response.respond_json (models_json store.Runtime_state.config)
  | `POST, "/v1/chat/completions" ->
    read_json_body body
    >>= fun json ->
    let json =
      Secret_redaction.redact_json
        ~sensitive_keys:store.Runtime_state.config.security_policy.redaction.json_keys
        ~replacement:store.Runtime_state.config.security_policy.redaction.replacement
        json
    in
    (* parsing uses the original request shape; redaction only protects later logging hooks *)
    let request_json = json in
    (match Openai_types.chat_request_of_yojson request_json with
     | Error field ->
       Json_response.respond_error
         (Domain_error.upstream ("Invalid chat request field: " ^ field))
     | Ok request ->
       Router.dispatch_chat store ~authorization:(authorization_header store req) request
       >>= (function
        | Ok response ->
          Json_response.respond_json (Openai_types.chat_response_to_yojson response)
        | Error error -> Json_response.respond_error error))
  | `POST, "/v1/embeddings" ->
    read_json_body body
    >>= fun json ->
    (match Openai_types.embeddings_request_of_yojson json with
     | Error field ->
       Json_response.respond_error
         (Domain_error.upstream ("Invalid embeddings request field: " ^ field))
     | Ok request ->
       Router.dispatch_embeddings
         store
         ~authorization:(authorization_header store req)
         request
       >>= (function
        | Ok response ->
          Json_response.respond_json (Openai_types.embeddings_response_to_yojson response)
        | Error error -> Json_response.respond_error error))
  | `POST, "/v1/responses" ->
    Json_response.respond_error (Domain_error.unsupported_feature "responses API")
  | _ ->
    Json_response.respond_error
      (Domain_error.route_not_found (Uri.path (Cohttp.Request.uri req)))
;;

let start store =
  let port = store.Runtime_state.config.security_policy.server.listen_port in
  let mode = `TCP (`Port port) in
  let server = Cohttp_lwt_unix.Server.make ~callback:(callback store) () in
  Logs.app (fun m ->
    m
      "AegisLM listening on http://%s:%d"
      store.Runtime_state.config.security_policy.server.listen_host
      port);
  Cohttp_lwt_unix.Server.create ~mode server
;;
