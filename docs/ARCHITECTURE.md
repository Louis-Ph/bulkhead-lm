# Architecture

BulkheadLM is not just a locked-down gateway. Architecturally, it is a secure AI router and hyper-connector: multi-provider, multi-machine, multi-client, and peer-to-peer, with enough structure to act as a powerful agent provider for swarm platforms without collapsing into routing chaos.

## Layers

- `config/`: hierarchical instance configuration, default policy catalogs, and a `local_only/` subtree for sensitive local configs that must stay out of git
- `src/client/`: direct terminal client and JSONL worker mode over the shared runtime
- `run.sh`: clone-and-run local wrapper that dispatches to the supported OS starter for macOS, Ubuntu, or FreeBSD
- `scripts/starter_common.sh`: shared shell bootstrap layer for the local starters, including env loading, opam checks, build validation, and local-switch fallback
- `scripts/toolchain_env.sh`: centralized project-local OCaml toolchain paths and version defaults
- `scripts/bootstrap_local_toolchain.sh`: self-contained bootstrap for a repo-local `opam` binary, opam root, and `_opam` switch
- `scripts/with_local_toolchain.sh`: wrapper that executes arbitrary commands inside the project-local switch
- `scripts/macos_starter.sh`: beginner-oriented macOS launcher with Homebrew-aware bootstrap behavior
- `scripts/ubuntu_starter.sh`: beginner-oriented Ubuntu launcher with `apt` bootstrap behavior
- `scripts/freebsd_starter.sh`: beginner-oriented FreeBSD launcher with `pkg` bootstrap behavior
- `scripts/remote_starter.sh`: remote human wrapper for SSH sessions with a TTY
- `scripts/remote_worker.sh`: remote machine wrapper for JSONL worker traffic over SSH without a TTY
- `scripts/remote_install.sh`: remote bootstrap wrapper that can serve a local installer or a filtered repo archive over SSH
- `scripts/package_common.sh`: common staging and wrapper helpers for distributable package builds
- `scripts/build_dist_package.sh`: native package builder for macOS, Ubuntu, and FreeBSD
- `src/domain/`: business types, OpenAI-compatible JSON parsing, normalized errors
- `src/security/`: authentication, privacy filtering, threat detection, output guarding, secret redaction, egress policy, and peer mesh hop control
- `src/runtime/`: in-memory state, budget ledger, rate limiting, routing
- `src/connectors/`: user-facing chat connectors that translate external chat platforms into normal BulkheadLM requests
- `src/providers/`: upstream adapters by provider family
- `src/providers/ssh_peer_protocol.ml`: JSONL-over-SSH envelope used by `bulkhead_ssh_peer`
- `src/http/`: HTTP handlers and SSE serialization
- `src/persistence/`: SQLite-backed persistence for keys, budgets, and audit events
- `test/`: behavior, security, and concurrency invariants

## Request flow for `/v1/chat/completions`

1. The HTTP layer parses the OpenAI-compatible request body.
2. Request body size is bounded by configured server policy before full materialization.
3. `Auth` resolves the presented virtual key from its hashed form.
4. `Rate_limiter` enforces a per-minute ceiling.
5. `Threat_detector` blocks prompt-injection, credential-exfiltration, and tool-abuse signals before upstream execution.
6. `Privacy_filter` redacts configured sensitive content from prompt text before provider dispatch.
7. `Router` resolves the public model to an explicit backend list.
8. `Egress_policy` blocks loopback and private destinations before any upstream call.
9. `Peer_mesh` validates inbound BulkheadLM hop headers before reflexive forwarding is allowed.
10. Each upstream attempt is time-boxed by configured request timeout policy.
11. The selected provider adapter rewrites the request for the upstream API or the SSH worker protocol.
12. `Budget_ledger` debits token usage after a successful response.
13. `Privacy_filter` and `Output_guard` sanitize and validate model output before it is serialized back to the client.

## SSE

- when `stream=true`, the gateway first normalizes the upstream response
- it then emits a consistent `text/event-stream` format to the client
- this keeps the external contract stable even though provider-native streaming is not yet wired per backend

## Terminal client and worker mode

