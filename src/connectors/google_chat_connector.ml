open Lwt.Infix

type http_get = User_connector_common.http_get

type inbound_event =
  { event_type : string
  ; space_name : string
  ; thread_name : string option
  ; message_name : string option
  ; message_text : string option
  ; user_name : string option
  ; user_display_name : string option
  }

let connector =
  { User_connector_common.channel_name = "Google Chat"
  ; provider_id = "google-chat"
  ; event_type = "connector.google_chat"
  ; session_prefix = "google_chat"
  }

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this Google Chat conversation. Use it as context, but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through Google Chat. Keep answers concise, professional, and easy to scan in a chat thread. Avoid wide formatting."
;;

let help_message =
  String.concat
    "\n"
    [ "Send a message to talk with the assistant."
    ; "Commands:"
    ; "/reset - clear this Google Chat conversation memory"
    ; "/help - show this help"
    ]
;;

let onboarding_message =
  "I am connected to BulkheadLM. Mention me in a space or send a direct message, then use /help or ask a normal question."
;;

let text_only_message = "Send a text message for now. Cards, files, and dialogs are not handled by this connector yet."
let reset_message = "Conversation memory cleared for this Google Chat thread."

let find_webhook_config (config : Config.t) ~path =
  match config.user_connectors.google_chat with
  | Some connector when String.equal connector.webhook_path path -> Some connector
  | _ -> None
;;

let sanitize_message_text text =
  let rec drop_leading_mentions candidate =
    let trimmed = String.trim candidate in
    if String.starts_with ~prefix:"<users/" trimmed
    then (
      match String.index_opt trimmed '>' with
      | Some index ->
        let remaining =
          String.sub trimmed (index + 1) (String.length trimmed - index - 1)
        in
        drop_leading_mentions remaining
      | None -> trimmed)
    else trimmed
  in
  drop_leading_mentions text
;;

let parse_inbound_event json =
  let event_type =
    User_connector_common.string_opt (User_connector_common.member "type" json)
  in
  let space_json =
    Option.value (User_connector_common.member "space" json) ~default:`Null
  in
  let thread_json =
    match User_connector_common.member "thread" json with
    | Some value -> value
    | None ->
      (match User_connector_common.member "message" json with
       | Some (`Assoc _ as message_json) ->
         Option.value (User_connector_common.member "thread" message_json) ~default:`Null
       | _ -> `Null)
  in
  let message_json =
    Option.value (User_connector_common.member "message" json) ~default:`Null
  in
  let user_json =
    Option.value (User_connector_common.member "user" json) ~default:`Null
  in
  match
    event_type,
    User_connector_common.string_opt (User_connector_common.member "name" space_json)
  with
  | Some event_type, Some space_name ->
    Ok
      { event_type
      ; space_name
      ; thread_name =
          User_connector_common.string_opt (User_connector_common.member "name" thread_json)
      ; message_name =
          User_connector_common.string_opt (User_connector_common.member "name" message_json)
      ; message_text =
          (match User_connector_common.string_opt (User_connector_common.member "text" message_json) with
           | Some text -> Some (sanitize_message_text text)
           | None -> None)
      ; user_name =
          User_connector_common.string_opt (User_connector_common.member "name" user_json)
      ; user_display_name =
          User_connector_common.string_opt
            (User_connector_common.member "displayName" user_json)
      }
  | _ -> Error (Domain_error.invalid_request "Google Chat event is missing type or space.name.")
;;

let is_allowed_space (connector_config : Config.google_chat_connector) space_name =
  connector_config.Config.allowed_space_names = []
  || List.mem space_name connector_config.Config.allowed_space_names
;;

let is_allowed_user (connector_config : Config.google_chat_connector) = function
  | None -> connector_config.Config.allowed_user_names = []
  | Some user_name ->
    connector_config.Config.allowed_user_names = []
    || List.mem user_name connector_config.Config.allowed_user_names
;;

let verify_request
  ?(http_get = User_connector_common.default_http_get)
  req
  (connector_config : Config.google_chat_connector)
  =
  match connector_config.Config.id_token_auth with
  | None -> Lwt.return (Ok ())
  | Some auth_config ->
    let authorization =
      Cohttp.Header.get (Cohttp.Request.headers req) "authorization"
      |> Option.value ~default:""
    in
    Google_chat_id_token.verify ~http_get auth_config authorization >|= Result.map (fun _ -> ())
;;

let connector_system_messages (connector_config : Config.google_chat_connector) event =
  let metadata_lines =
    [ Some ("Space: " ^ event.space_name)
    ; Option.map (fun thread_name -> "Thread: " ^ thread_name) event.thread_name
    ; Option.map (fun user_name -> "User identity: " ^ user_name) event.user_name
    ; Option.map (fun display_name -> "User: " ^ display_name) event.user_display_name
    ]
    |> List.filter_map Fun.id
  in
  User_connector_common.connector_system_messages
    ~channel_name:connector.User_connector_common.channel_name
    ~default_system_prompt
    ?system_prompt:connector_config.Config.system_prompt
    metadata_lines
