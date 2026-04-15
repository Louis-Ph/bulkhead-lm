#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
CONFIG_FILE="${BULKHEAD_LM_OLLAMA_CONFIG:-$ROOT_DIR/config/example.ollama_swarm.gateway.json}"
PORT="${BULKHEAD_LM_SMOKE_PORT:-4111}"
OLLAMA_BASE="${BULKHEAD_LM_OLLAMA_BASE:-http://127.0.0.1:11434}"
PID=""
STARTUP_RETRIES="${BULKHEAD_LM_SMOKE_STARTUP_RETRIES:-120}"

export OLLAMA_API_KEY="${OLLAMA_API_KEY:-ollama}"

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

run_gateway() {
  BULKHEAD_LM_OLLAMA_CONFIG="$CONFIG_FILE" "$ROOT_DIR/run-ollama.sh" --port "$PORT"
}

post_json() {
  local path="$1"
  local payload="$2"
  local expected="$3"
  local label="$4"
  local body_file http_code body

  body_file=$(/usr/bin/mktemp)
  http_code=$(/usr/bin/curl -sS -o "$body_file" -w '%{http_code}' "http://127.0.0.1:${PORT}${path}" \
    -H "content-type: application/json" \
    -H "authorization: Bearer sk-bulkhead-lm-dev" \
    -d "$payload")
  body=$(<"$body_file")
  /bin/rm -f "$body_file"

  if (( http_code >= 400 )); then
    print -u2 "${label} failed with HTTP ${http_code}"
    print -u2 "$body"
    exit 1
  fi

  print "$body" | /usr/bin/grep -q "$expected"
}

if ! /usr/bin/curl -fsS "${OLLAMA_BASE}/v1/models" >/dev/null 2>&1; then
  print -u2 "Ollama OpenAI endpoint is not reachable at ${OLLAMA_BASE}/v1/models"
  print -u2 ""
  print -u2 "Is Ollama installed and running? Install: https://ollama.com/download"
  print -u2 "Then start the daemon (e.g. 'ollama serve' or launch the Ollama app)."
  exit 1
fi

REQUIRED_MODELS=(swarm-router:latest swarm-worker:latest swarm-lead:latest swarm-critic:latest all-minilm:latest)
INSTALLED_MODELS=$(/usr/bin/curl -fsS "${OLLAMA_BASE}/v1/models" | /usr/bin/tr ',' '\n' | /usr/bin/grep -o '"id":"[^"]*"' | /usr/bin/cut -d'"' -f4 || true)

missing=()
for model in "${REQUIRED_MODELS[@]}"; do
  if ! print "$INSTALLED_MODELS" | /usr/bin/grep -Fxq "$model"; then
    missing+=("$model")
  fi
done

if (( ${#missing[@]} > 0 )); then
  print -u2 "The following Ollama models required by config/example.ollama_swarm.gateway.json are missing:"
  for model in "${missing[@]}"; do
    print -u2 "  - $model"
  done
  print -u2 ""
  print -u2 "The swarm-* aliases are local Modelfile-based models, not public Ollama models."
  print -u2 "To create each alias from an existing base model, run:"
  print -u2 "  printf 'FROM <base-model>\\n' | ollama create <alias-name> -f -"
  print -u2 ""
  print -u2 "Example (use any installed base model, e.g. llama3.2:1b or qwen3:4b):"
  print -u2 "  ollama pull llama3.2:1b"
  print -u2 "  printf 'FROM llama3.2:1b\\n' | ollama create swarm-router -f -"
  print -u2 "  printf 'FROM llama3.2:1b\\n' | ollama create swarm-worker -f -"
  print -u2 "  printf 'FROM llama3.2:1b\\n' | ollama create swarm-lead -f -"
  print -u2 "  printf 'FROM llama3.2:1b\\n' | ollama create swarm-critic -f -"
  print -u2 "  ollama pull all-minilm"
  print -u2 ""
  print -u2 "Installed models on ${OLLAMA_BASE}:"
  if [[ -n "$INSTALLED_MODELS" ]]; then
    print -u2 "$INSTALLED_MODELS" | /usr/bin/sed 's/^/  - /' >&2
  else
    print -u2 "  (none)"
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
  print -u2 "Gateway did not become healthy."
  if [[ -r /tmp/bulkhead-lm-ollama-smoke.log ]]; then
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

print "smoke_ollama: ok (swarm-router, swarm-worker, swarm-lead, swarm-critic, all-minilm-local)"
