# US and China Compliance Study

## Scope and non-claim

This document does not claim that BulkheadLM is currently certified or accredited for United States Department of Defense or Chinese military use.

It is a structured engineering study for turning the current OCaml gateway into:

- a defensible US defense-contractor or DoD-unclassified deployment candidate
- a defensible PRC regulated-network deployment candidate
- a preparation baseline for any later Chinese defense or GJB-specific sponsor profile

As of April 2, 2026, the right framing is not "make one binary compliant with both militaries at once." The defensible framing is "maintain separate assurance profiles, evidence packs, hosting boundaries, and operational controls."

That separation is an inference from the applicable source regimes: US DoD procurement and RMF requirements are not operationally identical to PRC network, data, identity, and military-information controls.

## Current BulkheadLM baseline

BulkheadLM already helps with several control objectives:

- explicit routing instead of arbitrary proxying
- fail-closed egress blocking for loopback and common private ranges
- hashed virtual keys
- persistent budget and audit data
- upstream error isolation
- deterministic configuration catalogs in JSON
- unit, concurrency, and integration test coverage for core security paths

Those are useful building blocks, but they are only a fraction of a real compliance package.

## US baseline: what actually applies

There are two realistic US tracks.

### Track A: defense contractor processing FCI or CUI

For a vendor-operated deployment handling defense data on nonfederal systems, the practical baseline is:

- FAR 52.204-21 for Federal Contract Information
- DFARS 252.204-7012 for Covered Defense Information and incident reporting
- DFARS 252.204-7019 and 252.204-7020 for NIST SP 800-171 assessments
- DFARS 252.204-7021 for CMMC flowdown and certification requirements
- NIST SP 800-171 Rev. 2 as the still-referenced contractual baseline in CMMC Level 2 today
- NIST SP 800-171 Rev. 3 as the modernization target you should map toward now
- NIST SP 800-172 for higher-risk or selected Level 3-style enhanced controls
- NIST SP 800-218 SSDF for secure software development evidence

### Track B: DoD-operated or DoD-hosted deployment

If the gateway is deployed as part of a DoD information system, the baseline expands to:

- DoDI 8510.01 RMF
- NIST SP 800-53 Rev. 5 control selection under RMF
- CNSSI 1253 overlays where applicable
- DISA hardening content and STIG-driven host/container/application baselines
- FIPS 140-3 validated cryptographic modules for the deployed crypto boundary
- incident response, logging, backup, continuity, and authorizing-official evidence

### US gap analysis for BulkheadLM

What BulkheadLM already does well:

- deny-by-default egress posture
- authenticated gateway-level access control
- rate limiting and token-budget enforcement
- persistent audit trail
- secure-SDLC direction through tests and explicit configuration

What is still missing before a serious US defense compliance effort:

- system security plan, asset inventory, system boundary, data flow diagrams, and POA&M
- CUI labeling, data handling policy, retention schedule, and tenant separation model
- strong identity integration such as SSO, mTLS, CAC/PIV-adjacent integration, or equivalent enterprise IAM
- tamper-evident logging, retention policy, time synchronization, and SIEM integration
- signed releases, SBOM generation, provenance attestation, reproducible-build discipline, and vulnerability management workflow
- host and container hardening guides aligned to STIG content
- incident reporting runbooks aligned with contract and RMF obligations
- backup, restore, disaster recovery, and continuity evidence
- FIPS-validated cryptographic deployment choices instead of default library assumptions
- administrative separation of duties and break-glass procedures

### US engineering actions in priority order

1. Add signed release artifacts, SBOM generation, dependency inventory, and provenance attestation.
2. Add structured audit retention, log signing or tamper evidence, and export to a SIEM-friendly format.
3. Add enterprise identity controls: mTLS, OIDC/SAML federation, scoped admin roles, and key rotation workflows.
4. Add deployment baselines for Linux, container, and reverse proxy hardening, with STIG-oriented checklists.
5. Add data classification labels, retention controls, and explicit CUI handling boundaries.
6. Add formal SSP, POA&M, incident response, recovery, and contingency documentation.
7. Validate the production crypto boundary against FIPS 140-3 requirements.

## PRC public and regulated-network baseline

For China, the publicly visible baseline is not a single "military standard." It is a layered compliance stack:

- the Cybersecurity Law, amended on October 28, 2025 and effective January 1, 2026
- the Data Security Law
- the Personal Information Protection Law
- the Network Data Security Management Regulation, effective January 1, 2025
- identity and data-minimization rules such as the National Network Identity Authentication Public Service Measures, effective July 15, 2025
- MLPS 2.0 style classified protection work, usually mapped through standards such as GB/T 22239-2019 and adjacent assessment and design standards
- cross-border data export controls administered through CAC rules and assessments

For any system deployed in China that sends prompts, logs, or embeddings to foreign providers, cross-border data controls become a first-order issue.

### PRC gap analysis for BulkheadLM

What BulkheadLM already helps with:

- explicit egress control
- auditability
- route allowlists
- secret minimization in logs
- deterministic policy files

