open Lwt.Infix

type http_post = User_connector_common.http_post

type inbound_message =
  { update_id : int option
  ; chat_id : string
  ; chat_type : string option
  ; message_thread_id : int option
  ; text : string option
  ; user_display_name : string option
  }

let connector =
  { User_connector_common.channel_name = "Telegram"
  ; provider_id = "telegram-bot-api"
  ; event_type = "connector.telegram"
  ; session_prefix = "telegram"
  }

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this Telegram conversation. Use it as context, but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through Telegram. Keep answers concise, readable on mobile, and immediately actionable. Avoid heavy formatting and wide tables unless the user explicitly asks for them."
;;

let help_message =
  String.concat
    "\n"
    [ "Send a normal text message to talk with the assistant."
    ; "Commands:"
    ; "/reset - clear this Telegram conversation memory"
    ; "/help - show this help"
    ]
;;

let reset_message = "Conversation memory cleared for this Telegram chat."
let text_only_message = "Send a text message for now. Media and files are not handled by this connector yet."

(** Find the connector entry whose webhook_path matches the inbound HTTP
    path. With multi-bot configurations there can be several Telegram entries
    on the same gateway, each registered against a distinct webhook_path; the
    first match wins. *)
let find_webhook_config (config : Config.t) ~path =
  List.find_opt
    (fun (connector : Config.telegram_connector) ->
      String.equal connector.webhook_path path)
    config.user_connectors.telegram
;;

(** Compose the conversation memory key.

    - [Shared_room] : every persona on the same chat_id reads and writes the
      SAME thread, so a group chat with two personas behaves as a real group:
      persona B sees what persona A just answered.
    - [Isolated_per_persona] : each persona keeps its own thread per chat_id;
      personas never see each other's replies (useful for parallel-bot setups
      that should NOT mingle context). *)
let session_key_for_message
  (connector_config : Config.telegram_connector)
  message
  =
  match connector_config.Config.room_memory_mode with
  | Config.Shared_room ->
    (* Reserved subject prefix [room:...] avoids clashing with the
       legacy single-bot [telegram:{chat_id}] key. *)
    User_connector_common.build_session_key connector ("room:" ^ message.chat_id)
  | Config.Isolated_per_persona ->
    User_connector_common.build_session_key
      connector
      (message.chat_id ^ ":" ^ connector_config.persona_name)
;;

(** When an assistant turn is committed to a SHARED room thread, we tag it
    with the persona's name so the next persona reading the history can tell
    who said what. The tag is invisible to the human user (it lives only in
    memory storage) but it gives every persona a clear "who said what" view. *)
let tag_assistant_turn_for_persona
  (connector_config : Config.telegram_connector)
  text
  =
  match connector_config.Config.room_memory_mode with
  | Config.Shared_room ->
    Fmt.str "[%s] %s" connector_config.persona_name text
  | Config.Isolated_per_persona -> text
;;

let telegram_api_uri bot_token method_name =
  Uri.of_string (Fmt.str "https://api.telegram.org/bot%s/%s" bot_token method_name)
;;

let parse_display_name json =
  let first_name = json |> User_connector_common.member "first_name" |> User_connector_common.string_opt in
  let last_name = json |> User_connector_common.member "last_name" |> User_connector_common.string_opt in
  let username = json |> User_connector_common.member "username" |> User_connector_common.string_opt in
  match first_name, last_name, username with
  | Some first_name, Some last_name, _ -> Some (first_name ^ " " ^ last_name)
  | Some first_name, None, _ -> Some first_name
  | None, Some last_name, _ -> Some last_name
  | None, _, Some username -> Some ("@" ^ username)
  | None, None, None -> None
;;

