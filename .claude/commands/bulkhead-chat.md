---
description: Send a one-shot chat completion to the local BulkheadLM gateway
---

Send a chat completion to the local BulkheadLM gateway and show the reply.

`$ARGUMENTS` should be `MODEL "PROMPT"`. If it is missing or only one part
is present, ask the user once for the missing piece. The MODEL can be any
public route, any pool name (e.g. `pool-cheap`, `global`), or `auto` which
you should expand to whichever route is currently `[ready]` according to
`/bulkhead-models`.

Steps:

1. Confirm the gateway is up:
   `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4100/health`.
   Anything other than 200 means the gateway is not running; tell the
   user how to start it (see `/bulkhead-models`).

2. Send the request. Use the default local virtual key
   `sk-bulkhead-lm-dev` unless the user's environment exports
   `BULKHEAD_LM_API_KEY`, in which case use that.

   ```bash
   curl -s http://127.0.0.1:4100/v1/chat/completions \
     -H 'Authorization: Bearer sk-bulkhead-lm-dev' \
     -H 'Content-Type: application/json' \
     -d '{
       "model": "MODEL_PLACEHOLDER",
       "messages": [{"role":"user","content":"PROMPT_PLACEHOLDER"}]
     }'
   ```

   Properly JSON-escape the prompt before substituting it.

3. Pull `choices[0].message.content` from the response and print it
   verbatim, followed by a one-line footer with `usage.total_tokens`
   and the resolved `model` field. Do not dump the whole response.

4. If the response is an error (HTTP 4xx / 5xx, or `{"error": ...}` body),
   surface the error message specifically. Common cases:
   - `route_not_found` → suggest running `/bulkhead-models`
   - `budget_exceeded` → suggest `/bulkhead-pool` or wait until UTC
     midnight
   - `circuit_open` → the upstream is failing, suggest a different model
   - `Missing environment variable X_API_KEY` → the user has not exported
     the provider's API key in the gateway's process; remind them to
     restart the gateway after sourcing `~/.bashrc.secrets` (or the zsh
     equivalent).
