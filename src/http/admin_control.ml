open Lwt.Infix

let respond_html html =
  let headers = Cohttp.Header.of_list [ "content-type", "text/html; charset=utf-8" ] in
  Cohttp_lwt_unix.Server.respond_string ~status:`OK ~headers ~body:html ()
;;

let path_prefix_matches_request prefix request_path =
  prefix = request_path
  || (prefix <> "/"
      && String.starts_with ~prefix:(prefix ^ "/") request_path)
;;

let status_path control_plane =
  control_plane.Security_policy.path_prefix ^ Admin_control_constants.Path.status_suffix
;;

let reload_path control_plane =
  control_plane.Security_policy.path_prefix ^ Admin_control_constants.Path.reload_suffix
;;

let memory_session_path control_plane =
  control_plane.Security_policy.path_prefix
  ^ Admin_control_constants.Path.memory_session_suffix
;;

let privacy_preview_path control_plane =
  control_plane.Security_policy.path_prefix
  ^ Admin_control_constants.Path.privacy_preview_suffix
;;

let current_store control = Runtime_control.current_store control

let current_control_plane control =
  let store = current_store control in
  store.Runtime_state.config.Config.security_policy.control_plane
;;

let matches control path =
  let control_plane = current_control_plane control in
  control_plane.enabled && path_prefix_matches_request control_plane.path_prefix path
;;

let non_empty_env name =
  match Sys.getenv_opt name with
  | Some value when String.trim value <> "" -> true
  | _ -> false
;;

let route_readiness_json (route : Config.route) =
  let backend_envs =
    route.backends
    |> List.map (fun (backend : Config.backend) -> backend.api_key_env)
    |> List.sort_uniq String.compare
  in
  let ready = List.exists non_empty_env backend_envs in
  `Assoc
    [ "public_model", `String route.public_model
    ; "ready", `Bool ready
    ; "backend_envs", `List (List.map (fun env -> `String env) backend_envs)
    ; "backend_count", `Int (List.length route.backends)
    ]
;;

let user_connector_json (connector_id, webhook_path) =
  `Assoc [ "id", `String connector_id; "webhook_path", `String webhook_path ]
;;

let virtual_key_json (virtual_key : Config.virtual_key) =
  `Assoc
    [ "name", `String virtual_key.name
    ; "daily_token_budget", `Int virtual_key.daily_token_budget
    ; "requests_per_minute", `Int virtual_key.requests_per_minute
    ; ( "allowed_routes"
      , `List (List.map (fun route -> `String route) virtual_key.allowed_routes) )
    ]
;;

