# CLAUDE.md

> Hub for Claude Code (and other LLM coding assistants) working in this repo.
> This file is loaded automatically at session start. Keep it short, factual,
> and pointer-heavy — the long-form docs live elsewhere.

## What this project is

BulkheadLM is a **security-first OCaml LLM gateway**. It exposes an
OpenAI-compatible HTTP API at `http://127.0.0.1:4100`, routes requests
across explicit provider backends, and keeps routing, security policy, and
error behavior in hierarchical JSON. Production-quality, single-maintainer,
~16k lines of OCaml.

## Layout you will use most

| Where | What |
|---|---|
| `src/domain/` | OpenAI-compatible types, `Config.t`, parsing, validation |
| `src/runtime/` | router, pool selector, latency tracker, circuit breaker, budget ledger |
| `src/providers/` | per-provider HTTP adapters (Anthropic, OpenAI-compat, SSH peers) |
| `src/connectors/` | webhook bridges to chat platforms (Telegram multi-persona, WhatsApp, Discord, ...) |
| `src/http/` | request body parsing, SSE serialization, control plane |
| `src/persistence/` | SQLite-backed virtual keys, budgets, pool overrides, audit log |
| `src/client/` | starter REPL, terminal client (ask/call/worker), starter wizard |
| `test/` | Alcotest-Lwt suites, organized by feature area (numbered prefixes) |
| `config/` | example gateway configs, default policies, local_only/ for git-ignored secrets |
| `docs/` | ARCHITECTURE.md, SECURITY.md, COMPLIANCE_US_CN.md, USER_CONNECTOR_ROADMAP.md |

## Build, test, run

The project ships with a project-local OCaml toolchain under
`.bulkhead-tools/` and `_opam/`, so you almost never need a global opam.

```bash
./scripts/with_local_toolchain.sh dune build
./scripts/with_local_toolchain.sh dune runtest
./scripts/with_local_toolchain.sh dune exec bulkhead-lm -- --config config/example.gateway.json
```

If a global `opam`/`dune` is installed, `dune build` and `dune runtest`
work directly. Tests must stay green: 121+ Alcotest cases at the time of
writing.

## Conventions to follow

- **Hierarchy first.** New features add a new module in the right layer
  rather than extending an existing god-module.
- **Fail-closed defaults.** Egress, threat detection, and output guards
  block by default. Don't relax them in shared configs; isolate
  permissive configs under `config/local_only/` (git-ignored).
- **No implicit secret propagation.** Client `authorization` and
  `x-api-key` headers are NEVER forwarded upstream. Each backend has its
  own `api_key_env`.
- **Explicit provider registration.** Adding a provider kind requires a
  new constructor in `Config.provider_kind`, a parser entry, an adapter
  in `src/providers/`, the registry, and the schema in
  `config/defaults/providers.schema.json`.
- **Tests next to the change.** A behaviour change must come with a test
  in the relevant suite under `test/`. Suites are numbered for ordering.
- **Conventional commits.** `feat(scope):`, `fix(scope):`,
  `docs(scope):`, `chore(scope):`, etc. The recent history is a good
  reference.

## Key concepts (one-liners)

- **Route** = `public_model -> [backend, ...]`; existing fallback ladder
  with circuit breaker per backend.
- **Pool** = named group of routes with per-member daily token budgets;
  the router picks the lowest-latency healthy in-budget member. The
  special `global` pool aggregates every configured route.
- **Persona** = a Telegram bot entry in
  `Config.user_connectors.telegram`; multiple personas in the same chat
  with `room_memory_mode: shared` see each other's replies.
- **Virtual key** = a hashed bearer token with route allowlist, daily
  token budget, and per-minute rate limit; the gateway authenticates
  every request against this list.
- **Discovery** = read-only fetch of a provider's `/models` endpoint
  with a 24h on-disk cache; never rewrites routes.

## Useful slash commands (for Claude Code)

This repo ships custom Claude Code commands under `.claude/commands/`.
Type `/` in Claude Code to see them. The most useful ones are:

- `/install-bulkhead` — paste the 5-minute install prompt into the
  current Claude Code session and run it
- `/bulkhead-models` — list configured models and pools via curl
- `/bulkhead-chat` — send a one-shot chat completion through the gateway
- `/bulkhead-pool` — pool inspection and mutation
- `/bulkhead-persona` — show Telegram persona config
- `/bulkhead-discover` — provider model discovery
- `/bulkhead-health` — health check + ready model count

The same commands are described in `INSTALL_PROMPT.md` for users on
non-Claude-Code IDEs (Cursor, ChatGPT, Copilot Chat).

## When you write OCaml here

- Match existing module style: `*_test_support.ml` for shared test
  helpers, no global mutable state at module scope, `Mutex` for the few
  shared mutable maps that exist
- Prefer `Result.bind`/`>>=` over deeply-nested `match`
- Use `Fmt.str` for formatted strings (already a dependency)
- Use `Lwt.Infix` for async; the project is Lwt-based, not Eio
- Type annotate record fields when the inferred type is ambiguous
  (especially around `Config.backend` and `Model_catalog.provider_model`
  which both have an `upstream_model` field)

## When you change starter behavior

- Add the command name to `src/client/starter_constants.ml`
- Add a parsed-command variant to `src/client/starter_session.ml`'s
  `command` type and an effect variant to its `effect` type
- Add the parser branch in `parse_command`
- Add the dispatch branch in `step` and the handler in
  `src/client/starter_wizard.ml`
- Add the help line in `command_help_entries`

## When you touch security policy

Update `docs/SECURITY.md`, add a test in `test/`, and call out the change
in the PR description. Default permission expansions need an explicit
opt-in flag.