let parse_inbound_message json =
  let update_id = User_connector_common.int_opt (User_connector_common.member "update_id" json) in
  match User_connector_common.member "message" json with
  | Some (`Assoc _ as message_json) ->
    let chat_json =
      Option.value (User_connector_common.member "chat" message_json) ~default:`Null
    in
    (match
       User_connector_common.string_of_scalar_opt
         (User_connector_common.member "id" chat_json)
     with
     | None -> Error (Domain_error.invalid_request "Telegram update is missing chat.id.")
     | Some chat_id ->
       Ok
         { update_id
         ; chat_id
         ; chat_type =
             User_connector_common.string_opt
               (User_connector_common.member "type" chat_json)
         ; message_thread_id =
             User_connector_common.int_opt
               (User_connector_common.member "message_thread_id" message_json)
         ; text =
             (match
                User_connector_common.string_opt
                  (User_connector_common.member "text" message_json)
              with
              | Some text -> Some text
              | None ->
                User_connector_common.string_opt
                  (User_connector_common.member "caption" message_json))
         ; user_display_name =
             (match User_connector_common.member "from" message_json with
              | Some (`Assoc _ as from_json) -> parse_display_name from_json
              | _ -> None)
         })
  | _ ->
    Ok
      { update_id
      ; chat_id = ""
      ; chat_type = None
      ; message_thread_id = None
      ; text = None
      ; user_display_name = None
      }
;;

let is_noop_update message = String.trim message.chat_id = ""

let send_telegram_message
  ?message_thread_id
  ?(http_post = User_connector_common.default_http_post)
  (connector_config : Config.telegram_connector)
  ~bot_token
  ~chat_id
  ~text
  =
  let send_one chunk =
    let uri = telegram_api_uri bot_token "sendMessage" in
    let headers = Cohttp.Header.of_list [ "content-type", "application/json" ] in
    let fields =
      [ "chat_id", `String chat_id
      ; "text", `String chunk
      ; "disable_web_page_preview", `Bool true
      ]
      @
      match message_thread_id with
      | Some value -> [ "message_thread_id", `Int value ]
      | None -> []
    in
    http_post uri ~headers (`Assoc fields)
    >>= fun (response, body_text) ->
    let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
    if status < 200 || status >= 300
    then
      Lwt.return
        (Error
           (Domain_error.upstream_status
              ~provider_id:connector.provider_id
              ~status
              (Fmt.str "Telegram sendMessage failed with status %d: %s" status body_text)))
    else
      match Yojson.Safe.from_string body_text with
      | `Assoc fields ->
        (match List.assoc_opt "ok" fields with
         | Some (`Bool true) -> Lwt.return (Ok ())
         | _ ->
           let description =
             match List.assoc_opt "description" fields with
             | Some (`String value) -> value
             | _ -> body_text
           in
           Lwt.return
             (Error
                (Domain_error.upstream
                   ~provider_id:connector.provider_id
                   ("Telegram sendMessage rejected the request: " ^ description))))
      | _ ->
        Lwt.return
          (Error
             (Domain_error.upstream
                ~provider_id:connector.provider_id
                "Telegram sendMessage returned malformed JSON."))
  in
  let rec send_all = function
    | [] -> Lwt.return (Ok ())
    | chunk :: rest ->
      send_one chunk
      >>= (function
       | Ok () -> send_all rest
       | Error err -> Lwt.return (Error err))
  in
  send_all (User_connector_common.split_text_for_channel text)
;;

let connector_system_messages (connector_config : Config.telegram_connector) message =
  let group_context_lines =
    match connector_config.Config.room_memory_mode with
    | Config.Shared_room ->
      [ Fmt.str
          "You are participating in a shared Telegram chat as the persona named %s. \
           Other participants may also be AI personas; when you see history lines \
           prefixed by [name], that is another participant speaking, not you. Stay \
           in your own role and refer to other participants by name when relevant."
          connector_config.persona_name
      ]
    | Config.Isolated_per_persona -> []
  in
  let metadata_lines =
    [ Option.map (fun chat_type -> "Chat type: " ^ chat_type) message.chat_type
    ; Option.map (fun name -> "User: " ^ name) message.user_display_name
    ; Some (Fmt.str "Persona: %s" connector_config.persona_name)
    ]
    |> List.filter_map Fun.id
  in
  User_connector_common.connector_system_messages
    ~channel_name:connector.User_connector_common.channel_name
    ~default_system_prompt
    ?system_prompt:connector_config.Config.system_prompt
    (group_context_lines @ metadata_lines)
;;

let user_text_from_message message =
  match message.text with
  | None -> None
  | Some text ->
    let trimmed = String.trim text in
    if trimmed = "" then None else Some trimmed
;;

let validate_webhook_secret (connector_config : Config.telegram_connector) req =
  match connector_config.Config.secret_token_env with
  | None -> Ok ()
  | Some env_name ->
    (match User_connector_common.env_value ~provider_id:connector.provider_id env_name with
     | Error err -> Error err
     | Ok expected ->
       let presented =
         Cohttp.Header.get
           (Cohttp.Request.headers req)
           "x-telegram-bot-api-secret-token"
       in
       if presented = Some expected
       then Ok ()
       else Error (Domain_error.operation_denied "Telegram webhook secret token mismatch."))
;;

let is_allowed_chat (connector_config : Config.telegram_connector) chat_id =
  connector_config.Config.allowed_chat_ids = []
  || List.mem chat_id connector_config.Config.allowed_chat_ids
;;

let handle_command
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.telegram_connector)
  ~bot_token
  message
  command
  =
  let session_key = session_key_for_message connector_config message in
  let reply_text =
    match command with
    | "/reset" ->
      Runtime_state.clear_user_connector_session store ~session_key;
      reset_message
    | "/help"
    | "/start" -> help_message
    | _ -> ""
  in
  if reply_text = ""
  then User_connector_common.respond_ok ()
  else
    send_telegram_message
      ?message_thread_id:message.message_thread_id
      ~http_post
      connector_config
      ~bot_token
      ~chat_id:message.chat_id
      ~text:reply_text
    >>= function
    | Ok () -> User_connector_common.respond_ok ()
    | Error err -> Json_response.respond_error err
;;

let handle_text_message
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.telegram_connector)
  ~bot_token
  ~authorization
  message
  text
  =
  let session_key = session_key_for_message connector_config message in
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
    (* When the room is shared, tag the assistant turn so the next persona
       reading shared memory can tell who answered. *)
    let assistant_for_memory =
      tag_assistant_turn_for_persona connector_config assistant_text
    in
    let updated_conversation, _ =
      Session_memory.commit_exchange
        session_limits
        conversation
        ~user:text
        ~assistant:assistant_for_memory
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
         ; "chat_id", `String message.chat_id
         ]
         |> fun details ->
         match message.update_id with
         | Some update_id ->
           (match details with
            | `Assoc fields -> `Assoc (("update_id", `Int update_id) :: fields)
            | _ -> details)
         | None -> details);
    send_telegram_message
      ?message_thread_id:message.message_thread_id
      ~http_post
      connector_config
      ~bot_token
      ~chat_id:message.chat_id
      ~text:assistant_text
    >>= (function
     | Ok () -> User_connector_common.respond_ok ()
     | Error err -> Json_response.respond_error err)
  | Error err ->
    User_connector_common.append_audit
      store
      connector
      ~authorization
      ~route_model:(Some connector_config.route_model)
      ~status_code:err.status
      (User_connector_common.audit_details
         [ "result", `String "router_error"
         ; "chat_id", `String message.chat_id
         ; "error", Domain_error.to_openai_json err
         ]
         |> fun details ->
         match message.update_id with
         | Some update_id ->
           (match details with
            | `Assoc fields -> `Assoc (("update_id", `Int update_id) :: fields)
            | _ -> details)
         | None -> details);
    send_telegram_message
      ?message_thread_id:message.message_thread_id
      ~http_post
      connector_config
      ~bot_token
      ~chat_id:message.chat_id
      ~text:(User_connector_common.user_error_message err)
    >>= function
    | Ok () -> User_connector_common.respond_ok ()
    | Error send_err -> Json_response.respond_error send_err
;;

let handle_webhook
  ?(http_post = User_connector_common.default_http_post)
  store
  req
  body
  (connector_config : Config.telegram_connector)
  =
  match validate_webhook_secret connector_config req with
  | Error err -> Json_response.respond_error err
  | Ok () ->
    Request_body.read_request_json store body
    >>= function
    | Error err -> Json_response.respond_error err
    | Ok json ->
      (match parse_inbound_message json with
       | Error err -> Json_response.respond_error err
       | Ok message when is_noop_update message -> User_connector_common.respond_ok ()
       | Ok message when not (is_allowed_chat connector_config message.chat_id) ->
         User_connector_common.respond_ok ()
       | Ok message ->
         (match
            User_connector_common.env_value
              ~provider_id:connector.provider_id
              connector_config.bot_token_env
          with
          | Error err -> Json_response.respond_error err
          | Ok bot_token ->
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
               match user_text_from_message message with
               | Some ("/reset" | "/help" | "/start" as command) ->
                 handle_command
                   ~http_post
                   store
                   connector_config
                   ~bot_token
                   message
                   command
               | None ->
                 send_telegram_message
                   ?message_thread_id:message.message_thread_id
                   ~http_post
                   connector_config
                   ~bot_token
                   ~chat_id:message.chat_id
                   ~text:text_only_message
                 >>= (function
                  | Ok () -> User_connector_common.respond_ok ()
                  | Error err -> Json_response.respond_error err)
               | Some text ->
                 handle_text_message
                   ~http_post
                   store
                   connector_config
                   ~bot_token
                   ~authorization
                   message
                   text)))
;;
