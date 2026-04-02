# Architecture

## Couches

- `config/`: politiques hiérarchisées et configuration d’instance.
- `src/domain/`: types métier, parsing JSON OpenAI-compatible, erreurs métier.
- `src/security/`: auth, redaction, politique d’egress.
- `src/runtime/`: état en mémoire, budget ledger, rate limiting, routage.
- `src/providers/`: adaptateurs upstream par famille de fournisseur.
- `src/http/`: exposition des endpoints HTTP.
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

## Différenciation volontaire

- configuration JSON hiérarchisée plutôt qu’accumulation de littéraux dispersés
- séparation nette entre politique de sécurité, runtime et adaptateurs de fournisseurs
- egress fail-closed par défaut
- aucune propagation implicite de headers secrets vers les providers