let privacy_filter_json control_plane (policy : Security_policy.privacy_filter) =
  `Assoc
    [ "enabled", `Bool policy.enabled
    ; "replacement", `String policy.replacement
    ; "redact_email_addresses", `Bool policy.redact_email_addresses
    ; "redact_phone_numbers", `Bool policy.redact_phone_numbers
    ; "redact_ipv4_addresses", `Bool policy.redact_ipv4_addresses
    ; "redact_national_ids", `Bool policy.redact_national_ids
    ; "redact_payment_cards", `Bool policy.redact_payment_cards
    ; "secret_prefix_count", `Int (List.length policy.secret_prefixes)
    ; "additional_literal_token_count", `Int (List.length policy.additional_literal_tokens)
    ; ( "pattern_rules"
      , `List
          (List.map
             (fun (rule : Security_policy.privacy_pattern_rule) ->
               `Assoc
                 [ "name", `String rule.name
                 ; "enabled", `Bool rule.enabled
                 ])
             policy.pattern_rules) )
    ; "preview_path", `String (privacy_preview_path control_plane)
    ]
;;

let iso8601_timestamp unix_time =
  let tm = Unix.gmtime unix_time in
  Printf.sprintf
    "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.Unix.tm_year + 1900)
    (tm.Unix.tm_mon + 1)
    tm.Unix.tm_mday
    tm.Unix.tm_hour
    tm.Unix.tm_min
    tm.Unix.tm_sec
;;

let status_json control =
  let store = current_store control in
  let config = store.Runtime_state.config in
  let server = config.Config.security_policy.Security_policy.server in
  let control_plane = config.security_policy.control_plane in
  `Assoc
    [ "status", `String "ok"
    ; "loaded_at", `String (iso8601_timestamp (Runtime_control.loaded_at_unix control))
    ; "config_path", `String (Runtime_control.config_path control)
    ; ( "listen"
      , `Assoc
          [ "host", `String server.listen_host
          ; "port", `Int server.listen_port
          ] )
    ; ( "control_plane"
      , `Assoc
          [ "path_prefix", `String control_plane.path_prefix
          ; "ui_enabled", `Bool control_plane.ui_enabled
          ; "allow_reload", `Bool control_plane.allow_reload
          ; "memory_session_path", `String (memory_session_path control_plane)
          ; "privacy_preview_path", `String (privacy_preview_path control_plane)
          ; "admin_token_env",
            (match control_plane.admin_token_env with
             | Some env_name -> `String env_name
             | None -> `Null)
          ; "admin_token_required", `Bool (Option.is_some control_plane.admin_token_env)
          ] )
    ; ( "routes"
      , `List (List.map route_readiness_json config.routes) )
    ; ( "user_connectors"
      , `List
          (Config.configured_user_connector_webhook_paths config.user_connectors
           |> List.map user_connector_json) )
    ; ( "virtual_keys"
      , `List (List.map virtual_key_json config.virtual_keys) )
    ; ( "privacy_filter"
      , privacy_filter_json control_plane config.security_policy.privacy_filter )
    ]
;;

let expected_admin_token control_plane =
  match control_plane.Security_policy.admin_token_env with
  | None -> None
  | Some env_name ->
    (match Sys.getenv_opt env_name with
     | Some value ->
       let trimmed = String.trim value in
       if trimmed = "" then None else Some trimmed
     | None -> None)
;;

let request_token store req =
  let auth = store.Runtime_state.config.Config.security_policy.Security_policy.auth in
  let header_value =
    Cohttp.Header.get
      (Cohttp.Request.headers req)
      (String.lowercase_ascii auth.header)
  in
  match header_value with
  | Some value when String.starts_with ~prefix:auth.bearer_prefix value ->
    let prefix_length = String.length auth.bearer_prefix in
    Some
      (String.sub value prefix_length (String.length value - prefix_length) |> String.trim)
  | Some value when String.trim value <> "" -> Some (String.trim value)
  | _ -> None
;;

let require_authorization control req =
  let store = current_store control in
  let control_plane = store.Runtime_state.config.Config.security_policy.control_plane in
  match expected_admin_token control_plane with
  | None -> Ok store
  | Some expected ->
    (match request_token store req with
     | Some presented when presented = expected -> Ok store
     | _ -> Error (Domain_error.invalid_api_key ()))
;;