;;

let response_message ?thread_name text =
  let fields =
    [ "text", `String text ]
    @
    match thread_name with
    | Some name -> [ "thread", `Assoc [ "name", `String name ] ]
    | None -> []
  in
  Json_response.respond_json (`Assoc fields)
;;

let empty_response () = Json_response.respond_json (`Assoc [])

let session_subject event =
  match event.thread_name with
  | Some thread_name -> event.space_name ^ ":" ^ thread_name
  | None -> event.space_name
;;

let append_audit
  store
  ~authorization
  (connector_config : Config.google_chat_connector)
  ~status_code
  details
  =
  User_connector_common.append_audit
    store
    connector
    ~authorization
    ~route_model:(Some connector_config.Config.route_model)
    ~status_code
    details
;;

let user_text_from_event event =
  match event.message_text with
  | Some text ->
    let trimmed = String.trim text in
    if trimmed = "" then None else Some trimmed
  | None -> None
;;

let handle_command store event command =
  let session_key =
    User_connector_common.build_session_key connector (session_subject event)
  in
  let reply_text =
    match command with
    | "/reset" ->
      Runtime_state.clear_user_connector_session store ~session_key;
      reset_message
    | "/help" -> help_message
    | _ -> ""
  in
  if reply_text = "" then empty_response () else response_message ?thread_name:event.thread_name reply_text
;;

let handle_text_message
  store
  (connector_config : Config.google_chat_connector)
  ~authorization
  event
  text
  =
  let session_key =
    User_connector_common.build_session_key connector (session_subject event)
  in
  let conversation = Runtime_state.get_user_connector_session store ~session_key in
  let request : Openai_types.chat_request =
    { Openai_types.model = connector_config.Config.route_model
    ; messages =
        connector_system_messages connector_config event
        @ Session_memory.request_messages session_limits conversation ~pending_user:text
    ; stream = false
    ; max_tokens = None
    }
  in
  Router.dispatch_chat store ~authorization request
  >>= function
  | Ok response ->
    let assistant_text = User_connector_common.text_of_chat_response response in
    let assistant_text =
      if String.trim assistant_text = ""
      then "The assistant returned an empty reply."
      else assistant_text
    in
    let updated_conversation, _ =
      Session_memory.commit_exchange session_limits conversation ~user:text ~assistant:assistant_text
    in
    Runtime_state.set_user_connector_session store ~session_key updated_conversation;
    append_audit
      store
      ~authorization
      connector_config
      ~status_code:200
      (User_connector_common.audit_details
         [ "result", `String "ok"
         ; "space_name", `String event.space_name
         ; "response_model", `String response.model
         ]);
    response_message ?thread_name:event.thread_name assistant_text
  | Error err ->
    append_audit
      store
      ~authorization
      connector_config
      ~status_code:err.status
      (User_connector_common.audit_details
         [ "result", `String "router_error"
         ; "space_name", `String event.space_name
         ; "error", Domain_error.to_openai_json err
         ]);
    response_message
      ?thread_name:event.thread_name
      (User_connector_common.user_error_message err)
;;

let handle_webhook
  ?(http_get = User_connector_common.default_http_get)
  store
  req
  body
  (connector_config : Config.google_chat_connector)
  =
  match Cohttp.Request.meth req with
  | `POST ->
    verify_request ~http_get req connector_config
    >>= (function
     | Error err ->
       Cohttp_lwt_unix.Server.respond_string
         ~status:(Cohttp.Code.status_of_code err.status)
         ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
         ~body:err.message
         ()
     | Ok () ->
       Request_body.read_request_json store body
       >>= function
       | Error err -> Json_response.respond_error err
       | Ok json ->
         (match parse_inbound_event json with
          | Error err -> Json_response.respond_error err
          | Ok event when not (is_allowed_space connector_config event.space_name) ->
            empty_response ()
          | Ok event when not (is_allowed_user connector_config event.user_name) ->
            empty_response ()
          | Ok { event_type = "ADDED_TO_SPACE"; thread_name; _ } ->
            response_message ?thread_name onboarding_message
          | Ok { event_type = "MESSAGE"; _ } as parsed_event ->
            let event =
              match parsed_event with
              | Ok value -> value
              | Error _ -> assert false
            in
            (match
               User_connector_common.env_value
                 ~provider_id:connector.provider_id
                 connector_config.authorization_env
             with
             | Error err -> Json_response.respond_error err
             | Ok authorization_raw ->
               let authorization =
                 User_connector_common.normalized_authorization store authorization_raw
               in
               (match user_text_from_event event with
                | Some ("/reset" | "/help" as command) -> handle_command store event command
                | None -> response_message ?thread_name:event.thread_name text_only_message
                | Some text -> handle_text_message store connector_config ~authorization event text))
          | Ok _ -> empty_response ()))
  | _ ->
    Cohttp_lwt_unix.Server.respond_string
      ~status:`Method_not_allowed
      ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
      ~body:"Method not allowed."
      ()
;;
