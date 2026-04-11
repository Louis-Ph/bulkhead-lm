# BulkheadLM

[![CI](https://github.com/Louis-Ph/bulkhead-lm/actions/workflows/ci.yml/badge.svg)](https://github.com/Louis-Ph/bulkhead-lm/actions/workflows/ci.yml)

BulkheadLM is a secure AI router, AI hyper-connector, and powerful AI agent provider. It connects multiple AI providers, multiple machines, multiple clients, and peer-to-peer BulkheadLM nodes, while staying accessible through the chat interfaces people already use.

In other words: it looks like a hardened bulkhead, but it behaves like a high-trust AI fabric for routing, peering, orchestration, and fast user access. It is meant to be used by agent-swarm platforms, not to replace them.

New here? Start with the very simple guide: [readme_for_dummies.md](readme_for_dummies.md)

BulkheadLM is a security-first LLM gateway written in OCaml. It exposes an OpenAI-compatible API, routes requests across explicit provider backends, and keeps routing, security policy, and error behavior in hierarchical JSON instead of ad-hoc runtime discovery.

It targets multi-provider LLM gateway routing with a stricter design bias: explicit module boundaries, explicit provider registration, bounded fallback, fail-closed egress, and auditable request controls.

## Why BulkheadLM

- OpenAI-compatible client surface for `models`, `chat/completions`, `responses`, and `embeddings`
- explicit provider hierarchy instead of blind proxying
- virtual keys with per-key route allowlists, rate limits, and token budgets
- fail-closed network posture for loopback and common private ranges
- stable gateway-level SSE contract even when providers differ
- programmable terminal client with a human-facing `ask` mode and a JSONL worker mode
- programmable terminal client ops for bounded file browsing, file writes, and command execution
- clone-and-run local starter for macOS, Ubuntu, and FreeBSD with guided first-run setup
- OCaml codebase with clear separation between domain, runtime, security, providers, HTTP, and persistence layers

## Current capabilities

- ordered backend fallback per public model route
- persistent virtual keys, budget usage, and audit events in SQLite
- recursive secret redaction before log-oriented handling
- prompt privacy filtering for common secrets, IDs, and contact data
- threat detection for prompt-injection, credential-exfiltration, and tool-abuse signals
- output guard that blocks high-risk secret material before it leaves the gateway
- request body limits and upstream request timeouts
- retry-aware fallback that avoids failing over on permanent upstream errors
- multicore-safe budget and rate-limit state with a `Domain.spawn` test
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

If you want the fastest first success with one key and a free route, start with
OpenRouter.

Research snapshot for this OpenRouter quick start: 2026-04-09.

```bash
git clone https://github.com/Louis-Ph/bulkhead-lm.git
cd bulkhead-lm
printf '%s\n' 'export OPEN_ROUTER_KEY="paste-your-key-here"' >> ~/.zshrc.secrets
./run.sh
```

On Ubuntu, `~/.bashrc.secrets` works just as well.

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

## User chat connectors

BulkheadLM can now expose nine user-facing chat connectors through the same
HTTP server architecture:

- Telegram Bot API
- WhatsApp Cloud API
- Facebook Messenger
- Instagram Direct
- LINE Messaging API
- Viber REST Bot API
- WeChat Service Account
- Discord Interactions
- Google Chat HTTP app webhooks

Each connector keeps the same gateway guarantees:

- it reuses a normal BulkheadLM virtual key from `authorization_env`
- route allowlists, budgets, rate limits, privacy filtering, and output guards still apply
- conversation memory is scoped per external conversation instead of being shared globally
- enabled connectors must use distinct `webhook_path` values, and config load now rejects ambiguous path reuse
- `/help` and `/reset` are supported on the text channels implemented here

### Telegram

Reference checked for this connector work: 2026-04-11.

```bash
export TELEGRAM_BOT_TOKEN="123456:telegram-bot-token"
export TELEGRAM_WEBHOOK_SECRET="choose-a-random-secret"
export BULKHEAD_TELEGRAM_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "telegram": {
      "enabled": true,
      "webhook_path": "/connectors/telegram/webhook",
      "bot_token_env": "TELEGRAM_BOT_TOKEN",
      "secret_token_env": "TELEGRAM_WEBHOOK_SECRET",
      "authorization_env": "BULKHEAD_TELEGRAM_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_chat_ids": []
    }
  }
}
```

```bash
curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H 'content-type: application/json' \
  -d '{
    "url": "https://your-public-host/connectors/telegram/webhook",
    "secret_token": "'"${TELEGRAM_WEBHOOK_SECRET}"'",
    "allowed_updates": ["message"]
  }'
```

### WhatsApp Cloud API

Reference checked for this connector work: 2026-04-11.

```bash
export WHATSAPP_VERIFY_TOKEN="choose-a-random-verify-token"
export WHATSAPP_APP_SECRET="meta-app-secret"
export WHATSAPP_ACCESS_TOKEN="meta-access-token"
export BULKHEAD_WHATSAPP_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "whatsapp": {
      "enabled": true,
      "webhook_path": "/connectors/whatsapp/webhook",
      "verify_token_env": "WHATSAPP_VERIFY_TOKEN",
      "app_secret_env": "WHATSAPP_APP_SECRET",
      "access_token_env": "WHATSAPP_ACCESS_TOKEN",
      "authorization_env": "BULKHEAD_WHATSAPP_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_sender_numbers": [],
      "api_base": "https://graph.facebook.com/v23.0"
    }
  }
}
```

Implementation notes:

- `verify_token_env` is used for Meta's initial webhook challenge
- `app_secret_env` enables `X-Hub-Signature-256` verification for webhook POSTs
- inbound text replies are sent back through the configured Graph API base

### Facebook Messenger

Reference checked for this connector work: 2026-04-11.

```bash
export MESSENGER_VERIFY_TOKEN="choose-a-random-verify-token"
export MESSENGER_APP_SECRET="meta-app-secret"
export MESSENGER_ACCESS_TOKEN="facebook-page-access-token"
export BULKHEAD_MESSENGER_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "messenger": {
      "enabled": true,
      "webhook_path": "/connectors/messenger/webhook",
      "verify_token_env": "MESSENGER_VERIFY_TOKEN",
      "app_secret_env": "MESSENGER_APP_SECRET",
      "access_token_env": "MESSENGER_ACCESS_TOKEN",
      "authorization_env": "BULKHEAD_MESSENGER_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_page_ids": [],
      "allowed_sender_ids": [],
      "api_base": "https://graph.facebook.com/v23.0"
    }
  }
}
```

Implementation notes:

- `access_token_env` should hold the Page access token used to send replies
- webhook verification and optional `X-Hub-Signature-256` validation follow the normal Meta webhook flow
- outbound text replies are sent to `/{page-id}/messages`
- conversation memory is scoped per `page_id + sender_id`

### Instagram Direct

Reference checked for this connector work: 2026-04-11.

```bash
export INSTAGRAM_VERIFY_TOKEN="choose-a-random-verify-token"
export INSTAGRAM_APP_SECRET="meta-app-secret"
export INSTAGRAM_ACCESS_TOKEN="instagram-access-token"
export BULKHEAD_INSTAGRAM_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "instagram": {
      "enabled": true,
      "webhook_path": "/connectors/instagram/webhook",
      "verify_token_env": "INSTAGRAM_VERIFY_TOKEN",
      "app_secret_env": "INSTAGRAM_APP_SECRET",
      "access_token_env": "INSTAGRAM_ACCESS_TOKEN",
      "authorization_env": "BULKHEAD_INSTAGRAM_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_account_ids": [],
      "allowed_sender_ids": [],
      "api_base": "https://graph.instagram.com/v23.0"
    }
  }
}
```

Implementation notes:

- webhook verification and optional `X-Hub-Signature-256` validation follow the normal Meta webhook flow
- inbound events are parsed from `object=instagram` with `entry[].messaging[]`
- outbound text replies are sent to `/me/messages`
- conversation memory is scoped per `instagram_account_id + sender_id`

### LINE

Reference checked for this connector work: 2026-04-11.

```bash
export LINE_CHANNEL_SECRET="line-channel-secret"
export LINE_ACCESS_TOKEN="line-channel-access-token"
export BULKHEAD_LINE_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "line": {
      "enabled": true,
      "webhook_path": "/connectors/line/webhook",
      "channel_secret_env": "LINE_CHANNEL_SECRET",
      "access_token_env": "LINE_ACCESS_TOKEN",
      "authorization_env": "BULKHEAD_LINE_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_user_ids": [],
      "allowed_group_ids": [],
      "allowed_room_ids": [],
      "api_base": "https://api.line.me/v2/bot"
    }
  }
}
```

Implementation notes:

- `channel_secret_env` verifies the `X-Line-Signature` HMAC on webhook POSTs
- replies use LINE's reply-token flow through `/message/reply`
- conversation memory is scoped to the smallest stable LINE conversation source: user, group, or room

### Viber

Reference checked for this connector work: 2026-04-11.

```bash
export VIBER_AUTH_TOKEN="viber-bot-auth-token"
export BULKHEAD_VIBER_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "viber": {
      "enabled": true,
      "webhook_path": "/connectors/viber/webhook",
      "auth_token_env": "VIBER_AUTH_TOKEN",
      "authorization_env": "BULKHEAD_VIBER_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_sender_ids": [],
      "sender_name": "BulkheadLM",
      "sender_avatar": "https://example.test/avatar.png",
      "api_base": "https://chatapi.viber.com/pa"
    }
  }
}
```

Implementation notes:

- `auth_token_env` is reused for both webhook signature validation (`X-Viber-Content-Signature`) and outbound `X-Viber-Auth-Token`
- outbound text replies are sent through `send_message`
- `conversation_started` receives an onboarding reply, while normal text messages reuse the standard BulkheadLM route and session memory path

### WeChat Service Account

Reference checked for this connector work: 2026-04-11.

```bash
export WECHAT_SIGNATURE_TOKEN="wechat-signature-token"
export WECHAT_ENCODING_AES_KEY="43-char-wechat-encoding-aes-key"
export WECHAT_APP_ID="wechat-app-id-example"
export BULKHEAD_WECHAT_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "wechat": {
      "enabled": true,
      "webhook_path": "/connectors/wechat/webhook",
      "signature_token_env": "WECHAT_SIGNATURE_TOKEN",
      "encoding_aes_key_env": "WECHAT_ENCODING_AES_KEY",
      "app_id_env": "WECHAT_APP_ID",
      "authorization_env": "BULKHEAD_WECHAT_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_open_ids": [],
      "allowed_account_ids": []
    }
  }
}
```

Implementation notes:

- `signature_token_env` is used for plaintext URL verification and plaintext POST signature validation through `signature + timestamp + nonce`
- `encoding_aes_key_env` plus `app_id_env` enable WeChat compatibility mode and security mode through the official `msg_signature + Encrypt` flow
- inbound user messages arrive as XML and are answered through passive XML replies on the same request
- encrypted WeChat requests are decrypted and encrypted replies are rewrapped into the standard `<Encrypt/> + <MsgSignature/> + <TimeStamp/> + <Nonce/>` XML envelope
- conversation memory is scoped per `account_id + open_id`
- because this is a passive reply flow, the model call still needs to finish within WeChat's response window

### Discord Interactions

Reference checked for this connector work: 2026-04-11.

```bash
export DISCORD_PUBLIC_KEY="discord-app-public-key-hex"
export BULKHEAD_DISCORD_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "discord": {
      "enabled": true,
      "webhook_path": "/connectors/discord/webhook",
      "public_key_env": "DISCORD_PUBLIC_KEY",
      "authorization_env": "BULKHEAD_DISCORD_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_application_ids": [],
      "allowed_user_ids": [],
      "allowed_channel_ids": [],
      "allowed_guild_ids": [],
      "ephemeral_by_default": true
    }
  }
}
```

Optional command-registration example:

```bash
export DISCORD_APPLICATION_ID="123456789012345678"
export DISCORD_BOT_TOKEN="discord-bot-token"

curl -sS "https://discord.com/api/v10/applications/${DISCORD_APPLICATION_ID}/commands" \
  -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{
    "name": "bulkhead",
    "type": 1,
    "description": "Talk to BulkheadLM",
    "integration_types": [0, 1],
    "contexts": [0, 1],
    "options": [
      {
        "name": "message",
        "description": "Your message to the assistant",
        "type": 3,
        "required": true
      }
    ]
  }'
```

Implementation notes:

- this connector uses Discord's signed outgoing interaction webhooks, not general gateway message events
- `public_key_env` is used to verify `X-Signature-Ed25519` and `X-Signature-Timestamp`
- application commands are acknowledged immediately, then the original Discord response is edited asynchronously so the model call can outlive Discord's 3-second initial-response window
- conversation memory is scoped per `application_id + guild_or_dm + channel_id + user_id`
- this connector currently targets slash-command style conversation rather than arbitrary message-content bot listeners

### Google Chat

Reference checked for this connector work: 2026-04-11.

```bash
export BULKHEAD_GOOGLE_CHAT_AUTH="sk-bulkhead-lm-dev"
```

```json
{
  "user_connectors": {
    "google_chat": {
      "enabled": true,
      "webhook_path": "/connectors/google-chat/webhook",
      "authorization_env": "BULKHEAD_GOOGLE_CHAT_AUTH",
      "route_model": "gpt-5-mini",
      "system_prompt": "Reply in a concise, practical tone for chat users.",
      "allowed_space_names": [],
      "allowed_user_names": [],
      "id_token_auth": {
        "audience": "https://your-public-host/connectors/google-chat/webhook",
        "certs_url": "https://www.googleapis.com/oauth2/v1/certs"
      }
    }
  }
}
```

Implementation notes:

- this connector uses synchronous Google Chat responses, so the model call must finish within Google's response window
- `id_token_auth` enables verification of the Google-signed bearer token sent in the `Authorization` header for self-hosted HTTP endpoints
- conversation memory is scoped to the Google Chat thread when a thread exists, otherwise to the space

## Local starter

On macOS, Ubuntu, or FreeBSD, the simplest entry point is the starter script:

```bash
./run.sh
```

On macOS, you can also use the Finder-friendly launcher:

```bash
./start-macos-client.command
```

The starter:

- supports local first-run flows on macOS, Ubuntu, and FreeBSD through OS-specific wrappers behind the same `./run.sh` entrypoint
- can bootstrap a repo-local `opam` binary before falling back to Homebrew, `apt`, or `pkg`
- sources `~/.zshrc.secret`, `~/.zshrc.secrets`, `~/.bashrc.secret`, `~/.bashrc.secrets`, `~/.profile.secret`, `~/.profile.secrets`, and `~/.config/bulkhead-lm/env` when present
- checks the current `opam` switch first and only offers a project-local fallback when the active toolchain is not coherent for this repo
- can offer Homebrew, `apt`, or `pkg` bootstrap steps instead of dropping raw OCaml build errors on a beginner
- reuses your configured provider keys from the shell environment
- asks which configured model you want to use now
- can generate a starter config that expands one provider key into several curated model routes for that provider
- can build a personal portable JSON config at `config/starter.gateway.json`
- uses real line editing in the human starter: left/right arrows, in-line edits, history recall, and tab completion
- keeps a followed conversation thread by default and compresses older turns into a shorter memory summary when the session grows
- includes an administrative assistant that prepares explicit plans before changing BulkheadLM config or attempting local system actions
- includes a guided packaging flow that can build a distributable package for macOS, Ubuntu, or FreeBSD from the same assistant terminal
- shows masked environment and provider readiness state from inside the REPL
- drops you into a simple terminal session with `/tools`, `/file PATH`, `/files`, `/clearfiles`, `/explore PATH`, `/open PATH`, `/run CMD`, `/admin`, `/package`, `/plan`, `/apply`, `/discard`, `/model`, `/models`, `/swap`, `/memory`, `/forget`, `/thread on|off`, `/providers`, `/env`, `/config`, `/help`, and `/quit`

Admin assistant flow inside the starter:

```text
/admin enable local file operations only for this repository and explain each step simply
/plan
/apply
```

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

Example route families currently implemented:

- `openai_compat`
- `anthropic`
- `openrouter_openai`
- `google_openai`
- `mistral_openai`
- `ollama_openai`
- `alibaba_openai`
- `moonshot_openai`
- `bulkhead_peer`
- `bulkhead_ssh_peer`

The bundled example config now exposes several curated public routes per cloud provider, so one upstream provider key can unlock several routed models. The current example includes:

- OpenAI: `gpt-5`, `gpt-5-mini`, `gpt-5-nano`
- OpenRouter: `openrouter-auto`, `openrouter-free`, `openrouter-gpt-5.2`
- Anthropic: `claude-opus`, `claude-sonnet`, `claude-haiku`
- Google Gemini: `gemini-2.5-pro`, `gemini-2.5-flash`, `gemini-2.5-flash-lite`
- Mistral: `mistral-medium`, `mistral-small`, `codestral`
- Alibaba Qwen: `qwen-max`, `qwen-plus`, `qwen-turbo`
- Moonshot Kimi: `kimi-latest`, `kimi-k2`, `kimi-k2.5`

OpenRouter is configured against `https://openrouter.ai/api/v1` with `api_key_env` set to `OPEN_ROUTER_KEY` by default. OpenRouter's optional attribution headers are not required for BulkheadLM routing.

These curated route families were last aligned with official provider docs on `2026-04-09`. They are not a claim that BulkheadLM enumerates every upstream model a provider may ever expose.

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
  example.gateway.json

docs/
  ARCHITECTURE.md
  COMPLIANCE_US_CN.md
  SECURITY.md

scripts/
  integration_matrix.sh
  macos_starter.sh
  starter_common.sh
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
  http/
  persistence/

test/
  bulkhead_lm_test.ml
```

See [Architecture](docs/ARCHITECTURE.md) for the layer-by-layer design.

## Security and compliance

BulkheadLM is a hardening-oriented gateway, not a certification claim.

Current built-in controls include:

- explicit upstream allow/deny decisions instead of runtime discovery
- no implicit forwarding of client `authorization` or `x-api-key` headers upstream
- bounded fallback routing
- request size and timeout enforcement
- persistent audit logging
- request and token budget enforcement before uncontrolled fan-out
- bounded worker concurrency with per-request output isolation on stdio

Detailed references:

- [Security Posture](docs/SECURITY.md)
- [Security Policy](SECURITY.md)
- [US and China Compliance Study](docs/COMPLIANCE_US_CN.md)

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

Run the full suite with:

```bash
dune build @runtest
```

## Status and limitations

- provider-native upstream streaming is not implemented yet; SSE is currently normalized by the gateway from the provider-normalized response
- provider coverage is intentionally narrow and explicit
- Moonshot is currently modeled as chat-only in the provider schema
- there is no admin UI or hot-reload control plane yet
- the worker protocol is currently JSONL over stdio rather than a binary IPC protocol
- the guided local starter currently targets macOS, Ubuntu, and FreeBSD; other systems should use `bulkhead-lm-client starter` directly
- military or sovereign-environment compliance still requires deployment hardening, supply-chain evidence, identity integration, and formal assessment artifacts

## License

BulkheadLM is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
