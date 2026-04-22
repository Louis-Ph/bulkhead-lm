open Lwt.Infix

type http_post = User_connector_common.http_post

type inbound_event =
  { event_type : string
  ; sender_id : string
  ; sender_name : string option
  ; sender_avatar : string option
  ; message_token : string option
  ; subscribed : bool option
  ; message_text : string option
  }

let connector =
  { User_connector_common.channel_name = "Viber"
  ; provider_id = "viber-bot-api"
  ; event_type = "connector.viber"
  ; session_prefix = "viber"
  }

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this Viber conversation. Use it as context, but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through Viber. Keep answers concise, clear, and easy to read on mobile."
;;

let help_message =
  String.concat
    "\n"
    [ "Send a text message to talk with the assistant."
    ; "Commands:"
    ; "/reset - clear this Viber conversation memory"
    ; "/help - show this help"
    ]
;;

let onboarding_message =
  "I am connected to BulkheadLM on Viber. Send a text message or use /help."
;;

let reset_message = "Conversation memory cleared for this Viber conversation."
let text_only_message = "Send a text message for now. Media, stickers, and files are not handled by this connector yet."
let send_message_path = "/send_message"

let find_webhook_config (config : Config.t) ~path =
  match config.user_connectors.viber with
  | Some connector when String.equal connector.webhook_path path -> Some connector
  | _ -> None
;;

let parse_party json ~field_name =
  let party_json = Option.value (User_connector_common.member field_name json) ~default:`Null in
  match User_connector_common.string_opt (User_connector_common.member "id" party_json) with
  | None ->
    Error
      (Domain_error.invalid_request
         (Fmt.str "Viber callback is missing %s.id." field_name))
  | Some sender_id ->
    Ok
      ( sender_id
      , User_connector_common.string_opt (User_connector_common.member "name" party_json)
      , User_connector_common.string_opt (User_connector_common.member "avatar" party_json)
      )
;;

let parse_message_text json =
  match User_connector_common.member "message" json with
  | Some (`Assoc _ as message_json) ->
    (match User_connector_common.string_opt (User_connector_common.member "type" message_json) with
     | Some "text" ->
       User_connector_common.string_opt (User_connector_common.member "text" message_json)
     | _ -> None)
  | _ -> None
;;

