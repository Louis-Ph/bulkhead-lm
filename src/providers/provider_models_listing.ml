(** Fetch the live list of models exposed by a provider.

    Most OpenAI-compatible providers expose a ["/models"] endpoint at their
    [api_base], requiring a Bearer token. Anthropic uses a slightly different
    auth scheme ([x-api-key] + [anthropic-version]) and PAGINATES the
    response (default page size 20, capped at 1000), so this module follows
    the [has_more] / [last_id] cursor until exhausted.

    SSH/peer providers do not expose a discovery endpoint; they short-circuit
    to a typed [Unsupported] error so callers can render them as informational
    rather than as a fetch failure.

    This module is intentionally narrow: it only performs the fetch and
    normalises the response into a list of [model_entry]. Caching and fallback
    logic live in {!Model_listing_cache}. *)

open Lwt.Infix

type model_entry =
  { id : string
  ; display_name : string option
  ; created : string option
  ; raw : Yojson.Safe.t
  }

type fetch_error_kind =
  | Unsupported
  | Auth_error
  | Forbidden
  | Rate_limited
  | Upstream_error of int (* non-2xx HTTP status *)
  | Network_error
  | Timeout
  | Body_too_large
  | Parse_error

type fetch_error =
  { message : string
  ; kind : fetch_error_kind
  }

(* Build the canonical [{api_base}/models] URI, taking care to preserve any
   path prefix the provider already declares (e.g. Google's
   [/v1beta/openai/]). *)
let models_endpoint ?query api_base =
  let base = Uri.of_string api_base in
  let base_path = Uri.path base in
  let normalized_base =
    if base_path = "" || base_path = "/"
    then ""
    else if String.ends_with ~suffix:"/" base_path
    then base_path
    else base_path ^ "/"
  in
  let with_path = Uri.with_path base (normalized_base ^ "models") in
  match query with
  | None -> with_path
  | Some pairs -> Uri.with_query' with_path pairs
;;

let make_error ?(kind = Network_error) message = { message; kind }

(* Strip control characters and clamp length so we never echo terminal-corrupt
   bytes from a hostile or misbehaving provider into the wizard. *)
let sanitize_snippet ?(max_chars = 120) raw =
  let buffer = Buffer.create (min (String.length raw) max_chars) in
  let length = min (String.length raw) max_chars in
  let truncated = String.length raw > max_chars in
  for index = 0 to length - 1 do
    let ch = raw.[index] in
    let code = Char.code ch in
    if code = 9 || code = 10 || code = 13 || (code >= 32 && code < 127)
    then Buffer.add_char buffer ch
    else Buffer.add_char buffer '?'
  done;
  let contents = Buffer.contents buffer in
  if truncated then contents ^ "..." else contents
;;

let parse_string_field fields name =
  match List.assoc_opt name fields with
  | Some (`String value) -> Some value
  | _ -> None
;;

let parse_int_field fields name =
  match List.assoc_opt name fields with
  | Some (`Int value) -> Some (string_of_int value)
  | Some (`Intlit value) -> Some value
  | Some (`String value) -> Some value
  | _ -> None
;;

let parse_bool_field fields name =
  match List.assoc_opt name fields with
  | Some (`Bool value) -> Some value
  | _ -> None
;;

(* OpenAI-compatible response shape:
   {[
     { "object": "list",
       "data": [ { "id": "gpt-4o", "object": "model", "created": 1715367049, ... }, ... ] }
   ]}

   Anthropic returns the same outer envelope but each entry has
   ["display_name"] and ["created_at"] (string timestamp) and the envelope
   includes ["has_more"] / ["first_id"] / ["last_id"] for pagination. *)
let parse_entry json =
  match json with
  | `Assoc fields ->
    (match parse_string_field fields "id" with
     | None -> None
     | Some id ->
       let display_name = parse_string_field fields "display_name" in
       let created =
         match parse_string_field fields "created_at" with
         | Some value -> Some value
         | None -> parse_int_field fields "created"
       in
       Some { id; display_name; created; raw = json })
  | _ -> None
;;

type page =
  { entries : model_entry list
  ; has_more : bool
  ; last_id : string option
  }

let parse_page body_string =
  match Yojson.Safe.from_string body_string with
  | exception Yojson.Json_error err ->
    Error (make_error ~kind:Parse_error ("Could not parse JSON listing: " ^ err))
  | json ->
    (match json with
     | `Assoc fields ->
       (match List.assoc_opt "data" fields with
        | Some (`List entries) ->
          let parsed = List.filter_map parse_entry entries in
          let has_more =
            parse_bool_field fields "has_more" |> Option.value ~default:false
          in
          let last_id = parse_string_field fields "last_id" in
          Ok { entries = parsed; has_more; last_id }
        | _ ->
          Error
            (make_error
               ~kind:Parse_error
               "Listing response is missing a top-level \"data\" array."))
     | _ ->
       Error
         (make_error ~kind:Parse_error "Listing response is not a JSON object."))
;;

let auth_headers ~provider_kind ~api_key =
  match provider_kind with
  | Config.Anthropic ->
    Cohttp.Header.of_list
      [ "x-api-key", api_key; "anthropic-version", "2023-06-01" ]
  | _ ->
    Cohttp.Header.of_list [ "authorization", "Bearer " ^ api_key ]
;;

let supports_listing = function
  | Config.Bulkhead_peer | Config.Bulkhead_ssh_peer -> false
  | _ -> true
;;

let max_body_bytes = 4 * 1024 * 1024 (* 4 MB cap on the listing payload. *)

(* Read the response body chunk-by-chunk into a bounded buffer. Aborts cleanly
   if the provider streams more than [max_body_bytes], which protects the
   wizard against a misbehaving upstream that ignores Content-Length. *)
