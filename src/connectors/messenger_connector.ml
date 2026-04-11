open Lwt.Infix

type http_post = User_connector_common.http_post

type inbound_message = Meta_connector_common.inbound_message

let connector =
  { User_connector_common.channel_name = "Facebook Messenger"
  ; provider_id = "facebook-messenger"
  ; event_type = "connector.messenger"
  ; session_prefix = "messenger"
  }

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this Messenger conversation. Use it as context, but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through Facebook Messenger. Keep answers concise, practical, and easy to scan on mobile. Prefer short paragraphs and direct next steps."
;;

let help_message =
  String.concat
    "\n"
    [ "Send a text message to talk with the assistant."
    ; "Commands:"
    ; "/reset - clear this Messenger conversation memory"
    ; "/help - show this help"
    ]
;;

let reset_message = "Conversation memory cleared for this Messenger conversation."
let text_only_message = "Send a text message for now. Attachments and templates are not handled by this connector yet."

let find_webhook_config (config : Config.t) ~path =
  match config.user_connectors.messenger with
  | Some connector when String.equal connector.webhook_path path -> Some connector
  | _ -> None
;;

let session_subject (message : inbound_message) = message.account_id ^ ":" ^ message.sender_id

let is_allowed_page (connector_config : Config.messenger_connector) account_id =
  connector_config.Config.allowed_page_ids = []
  || List.mem account_id connector_config.Config.allowed_page_ids
;;

let is_allowed_sender (connector_config : Config.messenger_connector) sender_id =
  connector_config.Config.allowed_sender_ids = []
  || List.mem sender_id connector_config.Config.allowed_sender_ids
;;

let send_messenger_message
  ?(http_post = User_connector_common.default_http_post)
  (connector_config : Config.messenger_connector)
  ~access_token
  (message : inbound_message)
  ~text
  =
  Meta_connector_common.send_text_message
    ~http_post
    ~messaging_type:Meta_connector_common.response_messaging_type
    ~provider_id:connector.provider_id
    ~api_base:connector_config.Config.api_base
    ~access_token
    ~endpoint:(Meta_connector_common.Account_messages message.account_id)
    ~recipient_id:message.sender_id
    ~text
    ()
;;

let connector_system_messages
  (connector_config : Config.messenger_connector)
  (message : inbound_message)
  =
  let metadata_lines =
    [ Some ("Page id: " ^ message.account_id)
    ; Some ("User PSID: " ^ message.sender_id)
    ]
    |> List.filter_map Fun.id
  in
  User_connector_common.connector_system_messages
    ~channel_name:connector.User_connector_common.channel_name
    ~default_system_prompt
    ?system_prompt:connector_config.Config.system_prompt
    metadata_lines
;;

let handle_command
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.messenger_connector)
  ~access_token
  (message : inbound_message)
  command
  =
  let session_key =
    User_connector_common.build_session_key connector (session_subject message)
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
  else send_messenger_message ~http_post connector_config ~access_token message ~text:reply_text
;;

let handle_text_message
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.messenger_connector)
  ~access_token
  ~authorization
  (message : inbound_message)
  text
  =
  let session_key =
    User_connector_common.build_session_key connector (session_subject message)
  in
  let conversation = Runtime_state.get_user_connector_session store ~session_key in
  let request : Openai_types.chat_request =
    { Openai_types.model = connector_config.Config.route_model
    ; messages =
        connector_system_messages connector_config message
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
    let () =
      User_connector_common.append_audit
        store
        connector
        ~authorization
        ~route_model:(Some connector_config.route_model)
        ~status_code:200
        (User_connector_common.audit_details
           [ "result", `String "ok"
           ; "response_model", `String response.model
           ; "page_id", `String message.account_id
           ; "sender_id", `String message.sender_id
           ])
    in
    send_messenger_message
      ~http_post
      connector_config
      ~access_token
      message
      ~text:assistant_text
  | Error err ->
    let () =
      User_connector_common.append_audit
        store
        connector
        ~authorization
        ~route_model:(Some connector_config.route_model)
        ~status_code:err.status
        (User_connector_common.audit_details
           [ "result", `String "router_error"
           ; "page_id", `String message.account_id
           ; "sender_id", `String message.sender_id
           ; "error", Domain_error.to_openai_json err
           ])
    in
    send_messenger_message
      ~http_post
      connector_config
      ~access_token
      message
      ~text:(User_connector_common.user_error_message err)
;;

let handle_single_message
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.messenger_connector)
  ~access_token
  ~authorization
  (message : inbound_message)
  =
  if
    not (is_allowed_page connector_config message.account_id)
    || not (is_allowed_sender connector_config message.sender_id)
  then Lwt.return (Ok ())
  else
    match Meta_connector_common.user_text_from_message message with
    | Some ("/reset" | "/help" | "/start" as command) ->
      handle_command
        ~http_post
        store
        connector_config
        ~access_token
        message
        command
    | None ->
      send_messenger_message
        ~http_post
        connector_config
        ~access_token
        message
        ~text:text_only_message
    | Some text ->
      handle_text_message
        ~http_post
        store
        connector_config
        ~access_token
        ~authorization
        message
        text
;;

let handle_messages
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.messenger_connector)
  ~access_token
  ~authorization
  messages
  =
  let rec loop = function
    | [] -> User_connector_common.respond_ok ()
    | message :: rest ->
      handle_single_message
        ~http_post
        store
        connector_config
        ~access_token
        ~authorization
        message
      >>= function
      | Ok () -> loop rest
      | Error err -> Json_response.respond_error err
  in
  loop messages
;;

let handle_webhook
  ?(http_post = User_connector_common.default_http_post)
  store
  req
  body
  (connector_config : Config.messenger_connector)
  =
  match Cohttp.Request.meth req with
  | `GET ->
    Meta_connector_common.handle_verification
      req
      ~provider_id:connector.provider_id
      connector_config.verify_token_env
  | `POST -> (
    Request_body.read_request_text store body
    >>= function
    | Error err -> Json_response.respond_error err
    | Ok raw_body ->
      (match
         Meta_connector_common.verify_signature
           ~provider_id:connector.provider_id
           ?app_secret_env:connector_config.app_secret_env
           raw_body
           req
       with
       | Error err -> Json_response.respond_error err
       | Ok () ->
         (match Request_body.parse_json_string raw_body with
          | Error err -> Json_response.respond_error err
          | Ok json ->
            (match
               Meta_connector_common.parse_inbound_messages ~expected_object:"page" json
             with
             | Error err -> Json_response.respond_error err
             | Ok [] -> User_connector_common.respond_ok ()
             | Ok messages ->
               (match
                  User_connector_common.env_value
                    ~provider_id:connector.provider_id
                    connector_config.access_token_env
                with
                | Error err -> Json_response.respond_error err
                | Ok access_token ->
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
                     handle_messages
                       ~http_post
                       store
                       connector_config
                       ~access_token
                       ~authorization
                       messages)))))
    )
  | _ ->
    Cohttp_lwt_unix.Server.respond_string
      ~status:`Method_not_allowed
      ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
      ~body:"Method not allowed."
      ()
;;
