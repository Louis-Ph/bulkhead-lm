open Lwt.Infix

type http_post = User_connector_common.http_post

type delivery_endpoint =
  | Account_messages of string
  | Me_messages

type inbound_message =
  { object_kind : string
  ; account_id : string
  ; sender_id : string
  ; recipient_id : string option
  ; message_id : string option
  ; text : string option
  ; quick_reply_payload : string option
  ; postback_payload : string option
  ; timestamp_ms : int option
  }

let webhook_signature_header = "x-hub-signature-256"
let graph_api_default_base = "https://graph.facebook.com/v23.0"
let response_messaging_type = "RESPONSE"
let max_outbound_text_bytes = 1000

let graph_api_uri api_base = function
  | Account_messages account_id ->
    Uri.of_string (Fmt.str "%s/%s/messages" api_base account_id)
  | Me_messages -> Uri.of_string (Fmt.str "%s/me/messages" api_base)
;;

let query_param req name =
  Uri.get_query_param (Cohttp.Request.uri req) name |> Option.map String.trim
;;

let handle_verification req ~provider_id verify_token_env =
  match
    query_param req "hub.mode",
    query_param req "hub.verify_token",
    query_param req "hub.challenge"
  with
  | Some "subscribe", Some presented_token, Some challenge ->
    (match User_connector_common.env_value ~provider_id verify_token_env with
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
      ~body:"Invalid Meta webhook verification request."
      ()
;;

let verify_signature ~provider_id ?app_secret_env raw_body req =
  match app_secret_env with
  | None -> Ok ()
  | Some env_name ->
    (match User_connector_common.env_value ~provider_id env_name with
     | Error err -> Error err
     | Ok app_secret ->
       let presented =
         Cohttp.Header.get (Cohttp.Request.headers req) webhook_signature_header
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
       else Error (Domain_error.operation_denied "Meta webhook signature mismatch."))
;;

let parse_event_message event_json =
  match User_connector_common.member "message" event_json with
  | Some (`Assoc _ as message_json) ->
    let text =
      User_connector_common.string_opt (User_connector_common.member "text" message_json)
    in
    let quick_reply_payload =
      match User_connector_common.member "quick_reply" message_json with
      | Some (`Assoc _ as quick_reply_json) ->
        User_connector_common.string_opt (User_connector_common.member "payload" quick_reply_json)
      | _ -> None
    in
    let message_id =
      User_connector_common.string_opt (User_connector_common.member "mid" message_json)
    in
    text, quick_reply_payload, message_id
  | _ -> None, None, None
;;

let parse_event_postback event_json =
  match User_connector_common.member "postback" event_json with
  | Some (`Assoc _ as postback_json) ->
    User_connector_common.string_opt (User_connector_common.member "payload" postback_json)
  | _ -> None
;;

let parse_single_event ~object_kind ~entry_id event_json =
  let sender_json =
    Option.value (User_connector_common.member "sender" event_json) ~default:`Null
  in
  let recipient_json =
    Option.value (User_connector_common.member "recipient" event_json) ~default:`Null
  in
  match
    User_connector_common.string_of_scalar_opt
      (User_connector_common.member "id" sender_json)
  with
  | None -> None
  | Some sender_id ->
    let recipient_id =
      User_connector_common.string_of_scalar_opt
        (User_connector_common.member "id" recipient_json)
    in
    let account_id = Option.value recipient_id ~default:entry_id in
    if String.trim account_id = ""
    then None
    else
      let text, quick_reply_payload, message_id = parse_event_message event_json in
      Some
        { object_kind
        ; account_id
        ; sender_id
        ; recipient_id
        ; message_id
        ; text
        ; quick_reply_payload
        ; postback_payload = parse_event_postback event_json
        ; timestamp_ms =
            User_connector_common.int_opt (User_connector_common.member "timestamp" event_json)
        }
;;

let parse_entry ~object_kind entry_json =
  let entry_id =
    Option.value
      (User_connector_common.string_of_scalar_opt (User_connector_common.member "id" entry_json))
      ~default:""
  in
  match User_connector_common.member "messaging" entry_json with
  | Some (`List events) ->
    events
    |> List.filter_map (function
      | `Assoc _ as event_json -> parse_single_event ~object_kind ~entry_id event_json
      | _ -> None)
  | _ -> []
;;

let parse_inbound_messages ~expected_object json =
  match User_connector_common.string_opt (User_connector_common.member "object" json) with
  | Some object_kind when String.equal object_kind expected_object ->
    (match User_connector_common.member "entry" json with
     | Some (`List entries) ->
       entries
       |> List.concat_map (function
         | `Assoc _ as entry_json -> parse_entry ~object_kind entry_json
         | _ -> [])
       |> fun messages -> Ok messages
     | _ -> Ok [])
  | Some _ ->
    Error
      (Domain_error.invalid_request
         (Fmt.str "Unexpected Meta webhook object. Expected %s." expected_object))
  | None -> Error (Domain_error.invalid_request "Meta webhook is missing object.")
;;

let user_text_from_message message =
  let first_non_empty =
    [ message.text; message.quick_reply_payload; message.postback_payload ]
    |> List.find_map (function
      | Some value ->
        let trimmed = String.trim value in
        if trimmed = "" then None else Some trimmed
      | None -> None)
  in
  first_non_empty
;;

let send_text_message
  ?(http_post = User_connector_common.default_http_post)
  ?messaging_type
  ~provider_id
  ~api_base
  ~access_token
  ~endpoint
  ~recipient_id
  ~text
  ()
  =
  let send_one chunk =
    let uri = graph_api_uri api_base endpoint in
    let headers =
      Cohttp.Header.of_list
        [ "content-type", "application/json"
        ; "authorization", "Bearer " ^ access_token
        ]
    in
    let fields =
      [ "recipient", `Assoc [ "id", `String recipient_id ]
      ; "message", `Assoc [ "text", `String chunk ]
      ]
      @
      match messaging_type with
      | Some value -> [ "messaging_type", `String value ]
      | None -> []
    in
    http_post uri ~headers (`Assoc fields)
    >>= fun (response, body_text) ->
    let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
    if status >= 200 && status < 300
    then Lwt.return (Ok ())
    else
      Lwt.return
        (Error
           (Domain_error.upstream_status
              ~provider_id
              ~status
              (Fmt.str "Meta messages API failed with status %d: %s" status body_text)))
  in
  let rec send_all = function
    | [] -> Lwt.return (Ok ())
    | chunk :: rest ->
      send_one chunk
      >>= (function
       | Ok () -> send_all rest
       | Error err -> Lwt.return (Error err))
  in
  send_all
    (User_connector_common.split_text_for_channel ~max_bytes:max_outbound_text_bytes text)
;;
