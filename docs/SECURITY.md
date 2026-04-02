# Security Posture

## Goals

- minimize secret exposure
- reduce SSRF, loopback, and RFC1918 egress risk
- make keys, budgets, and audit events inspectable
- keep upstream failures isolated and explicit

## Current controls

- virtual keys are hashed with SHA-256 in runtime state
- loopback hosts and common private ranges are blocked by default
- sensitive JSON fields are recursively redacted before log-oriented handling
- fallback routing is only allowed across explicitly configured backends
- daily budgets and per-minute request limits are enforced at the gateway
- audit events are durably stored when SQLite persistence is enabled

## Safety decisions

- the gateway does not implicitly forward client `authorization` or `x-api-key` headers upstream
- upstream URLs are not discovered dynamically
- there is no mandatory telemetry pipeline
- smoke tests read provider credentials from the local environment, never from the repository

## Current gaps

- cryptographic module validation is not tied to a FIPS 140-3 or PRC-approved cryptographic deployment profile yet
- audit storage is persistent, but not yet tamper-evident or WORM-like
- there is no integrated SSO, mTLS, HSM, or hardware-backed key management path yet
- provider-native upstream streaming is not yet implemented per backend
- there is no administrator control plane for live key rotation or policy changes
