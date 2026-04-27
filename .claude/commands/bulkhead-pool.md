---
description: Inspect and mutate BulkheadLM model pools (read via curl, mutate via the starter REPL)
---

Manage named model pools. Pools group several routes behind one model id;
the gateway picks the lowest-latency healthy in-budget member.

Parse `$ARGUMENTS` as the first word of a sub-command, with the rest as
sub-arguments. Recognized sub-commands:

| Sub-command | What you do |
|---|---|
| `list` (or empty) | Read-only: curl `/v1/models`, render the `pools[]` section as a table |
| `show NAME` | Read-only: curl `/v1/models`, find pool NAME, show its members and is_global flag |
| `create NAME` | Mutation: launch the starter REPL and forward `/pool create NAME` |
| `add NAME ROUTE [BUDGET]` | Mutation: launch the starter REPL and forward `/pool add ...` |
| `remove NAME ROUTE` | Mutation: launch the starter REPL and forward `/pool remove ...` |
| `drop NAME` | Mutation: launch the starter REPL and forward `/pool drop NAME` |
| `global on` / `global off` | Mutation: launch the starter REPL and forward `/pool global ...` |

For read-only sub-commands, do not start any process; just curl the
gateway. Tell the user "the gateway must be running" if the curl fails.

For mutation sub-commands, the starter REPL is the source of truth (it
persists changes to SQLite under `pool_overrides`). The cleanest path
inside Claude Code is:

1. Tell the user you will open the BulkheadLM starter REPL in a terminal
   (or that they should switch to one if it is already open).
2. Show them exactly what to type:

   ```
   ./run.sh
   # then at the BulkheadLM prompt:
   /pool SUBCOMMAND ARGS
   /quit
   ```

3. After they confirm the change, run `/bulkhead-pool show NAME` to
   verify the new state.

Reasoning: the wizard mutates in-process state and writes to the
gateway's SQLite. There is no public mutation HTTP endpoint by design,
because pool mutations should go through the same authentication and
audit path as everything else.

End with a tip: `/pool global on` followed by `/swap global` gives the
user one synthetic model that aggregates every configured route, which
is often what they actually want.
