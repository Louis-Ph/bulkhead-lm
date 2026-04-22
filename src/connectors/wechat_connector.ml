open Lwt.Infix

type inbound_message = Wechat_connector_xml.inbound_message
type encrypted_credentials = Wechat_connector_crypto.encrypted_credentials

type request_security =
  | Plaintext
  | Encrypted of encrypted_credentials

type outbound_body =
  | Success
  | Xml of string

let connector =
  { User_connector_common.channel_name = "WeChat Service Account"
  ; provider_id = "wechat-service-account"
  ; event_type = "connector.wechat"
  ; session_prefix = "wechat"
  }
;;

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this WeChat conversation. Use it as context, \
       but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through WeChat. Keep answers concise, clear, and immediately useful \
   on mobile."
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

let text_only_message =
  "Send a text message for now. Media and files are not handled by this connector yet."
;;

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

let respond_xml body = respond_string ~status:`OK ~content_type:xml_content_type ~body
let current_unix_timestamp () = int_of_float (Unix.time ())

let sha1_signature ~token ~timestamp ~nonce =
  Wechat_connector_crypto.sha1_signature [ token; timestamp; nonce ]
;;

let security_mode_of_request req (connector_config : Config.wechat_connector) =
  match query_param req "encrypt_type" |> Option.map String.lowercase_ascii with
  | None | Some "" | Some "raw" -> Ok Plaintext
  | Some "aes" ->
    (match
       User_connector_common.env_value
         ~provider_id:connector.provider_id
         connector_config.signature_token_env
     with
     | Error _ as error -> error
     | Ok token ->
       (match
          connector_config.Config.encoding_aes_key_env, connector_config.Config.app_id_env
        with
        | Some encoding_aes_key_env, Some app_id_env ->
          (match
             User_connector_common.env_value
               ~provider_id:connector.provider_id
               encoding_aes_key_env
           with
           | Error _ as error -> error
           | Ok encoding_aes_key ->
             User_connector_common.env_value ~provider_id:connector.provider_id app_id_env
             |> Result.map (fun app_id ->
               Encrypted { Wechat_connector_crypto.token; encoding_aes_key; app_id }))
        | _ ->
          Error
            (Domain_error.invalid_request
               "WeChat encrypted mode requires encoding_aes_key_env and app_id_env in \
                config.")))
  | Some _ ->
    Error (Domain_error.invalid_request "WeChat encrypt_type must be raw or aes.")
;;

let validate_plaintext_signature req (connector_config : Config.wechat_connector) =
  match
    query_param req "signature", query_param req "timestamp", query_param req "nonce"
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
         "WeChat webhook is missing signature, timestamp, or nonce.")
;;

let validate_encrypted_signature ~(credentials : encrypted_credentials) req ~encrypted =
  match
    query_param req "msg_signature", query_param req "timestamp", query_param req "nonce"
  with
  | Some msg_signature, Some timestamp, Some nonce ->
    let expected =
      Wechat_connector_crypto.ciphertext_signature
        ~token:credentials.token
        ~timestamp
        ~nonce
        ~encrypted
    in
    if User_connector_common.constant_time_equal expected msg_signature
    then Ok ()
    else Error (Domain_error.operation_denied "WeChat webhook msg_signature mismatch.")
  | _ ->
    Error
      (Domain_error.invalid_request
         "WeChat encrypted webhook is missing msg_signature, timestamp, or nonce.")
;;

let decrypt_request_body ~(credentials : encrypted_credentials) req raw_body =
  Result.bind (Wechat_connector_xml.parse_encrypted_envelope raw_body) (fun encrypted ->
    Result.bind (validate_encrypted_signature ~credentials req ~encrypted) (fun () ->
      Wechat_connector_crypto.decrypt_payload ~credentials ~encrypted))
;;

let respond_outbound req request_security outbound =
  match outbound, request_security with
  | Success, _ -> respond_success ()
  | Xml body, Plaintext -> respond_xml body
  | Xml body, Encrypted credentials ->
    let nonce = query_param req "nonce" in
    Wechat_connector_crypto.encrypt_reply ?nonce ~credentials ~plaintext:body ()
    |> (function
     | Ok encrypted_reply ->
       Wechat_connector_xml.render_encrypted_reply
         ~encrypted:encrypted_reply.encrypted
         ~msg_signature:encrypted_reply.msg_signature
         ~timestamp:encrypted_reply.timestamp
         ~nonce:encrypted_reply.nonce
       |> respond_xml
     | Error err -> Json_response.respond_error err)
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

let session_subject (message : inbound_message) =
  message.account_id ^ ":" ^ message.open_id
;;

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
  if reply_text = ""
  then Lwt.return Success
  else Lwt.return (Xml (reply_xml message reply_text))
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
      Session_memory.commit_exchange
        session_limits
        conversation
        ~user:text
        ~assistant:assistant_text
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
    Lwt.return (Xml (reply_xml message assistant_text))
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
    Lwt.return (Xml (reply_xml message (User_connector_common.user_error_message err)))
;;

let handle_verification req connector_config =
  match security_mode_of_request req connector_config, query_param req "echostr" with
  | Ok Plaintext, Some echostr ->
    (match validate_plaintext_signature req connector_config with
     | Ok () -> respond_string ~status:`OK ~content_type:text_content_type ~body:echostr
     | Error err ->
       respond_string
         ~status:(Cohttp.Code.status_of_code err.status)
         ~content_type:text_content_type
         ~body:err.message)
  | Ok (Encrypted credentials), Some echostr ->
    (match
       Result.bind
         (validate_encrypted_signature ~credentials req ~encrypted:echostr)
         (fun () ->
            Wechat_connector_crypto.decrypt_payload ~credentials ~encrypted:echostr)
     with
     | Ok verified_echo ->
       respond_string ~status:`OK ~content_type:text_content_type ~body:verified_echo
     | Error err ->
       respond_string
         ~status:(Cohttp.Code.status_of_code err.status)
         ~content_type:text_content_type
         ~body:err.message)
  | Ok _, None ->
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
  if (not (is_allowed_account_id connector_config message.account_id))
     || not (is_allowed_open_id connector_config message.open_id)
  then Lwt.return Success
  else (
    match message.msg_type, message.event, message.content, message.event_key with
    | "event", Some "subscribe", _, _ ->
      Lwt.return (Xml (reply_xml message onboarding_message))
    | "event", Some "unsubscribe", _, _ -> Lwt.return Success
    | "event", Some "CLICK", _, Some (("/reset" | "/help" | "/start") as command) ->
      handle_command store message command
    | "event", Some "CLICK", _, Some event_key ->
      handle_text_message store connector_config ~authorization message event_key
    | "text", _, Some (("/reset" | "/help" | "/start") as command), _ ->
      handle_command store message command
    | "text", _, Some text, _ ->
      let trimmed = String.trim text in
      if trimmed = ""
      then Lwt.return (Xml (reply_xml message text_only_message))
      else handle_text_message store connector_config ~authorization message trimmed
    | "text", _, None, _ -> Lwt.return (Xml (reply_xml message text_only_message))
    | _ -> Lwt.return (Xml (reply_xml message text_only_message)))
;;

let handle_webhook store req body (connector_config : Config.wechat_connector) =
  match Cohttp.Request.meth req with
  | `GET -> handle_verification req connector_config
  | `POST ->
    (match security_mode_of_request req connector_config with
     | Error err ->
       respond_string
         ~status:(Cohttp.Code.status_of_code err.status)
         ~content_type:text_content_type
         ~body:err.message
     | Ok request_security ->
       Request_body.read_request_text store body
       >>= (function
        | Error err -> Json_response.respond_error err
        | Ok raw_body ->
          let payload_result =
            match request_security with
            | Plaintext ->
              validate_plaintext_signature req connector_config
              |> Result.map (fun () -> raw_body)
            | Encrypted credentials -> decrypt_request_body ~credentials req raw_body
          in
          (match payload_result with
           | Error err ->
             respond_string
               ~status:(Cohttp.Code.status_of_code err.status)
               ~content_type:text_content_type
               ~body:err.message
           | Ok payload_xml ->
             (match Wechat_connector_xml.parse payload_xml with
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
                     User_connector_common.normalized_authorization
                       store
                       authorization_raw
                   in
                   handle_message store connector_config ~authorization message
                   >>= fun outbound -> respond_outbound req request_security outbound)))))
  | _ ->
    Cohttp_lwt_unix.Server.respond_string
      ~status:`Method_not_allowed
      ~headers:(Cohttp.Header.of_list [ "content-type", text_content_type ])
      ~body:"Method not allowed."
      ()
;;