What is still missing for a serious PRC-regulated deployment:

- in-country deployment profile with no uncontrolled foreign-provider fallback
- data classification, important-data identification, and export-control workflow
- personal-information handling inventory, minimization, retention, deletion, and incident procedures
- MLPS-oriented host, network, identity, and operational documentation
- regulated identity verification or integration with approved identity services when the use case requires it
- domestic cryptographic deployment decisions where the applicable sector or assessor requires them
- local operational procedures, local assessors, and Chinese-language evidence artifacts

### PRC engineering actions in priority order

1. Create a China deployment profile that disables foreign provider routes by default.
2. Add data-residency flags, export-control routing policy, and per-route sovereignty labels.
3. Add personal-information and important-data inventory fields to request, log, and storage policy.
4. Add retention, deletion, and incident-handling controls with explicit operator workflows.
5. Add MLPS-oriented deployment and evidence checklists for host, network, database, and operations layers.
6. Add a local identity profile for high-assurance deployments instead of relying only on bearer-style gateway keys.

## Chinese military or GJB-specific preparation

For actual Chinese military or defense-procurement use, public sources are not enough to make a defensible certification claim.

Two facts matter:

- the Data Security Law explicitly leaves military-data protection measures to the Central Military Commission
- Chinese defense work often introduces GJB family standards and secrecy-system requirements that are sponsor-specific and may not be fully public

What can be done now is preparation, not certification:

- keep architecture modular and policy-driven
- separate public-regulated deployment controls from defense overlays
- keep military-information handling disabled by default
- prepare evidence packs that can later be mapped to sponsor-provided GJB or secrecy requirements

If the gateway will publish, transmit, or manage military information on the internet in China, the `Internet Military Information Dissemination Management Measures` become immediately relevant and must be reviewed with local counsel and the sponsoring authority.

## Hard conflicts between US DoD and PRC defense profiles

The following are likely to conflict and should be separated into distinct deployment profiles:

- foreign-provider access and cross-border data transfer
- cryptographic module expectations and approved deployment stacks
- identity and operator vetting mechanisms
- logging retention and sovereign access requirements
- supply-chain trust, hosting jurisdiction, and assessor accreditation

Inference: a single multi-tenant production deployment should not be represented as satisfying both a US defense profile and a PRC defense profile. Separate environments, separate keys, separate logs, and separate evidence packages are the defensible approach.

## Immediate repository roadmap

The next concrete repository improvements should be:

1. Add `config/compliance/`-driven deployment profiles to the runtime, not just documentation files.
2. Add structured audit export, retention policy, and log integrity support.
3. Add OIDC or mTLS operator authentication and role separation.
4. Add SBOM generation, dependency scanning, release signing, and provenance in CI.
5. Add deployment hardening guides for Linux, reverse proxy, container, and database layers.
6. Add data-sovereignty routing rules so a route can be marked `domestic_only`, `cross_border_forbidden`, or equivalent.

## Sources

### United States

- [NIST SP 800-171 Rev. 3](https://csrc.nist.gov/pubs/sp/800/171/r3/final)
- [NIST SP 800-171 Rev. 2 status page](https://csrc.nist.gov/pubs/sp/800/171/r2/upd1/final)
- [NIST SP 800-172](https://csrc.nist.gov/pubs/sp/800/172/final)
- [NIST SP 800-53 Rev. 5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)
- [NIST SP 800-218 SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)
- [FIPS 140-3](https://csrc.nist.gov/pubs/fips/140-3/final)
- [DoD CMMC program page](https://www.acq.osd.mil/asda/dpc/cp/cyber/cmmc.html)
- [DFARS 204.7302 policy](https://www.acquisition.gov/dfars/204.7302-policy.)
- [DFARS 252.204-7021](https://www.acquisition.gov/dfars/252.204-7021-contractor-compliance-cybersecurity-maturity-model-certification-level-requirements.)
- [CDSE RMF resource page linking DoDI 8510.01 and NIST RMF materials](https://www.cdse.edu/Training/eLearning/CS101-resources/)

### China

- [PRC Cybersecurity Law, amended text published by CAC on December 29, 2025](https://www.cac.gov.cn/2025-12/29/c_1768735112911946.htm)
- [NPC report on the October 28, 2025 amendment to the Cybersecurity Law](https://www.npc.gov.cn/npc/c1773/c1848/c21114/wlaqfxz/wlaqfxz002/202511/t20251103_449242.html)
- [CAC cross-border data security policy Q&A, May 30, 2025](https://www.cac.gov.cn/2025-05/30/c_1750315283722063.htm)
- [National Network Identity Authentication Public Service Measures, CAC announcement, May 23, 2025](https://www.cac.gov.cn/2025-05/23/c_1749711107837215.htm)
- [Ministry of National Defense notice on the Internet Military Information Dissemination Management Measures](https://www.mod.gov.cn/gfbw/qwfb/16368422.html)

Public Chinese military-standard mapping beyond those sources will require sponsor-provided GJB or secrecy-system profiles plus local compliance review.
