type t =
  { code : string
  ; status : int
  ; error_type : string
  ; message : string
  ; provider_id : string option
  }

let make ?provider_id ~code ~status ~error_type message =
  { code; status; error_type; message; provider_id }
;;

let invalid_api_key () =
  make
    ~code:"invalid_api_key"
    ~status:401
    ~error_type:"invalid_request_error"
    "Invalid or missing API key."
;;

let budget_exceeded () =
  make
    ~code:"budget_exceeded"
    ~status:429
    ~error_type:"rate_limit_error"
    "Daily token budget exceeded."
;;

let rate_limited () =
  make
    ~code:"rate_limited"
    ~status:429
    ~error_type:"rate_limit_error"
    "Rate limit exceeded."
;;

let route_not_found model =
  make
    ~code:"route_not_found"
    ~status:404
    ~error_type:"invalid_request_error"
    (Fmt.str "Requested model route is not configured: %s" model)
;;

let route_forbidden model =
  make
    ~code:"route_forbidden"
    ~status:403
    ~error_type:"permission_error"
    (Fmt.str "The presented virtual key is not allowed to access route %s" model)
;;

let provider_denied message =
  make ~code:"provider_denied" ~status:403 ~error_type:"permission_error" message
;;

let unsupported_feature feature =
  make
    ~code:"unsupported_feature"
    ~status:501
    ~error_type:"invalid_request_error"
    (Fmt.str "Feature not implemented in this build: %s" feature)
;;

let upstream ?provider_id message =
  make ?provider_id ~code:"upstream_failure" ~status:502 ~error_type:"api_error" message
;;

let to_openai_json error =
  `Assoc
    [ ( "error"
      , `Assoc
          [ "message", `String error.message
          ; "type", `String error.error_type
          ; "code", `String error.code
          ] )
    ]
;;

let to_string error =
  match error.provider_id with
  | None -> Fmt.str "%s (%d): %s" error.code error.status error.message
  | Some provider_id ->
    Fmt.str "%s (%d) [%s]: %s" error.code error.status provider_id error.message
;;
