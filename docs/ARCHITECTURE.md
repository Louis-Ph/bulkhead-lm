# Architecture

## Layers

- `config/`: hierarchical instance configuration and default policy catalogs
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
- explicit separation between security policy, runtime state, and provider adapters
- fail-closed egress defaults
- no implicit propagation of client secrets to upstream providers
