open Lwt.Infix

type http_post = User_connector_common.http_post
type http_patch = User_connector_common.http_patch
type async_runner = (unit -> unit Lwt.t) -> unit

type inbound_interaction =
  { interaction_id : string
  ; application_id : string
  ; interaction_type : int
  ; token : string
  ; command_name : string option
  ; prompt : string option
  ; user_id : string
  ; user_display_name : string option
  ; channel_id : string option
  ; guild_id : string option
  }

let connector =
  { User_connector_common.channel_name = "Discord"
  ; provider_id = "discord-interactions"
  ; event_type = "connector.discord"
  ; session_prefix = "discord"
  }

let session_limits =
  User_connector_common.session_limits
    ~summary_intro:
      "Compressed memory from earlier in this Discord conversation. Use it as context, but prefer the recent verbatim turns if they differ."
;;

let default_system_prompt =
  "You are replying through Discord. Keep answers concise, readable in chat, and immediately useful. Avoid heavy formatting and wide tables unless the user explicitly asks for them."
;;

let help_message =
  String.concat
    "\n"
    [ "Use a slash command with one string option named message, prompt, text, query, or input."
    ; "Examples:"
    ; "/bulkhead message: Summarize this repository"
    ; "/bulkhead message: /reset"
    ; "/bulkhead message: /help"
    ]
;;

let reset_message = "Conversation memory cleared for this Discord session."

let invalid_command_message =
  "This Discord command needs a string option named message, prompt, text, query, or input."
;;

let empty_reply_message = "The assistant returned an empty reply."
let discord_api_base = "https://discord.com/api/v10"
let discord_json_content_type = "application/json; charset=utf-8"
let discord_message_max_chars = 1900
let discord_ephemeral_flag = 64
let discord_type_ping = 1
let discord_type_application_command = 2
let discord_type_autocomplete = 4
let discord_response_pong = 1
let discord_response_message = 4
let discord_response_deferred_message = 5
let discord_response_autocomplete = 8
let discord_signature_header = "x-signature-ed25519"
let discord_timestamp_header = "x-signature-timestamp"
let prompt_option_names = [ "message"; "prompt"; "text"; "query"; "input" ]

let find_webhook_config (config : Config.t) ~path =
  match config.user_connectors.discord with
  | Some connector when String.equal connector.webhook_path path -> Some connector
  | _ -> None
;;

let respond_json payload =
  Cohttp_lwt_unix.Server.respond_string
    ~status:`OK
    ~headers:(Cohttp.Header.of_list [ "content-type", discord_json_content_type ])
    ~body:(Yojson.Safe.to_string payload)
    ()
;;

let interaction_response ?flags ~response_type content =
  let data_fields =
    [ Some ("content", `String content)
    ; Some ("allowed_mentions", `Assoc [ "parse", `List [] ])
    ; Option.map (fun value -> "flags", `Int value) flags
    ]
    |> List.filter_map Fun.id
  in
  `Assoc [ "type", `Int response_type; "data", `Assoc data_fields ]
;;

let immediate_message_response ?flags content =
  interaction_response ?flags ~response_type:discord_response_message content
;;

let deferred_response ?flags () =
  let data_fields =
    [ Option.map (fun value -> "flags", `Int value) flags ] |> List.filter_map Fun.id
  in
  `Assoc [ "type", `Int discord_response_deferred_message; "data", `Assoc data_fields ]
;;

let autocomplete_response () =
  `Assoc
    [ "type", `Int discord_response_autocomplete
    ; "data", `Assoc [ "choices", `List [] ]
    ]
;;

let pong_response = `Assoc [ "type", `Int discord_response_pong ]

let string_member_required name json =
  match User_connector_common.string_of_scalar_opt (User_connector_common.member name json) with
  | Some value -> Ok value
  | None ->
    Error
      (Domain_error.invalid_request
         (Fmt.str "Discord interaction is missing %s." name))
;;

