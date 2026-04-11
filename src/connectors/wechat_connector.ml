open Lwt.Infix

type inbound_message = Wechat_connector_xml.inbound_message

let connector =
  { User_connector_common.channel_name = "WeChat Service Account"
  ; provider_id = "wechat-service-account"
  ; event_type = "connector.wechat"
  ; session_prefix = "wechat"
  }

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this WeChat conversation. Use it as context, but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through WeChat. Keep answers concise, clear, and immediately useful on mobile."
;;

let help_message =
  String.concat
    "\n"
    [ "Send a text message to talk with the assistant."
    ; "Commands:"
    ; "/reset - clear this WeChat conversation memory"
    ; "/help - show this help"
    ]
;;

let onboarding_message =
  "I am connected to BulkheadLM on WeChat. Send a text message or use /help."
;;

let reset_message = "Conversation memory cleared for this WeChat conversation."
let text_only_message = "Send a text message for now. Media and files are not handled by this connector yet."
let xml_content_type = "application/xml; charset=utf-8"
let text_content_type = "text/plain; charset=utf-8"
let success_body = "success"

let find_webhook_config (config : Config.t) ~path =
  match config.user_connectors.wechat with
  | Some connector when String.equal connector.webhook_path path -> Some connector
  | _ -> None
;;

let query_param req name =
  Uri.get_query_param (Cohttp.Request.uri req) name |> Option.map String.trim
;;

let respond_string ~status ~content_type ~body =
  Cohttp_lwt_unix.Server.respond_string
    ~status
    ~headers:(Cohttp.Header.of_list [ "content-type", content_type ])
    ~body
    ()
;;

let respond_success () =
  respond_string ~status:`OK ~content_type:text_content_type ~body:success_body
;;

let respond_xml body =
  respond_string ~status:`OK ~content_type:xml_content_type ~body
;;

let current_unix_timestamp () = int_of_float (Unix.time ())

let sha1_signature ~token ~timestamp ~nonce =
  [ token; timestamp; nonce ]
  |> List.sort String.compare
  |> String.concat ""
  |> Digestif.SHA1.digest_string
  |> Digestif.SHA1.to_hex
;;

let validate_signature req (connector_config : Config.wechat_connector) =
  match query_param req "encrypt_type" with
  | Some encrypt_type when not (String.equal encrypt_type "raw") ->
    Error
      (Domain_error.invalid_request
         "Encrypted WeChat webhook mode is not supported yet. Use plaintext mode.")
  | _ ->
    (match
       query_param req "signature",
       query_param req "timestamp",
       query_param req "nonce"
     with
     | Some signature, Some timestamp, Some nonce ->
       (match
          User_connector_common.env_value
            ~provider_id:connector.provider_id
            connector_config.signature_token_env
        with
        | Error _ as error -> error
        | Ok token ->
          let expected = sha1_signature ~token ~timestamp ~nonce in
          if User_connector_common.constant_time_equal expected signature
          then Ok ()
          else Error (Domain_error.operation_denied "WeChat webhook signature mismatch."))
     | _ ->
       Error
         (Domain_error.invalid_request
            "WeChat webhook is missing signature, timestamp, or nonce."))
;;

let is_allowed_open_id (connector_config : Config.wechat_connector) open_id =
  connector_config.Config.allowed_open_ids = []
  || List.mem open_id connector_config.Config.allowed_open_ids
;;

let is_allowed_account_id (connector_config : Config.wechat_connector) account_id =
  connector_config.Config.allowed_account_ids = []
  || List.mem account_id connector_config.Config.allowed_account_ids
;;

let connector_system_messages
  (connector_config : Config.wechat_connector)
  (message : inbound_message)
  =
  let metadata_lines =
    [ Some ("WeChat account id: " ^ message.account_id)
    ; Some ("WeChat open id: " ^ message.open_id)
    ]
    |> List.filter_map Fun.id
  in
  User_connector_common.connector_system_messages
    ~channel_name:connector.User_connector_common.channel_name
    ~default_system_prompt
    ?system_prompt:connector_config.Config.system_prompt
    metadata_lines
;;

