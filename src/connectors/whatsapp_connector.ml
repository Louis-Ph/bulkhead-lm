open Lwt.Infix

type http_post = User_connector_common.http_post

type inbound_message =
  { entry_id : string option
  ; phone_number_id : string
  ; sender_number : string
  ; sender_name : string option
  ; message_id : string option
  ; text : string option
  }

let connector =
  { User_connector_common.channel_name = "WhatsApp"
  ; provider_id = "whatsapp-cloud-api"
  ; event_type = "connector.whatsapp"
  ; session_prefix = "whatsapp"
  }

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this WhatsApp conversation. Use it as context, but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through WhatsApp. Keep answers concise, practical, and easy to scan on a phone. Prefer short paragraphs over heavy formatting."
;;

let help_message =
  String.concat
    "\n"
    [ "Send a text message to talk with the assistant."
    ; "Commands:"
    ; "/reset - clear this WhatsApp conversation memory"
    ; "/help - show this help"
    ]
;;

let reset_message = "Conversation memory cleared for this WhatsApp chat."
let text_only_message = "Send a text message for now. Media and files are not handled by this connector yet."

let find_webhook_config (config : Config.t) ~path =
  match config.user_connectors.whatsapp with
  | Some connector when String.equal connector.webhook_path path -> Some connector
  | _ -> None
;;

let normalize_phone_number value =
  value |> String.trim |> String.map (fun ch -> if ch = ' ' then '\000' else ch)
  |> String.split_on_char '\000'
  |> String.concat ""
;;

let parse_sender_name value_json sender_number =
  let contacts =
    match User_connector_common.member "contacts" value_json with
    | Some (`List values) -> values
    | _ -> []
  in
  let matches_sender contact_json =
    String.equal
      (Option.value
         (User_connector_common.string_of_scalar_opt
            (User_connector_common.member "wa_id" contact_json))
         ~default:"")
      sender_number
  in
  let contact =
    List.find_opt
      (function
        | `Assoc _ as contact_json -> matches_sender contact_json
        | _ -> false)
      contacts
  in
  match contact with
  | Some (`Assoc _ as contact_json) ->
    (match User_connector_common.member "profile" contact_json with
     | Some (`Assoc _ as profile_json) ->
       User_connector_common.string_opt
         (User_connector_common.member "name" profile_json)
     | _ -> None)
  | _ -> None
;;

