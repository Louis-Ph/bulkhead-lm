module Path = struct
  let status_suffix = "/api/status"
  let reload_suffix = "/api/reload"
  let memory_session_suffix = "/api/memory/session"
  let privacy_preview_suffix = "/api/privacy/preview"
end

module Text = struct
  let page_title = "BulkheadLM Control Plane"
  let page_subtitle =
    "Live admin status, config-aware route inventory, and one-click hot reload for the running gateway."

  let token_label = "Admin token"
  let refresh_label = "Refresh status"
  let reload_label = "Reload config"
  let loading_message = "Loading control-plane status..."
  let reload_success = "Reload completed."
end