- `bulkhead-lm-client ask` dispatches directly against the shared runtime without starting the HTTP server
- `bulkhead-lm-client call` accepts one JSON request on stdin and returns one JSON response on stdout
- `bulkhead-lm-client worker` keeps one runtime store alive and processes JSONL requests with bounded concurrency
- `bulkhead-lm-client starter` is an interactive wizard that can write a portable config JSON and then launch a local terminal session
- `Admin_assistant` builds structured admin plans from the selected model, local BulkheadLM docs, and the active config files
- `Admin_assistant_plan` keeps config-edit and system-action steps in a typed format before anything is applied
- `Starter_packaging` owns host detection, package defaults, and the live package-build runner used by the starter
- packaging from a source checkout can now reuse the same project-local toolchain wrapper when no global `dune` is present
- `Terminal_ops` owns the structured `ops` protocol for filesystem and command requests under explicit security-policy roots
- `Starter_constants` centralizes the public starter command strings and defaults
- `Starter_conversation` keeps a compressed local transcript and converts older turns into a shorter summary message
- `Starter_saved_config` owns first-run bootstrap and safe migration of the git-ignored local starter config under `config/local_only/`
- `Starter_runtime` isolates mutable starter session data, such as conversation memory and pending admin plans, from the finite-state command parser
- `Starter_session` models the starter REPL as a finite-state machine with explicit `Ready`, `Streaming`, and `Closed` states plus explicit admin-plan effects
- `Starter_terminal` owns human-facing line editing, persistent history, and slash-command/model completion
- `/control` is a factual starter command that renders the current HTTP control-plane status and exact URLs from the active config instead of delegating that answer to model guesswork
- `/package` is a guided starter flow that builds a distributable OS-native package from either a source checkout or an installed BulkheadLM tree
- `ask` and `call` are isolated per-process invocations, while `worker` is the mode intended to coordinate many concurrent local jobs through one runtime instance
- worker outputs are serialized under a dedicated stdout lock so parallel jobs do not interleave their JSON lines
- shared rate-limit, budget, and persistence state remain protected by the existing `Mutex` and SQLite locking strategy
- `ops` requests reuse virtual-key auth and request-rate checks, but they are fail-closed until `security_policy.client_ops` enables explicit read, write, or exec roots
- `chat`, `responses`, and `embeddings` requests all pass through the same threat-detection and privacy-filter chain inside the shared router
- command execution is shell-free: callers send `command` plus `args`, and BulkheadLM applies timeout and output caps before returning a structured result
- starter admin requests are plan-first: the model returns typed JSON, the user reviews it with `/plan`, and only `/apply` mutates config files or runs allowed local ops
- `User_connector_router` centralizes webhook path dispatch instead of growing `Server` route conditionals one connector at a time
- `User_connector_registry` makes connector rollout order and runtime class explicit, so webhook dispatch stays hierarchical as the connector list grows
- `Runtime_control` owns the reloadable top-level gateway state: config path, startup port override, validated runtime swaps, and preservation of in-memory connector sessions across reloads
- `Admin_control` exposes the HTTP control plane UI plus guarded JSON endpoints for status and in-place config reload without mixing those concerns into the inference routes
- `User_connector_common` centralizes per-channel session memory limits, authorization normalization, audit helpers, and text splitting
- `Meta_connector_common` centralizes the shared Meta webhook challenge flow, optional HMAC verification, inbound `entry[].messaging[]` parsing, and Graph send API text delivery for Messenger and Instagram
- `Line_connector` adds LINE-specific reply-token handling and source-scoped session identity without leaking LINE protocol details into the generic router
- `Viber_connector` adds Viber-specific HMAC verification and `send_message` delivery while still reusing the same BulkheadLM auth, memory, and audit path
- `Wechat_connector_crypto` isolates WeChat AES-CBC payload encryption, decryption, `msg_signature` generation, PKCS#7 handling, and secure reply envelopes instead of scattering crypto literals through the connector
- `Wechat_connector_xml` isolates the XML parsing and rendering needed for plaintext and encrypted WeChat Service Account payloads
- `Wechat_connector` adds WeChat plaintext signature validation, encrypted `msg_signature` validation, passive XML replies, and per-account OpenID session scoping on the same policy path as the other chat connectors
- `Discord_connector` adds Discord Ed25519 request verification, slash-command parsing, and deferred interaction response editing without polluting the simpler synchronous connectors
- `Google_chat_id_token` isolates Google Chat bearer-token verification from the higher-level Google Chat event bridge
- user chat connectors reuse the same virtual-key auth path, route allowlists, budgets, and output guards instead of bypassing gateway policy
- connector config is fail-closed on duplicate `webhook_path` values so one HTTP path cannot ambiguously match multiple enabled connectors
- control-plane config is fail-closed on `path_prefix` collisions with `/health`, `/v1/*`, or enabled chat webhooks so the admin surface cannot shadow production endpoints
- `docs/USER_CONNECTOR_ROADMAP.md` keeps the wave-based rollout order explicit, including implemented versus deferred platforms, instead of letting connector growth become opportunistic

## Concurrency model

- mutable request windows and budget counters are protected with `Mutex`
- principals are loaded into an immutable map at initialization time
- the test suite uses `Domain.spawn` to verify that concurrent budget debits do not overspend the daily cap

## Persistence model

- `virtual_keys` stores hashed virtual keys, budgets, request ceilings, and route allowlists
- `budget_usage` persists daily consumption across restarts
- `audit_log` persists security-relevant gateway events and statuses

## Intentional design choices

- hierarchical JSON configuration instead of scattered literals
- a dedicated client layer instead of burying terminal and worker behavior inside the HTTP server
- explicit separation between security policy, runtime state, and provider adapters
- fail-closed egress defaults
- no implicit propagation of client secrets to upstream providers
- reflexive BulkheadLM peering is explicit as `bulkhead_peer`, with bounded hop count by policy
- SSH peering is also explicit as `bulkhead_ssh_peer`, reusing the remote worker protocol instead of tunneling hidden HTTP
