---
description: Discover the live model list from each provider with a detected API key
---

Run BulkheadLM's provider model discovery and show the user what each
configured provider account currently exposes.

Discovery is the inspection feature, not a routing feature. It hits each
provider's `/models` endpoint (or Anthropic's `x-api-key` equivalent),
caches the result on disk for 24 hours, and prints what it finds.

`$ARGUMENTS` may be empty (use the cache when fresh) or `refresh` (force
a refetch, equivalent to `/refresh-models` in the starter).

Steps:

1. Verify the gateway is running (curl
   `http://127.0.0.1:4100/health`).

2. The HTTP `/v1/models` endpoint exposes cached discovery results in
   the `providers[].discovered_models` field, but it never refreshes
   live. So:

   - If `$ARGUMENTS` is empty: just curl `/v1/models`, render
     `providers[].discovered_models[]` as a table grouped by provider.
   - If `$ARGUMENTS` is `refresh`: tell the user to run
     `/refresh-models` inside the BulkheadLM starter REPL (it is the
     only path that triggers a live fetch). Show them the exact commands:

     ```
     ./run.sh
     # then at the BulkheadLM prompt:
     /refresh-models
     /quit
     ```

     After they say it is done, re-run yourself with empty
     `$ARGUMENTS` to render the freshened cache.

3. Format: one section per provider, with the env var, the cache age
   (from `fetched_at_unix`), and the model ids indented underneath.
   Cap each provider at the first 25 entries with a `... N more` line
   if needed.

4. If `discovered_models` is missing for a provider, say "no cache yet"
   and remind the user that `$ARGUMENTS=refresh` will populate it.

The cache lives under `$XDG_CACHE_HOME/bulkhead-lm/models` (default:
`~/.cache/bulkhead-lm/models`). Files there are safe to delete; they
will be repopulated on the next `/refresh-models`.
