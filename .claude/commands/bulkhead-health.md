---
description: Health check the local BulkheadLM gateway and report ready models
---

Health check the local BulkheadLM gateway and produce a one-screen
status summary.

Steps:

1. Probe the health endpoint:

   ```bash
   curl -s -o /tmp/bulkhead-health.json -w '%{http_code}' \
     http://127.0.0.1:4100/health
   ```

   - HTTP 200 means the gateway is up; the body is a JSON object with
     `status`, `routes_total`, `backends_open`, `backends_closed`,
     `inflight`. Report each.
   - HTTP 503 means the gateway is up but no backend can serve right
     now (every backend has its circuit open). Tell the user this
     specifically.
   - Connection refused / timeout means the gateway is not running.
     Tell the user to start it with
     `cd ~/bulkhead-lm && ./scripts/with_local_toolchain.sh dune exec bulkhead-lm -- --config config/local_only/starter.gateway.json`.

2. If the gateway is up, fetch `/v1/models` and count:
   - total routes
   - total pools (entries with `model_kind: "pool"`)
   - global pool present? yes/no
   - providers with `discovered_models` cached (just the count of
     entries in `providers[]` whose `discovered_models.count > 0`)

3. Render the result as a 5-line summary:

   ```
   gateway   : ok
   routes    : 46 configured, 6 backends open
   pools     : 3 (global pool ON)
   discovery : 4 / 9 providers cached
   inflight  : 0 requests
   ```

4. If anything looks wrong (status != ok, all backends closed, no
   route ready), end with a one-line "next step" suggestion: `/bulkhead-models`
   to see what is configured, or `/install-bulkhead` to redo setup.

Do not attempt to start the gateway yourself. The user runs it; you
only inspect.
