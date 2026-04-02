# AegisLM

AegisLM est une passerelle LLM écrite en OCaml, conçue comme une réinterprétation fonctionnelle et sécurisée des usages couverts publiquement par LiteLLM, sans reprise de code ni de structure interne.

## Objectif

- exposer des endpoints compatibles OpenAI pour `chat/completions`, `responses`, `embeddings`, `models`
- supporter `stream=true` via SSE pour `chat/completions` et `responses`
- router vers plusieurs fournisseurs avec fallback ordonné
- appliquer des clés virtuelles, budgets et rate limits
- persister durablement clés virtuelles, budgets et audit log dans SQLite
- bloquer par défaut les destinations d'egress sensibles
- redacter systématiquement les secrets dans les traces

## Principes de différenciation

- architecture hiérarchique par domaines métier
- configuration externalisée et versionnée en JSON hiérarchisé
- auth fail-closed, egress allowlist/denylist, et absence de forwarding implicite de headers sensibles
- couverture de tests intégration et unités avant extension fonctionnelle
- compteurs en mémoire protégés pour l’accès concurrent, avec test multicœur
- persistance SQLite hiérarchisée hors du code métier

## Démarrage

```bash
opam install . --deps-only --with-test
dune runtest
dune exec aegislm -- --config config/example.gateway.json
./scripts/smoke_openai.sh
./scripts/integration_matrix.sh
```

Le script de smoke choisit automatiquement `claude-sonnet` si `ANTHROPIC_API_KEY` est disponible, sinon `gpt-5-mini` si `OPENAI_API_KEY` est disponible.
Le script `integration_matrix.sh` vérifie en réel Anthropic, Google, OpenAI si disponible, les deux endpoints SSE et la persistance SQLite.

## Limites actuelles

- providers implémentés: `openai_compat`, `anthropic`, `google_openai`
- le SSE est actuellement généré par la gateway à partir de la réponse provider normalisée
- pas encore de streaming upstream natif provider par provider
