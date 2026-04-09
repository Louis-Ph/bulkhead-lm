#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
CONFIG_FILE="$ROOT_DIR/config/example.gateway.json"
PORT="${BULKHEAD_LM_SMOKE_PORT:-4110}"
MODEL="${BULKHEAD_LM_SMOKE_MODEL:-}"
PID=""
STARTUP_RETRIES="${BULKHEAD_LM_SMOKE_STARTUP_RETRIES:-20}"
USE_LOCAL_TOOLCHAIN_WRAPPER=0

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

prepare_gateway_runtime() {
  if command -v dune >/dev/null 2>&1; then
    return 0
  fi

  if [[ -x "$ROOT_DIR/scripts/bootstrap_local_toolchain.sh" ]]; then
    "$ROOT_DIR/scripts/bootstrap_local_toolchain.sh"
  fi

  if [[ -x "$ROOT_DIR/scripts/with_local_toolchain.sh" ]]; then
    USE_LOCAL_TOOLCHAIN_WRAPPER=1
    STARTUP_RETRIES="${BULKHEAD_LM_SMOKE_STARTUP_RETRIES:-120}"
    return 0
  fi

  print -u2 "Neither dune nor the local toolchain wrapper is available."
  exit 1
}

run_gateway() {
  if (( USE_LOCAL_TOOLCHAIN_WRAPPER )); then
    "$ROOT_DIR/scripts/with_local_toolchain.sh" dune exec ./bin/main.exe -- --config "$CONFIG_FILE" --port "$PORT"
  else
    dune exec ./bin/main.exe -- --config "$CONFIG_FILE" --port "$PORT"
  fi
}

if [[ -r "$HOME/.zshrc.secrets" ]]; then
  source "$HOME/.zshrc.secrets"
fi

if [[ -z "$MODEL" ]]; then
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    MODEL="claude-sonnet"
  elif [[ -n "${MISTRAL_API_KEY:-}" ]]; then
    MODEL="mistral-small"
  elif [[ -n "${DASHSCOPE_API_KEY:-}" ]]; then
    MODEL="qwen-plus"
  elif [[ -n "${MOONSHOT_API_KEY:-}" ]]; then
    MODEL="kimi-k2.5"
  elif [[ -n "${GOOGLE_API_KEY:-}" ]]; then
    MODEL="gemini-2.5-flash"
  elif [[ -n "${OPEN_ROUTER_KEY:-}" ]]; then
    MODEL="openrouter-free"
  elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
    MODEL="gpt-5-mini"
  else
    print -u2 "No supported provider key is set."
    exit 1
  fi
fi

prepare_gateway_runtime
run_gateway >/tmp/bulkhead-lm-smoke.log 2>&1 &
PID=$!

for (( attempt = 1; attempt <= STARTUP_RETRIES; attempt++ )); do
  if /usr/bin/curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

if ! /usr/bin/curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  print -u2 "Gateway did not become healthy."
  if [[ -r /tmp/bulkhead-lm-smoke.log ]]; then
    /bin/cat /tmp/bulkhead-lm-smoke.log >&2
  fi
  exit 1
fi

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

post_json \
  "/v1/chat/completions" \
  "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word OK.\"}]}" \
  '"object":"chat.completion"' \
  "chat"

post_json \
  "/v1/responses" \
  "{\"model\":\"${MODEL}\",\"input\":\"Reply with the single word OK.\"}" \
  '"object":"response"' \
  "responses"

print "smoke_openai: ok (${MODEL})"
