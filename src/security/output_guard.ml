module Patterns = struct
  let private_key_block =
    Str.regexp_case_fold "-----begin \\(openssh \\)?private key-----"
  ;;
end

let ensure_text_is_safe policy text =
  if not policy.Security_policy.enabled
  then Ok ()
  else if Text_guard_common.contains Patterns.private_key_block text
  then Error (Domain_error.unsafe_output_blocked ~signal:"private_key_material" ())
  else
    match Text_guard_common.first_literal_match text policy.blocked_substrings with
    | Some signal -> Error (Domain_error.unsafe_output_blocked ~signal ())
    | None ->
      (match Text_guard_common.first_prefixed_token_match text policy.blocked_secret_prefixes with
       | Some signal -> Error (Domain_error.unsafe_output_blocked ~signal ())
       | None -> Ok ())
;;

let ensure_chat_response_is_safe policy (response : Openai_types.chat_response) =
  response.choices
  |> List.map (fun (choice : Openai_types.chat_choice) -> choice.message.content)
  |> String.concat "\n"
  |> ensure_text_is_safe policy
;;
