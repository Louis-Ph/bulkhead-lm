type inbound_message =
  { account_id : string
  ; open_id : string
  ; create_time : int option
  ; msg_type : string
  ; content : string option
  ; msg_id : string option
  ; event : string option
  ; event_key : string option
  }

let index_substring haystack needle ~from_index =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec loop index =
    if needle_length = 0
    then Some from_index
    else if index + needle_length > haystack_length
    then None
    else if String.sub haystack index needle_length = needle
    then Some index
    else loop (index + 1)
  in
  if from_index < 0 then None else loop from_index
;;

let find_between haystack ~start_marker ~end_marker =
  match index_substring haystack start_marker ~from_index:0 with
  | None -> None
  | Some start_index ->
    let content_start = start_index + String.length start_marker in
    (match index_substring haystack end_marker ~from_index:content_start with
     | None -> None
     | Some end_index ->
       Some (String.sub haystack content_start (end_index - content_start)))
;;

let find_tag xml tag_name =
  let cdata_start = "<" ^ tag_name ^ "><![CDATA[" in
  let cdata_end = "]]></" ^ tag_name ^ ">" in
  match find_between xml ~start_marker:cdata_start ~end_marker:cdata_end with
  | Some value ->
    let trimmed = String.trim value in
    if trimmed = "" then None else Some trimmed
  | None ->
    let plain_start = "<" ^ tag_name ^ ">" in
    let plain_end = "</" ^ tag_name ^ ">" in
    (match find_between xml ~start_marker:plain_start ~end_marker:plain_end with
     | Some value ->
       let trimmed = String.trim value in
       if trimmed = "" then None else Some trimmed
     | None -> None)
;;

let find_int_tag xml tag_name =
  match find_tag xml tag_name with
  | Some value -> int_of_string_opt value
  | None -> None
;;

let parse_encrypted_envelope xml =
  match find_tag xml "Encrypt" with
  | Some encrypted -> Ok encrypted
  | None ->
    Error
      (Domain_error.invalid_request
         "WeChat encrypted XML payload is missing the Encrypt field.")
;;

let parse xml =
  match
    find_tag xml "ToUserName", find_tag xml "FromUserName", find_tag xml "MsgType"
  with
  | Some account_id, Some open_id, Some msg_type ->
    Ok
      { account_id
      ; open_id
      ; create_time = find_int_tag xml "CreateTime"
      ; msg_type
      ; content = find_tag xml "Content"
      ; msg_id = find_tag xml "MsgId"
      ; event = find_tag xml "Event"
      ; event_key = find_tag xml "EventKey"
      }
  | _ ->
    Error
      (Domain_error.invalid_request
         "WeChat XML payload is missing ToUserName, FromUserName, or MsgType.")
;;

let cdata value =
  let escaped = Str.global_replace (Str.regexp_string "]]>") "]]]]><![CDATA[>" value in
  "<![CDATA[" ^ escaped ^ "]]>"
;;

let render_text_reply ~to_user ~from_user ~create_time ~text =
  String.concat
    ""
    [ "<xml>"
    ; "<ToUserName>"
    ; cdata to_user
    ; "</ToUserName>"
    ; "<FromUserName>"
    ; cdata from_user
    ; "</FromUserName>"
    ; "<CreateTime>"
    ; string_of_int create_time
    ; "</CreateTime>"
    ; "<MsgType>"
    ; cdata "text"
    ; "</MsgType>"
    ; "<Content>"
    ; cdata text
    ; "</Content>"
    ; "</xml>"
    ]
;;

let render_encrypted_reply ~encrypted ~msg_signature ~timestamp ~nonce =
  String.concat
    ""
    [ "<xml>"
    ; "<Encrypt>"
    ; cdata encrypted
    ; "</Encrypt>"
    ; "<MsgSignature>"
    ; cdata msg_signature
    ; "</MsgSignature>"
    ; "<TimeStamp>"
    ; timestamp
    ; "</TimeStamp>"
    ; "<Nonce>"
    ; cdata nonce
    ; "</Nonce>"
    ; "</xml>"
    ]
;;
