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

let handle control req _body =
  let path = Uri.path (Cohttp.Request.uri req) in
  let control_plane = current_control_plane control in
  match Cohttp.Request.meth req, path with
  | `GET, path when path = control_plane.path_prefix && control_plane.ui_enabled ->
    respond_html (page_html control)
  | `GET, path when path = status_path control_plane -> handle_api_status control req
  | `POST, path when path = reload_path control_plane -> handle_api_reload control req
  | _ -> Json_response.respond_error (Domain_error.route_not_found path)
;;
