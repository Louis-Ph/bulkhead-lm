type retry_disposition =
  | Retryable
  | Non_retryable

type t =
  { code : string
  ; status : int
  ; error_type : string
  ; message : string
  ; provider_id : string option
  ; retry_disposition : retry_disposition
  }

let make ?provider_id ~retry_disposition ~code ~status ~error_type message =
  { code; status; error_type; message; provider_id; retry_disposition }
;;

let invalid_api_key () =
  make
    ~retry_disposition:Non_retryable
    ~code:"invalid_api_key"
    ~status:401
    ~error_type:"invalid_request_error"
    "Invalid or missing API key."
;;

let budget_exceeded () =
  make
    ~retry_disposition:Non_retryable
    ~code:"budget_exceeded"
    ~status:429
    ~error_type:"rate_limit_error"
    "Daily token budget exceeded."
;;

let rate_limited () =
  make
    ~retry_disposition:Non_retryable
    ~code:"rate_limited"
    ~status:429
    ~error_type:"rate_limit_error"
    "Rate limit exceeded."
;;

let route_not_found model =
  make
    ~retry_disposition:Non_retryable
    ~code:"route_not_found"
    ~status:404
    ~error_type:"invalid_request_error"
    (Fmt.str "Requested model route is not configured: %s" model)
;;

let route_forbidden model =
  make
    ~retry_disposition:Non_retryable
    ~code:"route_forbidden"
    ~status:403
    ~error_type:"permission_error"
    (Fmt.str "The presented virtual key is not allowed to access route %s" model)
;;

let provider_denied message =
  make
    ~retry_disposition:Non_retryable
    ~code:"provider_denied"
    ~status:403
    ~error_type:"permission_error"
    message
;;

let operation_denied message =
  make
    ~retry_disposition:Non_retryable
    ~code:"operation_denied"
    ~status:403
    ~error_type:"permission_error"
    message
;;

let threat_detected ~category ~signal () =
  make
    ~retry_disposition:Non_retryable
    ~code:"threat_detected"
    ~status:403
    ~error_type:"permission_error"
    (Fmt.str
       "Threat detector blocked the request after matching %s signal \"%s\"."
       category
       signal)
;;

let unsafe_output_blocked ~signal () =
  make
    ~retry_disposition:Non_retryable
    ~code:"unsafe_output_blocked"
    ~status:403
    ~error_type:"permission_error"
    (Fmt.str "Output guard blocked the model response after matching \"%s\"." signal)
;;

let invalid_request message =
  make
    ~retry_disposition:Non_retryable
    ~code:"invalid_request"
    ~status:400
    ~error_type:"invalid_request_error"
    message
;;

let resource_not_found message =
  make
    ~retry_disposition:Non_retryable
    ~code:"resource_not_found"
    ~status:404
    ~error_type:"invalid_request_error"
    message
;;

let resource_conflict message =
  make
    ~retry_disposition:Non_retryable
    ~code:"resource_conflict"
    ~status:409
    ~error_type:"invalid_request_error"
    message
;;

let request_too_large ~max_bytes =
  make
    ~retry_disposition:Non_retryable
    ~code:"request_too_large"
    ~status:413
    ~error_type:"invalid_request_error"
    (Fmt.str "Request body exceeds configured limit of %d bytes." max_bytes)
;;

let operation_too_large ~subject ~max_bytes =
  make
    ~retry_disposition:Non_retryable
    ~code:"operation_too_large"
    ~status:413
    ~error_type:"invalid_request_error"
    (Fmt.str "%s exceeds configured limit of %d bytes." subject max_bytes)
;;

let malformed_json_body () =
  make
    ~retry_disposition:Non_retryable
    ~code:"malformed_json_body"
    ~status:400
    ~error_type:"invalid_request_error"
    "Malformed JSON request body."
;;

let request_timeout ?provider_id ~timeout_ms () =
  make
    ?provider_id
    ~retry_disposition:Retryable
    ~code:"request_timeout"
    ~status:504
    ~error_type:"api_error"
    (Fmt.str "Request exceeded configured timeout of %d ms." timeout_ms)
;;

let command_timeout ~timeout_ms () =
  make
    ~retry_disposition:Non_retryable
    ~code:"command_timeout"
    ~status:504
    ~error_type:"api_error"
    (Fmt.str "Command exceeded configured timeout of %d ms." timeout_ms)
;;

let unsupported_feature feature =
  make
    ~retry_disposition:Non_retryable
    ~code:"unsupported_feature"
    ~status:501
    ~error_type:"invalid_request_error"
    (Fmt.str "Feature not implemented in this build: %s" feature)
;;

let upstream ?provider_id message =
  make
    ?provider_id
    ~retry_disposition:Retryable
    ~code:"upstream_failure"
    ~status:502
    ~error_type:"api_error"
    message
;;

let retry_disposition_of_upstream_status status =
  if status = 429
  then Retryable
  else if status = 508
  then Non_retryable
  else if status >= 500 && status <= 599
  then Retryable
  else Non_retryable
;;

let upstream_status ?provider_id ~status message =
  make
    ?provider_id
    ~retry_disposition:(retry_disposition_of_upstream_status status)
    ~code:"upstream_failure"
    ~status
    ~error_type:"api_error"
    message
;;

let loop_detected ~max_hops ~request_id ~hop_count () =
  make
    ~retry_disposition:Non_retryable
    ~code:"loop_detected"
    ~status:508
    ~error_type:"api_error"
    (Fmt.str
       "BulkheadLM peer hop limit exceeded for request %s: received hop count %d with max_hops=%d."
       request_id
       hop_count
       max_hops)
;;

let is_retryable error =
  match error.retry_disposition with
  | Retryable -> true
  | Non_retryable -> false
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