let parse_text_message entry_id phone_number_id value_json message_json =
  match
    User_connector_common.string_of_scalar_opt
      (User_connector_common.member "from" message_json)
  with
  | None -> None
  | Some sender_number ->
    let sender_number = normalize_phone_number sender_number in
    let text =
      match User_connector_common.member "text" message_json with
      | Some (`Assoc _ as text_json) ->
        User_connector_common.string_opt (User_connector_common.member "body" text_json)
      | _ -> None
    in
    Some
      { entry_id
      ; phone_number_id
      ; sender_number
      ; sender_name = parse_sender_name value_json sender_number
      ; message_id = User_connector_common.string_opt (User_connector_common.member "id" message_json)
      ; text
      }
;;

let parse_change entry_id change_json =
  let value_json =
    Option.value (User_connector_common.member "value" change_json) ~default:`Null
  in
  let phone_number_id =
    User_connector_common.string_of_scalar_opt
      (User_connector_common.member "phone_number_id"
         (Option.value (User_connector_common.member "metadata" value_json) ~default:`Null))
  in
  match
    User_connector_common.string_opt (User_connector_common.member "field" change_json),
    phone_number_id
  with
  | Some "messages", Some phone_number_id ->
    (match User_connector_common.member "messages" value_json with
     | Some (`List messages) ->
       messages
       |> List.filter_map (function
         | `Assoc _ as message_json ->
           let message_type =
             User_connector_common.string_opt
               (User_connector_common.member "type" message_json)
           in
           (match message_type with
            | Some "text" -> parse_text_message entry_id phone_number_id value_json message_json
            | _ -> None)
         | _ -> None)
     | _ -> [])
  | _ -> []
;;

let parse_inbound_messages json =
  match User_connector_common.string_opt (User_connector_common.member "object" json) with
  | Some "whatsapp_business_account" ->
    (match User_connector_common.member "entry" json with
     | Some (`List entries) ->
       entries
       |> List.concat_map (function
         | `Assoc _ as entry_json ->
           let entry_id =
             User_connector_common.string_of_scalar_opt
               (User_connector_common.member "id" entry_json)
           in
           (match User_connector_common.member "changes" entry_json with
            | Some (`List changes) ->
              changes
              |> List.concat_map (function
                | `Assoc _ as change_json -> parse_change entry_id change_json
                | _ -> [])
            | _ -> [])
         | _ -> [])
       |> fun messages -> Ok messages
     | _ -> Ok [])
  | Some _ -> Error (Domain_error.invalid_request "Unexpected WhatsApp webhook object.")
  | None -> Error (Domain_error.invalid_request "WhatsApp webhook is missing object.")
;;

let send_whatsapp_message
  ?(http_post = User_connector_common.default_http_post)
  (connector_config : Config.whatsapp_connector)
  ~access_token
  ~phone_number_id
  ~recipient
  ~text
  =
  let send_one chunk =
    let uri =
      Uri.of_string
        (Fmt.str "%s/%s/messages" connector_config.Config.api_base phone_number_id)
    in
    let headers =
      Cohttp.Header.of_list
        [ "content-type", "application/json"
        ; "authorization", "Bearer " ^ access_token
        ]
    in
    let body =
      `Assoc
        [ "messaging_product", `String "whatsapp"
        ; "recipient_type", `String "individual"
        ; "to", `String recipient
        ; "type", `String "text"
        ; ( "text"
          , `Assoc [ "body", `String chunk; "preview_url", `Bool false ] )
        ]
    in
    http_post uri ~headers body
    >>= fun (response, body_text) ->
    let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
    if status >= 200 && status < 300
    then Lwt.return (Ok ())
    else
      Lwt.return
        (Error
           (Domain_error.upstream_status
              ~provider_id:connector.provider_id
              ~status
              (Fmt.str "WhatsApp messages API failed with status %d: %s" status body_text)))
  in
  let rec send_all = function
    | [] -> Lwt.return (Ok ())
    | chunk :: rest ->
      send_one chunk
      >>= (function
       | Ok () -> send_all rest
       | Error err -> Lwt.return (Error err))
  in
  send_all (User_connector_common.split_text_for_channel ~max_bytes:3500 text)
;;

let connector_system_messages (connector_config : Config.whatsapp_connector) message =
  let metadata_lines =
    [ Some ("Sender number: " ^ message.sender_number)
    ; Option.map (fun name -> "User: " ^ name) message.sender_name
    ]
    |> List.filter_map Fun.id
  in
  User_connector_common.connector_system_messages
    ~channel_name:connector.User_connector_common.channel_name
    ~default_system_prompt
    ?system_prompt:connector_config.Config.system_prompt
    metadata_lines
;;

let user_text_from_message message =
  match message.text with
  | None -> None
  | Some text ->
    let trimmed = String.trim text in
    if trimmed = "" then None else Some trimmed
;;

let is_allowed_sender (connector_config : Config.whatsapp_connector) sender_number =
  connector_config.Config.allowed_sender_numbers = []
  || List.mem sender_number connector_config.Config.allowed_sender_numbers
;;

let verify_signature (connector_config : Config.whatsapp_connector) raw_body req =
  match connector_config.Config.app_secret_env with
  | None -> Ok ()
  | Some env_name ->
    (match User_connector_common.env_value ~provider_id:connector.provider_id env_name with
     | Error err -> Error err
     | Ok app_secret ->
       let presented =
         Cohttp.Header.get (Cohttp.Request.headers req) "x-hub-signature-256"
       in
       let expected =
         "sha256="
         ^ Digestif.SHA256.(to_hex (hmac_string ~key:app_secret raw_body))
       in
       if
         User_connector_common.constant_time_equal
           (Option.value presented ~default:"")
           expected
       then Ok ()
       else Error (Domain_error.operation_denied "WhatsApp webhook signature mismatch."))
;;

let webhook_query_param req name =
  Uri.get_query_param (Cohttp.Request.uri req) name |> Option.map String.trim
;;

let handle_verification req (connector_config : Config.whatsapp_connector) =
  match
    webhook_query_param req "hub.mode",
    webhook_query_param req "hub.verify_token",
    webhook_query_param req "hub.challenge"
  with
  | Some "subscribe", Some presented_token, Some challenge ->
    (match
       User_connector_common.env_value
         ~provider_id:connector.provider_id
         connector_config.verify_token_env
     with
     | Error err -> Json_response.respond_error err
     | Ok expected_token ->
       if User_connector_common.constant_time_equal expected_token presented_token
       then
         Cohttp_lwt_unix.Server.respond_string
           ~status:`OK
           ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
           ~body:challenge
           ()
       else
         Cohttp_lwt_unix.Server.respond_string
           ~status:`Forbidden
           ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
           ~body:"Forbidden"
           ())
  | _ ->
    Cohttp_lwt_unix.Server.respond_string
      ~status:`Bad_request
      ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
      ~body:"Invalid WhatsApp webhook verification request."
      ()
;;

let handle_command
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.whatsapp_connector)
  ~access_token
  message
  command
  =
  let session_key =
    User_connector_common.build_session_key connector message.sender_number
  in
  let reply_text =
    match command with
    | "/reset" ->
      Runtime_state.clear_user_connector_session store ~session_key;
      reset_message
    | "/help" -> help_message
    | _ -> ""
  in
  if reply_text = ""
  then Lwt.return (Ok ())
  else
    send_whatsapp_message
      ~http_post
      connector_config
      ~access_token
      ~phone_number_id:message.phone_number_id
      ~recipient:message.sender_number
      ~text:reply_text
    >|= function
    | Ok () -> Ok ()
    | Error err -> Error err
;;

let handle_text_message
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.whatsapp_connector)
  ~access_token
  ~authorization
  message
  text
  =
  let session_key =
    User_connector_common.build_session_key connector message.sender_number
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
           ; "sender_number", `String message.sender_number
           ; "phone_number_id", `String message.phone_number_id
           ])
    in
    send_whatsapp_message
      ~http_post
      connector_config
      ~access_token
      ~phone_number_id:message.phone_number_id
      ~recipient:message.sender_number
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
           ; "sender_number", `String message.sender_number
           ; "phone_number_id", `String message.phone_number_id
           ; "error", Domain_error.to_openai_json err
           ])
    in
    send_whatsapp_message
      ~http_post
      connector_config
      ~access_token
      ~phone_number_id:message.phone_number_id
      ~recipient:message.sender_number
      ~text:(User_connector_common.user_error_message err)
;;

let handle_single_message
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.whatsapp_connector)
  ~access_token
  ~authorization
  message
  =
  if not (is_allowed_sender connector_config message.sender_number)
  then Lwt.return (Ok ())
  else
    match user_text_from_message message with
    | Some ("/reset" | "/help" as command) ->
      handle_command
        ~http_post
        store
        connector_config
        ~access_token
        message
        command
    | None ->
      send_whatsapp_message
        ~http_post
        connector_config
        ~access_token
        ~phone_number_id:message.phone_number_id
        ~recipient:message.sender_number
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
  (connector_config : Config.whatsapp_connector)
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
  (connector_config : Config.whatsapp_connector)
  =
  match Cohttp.Request.meth req with
  | `GET -> handle_verification req connector_config
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
            (match parse_inbound_messages json with
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