let object_member_or_null name json =
  Option.value (User_connector_common.member name json) ~default:`Null
;;

let parse_display_name json =
  match
    User_connector_common.string_opt (User_connector_common.member "global_name" json),
    User_connector_common.string_opt (User_connector_common.member "username" json)
  with
  | Some global_name, _ -> Some global_name
  | None, Some username -> Some username
  | None, None -> None
;;

let parse_user json =
  string_member_required "id" json
  |> Result.map (fun user_id -> user_id, parse_display_name json)
;;

let rec first_string_option options =
  let rec loop fallback = function
    | [] -> fallback
    | (`Assoc _ as option_json) :: rest ->
      let nested =
        match User_connector_common.member "options" option_json with
        | Some (`List nested_options) -> first_string_option nested_options
        | _ -> None
      in
      let value =
        User_connector_common.string_opt (User_connector_common.member "value" option_json)
      in
      let name =
        User_connector_common.string_opt (User_connector_common.member "name" option_json)
      in
      (match name, value with
       | Some option_name, Some option_value
         when List.mem (String.lowercase_ascii option_name) prompt_option_names ->
         Some option_value
       | _ ->
         let fallback =
           match fallback, value, nested with
           | Some _ as existing, _, _ -> existing
           | None, Some option_value, _ -> Some option_value
           | None, None, Some nested_value -> Some nested_value
           | None, None, None -> None
         in
         loop fallback rest)
    | _ :: rest -> loop fallback rest
  in
  loop None options
;;

let parse_prompt data_json =
  match User_connector_common.member "options" data_json with
  | Some (`List options) -> first_string_option options
  | _ -> None
;;

let parse_interaction json =
  Result.bind (string_member_required "id" json) (fun interaction_id ->
    Result.bind (string_member_required "application_id" json) (fun application_id ->
      Result.bind (string_member_required "token" json) (fun token ->
        match User_connector_common.int_opt (User_connector_common.member "type" json) with
        | None -> Error (Domain_error.invalid_request "Discord interaction is missing type.")
        | Some interaction_type ->
          let user_json =
            match object_member_or_null "member" json with
            | `Assoc _ as member_json -> object_member_or_null "user" member_json
            | _ -> object_member_or_null "user" json
          in
          (match user_json with
           | `Assoc _ as user_json ->
             Result.map
               (fun (user_id, user_display_name) ->
                 let data_json = object_member_or_null "data" json in
                 { interaction_id
                 ; application_id
                 ; interaction_type
                 ; token
                 ; command_name =
                     User_connector_common.string_opt
                       (User_connector_common.member "name" data_json)
                 ; prompt = parse_prompt data_json
                 ; user_id
                 ; user_display_name
                 ; channel_id =
                     User_connector_common.string_of_scalar_opt
                       (User_connector_common.member "channel_id" json)
                 ; guild_id =
                     User_connector_common.string_of_scalar_opt
                       (User_connector_common.member "guild_id" json)
                 })
               (parse_user user_json)
           | _ ->
             Error
               (Domain_error.invalid_request
                  "Discord interaction is missing the invoking user.")))))
;;

let hex_char_value = function
  | '0' .. '9' as ch -> Ok (Char.code ch - Char.code '0')
  | 'a' .. 'f' as ch -> Ok (10 + Char.code ch - Char.code 'a')
  | 'A' .. 'F' as ch -> Ok (10 + Char.code ch - Char.code 'A')
  | _ -> Error ()
;;

let decode_hex label value =
  let trimmed = String.trim value in
  let length = String.length trimmed in
  if length = 0
  then Error (Domain_error.invalid_request (Fmt.str "%s is empty." label))
  else if length mod 2 <> 0
  then Error (Domain_error.invalid_request (Fmt.str "%s must have even-length hex." label))
  else
    let bytes = Bytes.create (length / 2) in
    let rec loop index =
      if index >= length
      then Ok (Bytes.unsafe_to_string bytes)
      else
        match hex_char_value trimmed.[index], hex_char_value trimmed.[index + 1] with
        | Ok high, Ok low ->
          Bytes.set bytes (index / 2) (Char.chr ((high lsl 4) lor low));
          loop (index + 2)
        | _ ->
          Error
            (Domain_error.invalid_request
               (Fmt.str "%s contains non-hex characters." label))
    in
    loop 0
;;

