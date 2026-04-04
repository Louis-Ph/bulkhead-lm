# AegisLM

[![CI](https://github.com/Louis-Ph/aegis-lm/actions/workflows/ci.yml/badge.svg)](https://github.com/Louis-Ph/aegis-lm/actions/workflows/ci.yml)

AegisLM is a security-first LLM gateway written in OCaml. It exposes an OpenAI-compatible API, routes requests across explicit provider backends, and keeps routing, security policy, and error behavior in hierarchical JSON instead of ad-hoc runtime discovery.

It targets multi-provider LLM gateway routing with a stricter design bias: explicit module boundaries, explicit provider registration, bounded fallback, fail-closed egress, and auditable request controls.

## Why AegisLM

- OpenAI-compatible client surface for `models`, `chat/completions`, `responses`, and `embeddings`
- explicit provider hierarchy instead of blind proxying
- virtual keys with per-key route allowlists, rate limits, and token budgets
- fail-closed network posture for loopback and common private ranges
- stable gateway-level SSE contract even when providers differ
- programmable terminal client with a human-facing `ask` mode and a JSONL worker mode
- programmable terminal client ops for bounded file browsing, file writes, and command execution
- clone-and-run local starter for macOS, Ubuntu, and FreeBSD with guided first-run setup
- OCaml codebase with clear separation between domain, runtime, security, providers, HTTP, and persistence layers

## Current capabilities

- ordered backend fallback per public model route
- persistent virtual keys, budget usage, and audit events in SQLite
- recursive secret redaction before log-oriented handling
- request body limits and upstream request timeouts
- retry-aware fallback that avoids failing over on permanent upstream errors
- multicore-safe budget and rate-limit state with a `Domain.spawn` test

## Quick start

Install dependencies, run the test suite, and start the gateway:

```bash
opam install . --deps-only --with-test
dune runtest
dune exec aegislm -- --config config/example.gateway.json
```

The bundled example listens on `http://127.0.0.1:4100` and creates a local virtual key: `sk-aegis-dev`.

You can also override the listen port:

```bash
dune exec aegislm -- --config config/example.gateway.json --port 4200
```

## Local starter

On macOS, Ubuntu, or FreeBSD, the simplest entry point is the starter script:

```bash
./run.sh
```

On macOS, you can also use the Finder-friendly launcher:

```bash
./start-macos-client.command
```

The starter:

- supports local first-run flows on macOS, Ubuntu, and FreeBSD through OS-specific wrappers behind the same `./run.sh` entrypoint
- sources `~/.zshrc.secret`, `~/.zshrc.secrets`, `~/.bashrc.secret`, `~/.bashrc.secrets`, `~/.profile.secret`, `~/.profile.secrets`, and `~/.config/aegislm/env` when present
- checks the current `opam` switch first and only offers a project-local fallback when the active toolchain is not coherent for this repo
- can offer Homebrew, `apt`, or `pkg` bootstrap steps instead of dropping raw OCaml build errors on a beginner
- reuses your configured provider keys from the shell environment
- asks which configured model you want to use now
- can build a personal portable JSON config at `config/starter.gateway.json`
- uses real line editing in the human starter: left/right arrows, in-line edits, history recall, and tab completion
- keeps a followed conversation thread by default and compresses older turns into a shorter memory summary when the session grows
- shows masked environment and provider readiness state from inside the REPL
- drops you into a simple terminal session with `/model`, `/models`, `/swap`, `/memory`, `/forget`, `/thread on|off`, `/providers`, `/env`, `/config`, `/help`, and `/quit`

## Terminal client

For direct terminal use without starting the HTTP gateway, use `aegislm-client`.

Human-facing prompt mode:

```bash
dune exec aegislm-client -- ask \
  --config config/example.gateway.json \
  --model gpt-5-mini \
  "Summarize the value of AegisLM in one sentence."
```

Programmatic one-shot mode:

```bash
printf '%s\n' \
  '{"model":"gpt-5-mini","messages":[{"role":"user","content":"Reply with OK."}]}' \
  | dune exec aegislm-client -- call \
      --config config/example.gateway.json \
      --kind chat
```

Long-running worker mode over JSONL with bounded parallelism:

```bash
dune exec aegislm-client -- worker \
  --config config/example.gateway.json \
  --jobs 4
```

Worker input line example:

```json
{"id":"job-1","kind":"chat","request":{"model":"gpt-5-mini","messages":[{"role":"user","content":"Reply with OK."}]}}
```

Worker output line example:

```json
{"ok":true,"id":"job-1","kind":"chat","line":1,"response":{"id":"chatcmpl-...","object":"chat.completion","model":"gpt-5-mini","choices":[...],"usage":{...}}}
```

Worker responses are emitted when jobs complete, not in submission order. Use `id` for correlation.

Use `worker` when several programmatic callers should share one in-process runtime, one rate-limit state, and one persistence handle. Use `ask` or `call` for isolated one-shot invocations.

Structured client operations are also available through `--kind ops`. They are disabled by default and only activate when `security_policy.client_ops` explicitly enables bounded roots.

Minimal policy example:

```json
{
  "client_ops": {
    "files": {
      "enabled": true,
      "read_roots": ["/srv/aegislm/workspace"],
      "write_roots": ["/srv/aegislm/workspace"],
      "max_read_bytes": 1048576,
      "max_write_bytes": 1048576
    },
    "exec": {
      "enabled": true,
      "working_roots": ["/srv/aegislm/workspace"],
      "timeout_ms": 10000,
      "max_output_bytes": 65536
    }
  }
}
```

One-shot directory listing:

```bash
printf '%s\n' \
  '{"op":"list_dir","path":"."}' \
  | dune exec aegislm-client -- call \
      --config config/example.gateway.json \
      --kind ops
```

One-shot file upload/write with base64:

```bash
printf '%s\n' \
  '{"op":"write_file","path":"artifacts/report.bin","encoding":"base64","content":"SGVsbG8=","create_parents":true}' \
  | dune exec aegislm-client -- call \
      --config config/example.gateway.json \
      --kind ops
```

One-shot command execution:

```bash
printf '%s\n' \
  '{"op":"exec","command":"/bin/ls","args":["-la"],"cwd":"."}' \
  | dune exec aegislm-client -- call \
      --config config/example.gateway.json \
      --kind ops
```

## SSH remote usage

For a human remote session over SSH:

```bash
ssh -t user@remote '/opt/aegis-lm/scripts/remote_starter.sh'
```

For a programmatic remote worker over SSH:

```bash
ssh -T user@remote '/opt/aegis-lm/scripts/remote_worker.sh --config /etc/aegislm/gateway.json'
```

The full guide is in [docs/SSH_REMOTE.md](docs/SSH_REMOTE.md).

For a clean client machine that does not have AegisLM yet, an existing remote
AegisLM install can also serve a local bootstrap installer over SSH:

```bash
ssh user@remote '/opt/aegis-lm/scripts/remote_install.sh --emit-installer --origin user@remote' | sh
```

That installs a filtered snapshot locally, by default into `~/opt/aegis-lm`,
then the local user can start it with:

```bash
cd ~/opt/aegis-lm
./run.sh
```

## Peer mesh

One AegisLM instance can use another AegisLM instance as an upstream LLM by
declaring the backend as `aegis_peer` for HTTP or `aegis_ssh_peer` for direct
worker-over-SSH transport. Both keep the relationship explicit in config and
both preserve bounded peer hop headers so accidental `A -> B -> A` loops fail
closed instead of recursing.

The full guide is in [docs/PEER_MESH.md](docs/PEER_MESH.md).

## Copy-paste demo

List the public models exposed by the local gateway:

```bash
curl -s http://127.0.0.1:4100/v1/models \
  -H "Authorization: Bearer sk-aegis-dev"
```

Then call a routed model once at least one upstream provider key is exported in your shell:

```bash
curl -s http://127.0.0.1:4100/v1/chat/completions \
  -H "Authorization: Bearer sk-aegis-dev" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5-mini",
    "messages": [
      { "role": "user", "content": "Say hello from AegisLM in one sentence." }
    ]
  }'
```

The example gateway file is [config/example.gateway.json](config/example.gateway.json).

## Providers and routes

Example route families currently implemented:

- `openai_compat`
- `anthropic`
- `google_openai`
- `ollama_openai`
- `alibaba_openai`
- `moonshot_openai`
- `aegis_peer`
- `aegis_ssh_peer`

The bundled example config includes:

- `gpt-5-mini` via OpenAI
- `claude-sonnet` via Anthropic
- `gemini-2.5-flash` via Google's OpenAI-compatible interface
- `qwen-plus` via Alibaba Model Studio OpenAI-compatible mode
- `kimi-k2.5` via Moonshot's OpenAI-compatible interface

Ollama is also supported through its OpenAI-compatible interface, for example on `http://127.0.0.1:11434/v1` with a local model such as `llama3.2`.

It is not enabled in the bundled example config because the default fail-closed egress policy blocks loopback and private-range upstreams. To use Ollama intentionally, relax the egress policy for your deployment and add a route such as:

```json
{
  "public_model": "llama3.2-local",
  "backends": [
    {
      "provider_id": "ollama-local",
      "provider_kind": "ollama_openai",
      "upstream_model": "llama3.2",
      "api_base": "http://127.0.0.1:11434/v1",
      "api_key_env": "OLLAMA_API_KEY"
    }
  ]
}
```

Set `OLLAMA_API_KEY=ollama` when using that interface. Ollama documents that this key is required by client tooling but ignored by the local server.

Use the Beijing DashScope base instead of the international base when you intentionally deploy against the mainland China region.

## Real-provider smoke tests

```bash
./scripts/smoke_openai.sh
./scripts/integration_matrix.sh
```

`smoke_openai.sh` automatically selects, in order, `claude-sonnet`, `qwen-plus`, `kimi-k2.5`, `gemini-2.5-flash`, then `gpt-5-mini` when the corresponding provider key is present.

`integration_matrix.sh` exercises:

- Anthropic
- Google Gemini through the official OpenAI-compatible interface
- Alibaba Model Studio through DashScope OpenAI-compatible mode
- Moonshot Kimi through its OpenAI-compatible chat interface
- OpenAI when the upstream key is available and has quota
- SSE for `chat/completions`
- SSE for `responses`
- SQLite persistence for virtual keys and audit events

## Architecture at a glance

```text
start-macos-client.command

bin/
  client.ml
  main.ml

config/
  defaults/
    error_catalog.json
    providers.schema.json
    security_policy.json
  compliance/
    prc_defense_overlay_profile.json
    prc_regulated_network_profile.json
    us_dod_unclassified_profile.json
  example.gateway.json

docs/
  ARCHITECTURE.md
  COMPLIANCE_US_CN.md
  SECURITY.md

scripts/
  integration_matrix.sh
  macos_starter.sh
  starter_common.sh
  ubuntu_starter.sh
  freebsd_starter.sh
  remote_common.sh
  remote_starter.sh
  remote_worker.sh
  smoke_openai.sh

src/
  client/
  domain/
  security/
  runtime/
  providers/
  http/
  persistence/

test/
  aegis_lm_test.ml
```

See [Architecture](docs/ARCHITECTURE.md) for the layer-by-layer design.

## Security and compliance

AegisLM is a hardening-oriented gateway, not a certification claim.

Current built-in controls include:

- explicit upstream allow/deny decisions instead of runtime discovery
- no implicit forwarding of client `authorization` or `x-api-key` headers upstream
- bounded fallback routing
- request size and timeout enforcement
- persistent audit logging
- request and token budget enforcement before uncontrolled fan-out
- bounded worker concurrency with per-request output isolation on stdio

Detailed references:

- [Security Posture](docs/SECURITY.md)
- [Security Policy](SECURITY.md)
- [US and China Compliance Study](docs/COMPLIANCE_US_CN.md)

## Contributing and support

- contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- code of conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- repository settings guide: [docs/GITHUB_REPOSITORY_SETTINGS.md](docs/GITHUB_REPOSITORY_SETTINGS.md)
- support process: [SUPPORT.md](SUPPORT.md)
- vulnerability reporting: [SECURITY.md](SECURITY.md)

## Test strategy

The current suite covers:

- recursive secret redaction
- virtual-key authentication failure paths
- budget enforcement
- provider fallback behavior
- localhost and private-range egress blocking
- multicore-safe budget accounting
- `responses` request/response normalization
- SSE framing for `chat/completions` and `responses`
- persistence survival across restart
- audit-log persistence

Run the full suite with:

```bash
dune build @runtest
```

## Status and limitations

- provider-native upstream streaming is not implemented yet; SSE is currently normalized by the gateway from the provider-normalized response
- provider coverage is intentionally narrow and explicit
- Moonshot is currently modeled as chat-only in the provider schema
- there is no admin UI or hot-reload control plane yet
- the worker protocol is currently JSONL over stdio rather than a binary IPC protocol
- the guided local starter currently targets macOS, Ubuntu, and FreeBSD; other systems should use `aegislm-client starter` directly
- military or sovereign-environment compliance still requires deployment hardening, supply-chain evidence, identity integration, and formal assessment artifacts

## License

AegisLM is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
