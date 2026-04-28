# Architecture

BulkheadLM is not just a locked-down gateway. Architecturally, it is a secure AI router and hyper-connector: multi-provider, multi-machine, multi-client, and peer-to-peer, with enough structure to act as a powerful agent provider for swarm platforms without collapsing into routing chaos.

## Layers

- `config/`: hierarchical instance configuration, default policy catalogs, and a `local_only/` subtree for sensitive local configs that must stay out of git
- `src/client/`: direct terminal client and JSONL worker mode over the shared runtime
- `install.sh`: one-line curl installer that installs git, clones the repo, and launches `run.sh`
- `run.sh`: clone-and-run local wrapper that dispatches to the supported OS starter for any Linux, macOS, or FreeBSD
- `scripts/starter_common.sh`: shared shell bootstrap layer for the local starters, including env loading, opam checks, build validation, and local-switch fallback
- `scripts/toolchain_env.sh`: centralized project-local OCaml toolchain paths and version defaults
- `scripts/bootstrap_local_toolchain.sh`: self-contained bootstrap for a repo-local `opam` binary, opam root, and `_opam` switch
- `scripts/with_local_toolchain.sh`: wrapper that executes arbitrary commands inside the project-local switch
- `scripts/macos_starter.sh`: beginner-oriented macOS launcher with Homebrew-aware bootstrap behavior
- `scripts/linux_starter.sh`: beginner-oriented Linux launcher with auto-detected package manager (apt, dnf, yum, pacman, apk, zypper)
- `scripts/ubuntu_starter.sh`: legacy Ubuntu launcher (kept for backward compatibility)
- `scripts/freebsd_starter.sh`: beginner-oriented FreeBSD launcher with `pkg` bootstrap behavior
- `scripts/remote_starter.sh`: remote human wrapper for SSH sessions with a TTY
- `scripts/remote_worker.sh`: remote machine wrapper for JSONL worker traffic over SSH without a TTY
- `scripts/remote_install.sh`: remote bootstrap wrapper that can serve a local installer or a filtered repo archive over SSH
- `scripts/package_common.sh`: common staging and wrapper helpers for distributable package builds
- `scripts/build_dist_package.sh`: native package builder for macOS, Linux, and FreeBSD
- `src/domain/`: business types, OpenAI-compatible JSON parsing, normalized errors
- `src/security/`: authentication, privacy filtering, threat detection, output guarding, secret redaction, egress policy, and peer mesh hop control
- `src/runtime/`: in-memory state, budget ledger, rate limiting, routing, named-pool selector and latency tracker
- `src/connectors/`: user-facing chat connectors that translate external chat platforms into normal BulkheadLM requests
- `src/providers/`: upstream adapters by provider family
- `src/providers/provider_models_listing.ml`: bounded read-only fetcher for provider `/models` inventories
- `src/providers/ssh_peer_protocol.ml`: JSONL-over-SSH envelope used by `bulkhead_ssh_peer`
- `src/http/`: HTTP handlers and SSE serialization
- `src/persistence/`: SQLite-backed persistence for keys, budgets, and audit events, plus file-backed provider model listing caches
- `test/`: behavior, security, and concurrency invariants

## Request flow for `/v1/chat/completions`

1. The HTTP layer parses the OpenAI-compatible request body.
2. Request body size is bounded by configured server policy before full materialization.
3. `Auth` resolves the presented virtual key from its hashed form.
4. `Rate_limiter` enforces a per-minute ceiling.
5. `Threat_detector` blocks prompt-injection, credential-exfiltration, and tool-abuse signals before upstream execution.
6. `Privacy_filter` redacts configured sensitive content from message text, structured request JSON, embeddings input, and provider-specific extra fields before provider dispatch.
7. `Router.resolve_target` first checks whether the requested public model is a pool name; if so, `Pool_selector.rank` picks ordered candidates and the router cascades through them, otherwise the existing direct-route fallback flow runs unchanged.
8. `Egress_policy` blocks loopback and private destinations before any upstream call.
9. `Peer_mesh` validates inbound BulkheadLM hop headers before reflexive forwarding is allowed.
10. Each upstream attempt is time-boxed by configured request timeout policy.
11. The selected provider adapter rewrites the request for the upstream API or the SSH worker protocol.
12. `Budget_ledger` debits token usage after a successful response. When the request was routed through a pool, `Pool_routing.consume_member_budget` also charges the per-pool-member daily budget atomically and `Pool_latency` records the wall-clock latency for the next ranking.
13. `Privacy_filter` and `Output_guard` sanitize and validate non-streaming output and materialized streaming output before it is serialized back to the client.

## SSE

- when `stream=true`, the gateway materializes the upstream stream before client emission
- the materialized content passes through the same privacy filter and output guard as non-streaming responses
- after that safety pass, the gateway emits a consistent `text/event-stream` format to the client
- this prioritizes pre-response blocking over real-time provider passthrough

## Provider Model Discovery

- production routing still comes from explicit JSON routes; discovered models do not auto-create or rewrite routes
- `Provider_models_listing` fetches model inventories only from known provider `api_base` values and normalizes OpenAI-compatible and Anthropic response shapes
- unsupported provider families such as `bulkhead_peer` and `bulkhead_ssh_peer` return a typed unsupported result instead of a synthetic listing
- `Model_listing_cache` stores one JSON file per provider under `$BULKHEAD_LM_MODEL_CACHE_DIR`, `$XDG_CACHE_HOME/bulkhead-lm/models`, or `~/.cache/bulkhead-lm/models`
- cache freshness is explicit: live, fresh cached, or stale fallback with the last fetch error
- `/discover` and `/refresh-models` are starter commands that populate or refresh the cache for providers with detected API keys
- `/v1/models` exposes configured route metadata plus cached `providers[].discovered_models` when present; it does not perform live provider network calls