let verify_signature raw_body req (connector_config : Config.discord_connector) =
  match
    Cohttp.Header.get (Cohttp.Request.headers req) discord_signature_header,
    Cohttp.Header.get (Cohttp.Request.headers req) discord_timestamp_header
  with
  | Some signature_hex, Some timestamp ->
    (match
       User_connector_common.env_value
         ~provider_id:connector.provider_id
         connector_config.public_key_env
     with
     | Error _ as error -> error
     | Ok public_key_hex ->
       (match decode_hex "Discord public key" public_key_hex with
        | Error _ as error -> error
        | Ok public_key_octets ->
          (match Mirage_crypto_ec.Ed25519.pub_of_octets public_key_octets with
           | Error _ ->
             Error
               (Domain_error.invalid_request
                  "Discord public key is not a valid Ed25519 public key.")
           | Ok public_key ->
             (match decode_hex "Discord request signature" signature_hex with
              | Error _ as error -> error
              | Ok signature ->
                if
                  Mirage_crypto_ec.Ed25519.verify
                    ~key:public_key
                    signature
                    ~msg:(timestamp ^ raw_body)
                then Ok ()
                else
                  Error
                    (Domain_error.operation_denied
                       "Discord interaction signature mismatch.")))))
  | _ ->
    Error
      (Domain_error.invalid_request
         "Discord interaction is missing signature headers.")
;;

let is_allowed config value allowed_values =
  allowed_values = []
  ||
  match value with
  | Some actual_value -> List.mem actual_value allowed_values
  | None -> false
;;

let interaction_allowed (connector_config : Config.discord_connector) interaction =
  is_allowed
    connector_config
    (Some interaction.application_id)
    connector_config.allowed_application_ids
  && is_allowed connector_config (Some interaction.user_id) connector_config.allowed_user_ids
  && is_allowed connector_config interaction.channel_id connector_config.allowed_channel_ids
  &&
  (connector_config.allowed_guild_ids = []
   ||
   match interaction.guild_id with
   | Some guild_id -> List.mem guild_id connector_config.allowed_guild_ids
   | None -> false)
;;

let connector_system_messages (connector_config : Config.discord_connector) interaction =
  let metadata_lines =
    [ Some ("Discord application id: " ^ interaction.application_id)
    ; Some ("Discord user id: " ^ interaction.user_id)
    ; Option.map (fun channel_id -> "Discord channel id: " ^ channel_id) interaction.channel_id
    ; Option.map (fun guild_id -> "Discord guild id: " ^ guild_id) interaction.guild_id
    ; Option.map (fun name -> "Discord user: " ^ name) interaction.user_display_name
    ; Option.map (fun name -> "Discord command: " ^ name) interaction.command_name
    ]
    |> List.filter_map Fun.id
  in
  User_connector_common.connector_system_messages
    ~channel_name:connector.User_connector_common.channel_name
    ~default_system_prompt
    ?system_prompt:connector_config.Config.system_prompt
    metadata_lines
;;

let interaction_subject interaction =
  String.concat
    ":"
    [ interaction.application_id
    ; Option.value interaction.guild_id ~default:"dm"
    ; Option.value interaction.channel_id ~default:"no-channel"
    ; interaction.user_id
    ]
;;

let interaction_webhook_uri application_id token suffix =
  Uri.of_string (discord_api_base ^ "/webhooks/" ^ application_id ^ "/" ^ token ^ suffix)
;;

let send_original_response
  ?(http_patch = User_connector_common.default_http_patch)
  ~application_id
  ~token
  ~text
  ()
  =
  let uri = interaction_webhook_uri application_id token "/messages/@original" in
  let headers = Cohttp.Header.of_list [ "content-type", "application/json" ] in
  let payload =
    `Assoc
      [ "content", `String text
      ; "allowed_mentions", `Assoc [ "parse", `List [] ]
      ]
  in
  http_patch uri ~headers payload
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
            (Fmt.str "Discord original response update failed: %s" body_text)))
;;

let send_followup_message
  ?(http_post = User_connector_common.default_http_post)
  ~application_id
  ~token
  ~text
  ()
  =
  let uri = interaction_webhook_uri application_id token "" in
  let headers = Cohttp.Header.of_list [ "content-type", "application/json" ] in
  let payload =
    `Assoc
      [ "content", `String text
      ; "allowed_mentions", `Assoc [ "parse", `List [] ]
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
            (Fmt.str "Discord follow-up message failed: %s" body_text)))
;;

