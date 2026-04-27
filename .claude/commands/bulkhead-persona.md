---
description: Show and explain Telegram personas for multi-bot group chats
---

Inspect the Telegram personas declared in the BulkheadLM gateway config
(used to put several AI personas in one Telegram group, each backed by a
different model or pool).

The `$ARGUMENTS` is optional and currently unused (only `list` is
supported).

Steps:

1. Locate the active gateway config. Try, in order:
   - `~/bulkhead-lm/config/local_only/starter.gateway.json`
   - `~/bulkhead-lm/config/example.gateway.json`
   - prompt the user for the path.

2. Read the file with `cat` and parse it with `jq` (or your built-in
   JSON parser if `jq` is not available). Look at
   `user_connectors.telegram`. Two shapes exist:
   - **Legacy single-bot**: a JSON object. Treat it as a list of one
     entry with `persona_name = "default"`.
   - **Multi-bot array**: a JSON array; each entry has
     `persona_name`, `webhook_path`, `bot_token_env`, `route_model`,
     `room_memory_mode` (default `"shared"`).

3. Render a one-line header per persona with this template:

   ```
   @persona_name → route_model     [shared|isolated]    via $BOT_TOKEN_ENV
     webhook: /connectors/telegram/persona_name
     system_prompt (truncated): "..."
   ```

4. Verify the env vars: for each `bot_token_env`, check
   `printenv "$bot_token_env" >/dev/null 2>&1`. Mark missing ones in
   yellow text or with `(env var not set)`.

5. End with a tip: explain that `room_memory_mode: "shared"` is what
   makes the personas behave like real group participants (each persona
   sees what the others have just answered, tagged `[name]` in the
   shared memory). If the user wants to ADD a persona, the recipe lives
   in `README.md` under "Group chat with multiple personas (multi-bot
   Telegram)".

Note: Claude Code cannot mutate this config safely on the user's behalf;
the right path for mutations is to either edit the JSON directly in the
editor or use `/admin` inside the BulkheadLM starter REPL.
