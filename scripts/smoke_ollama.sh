#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CONFIG_FILE="${BULKHEAD_LM_OLLAMA_CONFIG:-$ROOT_DIR/config/example.ollama_swarm.gateway.json}"
PORT="${BULKHEAD_LM_SMOKE_PORT:-4111}"
OLLAMA_BASE="${BULKHEAD_LM_OLLAMA_BASE:-http://127.0.0.1:11434}"
PID=""
STARTUP_RETRIES="${BULKHEAD_LM_SMOKE_STARTUP_RETRIES:-120}"

export OLLAMA_API_KEY="${OLLAMA_API_KEY:-ollama}"

cleanup() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

run_gateway() {
  BULKHEAD_LM_OLLAMA_CONFIG="$CONFIG_FILE" "$ROOT_DIR/run-ollama.sh" --port "$PORT"
}

post_json() {
  path="$1"
  payload="$2"
  expected="$3"
  label="$4"

  body_file=$(/usr/bin/mktemp)
  http_code=$(/usr/bin/curl -sS -o "$body_file" -w '%{http_code}' "http://127.0.0.1:${PORT}${path}" \
    -H "content-type: application/json" \
    -H "authorization: Bearer sk-bulkhead-lm-dev" \
    -d "$payload")
  body=$(/bin/cat "$body_file")
  /bin/rm -f "$body_file"

  if [ "$http_code" -ge 400 ]; then
    printf '%s\n' "${label} failed with HTTP ${http_code}" >&2
    printf '%s\n' "$body" >&2
    exit 1
  fi

  printf '%s\n' "$body" | /usr/bin/grep -q "$expected"
}

if ! /usr/bin/curl -fsS "${OLLAMA_BASE}/v1/models" >/dev/null 2>&1; then
  printf '%s\n' "Ollama OpenAI endpoint is not reachable at ${OLLAMA_BASE}/v1/models" >&2
  printf '%s\n' "" >&2
  printf '%s\n' "Is Ollama installed and running? Install: https://ollama.com/download" >&2
  printf '%s\n' "Then start the daemon (e.g. 'ollama serve' or launch the Ollama app)." >&2
  exit 1
fi

REQUIRED_MODELS="swarm-router:latest swarm-worker:latest swarm-lead:latest swarm-critic:latest all-minilm:latest"
INSTALLED_MODELS=$(/usr/bin/curl -fsS "${OLLAMA_BASE}/v1/models" | /usr/bin/tr ',' '\n' | /usr/bin/grep -o '"id":"[^"]*"' | /usr/bin/cut -d'"' -f4 || true)

missing=""
for model in $REQUIRED_MODELS; do
  if ! printf '%s\n' "$INSTALLED_MODELS" | /usr/bin/grep -Fxq "$model"; then
    missing="${missing}${missing:+
}${model}"
  fi
done

if [ -n "$missing" ]; then
  printf '%s\n' "The following Ollama models required by config/example.ollama_swarm.gateway.json are missing:" >&2
  printf '%s\n' "$missing" | while IFS= read -r model; do
    printf '%s\n' "  - $model" >&2
  done
  printf '%s\n' "" >&2
  printf '%s\n' "The swarm-* aliases are local Modelfile-based models, not public Ollama models." >&2
  printf '%s\n' "To create each alias from an existing base model, run:" >&2
  printf '%s\n' "  printf 'FROM <base-model>\n' | ollama create <alias-name> -f -" >&2
  printf '%s\n' "" >&2
  printf '%s\n' "Example (use any installed base model, e.g. llama3.2:1b or qwen3:4b):" >&2
  printf '%s\n' "  ollama pull llama3.2:1b" >&2
  printf '%s\n' "  printf 'FROM llama3.2:1b\n' | ollama create swarm-router -f -" >&2
  printf '%s\n' "  printf 'FROM llama3.2:1b\n' | ollama create swarm-worker -f -" >&2
  printf '%s\n' "  printf 'FROM llama3.2:1b\n' | ollama create swarm-lead -f -" >&2
  printf '%s\n' "  printf 'FROM llama3.2:1b\n' | ollama create swarm-critic -f -" >&2
  printf '%s\n' "  ollama pull all-minilm" >&2
  printf '%s\n' "" >&2
  printf '%s\n' "Installed models on ${OLLAMA_BASE}:" >&2
  if [ -n "$INSTALLED_MODELS" ]; then
    printf '%s\n' "$INSTALLED_MODELS" | /usr/bin/sed 's/^/  - /' >&2
  else
    printf '%s\n' "  (none)" >&2
  fi
  exit 1
fi

run_gateway >/tmp/bulkhead-lm-ollama-smoke.log 2>&1 &
PID=$!

attempt=1
while [ "$attempt" -le "$STARTUP_RETRIES" ]; do
  if /usr/bin/curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
  attempt=$((attempt + 1))
done

if ! /usr/bin/curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  printf '%s\n' "Gateway did not become healthy." >&2
  if [ -r /tmp/bulkhead-lm-ollama-smoke.log ]; then
    /bin/cat /tmp/bulkhead-lm-ollama-smoke.log >&2
  fi
  exit 1
fi

post_json \
  "/v1/chat/completions" \
  '{"model":"swarm-router","messages":[{"role":"user","content":"Classify this task in one compact JSON object: review a patch."}]}' \
  '"object":"chat.completion"' \
  "router chat"

post_json \
  "/v1/chat/completions" \
  '{"model":"swarm-worker","messages":[{"role":"user","content":"Reply with the single word OK."}]}' \
  '"object":"chat.completion"' \
  "worker chat"

post_json \
  "/v1/responses" \
  '{"model":"swarm-lead","input":"Reply with the single word OK."}' \
  '"object":"response"' \
  "lead responses"

post_json \
  "/v1/chat/completions" \
  '{"model":"swarm-critic","messages":[{"role":"user","content":"Reply with the single word OK."}]}' \
  '"object":"chat.completion"' \
  "critic chat"

post_json \
  "/v1/embeddings" \
  '{"model":"all-minilm-local","input":"bulkhead ollama smoke test"}' \
  '"object":"list"' \
  "memory embeddings"

printf '%s\n' "smoke_ollama: ok (swarm-router, swarm-worker, swarm-lead, swarm-critic, all-minilm-local)"
