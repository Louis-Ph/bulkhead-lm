let extract_token prefix authorization =
  if String.starts_with ~prefix authorization
  then
    Some
      (String.sub
         authorization
         (String.length prefix)
         (String.length authorization - String.length prefix))
  else None
;;

let authenticate store ~authorization =
  let auth_policy =
    store.Runtime_state.config.Config.security_policy.Security_policy.auth
  in
  match extract_token auth_policy.bearer_prefix authorization with
  | None -> Error (Domain_error.invalid_api_key ())
  | Some token ->
    let token_hash = Runtime_state.hash_token token in
    (match Runtime_state.find_principal store token_hash with
     | Some principal -> Ok principal
     | None -> Error (Domain_error.invalid_api_key ()))
;;
