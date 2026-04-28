module Patterns = struct
  let email = Str.regexp "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z][A-Za-z]+"
  let phone = Str.regexp "[+]?[0-9][0-9 ()-]+[0-9]"
  let ipv4 = Str.regexp "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"
  let national_id = Str.regexp "[0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]"

  let payment_card =
    Str.regexp
      "[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][ -]*[0-9][0-9 -]*"
  ;;

  let bearer = Str.regexp_case_fold "bearer[ \t]+[A-Za-z0-9_+/=-]+"
end

type rule =
  { name : string
  ; pattern : Str.regexp
  }

type match_count =
  { rule : string
  ; count : int
  }

type report =
  { redacted_text : string
  ; matches : match_count list
  }

let pattern_rule name pattern = { name; pattern }

let configured_pattern_rule (rule : Security_policy.privacy_pattern_rule) =
  if not rule.enabled
  then None
  else (
    match Str.regexp_case_fold rule.pattern with
    | pattern -> Some (pattern_rule ("pattern:" ^ rule.name) pattern)
    | exception _ -> None)
;;

let prefixed_secret_rule prefix =
  let trimmed = String.trim prefix in
  if trimmed = ""
  then None
  else Some (pattern_rule ("secret_prefix:" ^ trimmed) (Text_guard_common.prefixed_token_pattern trimmed))
;;

let literal_rule value =
  let trimmed = String.trim value in
  if trimmed = ""
  then None
  else Some (pattern_rule ("literal:" ^ trimmed) (Str.regexp_case_fold (Str.quote trimmed)))
;;

let rules
  ({ redact_email_addresses
   ; redact_phone_numbers
   ; redact_ipv4_addresses
   ; redact_national_ids
   ; redact_payment_cards
   ; secret_prefixes
   ; additional_literal_tokens
   ; pattern_rules
   ; _
   } : Security_policy.privacy_filter)
  =
  let builtins =
    [ if redact_email_addresses then Some (pattern_rule "email_address" Patterns.email) else None
    ; if redact_phone_numbers then Some (pattern_rule "phone_number" Patterns.phone) else None
    ; if redact_ipv4_addresses then Some (pattern_rule "ipv4_address" Patterns.ipv4) else None
    ; if redact_national_ids then Some (pattern_rule "national_id" Patterns.national_id) else None
    ; if redact_payment_cards then Some (pattern_rule "payment_card" Patterns.payment_card) else None
    ; Some (pattern_rule "bearer_token" Patterns.bearer)
    ]
    |> List.filter_map Fun.id
  in
  builtins
  @ List.filter_map prefixed_secret_rule secret_prefixes
  @ List.filter_map literal_rule additional_literal_tokens
  @ List.filter_map configured_pattern_rule pattern_rules
;;

let count_matches pattern text =
  let rec loop offset count =
    if offset >= String.length text
    then count
    else (
      match Str.search_forward pattern text offset with
      | _ ->
        let next_offset = max (offset + 1) (Str.match_end ()) in
        loop next_offset (count + 1)
      | exception Not_found -> count)
  in
  loop 0 0
;;

let filter_text_with_report (policy : Security_policy.privacy_filter) text =
  if not policy.Security_policy.enabled
  then { redacted_text = text; matches = [] }
  else (
    let replacement = policy.replacement in
    let redacted_text, matches =
      List.fold_left
        (fun (current_text, current_matches) rule ->
          let count = count_matches rule.pattern current_text in
          if count = 0
          then current_text, current_matches
          else
            ( Str.global_replace rule.pattern replacement current_text
            , { rule = rule.name; count } :: current_matches ))
        (text, [])
        (rules policy)
    in
    { redacted_text; matches = List.rev matches })
;;

let filter_text policy text = (filter_text_with_report policy text).redacted_text

let total_matches report =
  List.fold_left (fun total item -> total + item.count) 0 report.matches
;;

let filter_json policy json =
  let rec go = function
    | `Assoc fields -> `Assoc (List.map (fun (key, value) -> key, go value) fields)
    | `List values -> `List (List.map go values)
    | `String value -> `String (filter_text policy value)
    | other -> other
  in
  if not policy.Security_policy.enabled then json else go json
;;

let filter_message_extra policy fields =
  List.map (fun (key, value) -> key, filter_json policy value) fields
;;

let filter_session (policy : Security_policy.privacy_filter) (session : Session_memory.t) =
  if not policy.enabled
  then session
  else
    { session with
      summary = Option.map (filter_text policy) session.summary
    ; recent_turns =
        List.map
          (fun (turn : Session_memory.turn) ->
            { turn with content = filter_text policy turn.content })
          session.recent_turns
    }
;;

let filter_chat_request (policy : Security_policy.privacy_filter) (request : Openai_types.chat_request) =
  if not policy.enabled
  then request
  else
    { request with
      messages =
        List.map
          (fun (message : Openai_types.message) ->
            { message with
              content = filter_text policy message.content
            ; extra = filter_message_extra policy message.extra
            })
          request.messages
    ; extra = filter_message_extra policy request.extra
    }
;;

let filter_embeddings_request
  (policy : Security_policy.privacy_filter)
  (request : Openai_types.embeddings_request)
  =
  if not policy.enabled
  then request
  else { request with input = List.map (filter_text policy) request.input }
;;

let filter_chat_response
  (policy : Security_policy.privacy_filter)
  (response : Openai_types.chat_response)
  =
  if not policy.enabled
  then response
  else
    { response with
      choices =
        List.map
          (fun (choice : Openai_types.chat_choice) ->
            { choice with
              message =
                { choice.message with
                  content = filter_text policy choice.message.content
                ; extra = filter_message_extra policy choice.message.extra
                }
            })
          response.choices
    }
;;

let filter_stream_event policy = function
  | Provider_client.Text_delta text ->
    Provider_client.Text_delta (filter_text policy text)
  | Provider_client.Reasoning_delta text ->
    Provider_client.Reasoning_delta (filter_text policy text)
;;

let report_to_yojson report =
  `Assoc
    [ "redacted_text", `String report.redacted_text
    ; "total_replacements", `Int (total_matches report)
    ; ( "matches"
      , `List
          (List.map
             (fun item ->
               `Assoc [ "rule", `String item.rule; "count", `Int item.count ])
             report.matches) )
    ]
;;
