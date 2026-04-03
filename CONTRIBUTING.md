# Contributing to AegisLM

Thanks for taking the time to improve AegisLM.

This project favors explicit hierarchy, operational clarity, and test-backed
changes. Contributions are welcome, but they should preserve the design goals of
the repository instead of adding convenience layers that hide control flow or
security behavior.

## Before you start

- open an issue before large features, new provider families, or major refactors
- keep changes narrowly scoped and easy to review
- avoid introducing automatic provider discovery or implicit fallback behavior

## Development setup

```bash
opam install . --deps-only --with-test
dune runtest
```

Run the gateway locally with:

```bash
dune exec aegislm -- --config config/example.gateway.json
```

## Design expectations

- preserve the module hierarchy under `src/client`, `src/domain`, `src/security`, `src/runtime`, `src/providers`, `src/http`, and `src/persistence`
- prefer explicit types and explicit boundaries over convenience wrappers
- do not scatter magic numbers, route names, or externally visible strings when a shared definition or config entry is warranted
- keep provider behavior explicit and auditable
- do not weaken fail-closed security defaults without a documented reason

## Tests and documentation

- behavior changes should include or update tests in `test/`
- public-facing behavior changes should update `README.md` and the relevant docs
- provider additions should update the config schema, example config, and smoke or integration scripts when appropriate

## Pull requests

- describe the user-visible effect of the change
- call out security, routing, or persistence impacts explicitly
- list the tests you ran
- keep commits and diffs reviewable

Conventional commits are preferred, for example:

- `feat: add provider fallback classification`
- `fix: bound request body parsing`
- `docs: clarify security reporting policy`

## Security issues

Do not open public issues for vulnerabilities. Follow [SECURITY.md](SECURITY.md).

## Maintainer review

The maintainer may ask for design tightening, hierarchy cleanup, stronger test
coverage, or clearer externalized configuration before merge.
