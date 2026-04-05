# Security Posture

For supported versions and vulnerability reporting instructions, see the
repository [Security Policy](../SECURITY.md). This document describes the
technical control set and current gaps.

## Goals

- minimize secret exposure
- reduce SSRF, loopback, and RFC1918 egress risk
- make keys, budgets, and audit events inspectable
- keep upstream failures isolated and explicit

## Current controls

- virtual keys are hashed with SHA-256 in runtime state
- loopback hosts and common private ranges are blocked by default
- inbound JSON request bodies are rejected once they exceed the configured size limit
- sensitive JSON fields are recursively redacted before log-oriented handling
- fallback routing is only allowed across explicitly configured backends
- daily budgets and per-minute request limits are enforced at the gateway
- prompt privacy filtering redacts common contact data, national IDs, payment-card strings, and token-shaped secrets before upstream dispatch
- threat detection blocks prompt-injection, credential-exfiltration, and tool-abuse signals before provider execution
- output guard blocks private-key material and other configured secret markers before responses are returned
- upstream provider calls are time-boxed by configured request timeout policy
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
