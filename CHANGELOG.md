# Changelog

## Unreleased

### Added

- **Multi-persona Telegram bots** for "group chat where each member is a
  different model or pool":
  - `Config.user_connectors.telegram` is now a list, so several Telegram
    bots can run on one gateway, each with its own `persona_name`,
    `webhook_path`, and `route_model` (which can be a pool name)
  - Each entry has a `room_memory_mode` of `"shared"` (default; every
    persona on the same chat_id reads the same conversation history) or
    `"isolated"` (each persona keeps its own thread)
  - Assistant turns committed to a shared room are tagged
    `[persona_name] ...` so other personas can tell who said what; the
    system prompt is augmented automatically to make each persona aware
    that other AI participants may be in the room
  - Backward compatible: legacy single-bot config (the connector as a
    JSON object instead of an array) parses to a one-element list with a
    default persona name and shared room memory
  - New starter command `/persona list` (alias `/persona`) shows every
    configured persona, its route, env var status, webhook path, room
    mode and short system prompt summary
  - 6 new tests covering both config shapes, shared vs isolated session
    keys, and assistant turn tagging (121/121 total)

- **Named model pools** layered on top of routes:
  - Each pool is a named group of route members, each with its own
    per-day token budget; the pool name is itself a public model id, so
    a vanilla OpenAI client can target it directly with `model=pool-01`
  - The selector picks the member with the lowest observed latency that
    still has budget remaining and a closed circuit breaker; failures
    are penalised in the EWMA tracker and the request falls through to
    the next candidate
  - Members never observed yet rank BEFORE well-known slow members so
    new entries always get at least one probe instead of being starved
  - A reserved `is_global` pool ignores its declared members and
    recomputes them as every configured route at lookup time, giving a
    "one magic model" surface; toggle it with `/pool global on`
  - New starter commands: `/pool list`, `/pool show NAME`,
    `/pool create NAME`, `/pool drop NAME`,
    `/pool add NAME ROUTE [BUDGET]`,
    `/pool remove NAME ROUTE`, `/pool global on|off`
  - New SQLite tables `pool_member_usage` (atomic per-day token
    accounting) and `pool_overrides` (JSON snapshot so wizard mutations
    survive a gateway restart); declarative `gateway.json` is the seed
  - `/v1/models` exposes pools both inline in `data[]` (with
    `model_kind: "pool"` and `is_global` flag) and as a dedicated
    `pools[]` section listing members and per-member budgets
  - New modules: `Pool_latency` (in-memory EWMA tracker),
    `Pool_selector` (ranking + structured exhaustion error),
    `Pool_routing` (router glue + budget charging),
    `Pool_runtime` (mutations + persistence)
  - 7 new tests covering ranking, anti-starvation probing, structured
    exhaustion error, circuit-broken exclusion, global pool aggregate,
    runtime mutations, and JSON exposure (115/115 total)

- **Provider model discovery** for the starter:
  - New `/discover` command lists upstream models exposed by detected provider API keys
  - New `/refresh-models` command bypasses the cache and refetches provider listings
  - OpenAI-compatible providers use `{api_base}/models`; Anthropic uses its native headers and pagination
  - Provider listings are cached per provider under the XDG cache path or `BULKHEAD_LM_MODEL_CACHE_DIR`
  - `/v1/models` now includes provider groups and cached `discovered_models` when present, without doing live network refreshes

- **6 new direct provider kinds**: `deepseek_openai`, `groq_openai`, `perplexity_openai`, `together_openai`, `cerebras_openai`, `cohere_openai`
  - All six dispatch through the existing OpenAI-compatible adapter (`Openai_compat_provider`)
  - New env vars: `DEEPSEEK_API_KEY`, `GROQ_API_KEY`, `PERPLEXITY_API_KEY`, `TOGETHER_API_KEY`, `CEREBRAS_API_KEY`, `COHERE_API_KEY`
  - Embeddings support: `together_openai`, `cohere_openai`
  - Chat only: `deepseek_openai`, `groq_openai`, `perplexity_openai`, `cerebras_openai`

- **18 new example routes** in `config/example.gateway.json` (28 → 46 total):
  - DeepSeek: `deepseek-v3`, `deepseek-r1`, `deepseek-r1-lite`
  - Groq: `groq-llama-3.3-70b`, `groq-llama-3.1-8b`, `groq-qwen-qwq-32b`
  - Perplexity: `perplexity-sonar-pro`, `perplexity-sonar`, `perplexity-sonar-reasoning`
  - Together AI: `together-llama-3.3-70b`, `together-deepseek-v3`, `together-qwen-2.5-72b`
  - Cerebras: `cerebras-llama-3.3-70b`, `cerebras-llama-3.1-8b`
  - Cohere: `cohere-command-r-plus`, `cohere-command-r`, `cohere-embed-v3`

- Updated `config/defaults/providers.schema.json` with all 6 new provider kinds and their capabilities

### Changed

- `README.md`: expanded provider table to 19 kinds with key env vars, API base URLs, and route counts
- `readme_for_dummies.md`: added DeepSeek, Groq, Cerebras, Perplexity, Together AI, Cohere to cheapest-path guide and key-variable reference
- `scripts/smoke_ollama.sh`: switched from zsh-specific syntax to POSIX `sh` so CI and minimal Unix environments can run the smoke wrapper
- test fixture path handling now resolves config files from the repository root instead of assuming the current working directory
