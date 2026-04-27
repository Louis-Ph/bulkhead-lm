# BulkheadLM

[![CI](https://github.com/Louis-Ph/bulkhead-lm/actions/workflows/ci.yml/badge.svg)](https://github.com/Louis-Ph/bulkhead-lm/actions/workflows/ci.yml)

BulkheadLM is a secure AI router, AI hyper-connector, and powerful AI agent provider. It connects multiple AI providers, multiple machines, multiple clients, and peer-to-peer BulkheadLM nodes, while staying accessible through the chat interfaces people already use.

In other words: it looks like a hardened bulkhead, but it behaves like a high-trust AI fabric for routing, peering, orchestration, and fast user access. It is meant to be used by agent-swarm platforms, not to replace them.

New here? Three ways to install in 5 minutes:

- **Paste a single prompt to your favorite LLM** (Claude, ChatGPT, Cursor, Copilot, Gemini): the file [INSTALL_PROMPT.md](INSTALL_PROMPT.md) is self-contained and walks the LLM through the full setup with you.
- **Use Claude Code directly**: this repo ships custom slash commands under `.claude/commands/`. Type `/install-bulkhead` to start, then `/bulkhead-models`, `/bulkhead-chat`, `/bulkhead-pool`, `/bulkhead-persona`, `/bulkhead-discover`, `/bulkhead-health` for day-to-day operations. The hub for AI assistants is [CLAUDE.md](CLAUDE.md).
- **Run the script yourself**: `curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh`. The very simple step-by-step is in [readme_for_dummies.md](readme_for_dummies.md).

BulkheadLM is a security-first LLM gateway written in OCaml. It exposes an OpenAI-compatible API, routes requests across explicit provider backends, and keeps routing, security policy, and error behavior in hierarchical JSON. Optional provider model discovery is read-only, bounded, and cached; it never replaces explicit route configuration.

It targets multi-provider LLM gateway routing with a stricter design bias: explicit module boundaries, explicit provider registration, bounded fallback, fail-closed egress, and auditable request controls.

## Why BulkheadLM

- OpenAI-compatible client surface for `models`, `chat/completions`, `responses`, and `embeddings`
- explicit provider hierarchy instead of blind proxying
- virtual keys with per-key route allowlists, rate limits, and token budgets
- fail-closed network posture for loopback and common private ranges
- stable gateway-level SSE contract even when providers differ
- programmable terminal client with a human-facing `ask` mode and a JSONL worker mode
- programmable terminal client ops for bounded file browsing, file writes, and command execution
- one-line install on any Linux (Debian, Fedora, Arch, Alpine, openSUSE ...), macOS, FreeBSD, and Windows (WSL2 / Docker Desktop / cloud SSH, with a guided fault-tolerant decision tree)
- OCaml codebase with clear separation between domain, runtime, security, providers, HTTP, and persistence layers

## Current capabilities

- ordered backend fallback per public model route
- persistent virtual keys, budget usage, and audit events in SQLite
- persistent connector conversation snapshots in SQLite, so scoped chat memory survives restarts
- recursive secret redaction before log-oriented handling
- prompt privacy filtering for common secrets, IDs, and contact data
- threat detection for prompt-injection, credential-exfiltration, and tool-abuse signals
- output guard that blocks high-risk secret material before it leaves the gateway
- request body limits and upstream request timeouts
- retry-aware fallback that avoids failing over on permanent upstream errors
- multicore-safe budget and rate-limit state with a `Domain.spawn` test
- read-only provider model discovery through configured `/models` endpoints, with a 24-hour on-disk cache and stale fallback
- named model pools that group several routes behind a single public model id, each member with its own daily token budget; the gateway picks the lowest-latency healthy in-budget member and falls through automatically on failure
- a `global` pool option that aggregates every configured route as one synthetic model so a vanilla OpenAI client can target the entire fleet with `model=global`
- Telegram, WhatsApp Cloud API, Facebook Messenger, Instagram Direct, LINE, Viber, WeChat Service Account, Discord Interactions, and Google Chat user connectors over webhook, with per-conversation memory routed through normal BulkheadLM virtual-key auth

## Connector rollout roadmap

The chat-connector backlog is staged by global reach, API availability, and the
amount of adaptation a mainstream user needs before the assistant feels native.

- Wave 1: WhatsApp Cloud API, Telegram Bot API, Facebook Messenger, Instagram Direct
- Wave 2: LINE, Viber, WeChat Service Account
- Wave 2 deferred: TikTok Direct Messages
- Wave 3: Discord Interactions
- Wave 3 deferred: Snapchat, KakaoTalk, Zalo, QQ

The longer rationale lives in [docs/USER_CONNECTOR_ROADMAP.md](docs/USER_CONNECTOR_ROADMAP.md).

## Quick start

The fastest path on any machine (Linux, macOS, FreeBSD):

```bash
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

That single command installs git if needed, clones BulkheadLM, installs the
OCaml toolchain, and launches the interactive starter. Press ENTER through every
prompt to accept the defaults.

If you want the fastest first success with one key and a free route, start with
OpenRouter.

Research snapshot for this OpenRouter quick start: 2026-04-09.

```bash
printf '%s\n' 'export OPEN_ROUTER_KEY="paste-your-key-here"' >> ~/.zshrc.secrets
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

On Linux, `~/.bashrc.secrets` works just as well.

Then choose `openrouter-free` in the starter for a free first run, or keep the
generated starter config to expose `openrouter-auto`, `openrouter-free`, and
`openrouter-gpt-5.2` from the same key.

Why this path is attractive:

- one OpenRouter key can unlock several curated routes in BulkheadLM
- OpenRouter's free plan currently advertises 25+ free models and 50 requests per day
- `config/example.gateway.json` already includes `openrouter/free`
- later, the same provider integration can scale up to smarter paid routing without a provider rewrite

Free limits and free-model availability change over time, so check the official
pages before you rely on them:

- [OpenRouter Quickstart](https://openrouter.ai/docs/quickstart)
- [OpenRouter Pricing](https://openrouter.ai/pricing)
- [OpenRouter Free Models Router](https://openrouter.ai/docs/guides/routing/routers/free-models-router)

The repository can now bootstrap a project-local OCaml toolchain under
`.bulkhead-tools/`, `.opam-root/`, and `_opam/`, so `opam`, `ocamlc`, and
`dune` do not need to be preinstalled system-wide.

```bash
make test
make run CONFIG=config/example.gateway.json
```

The bundled example listens on `http://127.0.0.1:4100` and creates a local virtual key: `sk-bulkhead-lm-dev`.

If you already have a working global `opam` switch, the raw commands still work:

```bash
opam install . --deps-only --with-test
dune runtest
dune exec bulkhead-lm -- --config config/example.gateway.json --port 4200
```

## Chat connectors

BulkheadLM auto-detects chat platform credentials in the environment and
enables the matching connectors with zero manual config editing.

Set one environment variable, run `./run.sh`, and chat with your AI from
Telegram, WhatsApp, or any supported platform.

### How auto-detection works

1. Put your platform token in a secrets file (e.g. `~/.bashrc.secrets`).
2. Run `./run.sh` or the one-line installer.
3. The starter detects the token, auto-enables the connector, picks your first
   ready model, and wires up authentication automatically.
4. Start the BulkheadLM server. Point the platform's webhook to your server.
5. Chat.

No JSON editing. No separate auth env var. `BULKHEAD_LM_API_KEY` is exported
automatically to the default virtual key.

### Telegram (easiest)

1. Talk to [@BotFather](https://t.me/BotFather) on Telegram. Send `/newbot` and
   follow the prompts. Copy the token it gives you.
2. Add the token to your secrets:

```bash
printf 'export TELEGRAM_BOT_TOKEN="paste-your-token-here"\n' >> ~/.bashrc.secrets
```

3. Install and start BulkheadLM:

```bash
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

4. In a separate terminal, start the gateway server:

```bash
cd ~/bulkhead-lm
./scripts/with_local_toolchain.sh dune exec bulkhead-lm -- --config config/local_only/starter.gateway.json
```

5. Point Telegram to your server (replace `your-public-host`):

```bash
curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H 'content-type: application/json' \
  -d '{"url": "https://your-public-host/connectors/telegram/webhook", "allowed_updates": ["message"]}'
```

6. Open Telegram. Send a message to your bot. Done.

### Group chat with multiple personas (multi-bot Telegram)

You can run several Telegram bots on the same BulkheadLM gateway, each
backed by a different model or pool, and add them all to the same Telegram
group. From the user's point of view it looks like a chat group whose
members are AI; each persona stays in character and (with shared room
memory) sees what the others have said.

Setup:

1. Open Telegram and talk to [@BotFather](https://t.me/BotFather) once per
   persona. Send `/newbot`, pick a display name and username, copy the
   token. Repeat for as many personas as you want.
2. Save every token in your secrets file:

```bash
cat >> ~/.bashrc.secrets << 'EOF'
export TELEGRAM_TOKEN_MARIE="paste-marie-token"
export TELEGRAM_TOKEN_PAUL="paste-paul-token"
EOF
```

3. Replace the `telegram` section of your gateway config with an array, one
   entry per persona:

```json
{
  "user_connectors": {
    "telegram": [
      {
        "persona_name": "marie",
        "webhook_path": "/connectors/telegram/marie",
        "bot_token_env": "TELEGRAM_TOKEN_MARIE",
        "authorization_env": "BULKHEAD_LM_API_KEY",
        "route_model": "claude-opus",
        "system_prompt": "Tu es Marie, l'experte technique. Réponse courte, précise.",
        "room_memory_mode": "shared"
      },
      {
        "persona_name": "paul",
        "webhook_path": "/connectors/telegram/paul",
        "bot_token_env": "TELEGRAM_TOKEN_PAUL",
        "authorization_env": "BULKHEAD_LM_API_KEY",
        "route_model": "pool-cheap",
        "system_prompt": "Tu es Paul, l'éditeur. Tu reformules pour rendre les choses claires.",
        "room_memory_mode": "shared"
      }
    ]
  }
}
```

4. Start the gateway. Inside the starter, `/persona list` confirms both
   personas are loaded. Point each bot's webhook at the matching
   `webhook_path`:

```bash
curl -sS "https://api.telegram.org/bot${TELEGRAM_TOKEN_MARIE}/setWebhook" \
  -H 'content-type: application/json' \
  -d '{"url": "https://your-public-host/connectors/telegram/marie"}'

curl -sS "https://api.telegram.org/bot${TELEGRAM_TOKEN_PAUL}/setWebhook" \
  -H 'content-type: application/json' \
  -d '{"url": "https://your-public-host/connectors/telegram/paul"}'
```

5. Create a Telegram group, invite both bots, and (in BotFather, with
   `/setprivacy`) consider disabling privacy mode on each bot if you want
   them to see every message instead of only those that mention them.

How shared room memory works:

- Both bots share the same conversation thread keyed by the Telegram
  `chat_id`. When `marie` answers, her reply is committed to memory tagged
  `[marie] ...`. The next time someone @mentions `paul`, his bot reads the
  same thread and sees marie's reply.
- Each persona's system prompt is automatically augmented with a hint
  explaining that other participants may be AI personas and that lines
  prefixed `[name]` belong to them.
- A group with `pool-cheap` as one persona and `claude-opus` as another
  combines latency-aware routing with multi-persona dialogue: the cheap
  persona auto-falls back across its members while the expensive persona
  always answers as itself.

Set `room_memory_mode` to `"isolated"` instead of `"shared"` to give each
persona its own private thread per chat (parallel bots in the same group
that never see each other's replies).

The same pattern works for the legacy single-bot setup: a JSON object
under `telegram` (instead of an array) is still accepted and parses to a
one-element list with a default persona name and shared room memory.

### WhatsApp Cloud API

1. Create a Meta app at [developers.facebook.com](https://developers.facebook.com)
   and enable the WhatsApp product. Copy your temporary access token.
2. Add the tokens:

```bash
cat >> ~/.bashrc.secrets << 'EOF'
export WHATSAPP_ACCESS_TOKEN="paste-access-token"
export WHATSAPP_VERIFY_TOKEN="pick-any-random-string"
EOF
```

3. Run `./run.sh` (or the one-liner). The starter auto-enables WhatsApp.
4. Start the gateway server.
5. In the Meta App Dashboard, go to WhatsApp > Configuration > Webhook. Set the
   callback URL to `https://your-public-host/connectors/whatsapp/webhook` and
   the verify token to the same random string you chose above. Subscribe to
   `messages`.
6. Send a WhatsApp message to the test number shown in your Meta dashboard.

Optional: set `WHATSAPP_APP_SECRET` for `X-Hub-Signature-256` verification.

### Facebook Messenger

1. Create a Meta app and enable the Messenger product. Generate a Page access
   token.
2. Add the tokens:

```bash
cat >> ~/.bashrc.secrets << 'EOF'
export MESSENGER_ACCESS_TOKEN="paste-page-access-token"
export MESSENGER_VERIFY_TOKEN="pick-any-random-string"
EOF
```

3. Run `./run.sh`. Start the server. Set the webhook in the Meta dashboard to
   `https://your-public-host/connectors/messenger/webhook` with the same verify
   token. Subscribe to `messages`.
4. Message your page on Facebook.

### Instagram Direct

Same Meta app flow as Messenger:

```bash
cat >> ~/.bashrc.secrets << 'EOF'
export INSTAGRAM_ACCESS_TOKEN="paste-instagram-access-token"
export INSTAGRAM_VERIFY_TOKEN="pick-any-random-string"
EOF
```

Webhook URL: `https://your-public-host/connectors/instagram/webhook`.

### LINE

1. Create a Messaging API channel at
   [developers.line.biz](https://developers.line.biz).
2. Add the tokens:

```bash
cat >> ~/.bashrc.secrets << 'EOF'
export LINE_ACCESS_TOKEN="paste-channel-access-token"
export LINE_CHANNEL_SECRET="paste-channel-secret"
EOF
```

3. Run `./run.sh`. Start the server. Set the webhook URL in the LINE console to
   `https://your-public-host/connectors/line/webhook`.

### Viber

1. Create a bot at [partners.viber.com](https://partners.viber.com).
2. Add the token:

```bash
printf 'export VIBER_AUTH_TOKEN="paste-auth-token"\n' >> ~/.bashrc.secrets
```

3. Run `./run.sh`. Start the server. Register the webhook:

```bash
curl -sS https://chatapi.viber.com/pa/set_webhook \
  -H "X-Viber-Auth-Token: ${VIBER_AUTH_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"url": "https://your-public-host/connectors/viber/webhook"}'
```

### WeChat Service Account

1. Get your signature token from the WeChat Official Accounts Platform.
2. Add the token:

```bash
printf 'export WECHAT_SIGNATURE_TOKEN="paste-signature-token"\n' >> ~/.bashrc.secrets
```

3. Run `./run.sh`. Start the server. Set the URL in the WeChat developer
   console to `https://your-public-host/connectors/wechat/webhook`.

Optional: set `WECHAT_ENCODING_AES_KEY` and `WECHAT_APP_ID` for encrypted mode.

### Discord Interactions

1. Create an application at [discord.com/developers](https://discord.com/developers/applications).
   Copy the public key from General Information.
2. Add the key:

```bash
printf 'export DISCORD_PUBLIC_KEY="paste-public-key-hex"\n' >> ~/.bashrc.secrets
```

3. Run `./run.sh`. Start the server. In the Discord developer portal, set the
   Interactions Endpoint URL to
   `https://your-public-host/connectors/discord/webhook`.
4. Register a slash command (one-time):

```bash
curl -sS "https://discord.com/api/v10/applications/${DISCORD_APPLICATION_ID}/commands" \
  -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"name":"bulkhead","type":1,"description":"Talk to BulkheadLM","options":[{"name":"message","description":"Your message","type":3,"required":true}]}'
```

### Google Chat

1. Create a Google Chat app in [Google Cloud Console](https://console.cloud.google.com).
2. No extra env var needed beyond `BULKHEAD_LM_API_KEY` (auto-exported).
3. Set the HTTP endpoint in the Chat API configuration to
   `https://your-public-host/connectors/google-chat/webhook`.

### Connector quick reference

| Platform | Set this env var | Webhook path |
|---|---|---|
| Telegram | `TELEGRAM_BOT_TOKEN` | `/connectors/telegram/webhook` |
| WhatsApp | `WHATSAPP_ACCESS_TOKEN` + `WHATSAPP_VERIFY_TOKEN` | `/connectors/whatsapp/webhook` |
| Messenger | `MESSENGER_ACCESS_TOKEN` + `MESSENGER_VERIFY_TOKEN` | `/connectors/messenger/webhook` |
| Instagram | `INSTAGRAM_ACCESS_TOKEN` + `INSTAGRAM_VERIFY_TOKEN` | `/connectors/instagram/webhook` |
| LINE | `LINE_ACCESS_TOKEN` + `LINE_CHANNEL_SECRET` | `/connectors/line/webhook` |
| Viber | `VIBER_AUTH_TOKEN` | `/connectors/viber/webhook` |
| WeChat | `WECHAT_SIGNATURE_TOKEN` | `/connectors/wechat/webhook` |
| Discord | `DISCORD_PUBLIC_KEY` | `/connectors/discord/webhook` |
| Google Chat | (auto) | `/connectors/google-chat/webhook` |

All connectors share the same gateway guarantees: virtual-key auth, route
allowlists, budgets, rate limits, privacy filtering, output guards, and
per-conversation memory. `/help` and `/reset` work in every text channel.

## Local starter

The simplest entry point on any machine (Linux, macOS, FreeBSD):

```bash
curl -fsSL https://raw.githubusercontent.com/Louis-Ph/bulkhead-lm/main/install.sh | sh
```

Or, if you already cloned the repo:

```bash
./run.sh
```

On macOS, you can also double-click `start-macos-client.command` in Finder.

The starter:

- works on any Linux distro (Debian, Fedora, Arch, Alpine, openSUSE ...), macOS, and FreeBSD
- auto-detects the package manager and installs build prerequisites
- can bootstrap a repo-local `opam` binary before falling back to Homebrew, `apt`, `dnf`, `pacman`, `apk`, `zypper`, or `pkg`
- sources `~/.zshrc.secret`, `~/.zshrc.secrets`, `~/.bashrc.secret`, `~/.bashrc.secrets`, `~/.profile.secret`, `~/.profile.secrets`, and `~/.config/bulkhead-lm/env` when present
- auto-includes providers with detected API keys and auto-enables chat connectors with detected credentials
- defaults to creating a project-local switch when the active toolchain is not coherent for this repo
- reuses your configured provider keys from the shell environment
- asks which configured model you want to use now
- can generate a starter config that expands one provider key into several curated model routes for that provider
- auto-creates a first-run personal portable JSON config at `config/local_only/starter.gateway.json`
- uses real line editing in the human starter: left/right arrows, in-line edits, history recall, and tab completion
- keeps a followed conversation thread by default and compresses older turns into a shorter memory summary when the session grows
- includes an administrative assistant that prepares explicit plans before changing BulkheadLM config or attempting local system actions
- can expose a browser-based admin control plane with live route status and hot config reload under `security_policy.control_plane`
- includes a guided packaging flow that can build a distributable package for macOS, Ubuntu, or FreeBSD from the same assistant terminal
- shows masked environment and provider readiness state from inside the REPL
- can list live or cached upstream model inventories with `/discover` and force a refetch with `/refresh-models`
- can create, inspect and mutate named model pools with `/pool list|show|create|drop|add|remove|global on|off`; pool definitions persist across restarts in SQLite
- can run several Telegram bots on the same gateway as distinct personas, each backed by its own model or pool; with shared room memory the personas behave like real participants in the same group chat, viewable through `/persona list`
- drops you into a simple terminal session with `/tools`, `/file PATH`, `/files`, `/clearfiles`, `/explore PATH`, `/open PATH`, `/run CMD`, `/admin TEXT`, `/control`, `/package`, `/plan`, `/apply`, `/discard`, `/model`, `/models`, `/swap`, `/memory`, `/memory replace TEXT`, `/forget`, `/thread on|off`, `/providers`, `/discover`, `/refresh-models`, `/pool list|show|create|drop|add|remove|global`, `/persona list`, `/env`, `/config`, `/help`, and `/quit`

Admin assistant flow inside the starter:

```text
/admin enable local file operations only for this repository and explain each step simply
/plan
/apply
```

Control-plane check inside the starter:

```text
/control
```

`/control` tells you whether the current config actually enables the HTTP control plane, shows the exact UI and API URLs derived from that config, and reminds you that the starter itself is not the HTTP gateway server.

If you want to substitute the current starter thread memory with one explicit
summary, use:

```text
/memory replace Project alpha now focuses on deployment, with customer deadline preserved.
```

That clears the recent verbatim turns and replaces the remembered history with
the supplied summary snapshot.

The assistant uses the selected model together with the active BulkheadLM config, the referenced security policy, local repository documentation, and bounded local system context. It proposes structured config changes first and only falls back to `ops`-style filesystem or command actions when configuration alone is not enough.

Guided packaging inside the starter:

```text
/package
```

The packaging flow detects the current supported OS, walks through package metadata step by step, bundles the selected gateway config, then launches the native package build:

- macOS: `.pkg`
- Ubuntu: `.deb`
- FreeBSD: `.pkg`

On an installed tree, the starter now prefers bundled binaries directly. On a source checkout, it falls back to `dune` as before.

For non-interactive local development, the same project-local toolchain is available directly:

```bash
./scripts/bootstrap_local_toolchain.sh
./scripts/with_local_toolchain.sh dune build @install
./scripts/with_local_toolchain.sh dune runtest --no-buffer
```

HTTP control plane for the running gateway:

```json
{
  "control_plane": {
    "enabled": true,
    "path_prefix": "/_bulkhead/control",
    "ui_enabled": true,
    "allow_reload": true,
    "admin_token_env": "BULKHEAD_ADMIN_TOKEN"
  }
}
```

Set `BULKHEAD_ADMIN_TOKEN`, start the server normally, then open `http://127.0.0.1:4100/_bulkhead/control`. Inside the starter, `/control` prints the same derived URL set from the active config and makes the distinction explicit between the interactive starter client and the separate running gateway server. The UI shows the active config path, route readiness, enabled chat connectors, virtual-key inventory, and exposes a guarded `reload` action that swaps the runtime in place. Changes to `listen_host` and `listen_port` still require a restart because the listening socket is already bound.

The same guarded control plane now exposes session-memory replacement for
external orchestrators such as `ocaml-agent-graph`:

- `GET /_bulkhead/control/api/memory/session?session_key=...`
- `PUT /_bulkhead/control/api/memory/session`
- `DELETE /_bulkhead/control/api/memory/session?session_key=...`

`PUT` replaces the stored memory snapshot for the given `session_key` with a
caller-supplied `summary`, `recent_turns`, and `compressed_turn_count`. This
lets an external swarm runtime clear memory, inspect it, or substitute it with
its own adapted summary instead of relying only on `/reset`.

If you want a direct low-level smoke test against a running gateway, use:

```bash
BULKHEAD_ADMIN_TOKEN=... ./scripts/smoke_memory_control_plane.sh
```

That script performs one `PUT`, one `GET`, and one `DELETE` against the memory
session control-plane API and prints the returned JSON.

## Terminal client

For direct terminal use without starting the HTTP gateway, use `bulkhead-lm-client`.

Human-facing prompt mode:

```bash
dune exec bulkhead-lm-client -- ask \
  --config config/example.gateway.json \
  --model gpt-5-mini \
  "Summarize the value of BulkheadLM in one sentence."
```

Programmatic one-shot mode:

```bash
printf '%s\n' \
  '{"model":"gpt-5-mini","messages":[{"role":"user","content":"Reply with OK."}]}' \
  | dune exec bulkhead-lm-client -- call \
      --config config/example.gateway.json \
      --kind chat
```

Long-running worker mode over JSONL with bounded parallelism:

```bash
dune exec bulkhead-lm-client -- worker \
  --config config/example.gateway.json \
  --jobs 4
```

Worker input line example:

```json
{"id":"job-1","kind":"chat","request":{"model":"gpt-5-mini","messages":[{"role":"user","content":"Reply with OK."}]}}
```

Worker output line example:

```json
{"ok":true,"id":"job-1","kind":"chat","line":1,"response":{"id":"chatcmpl-...","object":"chat.completion","model":"gpt-5-mini","choices":[...],"usage":{...}}}
```

Worker responses are emitted when jobs complete, not in submission order. Use `id` for correlation.

Use `worker` when several programmatic callers should share one in-process runtime, one rate-limit state, and one persistence handle. Use `ask` or `call` for isolated one-shot invocations.

Structured client operations are also available through `--kind ops`. They are disabled by default and only activate when `security_policy.client_ops` explicitly enables bounded roots.

Minimal policy example:

```json
{
  "client_ops": {
    "files": {
      "enabled": true,
      "read_roots": ["/srv/bulkhead-lm/workspace"],
      "write_roots": ["/srv/bulkhead-lm/workspace"],
      "max_read_bytes": 1048576,
      "max_write_bytes": 1048576
    },
    "exec": {
      "enabled": true,
      "working_roots": ["/srv/bulkhead-lm/workspace"],
      "timeout_ms": 10000,
      "max_output_bytes": 65536
    }
  }
}
```

One-shot directory listing:

```bash
printf '%s\n' \
  '{"op":"list_dir","path":"."}' \
  | dune exec bulkhead-lm-client -- call \
      --config config/example.gateway.json \
      --kind ops
```

One-shot file upload/write with base64:

```bash
printf '%s\n' \
  '{"op":"write_file","path":"artifacts/report.bin","encoding":"base64","content":"SGVsbG8=","create_parents":true}' \
  | dune exec bulkhead-lm-client -- call \
      --config config/example.gateway.json \
      --kind ops
```

One-shot command execution:

```bash
printf '%s\n' \
  '{"op":"exec","command":"/bin/ls","args":["-la"],"cwd":"."}' \
  | dune exec bulkhead-lm-client -- call \
      --config config/example.gateway.json \
      --kind ops
```

## SSH remote usage

For a human remote session over SSH:

```bash
ssh -t user@remote '/opt/bulkhead-lm/scripts/remote_starter.sh'
```

For a programmatic remote worker over SSH:

```bash
ssh -T user@remote '/opt/bulkhead-lm/scripts/remote_worker.sh --config /etc/bulkhead-lm/gateway.json'
```

The full guide is in [docs/SSH_REMOTE.md](docs/SSH_REMOTE.md).

For a clean client machine that does not have BulkheadLM yet, an existing remote
BulkheadLM install can also serve a local bootstrap installer over SSH:

```bash
ssh user@remote '/opt/bulkhead-lm/scripts/remote_install.sh --emit-installer --origin user@remote' | sh
```

That installs a filtered snapshot locally, by default into `~/opt/bulkhead-lm`,
then the local user can start it with:

```bash
cd ~/opt/bulkhead-lm
./run.sh
```

## Peer mesh

One BulkheadLM instance can use another BulkheadLM instance as an upstream LLM by
declaring the backend as `bulkhead_peer` for HTTP or `bulkhead_ssh_peer` for direct
worker-over-SSH transport. Both keep the relationship explicit in config and
both preserve bounded peer hop headers so accidental `A -> B -> A` loops fail
closed instead of recursing.

The full guide is in [docs/PEER_MESH.md](docs/PEER_MESH.md).

## Copy-paste demo

List the public models exposed by the local gateway:

```bash
curl -s http://127.0.0.1:4100/v1/models \
  -H "Authorization: Bearer sk-bulkhead-lm-dev"
```

Each `/v1/models` item now keeps the route alias explicit and also includes
`display_name`, a `catalog` block for provider/version/mode hierarchy, and
`configured_backends` so you can see the actual upstream mapping without
guessing from short aliases alone.

The same response also includes a top-level `providers` array. Each provider
group keeps its credential environment variable, API base URL, curated route
models, and any cached `discovered_models` previously populated by the starter
with `/discover` or `/refresh-models`.

Then call a routed model once at least one upstream provider key is exported in your shell:

```bash
curl -s http://127.0.0.1:4100/v1/chat/completions \
  -H "Authorization: Bearer sk-bulkhead-lm-dev" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5-mini",
    "messages": [
      { "role": "user", "content": "Say hello from BulkheadLM in one sentence." }
    ]
  }'
```

The example gateway file is [config/example.gateway.json](config/example.gateway.json).

## Providers and routes

Example route families currently implemented (19 provider kinds):

| Kind | Provider | Key env |
|------|----------|---------|
| `openai_compat` | Generic OpenAI-compatible | _(set per backend)_ |
| `anthropic` | Anthropic | `ANTHROPIC_API_KEY` |
| `openrouter_openai` | OpenRouter | `OPEN_ROUTER_KEY` |
| `google_openai` | Google AI Studio | `GOOGLE_API_KEY` |
| `vertex_openai` | Google Vertex AI | `VERTEX_AI_ACCESS_TOKEN` |
| `mistral_openai` | Mistral | `MISTRAL_API_KEY` |
| `ollama_openai` | Ollama (local) | `OLLAMA_API_KEY` |
| `alibaba_openai` | Alibaba DashScope / Qwen | `DASHSCOPE_API_KEY` |
| `moonshot_openai` | Moonshot Kimi | `MOONSHOT_API_KEY` |
| `xai_openai` | xAI Grok | `XAI_API_KEY` |
| `meta_openai` | Meta Llama API | `META_API_KEY` |
| `deepseek_openai` | DeepSeek | `DEEPSEEK_API_KEY` |
| `groq_openai` | Groq | `GROQ_API_KEY` |
| `perplexity_openai` | Perplexity | `PERPLEXITY_API_KEY` |
| `together_openai` | Together AI | `TOGETHER_API_KEY` |
| `cerebras_openai` | Cerebras | `CEREBRAS_API_KEY` |
| `cohere_openai` | Cohere | `COHERE_API_KEY` |
| `bulkhead_peer` | BulkheadLM peer (HTTP) | _(bearer key per route)_ |
| `bulkhead_ssh_peer` | BulkheadLM peer (SSH) | _(ssh key per transport)_ |

The bundled example config exposes 46 curated public routes across ten cloud providers, so one upstream provider key can unlock several routed models. The current example includes:

- OpenAI: `gpt-5`, `gpt-5-mini`, `gpt-5-nano`
- OpenRouter: `openrouter-auto`, `openrouter-free`, `openrouter-gpt-5.2`
- Anthropic: `claude-opus`, `claude-sonnet`, `claude-haiku`
- Google AI Studio: `gemini-2.5-pro`, `gemini-2.5-flash`, `gemini-2.5-flash-lite`
- Google Vertex AI: `vertex-gemini-2.5-pro`, `vertex-gemini-2.5-flash`, `gpt-oss-120b`
- xAI: `grok-4`, `grok-4.20-reasoning`, `grok-4-1-fast-reasoning`
- Meta Llama API Preview: `meta-llama-4-scout`, `meta-llama-4-maverick`, `meta-llama-3.3-8b`
- Mistral: `mistral-medium`, `mistral-small`, `codestral`
- Alibaba Qwen: `qwen-max`, `qwen-plus`, `qwen-turbo`
- Moonshot Kimi: `kimi-latest`, `kimi-k2`, `kimi-k2.5`
- DeepSeek: `deepseek-v3`, `deepseek-r1`, `deepseek-r1-lite`
- Groq: `groq-llama-3.3-70b`, `groq-llama-3.1-8b`, `groq-qwen-qwq-32b`
- Perplexity: `perplexity-sonar-pro`, `perplexity-sonar`, `perplexity-sonar-reasoning`
- Together AI: `together-llama-3.3-70b`, `together-deepseek-v3`, `together-qwen-2.5-72b`
- Cerebras: `cerebras-llama-3.3-70b`, `cerebras-llama-3.1-8b`
- Cohere: `command-r-plus`, `command-r`, `command-a`

**New provider notes:**
- DeepSeek routes use `https://api.deepseek.com/v1`; `deepseek-chat` maps to DeepSeek-V3 and `deepseek-reasoner` maps to DeepSeek-R1.
- Groq routes use `https://api.groq.com/openai/v1` for ultra-low-latency inference on open models; `groq-qwen-qwq-32b` exposes Qwen's QwQ reasoning model on Groq hardware.
- Perplexity Sonar routes use `https://api.perplexity.ai`; Sonar models attach live web search to the response.
- Together AI routes use `https://api.together.xyz/v1` and expose the same open-weight models via Together's batch inference cluster.
- Cerebras routes use `https://api.cerebras.ai/v1` for wafer-scale chip inference; latency on 8b models is typically sub-100 ms.
- Cohere routes use the OpenAI-compatible shim at `https://api.cohere.ai/compatibility/v1`; `command-a-03-2025` is Cohere's 111B frontier model.

OpenRouter is configured against `https://openrouter.ai/api/v1` with `api_key_env` set to `OPEN_ROUTER_KEY` by default. OpenRouter's optional attribution headers are not required for BulkheadLM routing.
Vertex example routes keep `YOUR_PROJECT` as an explicit placeholder in the OpenAI-compatible endpoint path and expect a bearer access token in `VERTEX_AI_ACCESS_TOKEN`.
Meta's Llama API entries reflect the public preview announced on `2025-04-29`, so tenant access and exact upstream IDs can still evolve.

These curated route families were last aligned with official provider docs on `2026-04-14`. They are not a claim that BulkheadLM enumerates every upstream model a provider may ever expose.

### Provider model discovery

Curated routes remain the production routing source of truth. Discovery is a
separate inspection layer that helps you see what each configured provider key
can currently access:

```text
/discover
/refresh-models
```

`/discover` checks providers that have a detected API key, prefers fresh cached
listings, and prints the provider hierarchy as provider -> upstream models.
`/refresh-models` skips the cache and asks each provider API again.

The cache lives under `$BULKHEAD_LM_MODEL_CACHE_DIR` when set. Otherwise it uses
`$XDG_CACHE_HOME/bulkhead-lm/models`, falling back to
`~/.cache/bulkhead-lm/models`. Cache files are per provider, written with
restrictive permissions, and are considered fresh for 24 hours. If a refresh
fails but an older cache exists, the starter shows the cached listing as stale
with the last fetch error.

Discovery uses only the provider family already known to BulkheadLM:

- OpenAI-compatible providers call `{api_base}/models` with bearer auth.
- Anthropic uses its `x-api-key` and `anthropic-version` headers and follows
  `has_more` / `last_id` pagination.
- Bulkhead peer and SSH peer providers are reported as unsupported for public
  model listing.

The gateway's `/v1/models` endpoint never performs a live network refresh. It
only exposes configured route metadata plus whatever discovery cache is already
present, so model listing stays fast and route selection stays explicit.

### Named model pools

A pool is a named group of routes behind a single public model id. Each pool
member declares its own daily token budget; on every request the gateway picks
the member with the lowest observed latency that still has budget left and a
closed circuit, then falls through to the next-best candidate on failure. This
is useful when you want to fan out a stream of small jobs across many
tightly-budgeted upstream models without picking one by hand.

Declarative pools live in `gateway.json` next to `routes`:

```json
{
  "pools": [
    {
      "name": "pool-cheap",
      "members": [
        { "route_model": "groq-llama-3.1-8b", "daily_token_budget": 50000 },
        { "route_model": "cerebras-llama-3.1-8b", "daily_token_budget": 50000 },
        { "route_model": "deepseek-v3", "daily_token_budget": 25000 }
      ]
    },
    { "name": "global", "is_global": true }
  ]
}
```

Once defined, the pool name behaves exactly like a model id:

```bash
curl -s http://127.0.0.1:4100/v1/chat/completions \
  -H "Authorization: Bearer sk-bulkhead-lm-dev" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "pool-cheap",
    "messages": [
      { "role": "user", "content": "Hello via the cheap pool." }
    ]
  }'
```

Selection logic, in order:

1. drop members whose route is missing, whose daily token budget is exhausted,
   or whose every backend has its circuit open
2. sort the remainder by ascending observed latency (EWMA per pool member);
   members never observed yet rank first so they always get one probe
3. try each candidate in order; record latency on success or failure;
   on success, charge the per-member budget atomically

When `is_global` is true on a pool, the declared `members` list is ignored and
recomputed at lookup time as every configured route. That gives you a "single
magic model" called `global` that automatically picks up any route you add
later, without reconfiguration.

Pools can also be created and edited live from the starter without touching
`gateway.json`:

```text
/pool list
/pool create pool-cheap
/pool add pool-cheap groq-llama-3.1-8b 50000
/pool add pool-cheap cerebras-llama-3.1-8b 50000
/pool show pool-cheap
/pool global on
```

Wizard mutations are persisted in SQLite under `pool_overrides` and override
the declarative pool list at the next restart. Per-member token consumption is
tracked atomically in `pool_member_usage` so daily budgets survive restarts.

`/v1/models` exposes pools both as ordinary entries in `data[]` (with
`model_kind: "pool"` and `is_global` flag, so existing OpenAI SDKs see them as
plain models) and in a dedicated `pools[]` section that lists each pool's
members and per-member budgets.

Ollama is also supported through its OpenAI-compatible interface, for example on `http://127.0.0.1:11434/v1` with a local model such as `llama3.2`.

It is not enabled in the bundled example config because the default fail-closed egress policy blocks loopback and private-range upstreams. To use Ollama intentionally, relax the egress policy for your deployment and add a route such as:

```json
{
  "public_model": "llama3.2-local",
  "backends": [
    {
      "provider_id": "ollama-local",
      "provider_kind": "ollama_openai",
      "upstream_model": "llama3.2",
      "api_base": "http://127.0.0.1:11434/v1",
      "api_key_env": "OLLAMA_API_KEY"
    }
  ]
}
```

Set `OLLAMA_API_KEY=ollama` when using that interface. Ollama documents that this key is required by client tooling but ignored by the local server.

For a ready-to-run local swarm profile, use [config/example.ollama_swarm.gateway.json](config/example.ollama_swarm.gateway.json). It routes BulkheadLM public models to the local Ollama aliases `swarm-router`, `swarm-worker`, `swarm-lead`, `swarm-critic`, plus `all-minilm` for embeddings, and it opts into the explicit loopback/private-egress profile [config/defaults/security_policy.ollama_local.json](config/defaults/security_policy.ollama_local.json).

That path is intentionally separate from the cloud-oriented example config so the default repository posture stays fail-closed.

To launch that profile directly without the interactive starter menu, run:

```bash
./run-ollama.sh
```

The launcher defaults `OLLAMA_API_KEY=ollama`, uses [config/example.ollama_swarm.gateway.json](config/example.ollama_swarm.gateway.json), and accepts normal gateway flags such as `--port 4112`.

Smoke-test the full BulkheadLM to Ollama path with:

```bash
./scripts/smoke_ollama.sh
```

The smoke script defaults `OLLAMA_API_KEY` to `ollama`, starts BulkheadLM with the Ollama swarm config, then verifies chat, responses, and embeddings against the local aliases already served by Ollama.

Use the Beijing DashScope base instead of the international base when you intentionally deploy against the mainland China region.

## Real-provider smoke tests

```bash
./scripts/smoke_openai.sh
./scripts/integration_matrix.sh
```

`smoke_openai.sh` automatically selects, in order, `claude-sonnet`, `mistral-small`, `qwen-plus`, `kimi-k2.5`, `gemini-2.5-flash`, `openrouter-free`, then `gpt-5-mini` when the corresponding provider key is present.

`integration_matrix.sh` exercises:

- Anthropic
- OpenRouter through its direct OpenAI-compatible API
- Google Gemini through the official OpenAI-compatible interface
- Mistral through its `/v1` API
- Alibaba Model Studio through DashScope OpenAI-compatible mode
- Moonshot Kimi through its OpenAI-compatible chat interface
- OpenAI when the upstream key is available and has quota
- SSE for `chat/completions`
- SSE for `responses`
- SQLite persistence for virtual keys and audit events

## Architecture at a glance

```text
start-macos-client.command

bin/
  client.ml
  main.ml

config/
  defaults/
    error_catalog.json
    providers.schema.json
    security_policy.json
  compliance/
    prc_defense_overlay_profile.json
    prc_regulated_network_profile.json
    us_dod_unclassified_profile.json
  local_only/
    .gitignore
  example.gateway.json

docs/
  ARCHITECTURE.md
  COMPLIANCE_US_CN.md
  SECURITY.md

scripts/
  build_dist_package.sh
  integration_matrix.sh
  linux_starter.sh
  macos_starter.sh
  smoke_ollama.sh
  starter_common.sh
  toolchain_env.sh
  ubuntu_starter.sh
  freebsd_starter.sh
  remote_common.sh
  remote_starter.sh
  remote_worker.sh
  smoke_openai.sh

src/
  client/
  domain/
  security/
  runtime/
  providers/
    provider_models_listing.ml
  http/
  persistence/
    model_listing_cache.ml

test/
  bulkhead_lm_test.ml
  bulkhead_lm_test_paths.ml
```

See [Architecture](docs/ARCHITECTURE.md) for the layer-by-layer design.

## Security and compliance

BulkheadLM is a hardening-oriented gateway, not a certification claim.

Current built-in controls include:

- explicit upstream allow/deny decisions instead of runtime route discovery
- no implicit forwarding of client `authorization` or `x-api-key` headers upstream
- bounded fallback routing
- request size and timeout enforcement
- persistent audit logging
- request and token budget enforcement before uncontrolled fan-out
- provider model discovery is bounded to configured provider API bases and cached on disk; it does not rewrite routes
- bounded worker concurrency with per-request output isolation on stdio

Detailed references:

- [Security Posture](docs/SECURITY.md)
- [Security Policy](SECURITY.md)
- [US and China Compliance Study](docs/COMPLIANCE_US_CN.md)
- [Why OCaml — anti-slop manifesto](docs/MANIFESTO_OCAML.md): the philosophical case for OCaml as the on-ramp toward demonstrative programming with Rocq, given AI-assisted code generation at scale

## Contributing and support

- contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- code of conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- repository settings guide: [docs/GITHUB_REPOSITORY_SETTINGS.md](docs/GITHUB_REPOSITORY_SETTINGS.md)
- support process: [SUPPORT.md](SUPPORT.md)
- vulnerability reporting: [SECURITY.md](SECURITY.md)

## Test strategy

The current suite covers:

- recursive secret redaction
- virtual-key authentication failure paths
- budget enforcement
- provider fallback behavior
- localhost and private-range egress blocking
- multicore-safe budget accounting
- `responses` request/response normalization
- SSE framing for `chat/completions` and `responses`
- persistence survival across restart
- audit-log persistence
- config fixture path resolution from any test working directory

Run the full suite with:

```bash
dune build @runtest
```

## Status and limitations

- provider-native upstream streaming is not implemented yet; SSE is currently normalized by the gateway from the provider-normalized response
- provider coverage is intentionally narrow and explicit
- Moonshot is currently modeled as chat-only in the provider schema
- the worker protocol is currently JSONL over stdio rather than a binary IPC protocol
- provider model discovery is an inspection/cache feature, not a guarantee that every upstream model is routable through the current config
- the guided local starter targets any Linux distro with a supported package manager, macOS, and FreeBSD
- military or sovereign-environment compliance still requires deployment hardening, supply-chain evidence, identity integration, and formal assessment artifacts

## License

BulkheadLM is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
