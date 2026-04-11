open Lwt.Infix

type http_get = User_connector_common.http_get

type verified_token =
  { subject : string option
  ; email : string option
  }

let chat_service_account = "chat@system.gserviceaccount.com"
let accepted_issuers = [ "accounts.google.com"; "https://accounts.google.com" ]

let verification_error message =
  Domain_error.make
    ~retry_disposition:Domain_error.Non_retryable
    ~code:"unauthorized_connector_request"
    ~status:401
    ~error_type:"authentication_error"
    message
;;

let split_token token =
  match String.split_on_char '.' token with
  | [ header; payload; signature ] -> Ok (header, payload, signature)
  | _ -> Error (verification_error "Google Chat bearer token is not a valid JWT.")
;;

let decode_base64url input =
  Base64.decode ~pad:false ~alphabet:Base64.uri_safe_alphabet input
  |> Result.map_error (fun (`Msg message) ->
    verification_error ("Unable to decode Google Chat bearer token: " ^ message))
;;

let decode_json_part part =
  match decode_base64url part with
  | Error _ as error -> error
  | Ok decoded ->
    (try Ok (Yojson.Safe.from_string decoded) with
     | _exn ->
       Error (verification_error "Google Chat bearer token contains malformed JSON."))
;;

let string_member name json =
  match User_connector_common.member name json with
  | Some (`String value) when String.trim value <> "" -> Ok (String.trim value)
  | _ ->
    Error
      (verification_error
         (Fmt.str "Google Chat bearer token is missing claim %s." name))
;;

let optional_string_member name json =
  match User_connector_common.member name json with
  | Some (`String value) ->
    let trimmed = String.trim value in
    if trimmed = "" then None else Some trimmed
  | _ -> None
;;

let int64_member name json =
  match User_connector_common.member name json with
  | Some (`Int value) -> Ok (Int64.of_int value)
  | Some (`Intlit value) ->
    (match Int64.of_string_opt value with
     | Some parsed -> Ok parsed
     | None ->
       Error
         (verification_error
            (Fmt.str "Google Chat bearer token claim %s is invalid." name)))
  | _ ->
    Error
      (verification_error
         (Fmt.str "Google Chat bearer token is missing claim %s." name))
;;

let load_certificates ?(http_get = User_connector_common.default_http_get) certs_url =
  let uri = Uri.of_string certs_url in
  let headers = Cohttp.Header.of_list [ "accept", "application/json" ] in
  http_get uri ~headers
  >>= fun (response, body_text) ->
  let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
  if status < 200 || status >= 300
  then
    Lwt.return
      (Error
         (Domain_error.upstream_status
            ~provider_id:"google-chat-id-token"
            ~status
            (Fmt.str "Unable to fetch Google Chat ID token certificates: %s" body_text)))
  else
    try
      let json = Yojson.Safe.from_string body_text in
      match json with
      | `Assoc fields ->
        let certificates =
          fields
          |> List.filter_map (fun (kid, value) ->
            match value with
            | `String certificate_pem when String.trim certificate_pem <> "" ->
              Some (kid, certificate_pem)
            | _ -> None)
        in
        Lwt.return (Ok certificates)
      | _ ->
        Lwt.return
          (Error
             (Domain_error.upstream
                ~provider_id:"google-chat-id-token"
                "Google certificate endpoint returned malformed JSON."))
    with
    | _exn ->
      Lwt.return
        (Error
           (Domain_error.upstream
              ~provider_id:"google-chat-id-token"
              "Google certificate endpoint returned malformed JSON."))
;;

let verify_signature certificates ~header_part ~payload_part ~signature_part header_json =
  match string_member "kid" header_json with
  | Error _ as error -> error
  | Ok kid ->
    (match List.assoc_opt kid certificates with
     | None ->
       Error
         (verification_error
            "Google Chat bearer token references an unknown signing key.")
     | Some certificate_pem ->
       (match X509.Certificate.decode_pem certificate_pem with
        | Error (`Msg message) ->
          Error
            (Domain_error.upstream
               ~provider_id:"google-chat-id-token"
               ("Unable to decode Google signing certificate: " ^ message))
        | Ok certificate ->
          let public_key = X509.Certificate.public_key certificate in
          (match decode_base64url signature_part with
           | Error _ as error -> error
           | Ok signature ->
             X509.Public_key.verify
               `SHA256
               ~scheme:`RSA_PKCS1
               ~signature
               public_key
               (`Message (header_part ^ "." ^ payload_part))
             |> Result.map_error (fun (`Msg _message) ->
               verification_error "Google Chat bearer token signature verification failed."))))
;;

let validate_claims (auth_config : Config.google_chat_id_token_auth) payload_json =
  match int64_member "exp" payload_json with
  | Error _ as error -> error
  | Ok exp ->
    let now = Unix.gettimeofday () |> Int64.of_float in
    if Int64.compare exp now <= 0
    then Error (verification_error "Google Chat bearer token has expired.")
    else (
      match string_member "aud" payload_json with
      | Error _ as error -> error
      | Ok audience ->
        if not (String.equal audience auth_config.Config.audience)
        then
          Error
            (verification_error
               "Google Chat bearer token audience does not match this connector endpoint.")
        else
          let issuer = optional_string_member "iss" payload_json in
          let email = optional_string_member "email" payload_json in
          let email_verified =
            match User_connector_common.member "email_verified" payload_json with
            | Some (`Bool value) -> value
            | _ -> true
          in
          if not email_verified
          then
            Error
              (verification_error
                 "Google Chat bearer token email claim is not verified.")
          else if
            not
              (match issuer with
               | None -> true
               | Some value -> List.mem value accepted_issuers)
          then
            Error
              (verification_error
                 "Google Chat bearer token issuer is not trusted.")
          else if email <> Some chat_service_account
          then
            Error
              (verification_error
                 "Google Chat bearer token was not issued for the Chat service account.")
          else
            Ok
              { subject = optional_string_member "sub" payload_json
              ; email
              })
;;

let verify
  ?(http_get = User_connector_common.default_http_get)
  (auth_config : Config.google_chat_id_token_auth)
  authorization_header
  =
  let bearer_prefix = "Bearer " in
  if not (String.starts_with ~prefix:bearer_prefix authorization_header)
  then Lwt.return (Error (verification_error "Missing Google Chat bearer token."))
  else
    let token =
      String.sub
        authorization_header
        (String.length bearer_prefix)
        (String.length authorization_header - String.length bearer_prefix)
      |> String.trim
    in
    match split_token token with
    | Error err -> Lwt.return (Error err)
    | Ok (header_part, payload_part, signature_part) ->
      (match decode_json_part header_part, decode_json_part payload_part with
       | Ok header_json, Ok payload_json ->
         load_certificates ~http_get auth_config.certs_url
         >>= (function
          | Error _ as error -> Lwt.return error
          | Ok certificates ->
            (match
               verify_signature
                 certificates
                 ~header_part
                 ~payload_part
                 ~signature_part
                 header_json
             with
             | Error err -> Lwt.return (Error err)
             | Ok () -> Lwt.return (validate_claims auth_config payload_json)))
       | Error err, _ | _, Error err -> Lwt.return (Error err))
;;
