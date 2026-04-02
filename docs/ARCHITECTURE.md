# Architecture

## Couches

- `config/`: politiques hiérarchisées et configuration d’instance.
- `src/domain/`: types métier, parsing JSON OpenAI-compatible, erreurs métier.
- `src/security/`: auth, redaction, politique d’egress.
- `src/runtime/`: état en mémoire, budget ledger, rate limiting, routage.
- `src/providers/`: adaptateurs upstream par famille de fournisseur.
- `src/http/`: exposition des endpoints HTTP.
- `src/domain/responses_api.ml`: adaptation minimale de l’API OpenAI `responses`.
- `src/http/sse_stream.ml`: sérialisation SSE normalisée pour `chat/completions` et `responses`.
- `src/persistence/persistent_store.ml`: persistance SQLite des clés, budgets et audits.
- `test/`: invariants de sécurité et de comportement.

## Flux `chat/completions`

1. Le handler HTTP parse la requête OpenAI-compatible.
2. `Auth` vérifie une clé virtuelle par hash SHA-256.
3. `Rate_limiter` applique une limite par minute.
4. `Router` contrôle l’accès à la route publique demandée.
5. `Egress_policy` bloque les destinations locales/privées.
6. Le provider sélectionné traduit la requête vers l’API upstream.
7. `Budget_ledger` débite le coût tokenisé après réponse.
8. La réponse revient au client au format OpenAI-compatible.

## SSE

- si `stream=true`, la gateway normalise d’abord la réponse provider
- elle émet ensuite un flux `text/event-stream` homogène côté client
- cette version ne dépend donc pas encore des protocoles de streaming spécifiques à chaque provider

## Concurrence

- les compteurs `budget_usage` et `request_windows` sont protégés par `Mutex`
- les principals sont chargés dans une map immuable à l’initialisation
- un test `Domain.spawn` valide qu’un budget journalier n’est pas dépassé sous charge concurrente

## Persistance

- `virtual_keys` stocke les clés hashées, budgets, RPM et routes autorisées
- `budget_usage` garde les consommations journalières persistées entre redémarrages
- `audit_log` enregistre les appels métier et leurs statuts

## Différenciation volontaire

- configuration JSON hiérarchisée plutôt qu’accumulation de littéraux dispersés
- séparation nette entre politique de sécurité, runtime et adaptateurs de fournisseurs
- egress fail-closed par défaut
- aucune propagation implicite de headers secrets vers les providers
