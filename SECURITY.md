# Security Policy

This document covers supported versions and vulnerability reporting. For the
technical control set and current hardening posture, see [docs/SECURITY.md](docs/SECURITY.md).

## Supported versions

Until `1.0.0`, BulkheadLM is maintained as a fast-moving early-stage project.

| Version line | Supported |
| --- | --- |
| `main` | Yes |
| Latest tagged release | Yes, once tags exist |
| Older commits and ad-hoc forks | No |

## Reporting a vulnerability

Please do not open a public issue for security vulnerabilities.

Preferred channel:

1. Use GitHub Private Vulnerability Reporting for this repository if it is enabled.

Fallback channel:

1. Contact the maintainer privately on GitHub: `@Louis-Ph`.
2. Include the affected endpoint or feature, impact, reproduction steps, and any sanitized logs or payloads.
3. State whether the issue is already known publicly.

## Response targets

- initial acknowledgement within 5 business days
- status update after triage when the report is actionable
- coordinated disclosure after a fix or mitigation is available

## Scope guidance

The most security-sensitive areas in this repository currently include:

- authentication and virtual-key handling
- request normalization and body parsing
- routing and retry behavior
- egress filtering
- persistence of budgets and audit events
- SSE and streaming lifecycle management

## Operational note

If you plan to run BulkheadLM in a regulated or high-assurance environment, review
both [docs/SECURITY.md](docs/SECURITY.md) and
[docs/COMPLIANCE_US_CN.md](docs/COMPLIANCE_US_CN.md) before deployment.
