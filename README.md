# AegisLM

AegisLM est une passerelle LLM écrite en OCaml, conçue comme une réinterprétation fonctionnelle et sécurisée des usages couverts publiquement par LiteLLM, sans reprise de code ni de structure interne.

## Objectif

- exposer des endpoints compatibles OpenAI pour `chat/completions`, `responses`, `embeddings`, `models`
- router vers plusieurs fournisseurs avec fallback ordonné
- appliquer des clés virtuelles, budgets et rate limits
- bloquer par défaut les destinations d'egress sensibles
- redacter systématiquement les secrets dans les traces

## Principes de différenciation

- architecture hiérarchique par domaines métier
- configuration externalisée et versionnée en JSON hiérarchisé
- auth fail-closed, egress allowlist/denylist, et absence de forwarding implicite de headers sensibles
- couverture de tests intégration et unités avant extension fonctionnelle
- compteurs en mémoire protégés pour l’accès concurrent, avec test multicœur

## Démarrage

```bash
opam install . --deps-only --with-test
dune runtest
dune exec aegislm -- --config config/example.gateway.json
./scripts/smoke_openai.sh
```

Le script de smoke choisit automatiquement `claude-sonnet` si `ANTHROPIC_API_KEY` est disponible, sinon `gpt-5-mini` si `OPENAI_API_KEY` est disponible.

## Limites actuelles

- MVP centré sur `chat/completions`, `responses`, `embeddings`, `models`
- providers implémentés: `openai_compat`, `anthropic`
- stockage des budgets en mémoire pour le runtime courant
