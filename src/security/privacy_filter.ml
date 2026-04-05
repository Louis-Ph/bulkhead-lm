module Patterns = struct
  let email = Str.regexp "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z][A-Za-z]+"
  let phone = Str.regexp "\\+?[0-9][0-9 ()-]\\{8,\\}[0-9]"
  let ipv4 = Str.regexp "[0-9]\\{1,3\\}\\(\\.[0-9]\\{1,3\\}\\)\\{3\\}"
  let national_id = Str.regexp "[0-9]\\{3\\}-[0-9]\\{2\\}-[0-9]\\{4\\}"
  let payment_card = Str.regexp "\\([0-9][ -]*\\)\\{13,19\\}"
  let bearer = Str.regexp_case_fold "bearer[ \t]+[^ \t\r\n,;]+"
end

let replace_if enabled pattern ~replacement text =
  if enabled then Str.global_replace pattern replacement text else text
;;

let filter_text policy text =
  if not policy.Security_policy.enabled
  then text
  else (
    let replacement = policy.replacement in
    text
    |> replace_if policy.redact_email_addresses Patterns.email ~replacement
    |> replace_if policy.redact_phone_numbers Patterns.phone ~replacement
    |> replace_if policy.redact_ipv4_addresses Patterns.ipv4 ~replacement
    |> replace_if policy.redact_national_ids Patterns.national_id ~replacement
    |> replace_if policy.redact_payment_cards Patterns.payment_card ~replacement
    |> replace_if true Patterns.bearer ~replacement
    |> Text_guard_common.redact_prefixed_tokens ~replacement policy.secret_prefixes
    |> Text_guard_common.redact_literal_matches
         ~replacement
         policy.additional_literal_tokens)
;;

let filter_chat_request policy (request : Openai_types.chat_request) =
  if not policy.Security_policy.enabled
  then request
  else
    { request with
      messages =
        List.map
          (fun (message : Openai_types.message) ->
            { message with content = filter_text policy message.content })
          request.messages
    }
;;

let filter_embeddings_request policy (request : Openai_types.embeddings_request) =
  if not policy.Security_policy.enabled
  then request
  else { request with input = List.map (filter_text policy) request.input }
;;

let filter_chat_response policy (response : Openai_types.chat_response) =
  if not policy.Security_policy.enabled
  then response
  else
    { response with
      choices =
        List.map
          (fun (choice : Openai_types.chat_choice) ->
            { choice with
              message =
                { choice.message with content = filter_text policy choice.message.content }
            })
          response.choices
    }
;;
