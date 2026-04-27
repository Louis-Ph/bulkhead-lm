---
description: List all configured BulkheadLM models and pools via the local gateway
---

List every model and pool exposed by the local BulkheadLM gateway.

The user expects a clean summary, not raw JSON. Do this:

1. Verify the gateway is running on the default port. Try
   `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4100/health`.
   If the result is not 200, tell the user to start the gateway in
   another terminal with
   `cd ~/bulkhead-lm && ./scripts/with_local_toolchain.sh dune exec bulkhead-lm -- --config config/local_only/starter.gateway.json`
   and then re-run this command.

2. Fetch the model list:

   ```bash
   curl -s http://127.0.0.1:4100/v1/models \
     -H 'Authorization: Bearer sk-bulkhead-lm-dev'
   ```

   If the user has set a non-default virtual key, suggest
   `BULKHEAD_LM_API_KEY` from their environment instead.

3. Render a compact table with three sections:
   - **Routes**: every entry whose `model_kind` is unset or `"route"`,
     with `id` and `display_name` (when present)
   - **Pools**: every entry whose `model_kind` is `"pool"`, with `id`,
     `is_global`, and `member_count`
   - **Providers**: from the response's `providers[]` field, each
     provider's `label`, the env var, and how many discovered models
     are currently cached

4. End with one tip line: "Use `/bulkhead-chat MODEL "your prompt"` to
   try one of these immediately, or `/bulkhead-pool` to manage pools."

If the JSON parse fails, fall back to printing the raw response and ask
the user to confirm the gateway version.