## Named pools

Pools are a thin orchestration layer above the route table. Each pool is a
named group of route members with per-member daily token budgets, exposed to
clients as one OpenAI-compatible model id; the router picks the best member at
request time and falls through automatically on failure.

- `Config.pool_member` references an existing `route` by `route_model` and reserves a `daily_token_budget`; `Config.pool` carries the pool name, the member list, and an `is_global` flag
- declarative pools live under the `pools` key in `gateway.json` and are validated tolerantly: an entry that collides with a route name, references a missing route, or fails to parse is dropped silently so the gateway still starts
- `is_global = true` ignores the declared `members` field and recomputes the effective member list as every configured route at lookup time, so adding a route makes it immediately reachable through the global pool
- `Pool_latency` is an in-memory EWMA tracker keyed by `(pool_name, route_model)`; it adds a configurable failure penalty per consecutive failure and exposes a `score` that is `None` for never-observed members so the selector can probe them before well-known slow ones
- `Pool_selector.rank` filters out members whose route is missing, whose budget is exhausted, or whose every backend has its circuit open, and returns both the ranked candidates and the rejection reason for each excluded member; `exhaustion_error` turns an empty ranking into a structured `Domain_error` that lists exactly why every member was rejected
- `Router.resolve_target` is the only public entry point that decides whether the requested model is a pool or a direct route; the existing `try_backends` ladder runs untouched inside each pool candidate, so pool routing inherits per-route fallback, the circuit breaker, and the request timeout
- `Pool_routing.consume_member_budget` charges tokens against the member's daily budget atomically (SQLite `BEGIN IMMEDIATE` when persistence is configured, in-memory hash map otherwise) so two concurrent requests cannot both see a stale "below the limit" snapshot
- `Pool_runtime` owns runtime mutations (`/pool create|drop|add|remove|global`); the entire pool list is serialized as a JSON blob in the `pool_overrides` SQLite table and replayed at startup via `Pool_runtime.load_overrides_into`, so wizard edits survive a gateway restart without forcing an edit to `gateway.json`
- when a pool routes a request, `/v1/models` still surfaces the pool both as an entry in `data[]` (with `model_kind: "pool"` and the `is_global` flag, so vanilla OpenAI clients see it as a plain model) and inside the dedicated `pools[]` section that exposes member detail and per-member budgets

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
- `Starter_session` models the starter REPL as a finite-state machine with explicit `Ready`, `Streaming`, and `Closed` states plus explicit admin-plan and discovery effects
- `Starter_terminal` owns human-facing line editing, persistent history, and slash-command/model completion
- `/control` is a factual starter command that renders the current HTTP control-plane status and exact URLs from the active config instead of delegating that answer to model guesswork
- `/package` is a guided starter flow that builds a distributable OS-native package from either a source checkout or an installed BulkheadLM tree
- `/discover` and `/refresh-models` render provider -> model inventories from the cache/discovery layer without mixing that concern into route selection
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
- the Telegram connector list (`Config.user_connectors.telegram : telegram_connector list`) supports multi-persona deployments where several bots run on one gateway, each with its own `persona_name`, `webhook_path` and `route_model`; legacy single-bot configs (the connector as a JSON object) still parse to a one-element list for backward compatibility
- per-room memory composition uses two modes: `Shared_room` (every persona on the same `chat_id` reads/writes the same conversation thread, with assistant turns tagged `[persona_name] ...` so personas can tell who said what) and `Isolated_per_persona` (each persona keeps a private thread per `chat_id`, used for parallel-bot setups that should not mingle context)
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
- `pool_member_usage` persists daily token consumption per (pool_name, route_model) so per-member budgets reset cleanly at UTC midnight without losing already-charged usage
- `pool_overrides` stores the wizard-driven pool definition snapshot as a JSON blob keyed by scope so `/pool create|add|remove|drop|global` survives a restart, with the declarative `gateway.json` pools acting as the seed
- `audit_log` persists privacy-filtered security-relevant gateway events and statuses
- `connector_sessions` persists privacy-filtered scoped chat memory snapshots for connector-backed conversations
- provider model listings are file-backed JSON cache entries outside the gateway database because they are provider metadata, not security audit state
- pool latency samples are deliberately in-memory only because they are observability state that reconverges within a handful of requests; persisting them would buy little and would add an extra schema

## Intentional design choices

- hierarchical JSON configuration instead of scattered literals
- a dedicated client layer instead of burying terminal and worker behavior inside the HTTP server
- explicit separation between security policy, runtime state, and provider adapters
- explicit separation between curated routing config and provider model discovery cache
- pools are a thin orchestration layer above routes, never a substitute for them: every pool member references an existing route, so security policy, egress, and circuit breakers stay anchored at the route level
- fail-closed egress defaults
- no implicit propagation of client secrets to upstream providers
- reflexive BulkheadLM peering is explicit as `bulkhead_peer`, with bounded hop count by policy
- SSH peering is also explicit as `bulkhead_ssh_peer`, reusing the remote worker protocol instead of tunneling hidden HTTP
