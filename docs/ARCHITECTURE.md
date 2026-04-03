# Architecture

## Layers

- `config/`: hierarchical instance configuration and default policy catalogs
- `src/client/`: direct terminal client and JSONL worker mode over the shared runtime
- `run.sh`: clone-and-run local wrapper that dispatches to the supported OS starter for macOS, Ubuntu, or FreeBSD
- `scripts/starter_common.sh`: shared shell bootstrap layer for the local starters, including env loading, opam checks, build validation, and local-switch fallback
- `scripts/macos_starter.sh`: beginner-oriented macOS launcher with Homebrew-aware bootstrap behavior
- `scripts/ubuntu_starter.sh`: beginner-oriented Ubuntu launcher with `apt` bootstrap behavior
- `scripts/freebsd_starter.sh`: beginner-oriented FreeBSD launcher with `pkg` bootstrap behavior
- `scripts/remote_starter.sh`: remote human wrapper for SSH sessions with a TTY
- `scripts/remote_worker.sh`: remote machine wrapper for JSONL worker traffic over SSH without a TTY
- `src/domain/`: business types, OpenAI-compatible JSON parsing, normalized errors
- `src/security/`: authentication, secret redaction, egress policy
- `src/runtime/`: in-memory state, budget ledger, rate limiting, routing
- `src/providers/`: upstream adapters by provider family
- `src/http/`: HTTP handlers and SSE serialization
- `src/persistence/`: SQLite-backed persistence for keys, budgets, and audit events
- `test/`: behavior, security, and concurrency invariants

## Request flow for `/v1/chat/completions`

1. The HTTP layer parses the OpenAI-compatible request body.
2. Request body size is bounded by configured server policy before full materialization.
3. `Auth` resolves the presented virtual key from its hashed form.
4. `Rate_limiter` enforces a per-minute ceiling.
5. `Router` resolves the public model to an explicit backend list.
6. `Egress_policy` blocks loopback and private destinations before any upstream call.
7. Each upstream attempt is time-boxed by configured request timeout policy.
8. The selected provider adapter rewrites the request for the upstream API.
9. `Budget_ledger` debits token usage after a successful response.
10. The response is returned in OpenAI-compatible shape.

## SSE

- when `stream=true`, the gateway first normalizes the upstream response
- it then emits a consistent `text/event-stream` format to the client
- this keeps the external contract stable even though provider-native streaming is not yet wired per backend

## Terminal client and worker mode

- `aegislm-client ask` dispatches directly against the shared runtime without starting the HTTP server
- `aegislm-client call` accepts one JSON request on stdin and returns one JSON response on stdout
- `aegislm-client worker` keeps one runtime store alive and processes JSONL requests with bounded concurrency
- `aegislm-client starter` is an interactive wizard that can write a portable config JSON and then launch a local terminal session
- `Starter_constants` centralizes the public starter command strings and defaults
- `Starter_conversation` keeps a compressed local transcript and converts older turns into a shorter summary message
- `Starter_runtime` isolates mutable starter session data, such as conversation memory, from the finite-state command parser
- `Starter_session` models the starter REPL as a finite-state machine with explicit `Ready`, `Streaming`, and `Closed` states
- `Starter_terminal` owns human-facing line editing, persistent history, and slash-command/model completion
- `ask` and `call` are isolated per-process invocations, while `worker` is the mode intended to coordinate many concurrent local jobs through one runtime instance
- worker outputs are serialized under a dedicated stdout lock so parallel jobs do not interleave their JSON lines
- shared rate-limit, budget, and persistence state remain protected by the existing `Mutex` and SQLite locking strategy

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