let page_html control =
  let store = current_store control in
  let auth = store.Runtime_state.config.Config.security_policy.Security_policy.auth in
  let control_plane = store.Runtime_state.config.Config.security_policy.control_plane in
  let base_path_json = Yojson.Safe.to_string (`String control_plane.path_prefix) in
  let header_name_json = Yojson.Safe.to_string (`String auth.header) in
  let bearer_prefix_json = Yojson.Safe.to_string (`String auth.bearer_prefix) in
  String.concat
    "\n"
    [ "<!DOCTYPE html>"
    ; "<html lang=\"en\">"
    ; "<head>"
    ; "  <meta charset=\"utf-8\">"
    ; "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    ; Fmt.str "  <title>%s</title>" Admin_control_constants.Text.page_title
    ; "  <style>"
    ; "    :root { color-scheme: light dark; --bg: #0d1117; --panel: #161b22; --muted: #8b949e; --fg: #e6edf3; --accent: #2f81f7; --ok: #2ea043; --warn: #d29922; --bad: #f85149; --border: #30363d; }"
    ; "    * { box-sizing: border-box; }"
    ; "    body { margin: 0; font-family: Menlo, Monaco, Consolas, monospace; background: radial-gradient(circle at top, #1c2735, var(--bg) 45%); color: var(--fg); }"
    ; "    main { max-width: 1100px; margin: 0 auto; padding: 32px 20px 56px; }"
    ; "    .hero { display: grid; gap: 12px; margin-bottom: 24px; }"
    ; "    h1 { margin: 0; font-size: 32px; letter-spacing: 0.02em; }"
    ; "    p { margin: 0; color: var(--muted); line-height: 1.5; }"
    ; "    .panel { background: color-mix(in srgb, var(--panel) 92%, transparent); border: 1px solid var(--border); border-radius: 16px; padding: 18px; backdrop-filter: blur(10px); box-shadow: 0 24px 80px rgba(0,0,0,0.24); }"
    ; "    .toolbar { display: grid; gap: 12px; grid-template-columns: 1.8fr 1fr 1fr; align-items: end; margin-bottom: 18px; }"
    ; "    label { display: grid; gap: 8px; font-size: 12px; text-transform: uppercase; color: var(--muted); letter-spacing: 0.08em; }"
    ; "    input { width: 100%; border-radius: 12px; border: 1px solid var(--border); background: #0b0f14; color: var(--fg); padding: 12px 14px; }"
    ; "    button { border: 0; border-radius: 12px; padding: 12px 16px; font: inherit; color: white; cursor: pointer; background: linear-gradient(135deg, var(--accent), #1f6feb); }"
    ; "    button.secondary { background: linear-gradient(135deg, #444c56, #30363d); }"
    ; "    button:disabled { cursor: wait; opacity: 0.7; }"
    ; "    .status-line { margin: 0 0 16px; min-height: 1.4em; color: var(--muted); }"
    ; "    .status-line.ok { color: var(--ok); }"
    ; "    .status-line.error { color: var(--bad); }"
    ; "    .grid { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); }"
    ; "    .metric { display: grid; gap: 8px; }"
    ; "    .metric strong { font-size: 13px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.08em; }"
    ; "    .metric span { font-size: 20px; }"
    ; "    pre { margin: 0; white-space: pre-wrap; word-break: break-word; background: #0b0f14; border: 1px solid var(--border); border-radius: 14px; padding: 16px; overflow: auto; }"
    ; "    .section-title { margin: 24px 0 12px; font-size: 14px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.12em; }"
    ; "    @media (max-width: 820px) { .toolbar { grid-template-columns: 1fr; } }"
    ; "  </style>"
    ; "</head>"
    ; "<body>"
    ; "  <main>"
    ; "    <section class=\"hero\">"
    ; Fmt.str "      <h1>%s</h1>" Admin_control_constants.Text.page_title
    ; Fmt.str "      <p>%s</p>" Admin_control_constants.Text.page_subtitle
    ; "    </section>"
    ; "    <section class=\"panel\">"
    ; "      <div class=\"toolbar\">"
    ; Fmt.str "        <label>%s<input id=\"token\" type=\"password\" placeholder=\"Paste the control-plane token\"></label>" Admin_control_constants.Text.token_label
    ; Fmt.str "        <button id=\"refresh\">%s</button>" Admin_control_constants.Text.refresh_label
    ; Fmt.str "        <button id=\"reload\" class=\"secondary\">%s</button>" Admin_control_constants.Text.reload_label
    ; "      </div>"
    ; Fmt.str "      <p id=\"status\" class=\"status-line\">%s</p>" Admin_control_constants.Text.loading_message
    ; "      <div class=\"grid\">"
    ; "        <div class=\"metric\"><strong>Config Path</strong><span id=\"config-path\">-</span></div>"
    ; "        <div class=\"metric\"><strong>Loaded At</strong><span id=\"loaded-at\">-</span></div>"
    ; "        <div class=\"metric\"><strong>Listen</strong><span id=\"listen\">-</span></div>"
    ; "        <div class=\"metric\"><strong>Routes</strong><span id=\"route-count\">-</span></div>"
    ; "      </div>"
    ; "      <div class=\"section-title\">Status JSON</div>"
    ; "      <pre id=\"payload\"></pre>"
    ; "    </section>"
    ; "  </main>"
    ; "  <script>"
    ; Fmt.str "    const basePath = %s;" base_path_json
    ; Fmt.str "    const authHeaderName = %s;" header_name_json
    ; Fmt.str "    const bearerPrefix = %s;" bearer_prefix_json
    ; "    const tokenInput = document.getElementById('token');"
    ; "    const statusLine = document.getElementById('status');"
    ; "    const payloadNode = document.getElementById('payload');"
    ; "    const configPathNode = document.getElementById('config-path');"
    ; "    const loadedAtNode = document.getElementById('loaded-at');"
    ; "    const listenNode = document.getElementById('listen');"
    ; "    const routeCountNode = document.getElementById('route-count');"
    ; "    const storedToken = window.localStorage.getItem('bulkhead-admin-token') || '';"
    ; "    tokenInput.value = storedToken;"
    ; "    const setStatus = (message, kind='') => { statusLine.textContent = message; statusLine.className = `status-line ${kind}`.trim(); };"
    ; "    const headers = () => {"
    ; "      const token = tokenInput.value.trim();"
    ; "      const result = { 'content-type': 'application/json' };"
    ; "      if (token) { result[authHeaderName] = `${bearerPrefix}${token}`; }"
    ; "      return result;"
    ; "    };"
    ; "    const renderStatus = (payload) => {"
    ; "      configPathNode.textContent = payload.config_path;"
    ; "      loadedAtNode.textContent = payload.loaded_at;"
    ; "      listenNode.textContent = `${payload.listen.host}:${payload.listen.port}`;"
    ; "      routeCountNode.textContent = String(payload.routes.length);"
    ; "      payloadNode.textContent = JSON.stringify(payload, null, 2);"
    ; "    };"
    ; "    const fetchStatus = async () => {"
    ; "      window.localStorage.setItem('bulkhead-admin-token', tokenInput.value.trim());"
    ; "      setStatus('Refreshing status...');"
    ; "      const response = await fetch(`${basePath}/api/status`, { headers: headers() });"
    ; "      const payload = await response.json();"
    ; "      if (!response.ok) { throw new Error(payload.error?.message || `HTTP ${response.status}`); }"
    ; "      renderStatus(payload);"
    ; "      setStatus('Control-plane status loaded.', 'ok');"
    ; "    };"
    ; "    const reloadConfig = async () => {"
    ; "      window.localStorage.setItem('bulkhead-admin-token', tokenInput.value.trim());"
    ; "      setStatus('Reloading config...');"
    ; "      const response = await fetch(`${basePath}/api/reload`, { method: 'POST', headers: headers(), body: '{}' });"
    ; "      const payload = await response.json();"
    ; "      if (!response.ok) { throw new Error(payload.error?.message || `HTTP ${response.status}`); }"
    ; Fmt.str "      setStatus('%s', 'ok');" Admin_control_constants.Text.reload_success
    ; "      renderStatus(payload.status);"
    ; "    };"
    ; "    document.getElementById('refresh').addEventListener('click', () => { fetchStatus().catch((error) => setStatus(error.message, 'error')); });"
    ; "    document.getElementById('reload').addEventListener('click', () => { reloadConfig().catch((error) => setStatus(error.message, 'error')); });"
    ; "    fetchStatus().catch((error) => setStatus(error.message, 'error'));"
    ; "  </script>"
    ; "</body>"
    ; "</html>"
    ]
;;

let handle_api_status control req =
  match require_authorization control req with
  | Error err -> Json_response.respond_error err
  | Ok _ -> Json_response.respond_json (status_json control)
;;

let handle_api_reload control req =
  match require_authorization control req with
  | Error err -> Json_response.respond_error err
  | Ok store ->
    let control_plane = store.Runtime_state.config.Config.security_policy.control_plane in
    if not control_plane.allow_reload
    then Json_response.respond_error (Domain_error.operation_denied "Control-plane reload is disabled.")
    else
      (match Runtime_control.reload_result control with
       | Ok _ ->
         Json_response.respond_json
           (`Assoc
             [ "result", `String "reloaded"
             ; "status", status_json control
             ])
       | Error err -> Json_response.respond_error (Domain_error.invalid_request err))
;;

let handle_api_privacy_preview control req body =
  match require_authorization control req with
  | Error err -> Json_response.respond_error err
  | Ok store ->
    Request_body.read_request_json store body
    >>= function
    | Error err -> Json_response.respond_error err
    | Ok json ->
      let text =
        match json with
        | `Assoc fields ->
          (match List.assoc_opt "text" fields with
           | Some (`String value) ->
             let trimmed = String.trim value in
             if trimmed = "" then None else Some trimmed
           | _ -> None)
        | _ -> None
      in
      (match text with
       | None ->
         Json_response.respond_error
           (Domain_error.invalid_request "Privacy preview requires a non-empty text field.")
       | Some text ->
         let report =
           Privacy_filter.filter_text_with_report
             store.Runtime_state.config.security_policy.privacy_filter
             text
         in
         Json_response.respond_json (Privacy_filter.report_to_yojson report))
;;

let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None
;;

let string_member_opt name json =
  match member name json with
  | Some (`String value) ->
    let trimmed = String.trim value in
    if trimmed = "" then None else Some trimmed
  | _ -> None
;;

let int_member_opt name json =
  match member name json with
  | Some (`Int value) -> Some value
  | Some (`Intlit value) -> Some (int_of_string value)
  | _ -> None
;;

let turn_role_to_string = function
  | Session_memory.User -> "user"
  | Session_memory.Assistant -> "assistant"
;;

let turn_role_of_string = function
  | "user" -> Ok Session_memory.User
  | "assistant" -> Ok Session_memory.Assistant
  | value ->
    Error
      (Domain_error.invalid_request
         (Fmt.str
            "Invalid memory turn role %s. Expected user or assistant."
            value))
;;

let parse_recent_turns json =
  match member "recent_turns" json with
  | None -> Ok []
  | Some (`List values) ->
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | (`Assoc _ as value) :: rest ->
        let role =
          match string_member_opt "role" value with
          | Some role -> turn_role_of_string role
          | None -> Error (Domain_error.invalid_request "Memory turns require role.")
        in
        let content =
          match string_member_opt "content" value with
          | Some content -> Ok content
          | None -> Error (Domain_error.invalid_request "Memory turns require content.")
        in
        (match role, content with
         | Ok role, Ok content ->
           loop ({ Session_memory.role; content } :: acc) rest
         | Error err, _ | _, Error err -> Error err)
      | _ :: _ -> Error (Domain_error.invalid_request "recent_turns must be a list of objects.")
    in
    loop [] values
  | Some _ -> Error (Domain_error.invalid_request "recent_turns must be a list.")
;;

let conversation_json ~session_key (conversation : Session_memory.t) =
  let stats = Session_memory.stats conversation in
  `Assoc
    [ "session_key", `String session_key
    ; ( "summary"
      , match conversation.summary with
        | Some summary -> `String summary
        | None -> `Null )
    ; "compressed_turn_count", `Int conversation.compressed_turn_count
    ; ( "recent_turns"
      , `List
          (List.map
             (fun (turn : Session_memory.turn) ->
               `Assoc
                 [ "role", `String (turn_role_to_string turn.role)
                 ; "content", `String turn.content
                 ])
             conversation.recent_turns) )
    ; ( "stats"
      , `Assoc
          [ "recent_turn_count", `Int stats.recent_turn_count
          ; "compressed_turn_count", `Int stats.compressed_turn_count
          ; "summary_char_count", `Int stats.summary_char_count
          ; "estimated_context_chars", `Int stats.estimated_context_chars
          ] )
    ]
;;

let session_key_of_request req =
  Uri.get_query_param (Cohttp.Request.uri req) "session_key"
  |> Option.map String.trim
  |> function
  | Some value when value <> "" -> Ok value
  | _ ->
    Error
      (Domain_error.invalid_request
         "session_key query parameter is required for memory session requests.")
;;

let record_memory_admin_event store ~event_type ~session_key ~details =
  Runtime_state.append_audit_event
    store
    { Persistent_store.event_type = event_type
    ; principal_name = None
    ; route_model = None
    ; provider_id = None
    ; status_code = 200
    ; details =
        `Assoc
          [ "session_key", `String session_key
          ; "operation", `String event_type
          ; "details", details
          ]
    }
;;

let handle_api_memory_get control req =
  match require_authorization control req with
  | Error err -> Json_response.respond_error err
  | Ok store ->
    (match session_key_of_request req with
     | Error err -> Json_response.respond_error err
     | Ok session_key ->
       let conversation =
         Runtime_state.get_user_connector_session store ~session_key
       in
       Json_response.respond_json (conversation_json ~session_key conversation))
;;

let handle_api_memory_put control req body =
  match require_authorization control req with
  | Error err -> Json_response.respond_error err
  | Ok store ->
    Request_body.read_request_json store body
    >>= function
    | Error err -> Json_response.respond_error err
    | Ok json ->
      let session_key =
        match string_member_opt "session_key" json with
        | Some session_key -> Ok session_key
        | None -> Error (Domain_error.invalid_request "Memory replacement requires session_key.")
      in
      let summary =
        match member "summary" json with
        | Some `Null | None -> Ok None
        | Some (`String value) -> Ok (Some value)
        | Some _ -> Error (Domain_error.invalid_request "summary must be a string or null.")
      in
      let compressed_turn_count =
        match int_member_opt "compressed_turn_count" json with
        | Some value when value >= 0 -> Ok value
        | Some _ ->
          Error (Domain_error.invalid_request "compressed_turn_count must be >= 0.")
        | None -> Ok 0
      in
      let recent_turns = parse_recent_turns json in
      (match session_key, summary, compressed_turn_count, recent_turns with
       | Ok session_key, Ok summary, Ok compressed_turn_count, Ok recent_turns ->
         let conversation : Session_memory.t =
           { summary; recent_turns; compressed_turn_count }
         in
         Runtime_state.set_user_connector_session
           store
           ~session_key
           conversation;
         record_memory_admin_event
           store
           ~event_type:"admin.memory.replace"
           ~session_key
           ~details:
             (`Assoc
               [ "summary_present", `Bool (Option.is_some summary)
               ; "recent_turn_count", `Int (List.length recent_turns)
               ; "compressed_turn_count", `Int compressed_turn_count
               ]);
         Json_response.respond_json (conversation_json ~session_key conversation)
       | Error err, _, _, _
       | _, Error err, _, _
       | _, _, Error err, _
       | _, _, _, Error err -> Json_response.respond_error err)
;;

let handle_api_memory_delete control req =
  match require_authorization control req with
  | Error err -> Json_response.respond_error err
  | Ok store ->
    (match session_key_of_request req with
     | Error err -> Json_response.respond_error err
     | Ok session_key ->
       Runtime_state.clear_user_connector_session store ~session_key;
       record_memory_admin_event
         store
         ~event_type:"admin.memory.clear"
         ~session_key
         ~details:(`Assoc [ "result", `String "cleared" ]);
       Json_response.respond_json
         (`Assoc
           [ "result", `String "cleared"
           ; "session_key", `String session_key
           ]))
;;

let handle control req body =
  let path = Uri.path (Cohttp.Request.uri req) in
  let control_plane = current_control_plane control in
  match Cohttp.Request.meth req, path with
  | `GET, path when path = control_plane.path_prefix && control_plane.ui_enabled ->
    respond_html (page_html control)
  | `GET, path when path = status_path control_plane -> handle_api_status control req
  | `GET, path when path = memory_session_path control_plane ->
    handle_api_memory_get control req
  | `POST, path when path = reload_path control_plane -> handle_api_reload control req
  | `POST, path when path = privacy_preview_path control_plane ->
    handle_api_privacy_preview control req body
  | `PUT, path when path = memory_session_path control_plane ->
    handle_api_memory_put control req body
  | `DELETE, path when path = memory_session_path control_plane ->
    handle_api_memory_delete control req
  | _ -> Json_response.respond_error (Domain_error.route_not_found path)
;;
