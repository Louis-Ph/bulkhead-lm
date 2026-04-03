#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
CONFIG_FILE="$ROOT_DIR/config/example.gateway.json"
DB_FILE="$ROOT_DIR/var/aegislm.sqlite"
PORT="${AEGISLM_MATRIX_PORT:-4115}"
PID=""

cleanup() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [[ -r "$HOME/.zshrc.secrets" ]]; then
  source "$HOME/.zshrc.secrets"
fi

start_gateway() {
  /bin/rm -f "$DB_FILE" "$DB_FILE-shm" "$DB_FILE-wal"
  dune exec ./bin/main.exe -- --config "$CONFIG_FILE" --port "$PORT" >/tmp/aegislm-matrix.log 2>&1 &
  PID=$!
  for _ in {1..30}; do
    if /usr/bin/curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
  print -u2 "Gateway did not become healthy."
  /bin/cat /tmp/aegislm-matrix.log >&2
  exit 1
}

json_request() {
  local path="$1"
  local payload="$2"
  local body_file status_code body
  body_file=$(/usr/bin/mktemp)
  status_code=$(/usr/bin/curl -sS -o "$body_file" -w '%{http_code}' \
    "http://127.0.0.1:${PORT}${path}" \
    -H "content-type: application/json" \
    -H "authorization: Bearer sk-aegis-dev" \
    -d "$payload")
  body=$(<"$body_file")
  /bin/rm -f "$body_file"
  print "${status_code}"
  print -- "$body"
}

assert_successful_json() {
  local label="$1"
  local path="$2"
  local payload="$3"
  local expected="$4"
  local result status_code body
  result=$(json_request "$path" "$payload")
  status_code=${result%%$'\n'*}
  body=${result#*$'\n'}

  if (( status_code >= 400 )); then
    if [[ "$label" == openai* ]] && print -- "$body" | /usr/bin/grep -q 'insufficient_quota'; then
      print "skip ${label}: upstream quota exhausted"
      return 0
    fi
    print -u2 "${label} failed with HTTP ${status_code}"
    print -u2 "$body"
    exit 1
  fi

  print -- "$body" | /usr/bin/grep -q "$expected"
  print "ok ${label}"
}

assert_sse() {
  local label="$1"
  local path="$2"
  local payload="$3"
  local dump_file body
  dump_file=$(/usr/bin/mktemp)
  /usr/bin/curl -sS -D "$dump_file.headers" \
    "http://127.0.0.1:${PORT}${path}" \
    -H "content-type: application/json" \
    -H "authorization: Bearer sk-aegis-dev" \
    -d "$payload" \
    > "$dump_file"
  /usr/bin/grep -qi 'content-type: text/event-stream' "$dump_file.headers"
  body=$(<"$dump_file")
  /usr/bin/grep -q 'data: \[DONE\]' "$dump_file"
  /usr/bin/grep -q 'event: response.output_text.delta\|chat.completion.chunk\|"object":"chat.completion.chunk"' "$dump_file"
  /bin/rm -f "$dump_file" "$dump_file.headers"
  print "ok ${label}"
}

assert_persistence() {
  [[ -s "$DB_FILE" ]]
  [[ "$(/usr/bin/sqlite3 "$DB_FILE" 'select count(*) from virtual_keys;')" -ge 1 ]]
  [[ "$(/usr/bin/sqlite3 "$DB_FILE" 'select count(*) from audit_log;')" -ge 1 ]]
  print "ok persistence"
}

start_gateway

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  assert_successful_json \
    "anthropic chat" \
    "/v1/chat/completions" \
    '{"model":"claude-sonnet","messages":[{"role":"user","content":"Reply with the single word OK."}]}' \
    '"object":"chat.completion"'
fi

if [[ -n "${GOOGLE_API_KEY:-}" ]]; then
  assert_successful_json \
    "google chat" \
    "/v1/chat/completions" \
    '{"model":"gemini-2.5-flash","messages":[{"role":"user","content":"Reply with the single word OK."}]}' \
    '"object":"chat.completion"'
fi

if [[ -n "${DASHSCOPE_API_KEY:-}" ]]; then
  assert_successful_json \
    "alibaba chat" \
    "/v1/chat/completions" \
    '{"model":"qwen-plus","messages":[{"role":"user","content":"Reply with the single word OK."}]}' \
    '"object":"chat.completion"'
fi

if [[ -n "${MOONSHOT_API_KEY:-}" ]]; then
  assert_successful_json \
    "moonshot chat" \
    "/v1/chat/completions" \
    '{"model":"kimi-k2.5","messages":[{"role":"user","content":"Reply with the single word OK."}]}' \
    '"object":"chat.completion"'
fi

if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  assert_successful_json \
    "openai chat" \
    "/v1/chat/completions" \
    '{"model":"gpt-5-mini","messages":[{"role":"user","content":"Reply with the single word OK."}]}' \
    '"object":"chat.completion"'
fi

STREAM_MODEL=""
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  STREAM_MODEL="claude-sonnet"
elif [[ -n "${DASHSCOPE_API_KEY:-}" ]]; then
  STREAM_MODEL="qwen-plus"
elif [[ -n "${MOONSHOT_API_KEY:-}" ]]; then
  STREAM_MODEL="kimi-k2.5"
elif [[ -n "${GOOGLE_API_KEY:-}" ]]; then
  STREAM_MODEL="gemini-2.5-flash"
elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
  STREAM_MODEL="gpt-5-mini"
fi

if [[ -n "$STREAM_MODEL" ]]; then
  assert_sse \
    "chat sse" \
    "/v1/chat/completions" \
    "{\"model\":\"${STREAM_MODEL}\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word OK.\"}]}"

  assert_sse \
    "responses sse" \
    "/v1/responses" \
    "{\"model\":\"${STREAM_MODEL}\",\"stream\":true,\"input\":\"Reply with the single word OK.\"}"
fi

assert_persistence
print "integration_matrix: ok"
