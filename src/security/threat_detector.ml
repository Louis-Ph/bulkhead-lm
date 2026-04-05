let ensure_text_is_safe policy text =
  if not policy.Security_policy.enabled
  then Ok ()
  else
    let signals =
      [ "prompt_injection", policy.prompt_injection_signals
      ; "credential_exfiltration", policy.credential_exfiltration_signals
      ; "tool_abuse", policy.tool_abuse_signals
      ]
    in
    let rec loop = function
      | [] -> Ok ()
      | (category, values) :: rest ->
        (match Text_guard_common.first_literal_match text values with
         | Some signal -> Error (Domain_error.threat_detected ~category ~signal ())
         | None -> loop rest)
    in
    loop signals
;;

let ensure_chat_request_is_safe policy (request : Openai_types.chat_request) =
  request.messages
  |> List.map (fun (message : Openai_types.message) -> message.content)
  |> String.concat "\n"
  |> ensure_text_is_safe policy
;;

let ensure_embeddings_request_is_safe policy (request : Openai_types.embeddings_request) =
  request.input |> String.concat "\n" |> ensure_text_is_safe policy
;;
