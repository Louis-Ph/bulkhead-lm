open Lwt.Infix

type http_post = User_connector_common.http_post

type source_scope =
  | User of string
  | Group of string
  | Room of string

type inbound_event =
  { event_type : string
  ; reply_token : string option
  ; source_scope : source_scope
  ; user_id : string option
  ; message_id : string option
  ; message_text : string option
  ; postback_data : string option
  }

let connector =
  { User_connector_common.channel_name = "LINE"
  ; provider_id = "line-messaging-api"
  ; event_type = "connector.line"
  ; session_prefix = "line"
  }

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this LINE conversation. Use it as context, but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through LINE. Keep answers concise, readable on mobile, and immediately useful."
;;

let help_message =
  String.concat
    "\n"
    [ "Send a text message to talk with the assistant."
    ; "Commands:"
    ; "/reset - clear this LINE conversation memory"
    ; "/help - show this help"
    ]
;;

let onboarding_message =
  "I am connected to BulkheadLM on LINE. Send a text message or use /help."
;;

let reset_message = "Conversation memory cleared for this LINE conversation."
let text_only_message = "Send a text message for now. Media, stickers, and files are not handled by this connector yet."
let reply_message_path = "/message/reply"
let max_outbound_text_bytes = 4000
let max_reply_messages = 5
let truncated_suffix = "\n\n[Reply truncated for LINE]"

let find_webhook_config (config : Config.t) ~path =
  match config.user_connectors.line with
  | Some connector when String.equal connector.webhook_path path -> Some connector
  | _ -> None
;;

let source_scope_kind = function
  | User _ -> "user"
  | Group _ -> "group"
  | Room _ -> "room"
;;

let source_scope_id = function
  | User id | Group id | Room id -> id
;;

let session_subject event =
  source_scope_kind event.source_scope ^ ":" ^ source_scope_id event.source_scope
;;

let parse_source_scope source_json =
  match User_connector_common.string_opt (User_connector_common.member "type" source_json) with
  | Some "user" ->
    (match User_connector_common.string_opt (User_connector_common.member "userId" source_json) with
     | Some user_id -> Ok (User user_id)
     | None -> Error (Domain_error.invalid_request "LINE source.user is missing userId."))
  | Some "group" ->
    (match User_connector_common.string_opt (User_connector_common.member "groupId" source_json) with
     | Some group_id -> Ok (Group group_id)
     | None -> Error (Domain_error.invalid_request "LINE source.group is missing groupId."))
  | Some "room" ->
    (match User_connector_common.string_opt (User_connector_common.member "roomId" source_json) with
     | Some room_id -> Ok (Room room_id)
     | None -> Error (Domain_error.invalid_request "LINE source.room is missing roomId."))
  | Some source_type ->
    Error
      (Domain_error.invalid_request
         ("Unsupported LINE source type: " ^ source_type))
  | None -> Error (Domain_error.invalid_request "LINE event is missing source.type.")
;;

let parse_message_payload event_json =
  match User_connector_common.member "message" event_json with
  | Some (`Assoc _ as message_json) ->
    let message_id =
      User_connector_common.string_of_scalar_opt (User_connector_common.member "id" message_json)
    in
    let message_text =
      match User_connector_common.string_opt (User_connector_common.member "type" message_json) with
      | Some "text" ->
        User_connector_common.string_opt (User_connector_common.member "text" message_json)
      | _ -> None
    in
    message_id, message_text
  | _ -> None, None
;;

let parse_postback_data event_json =
  match User_connector_common.member "postback" event_json with
  | Some (`Assoc _ as postback_json) ->
    User_connector_common.string_opt (User_connector_common.member "data" postback_json)
  | _ -> None
;;