let send_discord_reply
  ?(http_post = User_connector_common.default_http_post)
  ?(http_patch = User_connector_common.default_http_patch)
  interaction
  text
  =
  let chunks =
    User_connector_common.split_text_for_channel ~max_bytes:discord_message_max_chars text
  in
  match chunks with
  | [] ->
    send_original_response
      ~http_patch
      ~application_id:interaction.application_id
      ~token:interaction.token
      ~text:empty_reply_message
      ()
  | first_chunk :: rest_chunks ->
    send_original_response
      ~http_patch
      ~application_id:interaction.application_id
      ~token:interaction.token
      ~text:first_chunk
      ()
    >>= function
    | Error _ as error -> Lwt.return error
    | Ok () ->
      let rec send_rest = function
        | [] -> Lwt.return (Ok ())
        | chunk :: rest ->
          send_followup_message
            ~http_post
            ~application_id:interaction.application_id
            ~token:interaction.token
            ~text:chunk
            ()
          >>= (function
           | Ok () -> send_rest rest
           | Error _ as error -> Lwt.return error)
      in
      send_rest rest_chunks
;;

let append_delivery_error_audit
  store
  (connector_config : Config.discord_connector)
  ~authorization
  interaction
  err
  =
  User_connector_common.append_audit
    store
    connector
    ~authorization
    ~route_model:(Some connector_config.Config.route_model)
    ~status_code:err.Domain_error.status
    (User_connector_common.audit_details
       [ "result", `String "delivery_error"
       ; "application_id", `String interaction.application_id
       ; "user_id", `String interaction.user_id
       ; "error", Domain_error.to_openai_json err
       ])
;;

let fulfill_interaction
  ?(http_post = User_connector_common.default_http_post)
  ?(http_patch = User_connector_common.default_http_patch)
  store
  (connector_config : Config.discord_connector)
  ~authorization
  interaction
  prompt
  =
  let session_key =
    User_connector_common.build_session_key connector (interaction_subject interaction)
  in
  let conversation = Runtime_state.get_user_connector_session store ~session_key in
  let request : Openai_types.chat_request =
    { Openai_types.model = connector_config.Config.route_model
    ; messages =
        connector_system_messages connector_config interaction
        @ Session_memory.request_messages session_limits conversation ~pending_user:prompt
    ; stream = false
    ; max_tokens = None
    }
  in
  Router.dispatch_chat store ~authorization request
  >>= function
  | Ok response ->
    let assistant_text =
      match String.trim (User_connector_common.text_of_chat_response response) with
      | "" -> empty_reply_message
      | value -> value
    in
    let updated_conversation, _ =
      Session_memory.commit_exchange
        session_limits
        conversation
        ~user:prompt
        ~assistant:assistant_text
    in
    Runtime_state.set_user_connector_session store ~session_key updated_conversation;
    send_discord_reply ~http_post ~http_patch interaction assistant_text
    >>= (function
     | Ok () ->
       User_connector_common.append_audit
         store
         connector
         ~authorization
         ~route_model:(Some connector_config.Config.route_model)
         ~status_code:200
         (User_connector_common.audit_details
            [ "result", `String "ok"
            ; "response_model", `String response.model
            ; "application_id", `String interaction.application_id
            ; "user_id", `String interaction.user_id
            ]);
       Lwt.return_unit
     | Error err ->
       append_delivery_error_audit store connector_config ~authorization interaction err;
       Lwt.return_unit)
  | Error err ->
    User_connector_common.append_audit
      store
      connector
      ~authorization
      ~route_model:(Some connector_config.Config.route_model)
      ~status_code:err.status
      (User_connector_common.audit_details
         [ "result", `String "router_error"
         ; "application_id", `String interaction.application_id
         ; "user_id", `String interaction.user_id
         ; "error", Domain_error.to_openai_json err
         ]);
    send_discord_reply
      ~http_post
      ~http_patch
      interaction
      (User_connector_common.user_error_message err)
    >>= (function
     | Ok () -> Lwt.return_unit
     | Error delivery_error ->
       append_delivery_error_audit
         store
         connector_config
         ~authorization
         interaction
         delivery_error;
       Lwt.return_unit)
;;

let reset_session store interaction =
  let session_key =
    User_connector_common.build_session_key connector (interaction_subject interaction)
  in
  Runtime_state.clear_user_connector_session store ~session_key