let parse_inbound_event json =
  let message_token =
    User_connector_common.string_of_scalar_opt (User_connector_common.member "message_token" json)
  in
  let subscribed =
    match User_connector_common.member "subscribed" json with
    | Some (`Bool value) -> Some value
    | _ -> None
  in
  match User_connector_common.string_opt (User_connector_common.member "event" json) with
  | None -> Error (Domain_error.invalid_request "Viber callback is missing event.")
  | Some "message" ->
    (match parse_party json ~field_name:"sender" with
     | Error _ as error -> error
     | Ok (sender_id, sender_name, sender_avatar) ->
       Ok
         { event_type = "message"
         ; sender_id
         ; sender_name
         ; sender_avatar
         ; message_token
         ; subscribed = None
         ; message_text = parse_message_text json
         })
  | Some "conversation_started" ->
    (match parse_party json ~field_name:"user" with
     | Error _ as error -> error
     | Ok (sender_id, sender_name, sender_avatar) ->
       Ok
         { event_type = "conversation_started"
         ; sender_id
         ; sender_name
         ; sender_avatar
         ; message_token
         ; subscribed
         ; message_text = None
         })
  | Some "subscribed" ->
    (match parse_party json ~field_name:"user" with
     | Error _ as error -> error
     | Ok (sender_id, sender_name, sender_avatar) ->
       Ok
         { event_type = "subscribed"
         ; sender_id
         ; sender_name
         ; sender_avatar
         ; message_token
         ; subscribed = Some true
         ; message_text = None
         })
  | Some ("unsubscribed" | "delivered" | "seen" | "failed" | "webhook" as event_type) ->
    Ok
      { event_type
      ; sender_id =
          Option.value
            (User_connector_common.string_opt (User_connector_common.member "user_id" json))
            ~default:""
      ; sender_name = None
      ; sender_avatar = None
      ; message_token
      ; subscribed = None
      ; message_text = None
      }
  | Some event_type ->
    Ok
      { event_type
      ; sender_id = ""
      ; sender_name = None
      ; sender_avatar = None
      ; message_token
      ; subscribed = None
      ; message_text = None
      }
;;

let verify_signature (connector_config : Config.viber_connector) raw_body req =
  match
    User_connector_common.env_value
      ~provider_id:connector.provider_id
      connector_config.auth_token_env
  with
  | Error _ as error -> error
  | Ok auth_token ->
    let presented =
      Cohttp.Header.get (Cohttp.Request.headers req) "x-viber-content-signature"
      |> Option.value ~default:""
    in
    let expected =
      Digestif.SHA256.(to_hex (hmac_string ~key:auth_token raw_body))
    in
    if User_connector_common.constant_time_equal presented expected
    then Ok ()
    else Error (Domain_error.operation_denied "Viber webhook signature mismatch.")
;;

let effective_sender_name (connector_config : Config.viber_connector) =
  Option.value connector_config.Config.sender_name ~default:"BulkheadLM"
;;

let send_viber_message
  ?(http_post = User_connector_common.default_http_post)
  (connector_config : Config.viber_connector)
  ~auth_token
  ~recipient
  ~text
  =
  let uri =
    Uri.of_string (connector_config.Config.api_base ^ send_message_path)
  in
  let headers =
    Cohttp.Header.of_list
      [ "content-type", "application/json"
      ; "x-viber-auth-token", auth_token
      ]
  in
  let sender_fields =
    [ Some ("name", `String (effective_sender_name connector_config))
    ; Option.map (fun avatar -> "avatar", `String avatar) connector_config.Config.sender_avatar
    ]
    |> List.filter_map Fun.id
  in
  let body =
    `Assoc
      [ "receiver", `String recipient
      ; "min_api_version", `Int 1
      ; "sender", `Assoc sender_fields
      ; "type", `String "text"
      ; "text", `String text
      ]
  in
  http_post uri ~headers body
  >>= fun (response, body_text) ->
  let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
  if status < 200 || status >= 300
  then
    Lwt.return
      (Error
         (Domain_error.upstream_status
            ~provider_id:connector.provider_id
            ~status
            (Fmt.str "Viber send_message failed with status %d: %s" status body_text)))
  else
    match Request_body.parse_json_string body_text with
    | Error _ as error -> Lwt.return error
    | Ok (`Assoc fields) ->
      (match List.assoc_opt "status" fields with
       | Some (`Int 0) -> Lwt.return (Ok ())
       | Some (`Int status_code) ->
         let status_message =
           match List.assoc_opt "status_message" fields with
           | Some (`String value) -> value
           | _ -> body_text
         in
         Lwt.return
           (Error
              (Domain_error.upstream
                 ~provider_id:connector.provider_id
                 (Fmt.str
                    "Viber send_message rejected the request with status %d: %s"
                    status_code
                    status_message)))
       | _ ->
         Lwt.return
           (Error
              (Domain_error.upstream
                 ~provider_id:connector.provider_id
                 "Viber send_message returned malformed JSON.")))
    | Ok _ ->
      Lwt.return
        (Error
           (Domain_error.upstream
              ~provider_id:connector.provider_id
              "Viber send_message returned malformed JSON."))
;;

let connector_system_messages (connector_config : Config.viber_connector) event =
  let metadata_lines =
    [ Some ("Viber user id: " ^ event.sender_id)
    ; Option.map (fun name -> "User: " ^ name) event.sender_name
    ; Option.map (fun value -> "Subscribed: " ^ string_of_bool value) event.subscribed
    ]
    |> List.filter_map Fun.id
  in
  User_connector_common.connector_system_messages
    ~channel_name:connector.User_connector_common.channel_name
    ~default_system_prompt
    ?system_prompt:connector_config.Config.system_prompt
    metadata_lines
;;

let is_allowed_sender (connector_config : Config.viber_connector) sender_id =
  sender_id <> ""
  &&
  (connector_config.Config.allowed_sender_ids = []
   || List.mem sender_id connector_config.Config.allowed_sender_ids)
;;

let event_requires_response event =
  match event.event_type with
  | "message" | "conversation_started" -> event.sender_id <> ""
  | _ -> false
;;

let handle_command
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.viber_connector)
  ~auth_token
  event
  command
  =
  let session_key =
    User_connector_common.build_session_key connector event.sender_id
  in
  let reply_text =
    match command with
    | "/reset" ->
      Runtime_state.clear_user_connector_session store ~session_key;
      reset_message
    | "/help" | "/start" -> help_message
    | _ -> ""
  in
  if reply_text = ""
  then Lwt.return (Ok ())
  else
    send_viber_message
      ~http_post
      connector_config
      ~auth_token
      ~recipient:event.sender_id
      ~text:reply_text
;;

let handle_text_message
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.viber_connector)
  ~auth_token
  ~authorization
  event
  text
  =
  let session_key =
    User_connector_common.build_session_key connector event.sender_id
  in
  let conversation = Runtime_state.get_user_connector_session store ~session_key in
  let request : Openai_types.chat_request =
    { Openai_types.model = connector_config.Config.route_model
    ; messages =
        connector_system_messages connector_config event
        @ Session_memory.request_messages session_limits conversation ~pending_user:text
    ; stream = false
    ; max_tokens = None
    ; extra = []
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
    User_connector_common.append_audit
      store
      connector
      ~authorization
      ~route_model:(Some connector_config.route_model)
      ~status_code:200
      (User_connector_common.audit_details
         [ "result", `String "ok"
         ; "response_model", `String response.model
         ; "sender_id", `String event.sender_id
         ]);
    send_viber_message
      ~http_post
      connector_config
      ~auth_token
      ~recipient:event.sender_id
      ~text:assistant_text
  | Error err ->
    User_connector_common.append_audit
      store
      connector
      ~authorization
      ~route_model:(Some connector_config.route_model)
      ~status_code:err.status
      (User_connector_common.audit_details
         [ "result", `String "router_error"
         ; "sender_id", `String event.sender_id
         ; "error", Domain_error.to_openai_json err
         ]);
    send_viber_message
      ~http_post
      connector_config
      ~auth_token
      ~recipient:event.sender_id
      ~text:(User_connector_common.user_error_message err)
;;

let handle_single_event
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.viber_connector)
  ~auth_token
  ~authorization
  event
  =
  if not (is_allowed_sender connector_config event.sender_id)
  then Lwt.return (Ok ())
  else
    match event.event_type, event.message_text with
    | "conversation_started", _ ->
      send_viber_message
        ~http_post
        connector_config
        ~auth_token
        ~recipient:event.sender_id
        ~text:onboarding_message
    | "message", Some ("/reset" | "/help" | "/start" as command) ->
      handle_command ~http_post store connector_config ~auth_token event command
    | "message", None ->
      send_viber_message
        ~http_post
        connector_config
        ~auth_token
        ~recipient:event.sender_id
        ~text:text_only_message
    | "message", Some text ->
      let trimmed = String.trim text in
      if trimmed = ""
      then
        send_viber_message
          ~http_post
          connector_config
          ~auth_token
          ~recipient:event.sender_id
          ~text:text_only_message
      else
        handle_text_message
          ~http_post
          store
          connector_config
          ~auth_token
          ~authorization
          event
          trimmed
    | _ -> Lwt.return (Ok ())