let parse_event event_json =
  let source_json =
    Option.value (User_connector_common.member "source" event_json) ~default:`Null
  in
  match User_connector_common.string_opt (User_connector_common.member "type" event_json) with
  | None -> Error (Domain_error.invalid_request "LINE event is missing type.")
  | Some event_type ->
    (match parse_source_scope source_json with
     | Error _ as error -> error
     | Ok source_scope ->
       let message_id, message_text = parse_message_payload event_json in
       Ok
         { event_type
         ; reply_token =
             User_connector_common.string_opt
               (User_connector_common.member "replyToken" event_json)
         ; source_scope
         ; user_id =
             User_connector_common.string_opt (User_connector_common.member "userId" source_json)
         ; message_id
         ; message_text
         ; postback_data = parse_postback_data event_json
         })
;;

let parse_inbound_events json =
  match User_connector_common.member "events" json with
  | Some (`List events) ->
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | (`Assoc _ as event_json) :: rest ->
        (match parse_event event_json with
         | Ok event -> loop (event :: acc) rest
         | Error _ as error -> error)
      | _ :: _ -> Error (Domain_error.invalid_request "Malformed LINE event payload.")
    in
    loop [] events
  | _ -> Error (Domain_error.invalid_request "LINE webhook is missing events.")
;;

let verify_signature (connector_config : Config.line_connector) raw_body req =
  match
    User_connector_common.env_value
      ~provider_id:connector.provider_id
      connector_config.channel_secret_env
  with
  | Error _ as error -> error
  | Ok channel_secret ->
    let presented =
      Cohttp.Header.get (Cohttp.Request.headers req) "x-line-signature"
      |> Option.value ~default:""
    in
    let expected =
      Digestif.SHA256.(to_raw_string (hmac_string ~key:channel_secret raw_body))
      |> Base64.encode_exn
    in
    if User_connector_common.constant_time_equal presented expected
    then Ok ()
    else Error (Domain_error.operation_denied "LINE webhook signature mismatch.")
;;

let trim_to_max_bytes text max_bytes =
  if String.length text <= max_bytes
  then text
  else String.sub text 0 (User_connector_common.utf8_safe_cut text max_bytes)
;;

let prepare_reply_chunks text =
  let chunks =
    User_connector_common.split_text_for_channel
      ~max_bytes:max_outbound_text_bytes
      text
  in
  let rec take acc remaining count =
    match remaining, count with
    | _, 0 -> List.rev acc, remaining
    | [], _ -> List.rev acc, []
    | chunk :: rest, _ -> take (chunk :: acc) rest (count - 1)
  in
  let selected_chunks, remaining_chunks = take [] chunks max_reply_messages in
  match remaining_chunks with
  | [] -> selected_chunks
  | _ ->
    let prefix, last_chunk =
      match List.rev selected_chunks with
      | [] -> [], ""
      | last_chunk :: rev_prefix -> List.rev rev_prefix, last_chunk
    in
    let merged_tail =
      last_chunk ^ String.concat "" remaining_chunks ^ truncated_suffix
      |> fun value -> trim_to_max_bytes value max_outbound_text_bytes
    in
    prefix @ [ merged_tail ]
;;

let send_line_message
  ?(http_post = User_connector_common.default_http_post)
  (connector_config : Config.line_connector)
  ~access_token
  ~reply_token
  ~text
  =
  let uri =
    Uri.of_string (connector_config.Config.api_base ^ reply_message_path)
  in
  let headers =
    Cohttp.Header.of_list
      [ "content-type", "application/json"
      ; "authorization", "Bearer " ^ access_token
      ]
  in
  let payload =
    `Assoc
      [ "replyToken", `String reply_token
      ; ( "messages"
        , `List
            (prepare_reply_chunks text
             |> List.map (fun chunk ->
               `Assoc [ "type", `String "text"; "text", `String chunk ])) )
      ]
  in
  http_post uri ~headers payload
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
            (Fmt.str "LINE reply API failed with status %d: %s" status body_text)))
;;

let connector_system_messages (connector_config : Config.line_connector) event =
  let metadata_lines =
    [ Some ("LINE source type: " ^ source_scope_kind event.source_scope)
    ; Some ("LINE source id: " ^ source_scope_id event.source_scope)
    ; Option.map (fun user_id -> "LINE user id: " ^ user_id) event.user_id
    ]
    |> List.filter_map Fun.id
  in
  User_connector_common.connector_system_messages
    ~channel_name:connector.User_connector_common.channel_name
    ~default_system_prompt
    ?system_prompt:connector_config.Config.system_prompt
    metadata_lines
;;

let is_allowed_source (connector_config : Config.line_connector) event =
  match event.source_scope with
  | User user_id ->
    connector_config.Config.allowed_user_ids = []
    || List.mem user_id connector_config.Config.allowed_user_ids
  | Group group_id ->
    connector_config.Config.allowed_group_ids = []
    || List.mem group_id connector_config.Config.allowed_group_ids
  | Room room_id ->
    connector_config.Config.allowed_room_ids = []
    || List.mem room_id connector_config.Config.allowed_room_ids
;;

let user_text_from_event event =
  [ event.message_text; event.postback_data ]
  |> List.find_map (function
    | Some value ->
      let trimmed = String.trim value in
      if trimmed = "" then None else Some trimmed
    | None -> None)
;;

let event_requires_response event =
  Option.is_some event.reply_token
  &&
  match event.event_type with
  | "message" | "postback" | "follow" | "join" -> true
  | _ -> false
;;

let send_reply
  ?(http_post = User_connector_common.default_http_post)
  connector_config
  ~access_token
  event
  text
  =
  match event.reply_token with
  | None -> Lwt.return (Ok ())
  | Some reply_token ->
    send_line_message
      ~http_post
      connector_config
      ~access_token
      ~reply_token
      ~text
;;

let handle_command
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.line_connector)
  ~access_token
  event
  command
  =
  let session_key =
    User_connector_common.build_session_key connector (session_subject event)
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
  else send_reply ~http_post connector_config ~access_token event reply_text
;;

let handle_text_message
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.line_connector)
  ~access_token
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
    User_connector_common.append_audit
      store
      connector
      ~authorization
      ~route_model:(Some connector_config.route_model)
      ~status_code:200
      (User_connector_common.audit_details
         [ "result", `String "ok"
         ; "response_model", `String response.model
         ; "source_type", `String (source_scope_kind event.source_scope)
         ; "source_id", `String (source_scope_id event.source_scope)
         ]
         |> fun details ->
         match event.message_id with
         | Some message_id ->
           (match details with
            | `Assoc fields -> `Assoc (("message_id", `String message_id) :: fields)
            | _ -> details)
         | None -> details);
    send_reply ~http_post connector_config ~access_token event assistant_text
  | Error err ->
    User_connector_common.append_audit
      store
      connector
      ~authorization
      ~route_model:(Some connector_config.route_model)
      ~status_code:err.status
      (User_connector_common.audit_details
         [ "result", `String "router_error"
         ; "source_type", `String (source_scope_kind event.source_scope)
         ; "source_id", `String (source_scope_id event.source_scope)
         ; "error", Domain_error.to_openai_json err
         ]);
    send_reply
      ~http_post
      connector_config
      ~access_token
      event
      (User_connector_common.user_error_message err)
;;

let handle_single_event
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.line_connector)
  ~access_token
  ~authorization
  event
  =
  if not (is_allowed_source connector_config event)
  then Lwt.return (Ok ())
  else
    match event.event_type, user_text_from_event event with
    | ("follow" | "join"), _ ->
      send_reply ~http_post connector_config ~access_token event onboarding_message
    | ("message" | "postback"), Some ("/reset" | "/help" | "/start" as command) ->
      handle_command ~http_post store connector_config ~access_token event command
    | ("message" | "postback"), None ->
      send_reply ~http_post connector_config ~access_token event text_only_message
    | ("message" | "postback"), Some text ->
      handle_text_message
        ~http_post
        store
        connector_config
        ~access_token
        ~authorization
        event
        text
    | _ -> Lwt.return (Ok ())
;;

let handle_events
  ?(http_post = User_connector_common.default_http_post)
  store
  (connector_config : Config.line_connector)
  ~access_token
  ~authorization
  events
  =
  let rec loop = function
    | [] -> User_connector_common.respond_ok ()
    | event :: rest ->
      handle_single_event
        ~http_post
        store
        connector_config
        ~access_token
        ~authorization
        event
      >>= function
      | Ok () -> loop rest
      | Error err -> Json_response.respond_error err
  in
  loop events
;;

let handle_webhook
  ?(http_post = User_connector_common.default_http_post)
  store
  req
  body
  (connector_config : Config.line_connector)
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
            (match parse_inbound_events json with
             | Error err -> Json_response.respond_error err
             | Ok events ->
               let actionable_events =
                 List.filter
                   (fun event ->
                     is_allowed_source connector_config event && event_requires_response event)
                   events
               in
               if actionable_events = []
               then User_connector_common.respond_ok ()
               else
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
                         User_connector_common.normalized_authorization
                           store
                           authorization_raw
                       in
                       handle_events
                         ~http_post
                         store
                         connector_config
                         ~access_token
                         ~authorization
                         actionable_events))))))
  | _ ->
    Cohttp_lwt_unix.Server.respond_string
      ~status:`Method_not_allowed
      ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
      ~body:"Method not allowed."
      ()
;;