;;

let effective_ephemeral_flag (connector_config : Config.discord_connector) =
  if connector_config.ephemeral_by_default then Some discord_ephemeral_flag else None
;;

let handle_inline_command store connector_config interaction command =
  let flags = effective_ephemeral_flag connector_config in
  let text =
    match command with
    | "/reset" ->
      reset_session store interaction;
      reset_message
    | "/help"
    | "/start" -> help_message
    | _ -> invalid_command_message
  in
  respond_json (immediate_message_response ?flags text)
;;

let handle_command
  ?(http_post = User_connector_common.default_http_post)
  ?(http_patch = User_connector_common.default_http_patch)
  ?(async_runner = Lwt.async)
  store
  (connector_config : Config.discord_connector)
  interaction
  command_text
  =
  if not (interaction_allowed connector_config interaction)
  then
    respond_json
      (immediate_message_response
         ?flags:(effective_ephemeral_flag connector_config)
         "This Discord context is not allowed by the connector configuration.")
  else
    match command_text with
    | "/reset" | "/help" | "/start" as command ->
      handle_inline_command store connector_config interaction command
    | _ ->
      (match
         User_connector_common.env_value
           ~provider_id:connector.provider_id
           connector_config.authorization_env
       with
       | Error err ->
         respond_json
           (immediate_message_response
              ?flags:(effective_ephemeral_flag connector_config)
              (User_connector_common.user_error_message err))
       | Ok authorization_raw ->
         let authorization =
           User_connector_common.normalized_authorization store authorization_raw
         in
         let job () =
           fulfill_interaction
             ~http_post
             ~http_patch
             store
             connector_config
             ~authorization
             interaction
             command_text
         in
         async_runner job;
         respond_json
           (deferred_response ?flags:(effective_ephemeral_flag connector_config) ()))
;;

let normalize_command interaction =
  match interaction.command_name, interaction.prompt with
  | Some ("help" | "bulkhead-help"), None -> Some "/help"
  | Some ("reset" | "bulkhead-reset"), None -> Some "/reset"
  | Some ("start" | "bulkhead-start"), None -> Some "/start"
  | _, Some prompt ->
    let trimmed = String.trim prompt in
    if trimmed = "" then None else Some trimmed
  | _ -> None
;;

let handle_webhook
  ?(http_post = User_connector_common.default_http_post)
  ?(http_patch = User_connector_common.default_http_patch)
  ?(async_runner = Lwt.async)
  store
  req
  body
  (connector_config : Config.discord_connector)
  =
  match Cohttp.Request.meth req with
  | `POST ->
    Request_body.read_request_text store body
    >>= (function
     | Error err -> Json_response.respond_error err
     | Ok raw_body ->
       (match verify_signature raw_body req connector_config with
        | Error err -> Json_response.respond_error err
        | Ok () ->
          (match Request_body.parse_json_string raw_body with
           | Error err -> Json_response.respond_error err
           | Ok json ->
             (match User_connector_common.int_opt (User_connector_common.member "type" json) with
              | Some value when value = discord_type_ping -> respond_json pong_response
              | _ ->
                (match parse_interaction json with
                 | Error err -> Json_response.respond_error err
                 | Ok interaction ->
                   (match interaction.interaction_type with
                    | value when value = discord_type_autocomplete ->
                      respond_json (autocomplete_response ())
                    | value when value = discord_type_application_command ->
                      (match normalize_command interaction with
                       | Some command_text ->
                         handle_command
                           ~http_post
                           ~http_patch
                           ~async_runner
                           store
                           connector_config
                           interaction
                           command_text
                       | None ->
                         respond_json
                           (immediate_message_response
                              ?flags:(effective_ephemeral_flag connector_config)
                              invalid_command_message))
                    | _ ->
                      respond_json
                        (immediate_message_response
                           ?flags:(effective_ephemeral_flag connector_config)
                           "Unsupported Discord interaction type for this connector.")))))))
  | _ ->
    Cohttp_lwt_unix.Server.respond_string
      ~status:`Method_not_allowed
      ~headers:(Cohttp.Header.of_list [ "content-type", "text/plain; charset=utf-8" ])
      ~body:"Method not allowed."
      ()
;;
