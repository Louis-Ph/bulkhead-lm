module Limits = struct
  let gateway_json_chars = 16_000
  let security_json_chars = 12_000
  let doc_excerpt_chars = 2_400
  let max_docs = 3
end

module Docs = struct
  let readme = "README.md"
  let architecture = "docs/ARCHITECTURE.md"
  let github = "docs/GITHUB_REPOSITORY_SETTINGS.md"
  let ssh_remote = "docs/SSH_REMOTE.md"
  let peer_mesh = "docs/PEER_MESH.md"
  let security = "SECURITY.md"

  let general = [ readme; architecture; security ]
  let github_related = [ github; readme; architecture ]
  let ssh_related = [ ssh_remote; peer_mesh; architecture ]
  let provider_related = [ readme; architecture; security ]
end

module Prompt = struct
  let system_instruction =
    String.concat
      "\n"
      [ "You are the AegisLM administrative assistant."
      ; "Always target AegisLM configuration first, then bounded local system actions if they are still needed."
      ; "Return JSON only. Do not wrap it in Markdown."
      ; "Explain the plan so a 10-year-old can understand it."
      ; "Never invent secrets, tokens, or file contents you were not given."
      ; "Prefer config_ops over system_ops."
      ; "Use system_ops only when configuration alone is insufficient."
      ; "If the request is unsafe, unclear, or unnecessary, return empty config_ops and empty system_ops with a warning."
      ; "Respect the response schema exactly:"
      ; "{\"kid_summary\": string, \"why\": string[], \"warnings\": string[], \"config_ops\": config_op[], \"system_ops\": terminal_op[]}"
      ; "config_op must be one of:"
      ; "{\"op\":\"set_json\",\"target\":\"gateway_config|security_policy\",\"path\":\"/json/pointer\",\"value\":...}"
      ; "{\"op\":\"delete_json\",\"target\":\"gateway_config|security_policy\",\"path\":\"/json/pointer\"}"
      ; "{\"op\":\"append_json\",\"target\":\"gateway_config|security_policy\",\"path\":\"/json/pointer\",\"value\":...,\"unique\":true|false}"
      ; "system_ops must use the existing terminal ops schema with op=list_dir|read_file|write_file|exec."
      ]
  ;;
end

module Text = struct
  let usage =
    "/admin expects a request, for example: /admin enable local file operations only for this repository"
  ;;

  let no_plan =
    "No admin plan is pending. Use /admin followed by a plain-language request first."
  ;;

  let discarded = "Pending admin plan discarded."
  let planning = "Preparing an admin plan with the current model..."
  let applying = "Applying the pending admin plan..."
  let empty_plan = "The assistant decided no change is needed."
end