let read_body_capped body =
  let buffer = Buffer.create 4096 in
  let stream = Cohttp_lwt.Body.to_stream body in
  let exception Body_overflow in
  Lwt.catch
    (fun () ->
      Lwt_stream.iter
        (fun chunk ->
          if Buffer.length buffer + String.length chunk > max_body_bytes
          then raise Body_overflow
          else Buffer.add_string buffer chunk)
        stream
      >|= fun () -> Ok (Buffer.contents buffer))
    (function
      | Body_overflow ->
        Lwt.return
          (Error
             (make_error
                ~kind:Body_too_large
                (Fmt.str
                   "Listing response exceeded the %d-byte cap"
                   max_body_bytes)))
      | exn ->
        Lwt.return
          (Error
             (make_error
                ~kind:Network_error
                ("HTTP body read failed: " ^ Printexc.to_string exn))))
;;

let perform_get ~timeout_ms uri ~headers =
  let request () =
    Cohttp_lwt_unix.Client.get ~headers uri
    >>= fun (response, body) ->
    read_body_capped body
    >|= function
    | Ok body_string -> Ok (response, body_string)
    | Error err -> Error err
  in
  let on_timeout () =
    Error
      (make_error
         ~kind:Timeout
         (Fmt.str "Listing request timed out after %d ms" timeout_ms))
  in
  let safe_request () =
    Lwt.catch request (fun exn ->
      Lwt.return
        (Error
           (make_error
              ~kind:Network_error
              ("HTTP request failed: " ^ Printexc.to_string exn))))
  in
  Timeout_guard.with_timeout_ms ~timeout_ms ~on_timeout (safe_request ())
;;

let kind_of_status = function
  | 401 -> Auth_error
  | 403 -> Forbidden
  | 429 -> Rate_limited
  | code -> Upstream_error code
;;

let interpret_response ~status ~body_string =
  if status >= 200 && status < 300
  then parse_page body_string
  else
    Error
      (make_error
         ~kind:(kind_of_status status)
         (Fmt.str
            "Provider returned HTTP %d: %s"
            status
            (sanitize_snippet body_string)))
;;

(* Anthropic uses [?after_id=...] cursor pagination; OpenAI-compat upstreams
   typically return everything in a single page so the loop terminates after
   the first call. We cap iterations to keep a runaway provider from looping
   forever. *)
let max_pages = 50
let anthropic_page_size = 1000

let rec collect_pages
  ~provider_kind
  ~api_base
  ~headers
  ~timeout_ms
  ~accumulated
  ~iterations
  ~after_id
  =
  if iterations >= max_pages
  then
    Lwt.return
      (Error
         (make_error
            ~kind:(Upstream_error 0)
            (Fmt.str
               "Provider listing did not terminate after %d pages"
               max_pages)))
  else (
    let query =
      match provider_kind, after_id with
      | Config.Anthropic, Some cursor ->
        Some
          [ "limit", string_of_int anthropic_page_size; "after_id", cursor ]
      | Config.Anthropic, None ->
        Some [ "limit", string_of_int anthropic_page_size ]
      | _, _ -> None
    in
    let uri = models_endpoint ?query api_base in
    perform_get ~timeout_ms uri ~headers
    >>= function
    | Error err -> Lwt.return (Error err)
    | Ok (response, body_string) ->
      let status =
        Cohttp.Response.status response |> Cohttp.Code.code_of_status
      in
      (match interpret_response ~status ~body_string with
       | Error err -> Lwt.return (Error err)
       | Ok page ->
         let merged = accumulated @ page.entries in
         (match provider_kind, page.has_more, page.last_id with
          | Config.Anthropic, true, Some cursor ->
            collect_pages
              ~provider_kind
              ~api_base
              ~headers
              ~timeout_ms
              ~accumulated:merged
              ~iterations:(iterations + 1)
              ~after_id:(Some cursor)
          | _ -> Lwt.return (Ok merged))))
;;

let default_timeout_ms = 8000

(** Fetch the live model list for a provider.

    [api_base] is the provider's HTTP base URL; the function appends ["/models"]
    while preserving any sub-path. [api_key] is the bearer secret to send.
    Providers that do not have a known listing endpoint return
    [Error { kind = Unsupported; ... }]. *)
let fetch ?(timeout_ms = default_timeout_ms) ~provider_kind ~api_base ~api_key () =
  if not (supports_listing provider_kind)
  then
    Lwt.return
      (Error
         (make_error
            ~kind:Unsupported
            "This provider does not expose a public model listing endpoint."))
  else (
    let headers = auth_headers ~provider_kind ~api_key in
    collect_pages
      ~provider_kind
      ~api_base
      ~headers
      ~timeout_ms
      ~accumulated:[]
      ~iterations:0
      ~after_id:None)
;;

(* Round-trip helpers used by the cache layer. We persist [created] as a
   tagged string to keep numeric and ISO-8601 forms unambiguous on reload. *)
let entry_to_yojson entry =
  let assoc =
    [ "id", `String entry.id ]
    @ (match entry.display_name with
       | Some value -> [ "display_name", `String value ]
       | None -> [])
    @ (match entry.created with
       | Some value -> [ "created", `String value ]
       | None -> [])
    @ [ "raw", entry.raw ]
  in
  `Assoc assoc
;;

let entry_of_yojson = function
  | `Assoc fields ->
    (match parse_string_field fields "id" with
     | None -> Error "missing id"
     | Some id ->
       let display_name = parse_string_field fields "display_name" in
       let created = parse_string_field fields "created" in
       let raw =
         match List.assoc_opt "raw" fields with
         | Some value -> value
         | None -> `Assoc fields
       in
       Ok { id; display_name; created; raw })
  | _ -> Error "expected JSON object"
;;