;;

let handle_webhook
  ?(http_post = User_connector_common.default_http_post)
  store
  req
  body
  (connector_config : Config.viber_connector)
  =
  match Cohttp.Request.meth req with
  | `POST -> (
    Request_body.read_request_text store body
    >>= function
    | Error err -> Json_response.respond_error err
    | Ok raw_body ->
      (match verify_signature connector_config raw_body req with
       | Error err -> Json_response.respond_error err
       | Ok () ->
         (match Request_body.parse_json_string raw_body with
          | Error err -> Json_response.respond_error err
          | Ok json ->
            (match parse_inbound_event json with
             | Error err -> Json_response.respond_error err
             | Ok event ->
               if
                 not (event_requires_response event)
                 || not (is_allowed_sender connector_config event.sender_id)
               then User_connector_common.respond_ok ()
               else
                 (match
                    User_connector_common.env_value
                      ~provider_id:connector.provider_id
                      connector_config.auth_token_env
                  with
                  | Error err -> Json_response.respond_error err
                  | Ok auth_token ->
                    (match
                       User_connector_common.env_value
                         ~provider_id:connector.provider_id
                         connector_config.authorization_env
                     with
                     | Error err -> Json_response.respond_error err
                     | Ok authorization_raw ->
                       let authorization =
                         User_connector_common.normalized_authorization
                           store
                           authorization_raw
                       in
                       handle_single_event
                         ~http_post
                         store
                         connector_config
                         ~auth_token
                         ~authorization
                         event
                       >>= function
                       | Ok () -> User_connector_common.respond_ok ()
                       | Error err -> Json_response.respond_error err))))))
  | _ ->
    Cohttp_lwt_unix.Server.respond_string
      ~status:`Method_not_allowed
      ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
      ~body:"Method not allowed."
      ()
;;
