# AegisLM

AegisLM is a security-first LLM gateway written in OCaml. It is designed as an independent, functionally comparable reinterpretation of the publicly documented LiteLLM use case surface, without reusing its code, internal structure, or implementation style.

The project favors explicit hierarchy over framework magic:

- business types and request normalization live in `src/domain/`
- security policy lives in `src/security/`
- mutable runtime concerns live in `src/runtime/`
- provider adapters live in `src/providers/`
- HTTP exposure lives in `src/http/`
- persistent state lives in `src/persistence/`
- instance behavior is externalized into hierarchical JSON files under `config/`

## Current capabilities

- OpenAI-compatible endpoints for `/v1/models`, `/v1/chat/completions`, `/v1/embeddings`, and `/v1/responses`
- `stream=true` support for `chat/completions` and `responses` over SSE
- ordered backend fallback per public model route
- virtual keys with per-key route allowlists
- per-key daily token budgets and per-minute request limits
- persistent virtual keys, budget usage, and audit events in SQLite
- fail-closed egress policy for loopback and common private ranges
- recursive secret redaction for sensitive JSON fields before logging paths
- multicore-safe budget and rate-limit state with a `Domain.spawn` test

## Architecture

```text
bin/
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

src/
  domain/
  security/
  runtime/
  providers/
  http/
  persistence/

test/
  aegis_lm_test.ml
```

See [Architecture](docs/ARCHITECTURE.md) and [Security Posture](docs/SECURITY.md) for the layer-by-layer design.

## Quick start

Install dependencies, run the test suite, and start the gateway:

```bash
opam install . --deps-only --with-test
dune runtest
dune exec aegislm -- --config config/example.gateway.json
```

The example policy binds to `http://127.0.0.1:4100`.

You can also override the listen port:

```bash
dune exec aegislm -- --config config/example.gateway.json --port 4200
```

## Real-provider smoke tests

```bash
./scripts/smoke_openai.sh
./scripts/integration_matrix.sh
```

`smoke_openai.sh` automatically selects `claude-sonnet` when `ANTHROPIC_API_KEY` is present, otherwise `gpt-5-mini` when `OPENAI_API_KEY` is present.

`integration_matrix.sh` exercises:

- Anthropic
- Google Gemini through the official OpenAI-compatible interface
- OpenAI when the upstream key is available and has quota
- SSE for `chat/completions`
- SSE for `responses`
- SQLite persistence for virtual keys and audit events

## Configuration model

The gateway intentionally keeps policy outside the code:

- `config/defaults/security_policy.json` defines server, auth, redaction, egress, routing, rate-limit, and budget defaults
- `config/defaults/error_catalog.json` defines externally visible error messages and status codes
- `config/defaults/providers.schema.json` defines supported provider kinds and operations
- `config/example.gateway.json` defines routes, provider backends, virtual keys, and persistence settings

Example route families currently implemented:

- `openai_compat`
- `anthropic`
- `google_openai`

## Security posture

Current built-in controls include:

- SHA-256 hashing for virtual keys at runtime
- no implicit forwarding of client `authorization` or `x-api-key` headers upstream
- explicit upstream allow/deny decisions instead of runtime discovery
- bounded fallback routing
- persistent audit logging
- request and token budget enforcement before uncontrolled fan-out

This is a hardening-oriented gateway, not a certification claim. See [US/China Compliance Study](docs/COMPLIANCE_US_CN.md) for a structured gap analysis.

## Compliance roadmap

The repository now includes a standards study and machine-readable baseline profiles:

- [US/China Compliance Study](docs/COMPLIANCE_US_CN.md)
- `config/compliance/us_dod_unclassified_profile.json`
- `config/compliance/prc_regulated_network_profile.json`
- `config/compliance/prc_defense_overlay_profile.json`

## Standards orientation

As of April 2, 2026, the repository is oriented toward separate compliance profiles, not a single universal claim.

The US-oriented profile is framed around:

- DFARS and CMMC obligations for defense contractors
- NIST SP 800-171 for contractor-side protection of sensitive government data
- NIST SP 800-53 and RMF expectations for DoD-operated environments
- NIST SP 800-218 SSDF for secure software development evidence
- FIPS 140-3 expectations for production cryptographic boundaries

The PRC-oriented profile is framed around:

- the Cybersecurity Law, including the amendment adopted on October 28, 2025 and effective on January 1, 2026
- the Data Security Law
- the Personal Information Protection Law
- CAC-administered cross-border data and identity requirements
- MLPS-style classified protection work for regulated systems

The Chinese defense overlay is intentionally treated as a separate sponsor-specific path. Public law and public standards are not enough to support a serious military-compliance claim on their own.

Important: the same deployed system should not be represented as simultaneously compliant for US DoD and PRC defense environments. Those assurance regimes create different legal, operational, data residency, identity, and cryptographic constraints. Separate deployment profiles and separate evidence packages are the defensible path.

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

## Current limitations

- provider-native upstream streaming is not implemented yet; SSE is currently normalized by the gateway from the provider-normalized response
- provider coverage is intentionally narrow and explicit
- there is no admin UI or hot-reload control plane yet
- military or sovereign-environment compliance still requires deployment hardening, supply-chain evidence, identity integration, and formal assessment artifacts