let session_subject (message : inbound_message) = message.account_id ^ ":" ^ message.open_id

let reply_xml (message : inbound_message) text =
  Wechat_connector_xml.render_text_reply
    ~to_user:message.open_id
    ~from_user:message.account_id
    ~create_time:(current_unix_timestamp ())
    ~text
;;

let handle_command store (message : inbound_message) command =
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
  if reply_text = "" then respond_success () else respond_xml (reply_xml message reply_text)
;;

let handle_text_message
  store
  (connector_config : Config.wechat_connector)
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
    User_connector_common.append_audit
      store
      connector
      ~authorization
      ~route_model:(Some connector_config.route_model)
      ~status_code:200
      (User_connector_common.audit_details
         [ "result", `String "ok"
         ; "response_model", `String response.model
         ; "account_id", `String message.account_id
         ; "open_id", `String message.open_id
         ]);
    respond_xml (reply_xml message assistant_text)
  | Error err ->
    User_connector_common.append_audit
      store
      connector
      ~authorization
      ~route_model:(Some connector_config.route_model)
      ~status_code:err.status
      (User_connector_common.audit_details
         [ "result", `String "router_error"
         ; "account_id", `String message.account_id
         ; "open_id", `String message.open_id
         ; "error", Domain_error.to_openai_json err
         ]);
    respond_xml (reply_xml message (User_connector_common.user_error_message err))
;;

let handle_verification req connector_config =
  match validate_signature req connector_config, query_param req "echostr" with
  | Ok (), Some echostr ->
    respond_string ~status:`OK ~content_type:text_content_type ~body:echostr
  | Ok (), None ->
    respond_string
      ~status:`Bad_request
      ~content_type:text_content_type
      ~body:"Invalid WeChat verification request."
  | Error err, _ ->
    respond_string
      ~status:(Cohttp.Code.status_of_code err.status)
      ~content_type:text_content_type
      ~body:err.message
;;

let handle_message
  store
  (connector_config : Config.wechat_connector)
  ~authorization
  (message : inbound_message)
  =
  if
    not (is_allowed_account_id connector_config message.account_id)
    || not (is_allowed_open_id connector_config message.open_id)
  then respond_success ()
  else
    match message.msg_type, message.event, message.content, message.event_key with
    | "event", Some "subscribe", _, _ -> respond_xml (reply_xml message onboarding_message)
    | "event", Some "unsubscribe", _, _ -> respond_success ()
    | "event", Some "CLICK", _, Some ("/reset" | "/help" | "/start" as command) ->
      handle_command store message command
    | "event", Some "CLICK", _, Some event_key ->
      handle_text_message store connector_config ~authorization message event_key
    | "text", _, Some ("/reset" | "/help" | "/start" as command), _ ->
      handle_command store message command
    | "text", _, Some text, _ ->
      let trimmed = String.trim text in
      if trimmed = ""
      then respond_xml (reply_xml message text_only_message)
      else handle_text_message store connector_config ~authorization message trimmed
    | "text", _, None, _ -> respond_xml (reply_xml message text_only_message)
    | _ -> respond_xml (reply_xml message text_only_message)
;;

let handle_webhook
  store
  req
  body
  (connector_config : Config.wechat_connector)
  =
  match Cohttp.Request.meth req with
  | `GET -> handle_verification req connector_config
  | `POST -> (
    match validate_signature req connector_config with
    | Error err ->
      respond_string
        ~status:(Cohttp.Code.status_of_code err.status)
        ~content_type:text_content_type
        ~body:err.message
    | Ok () ->
      Request_body.read_request_text store body
      >>= function
      | Error err -> Json_response.respond_error err
      | Ok raw_body ->
        (match Wechat_connector_xml.parse raw_body with
         | Error err -> Json_response.respond_error err
         | Ok message ->
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
              handle_message store connector_config ~authorization message)))
  | _ ->
    Cohttp_lwt_unix.Server.respond_string
      ~status:`Method_not_allowed
      ~headers:(Cohttp.Header.of_list [ "content-type", text_content_type ])
      ~body:"Method not allowed."
      ()
;;
