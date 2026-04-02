# Security Posture

## Objectifs

- minimiser l’exposition des secrets
- réduire le risque SSRF / loopback / RFC1918
- rendre le contrôle des budgets et des clés auditable
- garder les erreurs upstream isolées et explicites

## Mesures actuelles

- clés virtuelles stockées en hash SHA-256 côté runtime
- blocage des hosts `localhost`, `127.0.0.1`, `::1` et des plages privées usuelles
- redaction récursive des champs sensibles dans le JSON
- fallback ordonné uniquement entre backends explicitement déclarés
- budgets journaliers et rate limit par minute côté passerelle

## Choix de sûreté

- pas de forwarding implicite de `x-api-key` ou `authorization` du client vers les providers
- pas de découverte automatique d’URLs upstream
- pas de télémetrie imposée
- les smoke tests lisent les secrets via l’environnement local, jamais depuis le dépôt

## Limites actuelles

- budgets en mémoire seulement, non persistés
- pas encore de streaming SSE bout-en-bout
- pas encore de store durable, d’admin UI ni d’audit log append-only
