open Lwt.Infix

type http_post =
  Uri.t ->
  headers:Cohttp.Header.t ->
  Yojson.Safe.t ->
  (Cohttp.Response.t * string) Lwt.t

type http_get =
  Uri.t ->
  headers:Cohttp.Header.t ->
  (Cohttp.Response.t * string) Lwt.t

type http_patch =
  Uri.t ->
  headers:Cohttp.Header.t ->
  Yojson.Safe.t ->
  (Cohttp.Response.t * string) Lwt.t

type connector_descriptor =
  { channel_name : string
  ; provider_id : string
  ; event_type : string
  ; session_prefix : string
  }

let default_webhook_ok = `Assoc [ "ok", `Bool true ]

let session_limits ~summary_intro =
  { Session_memory.keep_recent_turns = Session_memory_defaults.keep_recent_turns
  ; compress_threshold_chars = Session_memory_defaults.compress_threshold_chars
  ; turn_excerpt_chars = Session_memory_defaults.turn_excerpt_chars
  ; summary_max_chars = Session_memory_defaults.summary_max_chars
  ; summary_intro
  }
;;

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None
;;

let int_opt = function
  | Some (`Int value) -> Some value
  | Some (`Intlit value) -> int_of_string_opt value
  | _ -> None
;;

let string_opt = function
  | Some (`String value) ->
    let trimmed = String.trim value in
    if trimmed = "" then None else Some trimmed
  | _ -> None
;;

let string_of_scalar_opt = function
  | Some (`String value) ->
    let trimmed = String.trim value in
    if trimmed = "" then None else Some trimmed
  | Some (`Int value) -> Some (string_of_int value)
  | Some (`Intlit value) -> Some value
  | _ -> None
;;

let env_value ~provider_id env_name =
  match Sys.getenv_opt env_name with
  | Some value when String.trim value <> "" -> Ok (String.trim value)
  | _ ->
    Error
      (Domain_error.upstream
         ~provider_id
         ("Missing environment variable " ^ env_name))
;;

let normalized_authorization store raw =
  let prefix =
    store.Runtime_state.config.Config.security_policy.Security_policy.auth.bearer_prefix
  in
  if String.starts_with ~prefix raw then raw else prefix ^ raw
;;

let principal_name store authorization =
  match Auth.authenticate store ~authorization with
  | Ok principal -> Some principal.Runtime_state.name
  | Error _ -> None
;;

let append_audit store connector ~authorization ~route_model ~status_code details =
  Runtime_state.append_audit_event
    store
    { Persistent_store.event_type = connector.event_type
    ; principal_name = principal_name store authorization
    ; route_model
    ; provider_id = Some connector.provider_id
    ; status_code
    ; details
    }
;;

let audit_details fields = `Assoc fields

let text_of_chat_response (response : Openai_types.chat_response) =
  response.choices
  |> List.filter_map (fun (choice : Openai_types.chat_choice) ->
    let content = String.trim choice.message.content in
    if content = "" then None else Some content)
  |> String.concat "\n"
;;

let connector_system_messages
  ~channel_name
  ~default_system_prompt
  ?system_prompt
  metadata_lines
  =
  let metadata_message : Openai_types.message list =
    if metadata_lines = []
    then []
    else
      [ ({ Openai_types.role = "system"; content = String.concat "\n" metadata_lines }
          : Openai_types.message)
      ]
  in
  let prompt_messages : Openai_types.message list =
    [ Some
        ({ Openai_types.role = "system"; content = default_system_prompt }
         : Openai_types.message)
    ; Option.map
        (fun content ->
          ({ Openai_types.role = "system"; content } : Openai_types.message))
        system_prompt
    ; Some
        ({ Openai_types.role = "system"; content = "Channel: " ^ channel_name }
         : Openai_types.message)
    ]
    |> List.filter_map Fun.id
  in
  prompt_messages @ metadata_message
;;

let build_session_key connector subject = connector.session_prefix ^ ":" ^ subject

let user_error_message (error : Domain_error.t) =
  match error.code with
  | "budget_exceeded" -> "The connector budget is exhausted for now. Try again later."
  | "rate_limited" -> "Too many requests are in flight right now. Try again in a moment."
  | "route_not_found" | "invalid_api_key" ->
    "This connector is not configured correctly yet."
  | _ -> "The assistant is temporarily unavailable on this connector. Try again shortly."
;;

let is_utf8_continuation_byte ch = Char.code ch land 0xC0 = 0x80

let utf8_safe_cut text max_bytes =
  let candidate = min max_bytes (String.length text) in
  if candidate >= String.length text
  then candidate
  else (
    let rec backtrack index =
      if index <= 0
      then candidate
      else if is_utf8_continuation_byte text.[index]
      then backtrack (index - 1)
      else index
    in
    backtrack candidate)
;;

let split_text_for_channel ?(max_bytes = 4000) text =
  let rec loop acc offset =
    if offset >= String.length text
    then List.rev acc
    else
      let remaining = String.length text - offset in
      let chunk_length = utf8_safe_cut (String.sub text offset remaining) max_bytes in
      let actual_length = if chunk_length <= 0 then min max_bytes remaining else chunk_length in
      let chunk = String.sub text offset actual_length in
      loop (chunk :: acc) (offset + actual_length)
  in
  if text = "" then [ "" ] else loop [] 0
;;

let constant_time_equal left right =
  let left_length = String.length left in
  let right_length = String.length right in
  let result = ref (left_length lxor right_length) in
  let iterations = max left_length right_length in
  for index = 0 to iterations - 1 do
    let left_char = if index < left_length then Char.code left.[index] else 0 in
    let right_char = if index < right_length then Char.code right.[index] else 0 in
    result := !result lor (left_char lxor right_char)
  done;
  !result = 0
;;

let default_http_post uri ~headers body =
  Cohttp_lwt_unix.Client.post
    ~headers
    ~body:(Cohttp_lwt.Body.of_string (Yojson.Safe.to_string body))
    uri
  >>= fun (response, body) ->
  Cohttp_lwt.Body.to_string body >|= fun body_text -> response, body_text
;;

let default_http_get uri ~headers =
  Cohttp_lwt_unix.Client.get ~headers uri
  >>= fun (response, body) ->
  Cohttp_lwt.Body.to_string body >|= fun body_text -> response, body_text
;;

let default_http_patch uri ~headers body =
  Cohttp_lwt_unix.Client.call
    ~headers
    ~body:(Cohttp_lwt.Body.of_string (Yojson.Safe.to_string body))
    `PATCH
    uri
  >>= fun (response, body) ->
  Cohttp_lwt.Body.to_string body >|= fun body_text -> response, body_text
;;

let respond_ok () = Json_response.respond_json default_webhook_ok
