#!/bin/sh
set -eu

CONTROL_BASE=${1:-http://127.0.0.1:4100/_bulkhead/control}
SESSION_KEY=${2:-demo:memory:session}
SUMMARY=${3:-Planner memory replaced by external orchestrator.}

say() { printf '%s\n' "$1"; }
say_err() { printf '%s\n' "$1" >&2; }

if [ -z "${BULKHEAD_ADMIN_TOKEN:-}" ]; then
  say_err "Set BULKHEAD_ADMIN_TOKEN before running this smoke script."
  exit 1
fi

AUTH_HEADER="authorization: Bearer ${BULKHEAD_ADMIN_TOKEN}"
PUT_JSON=$(mktemp)
GET_JSON=$(mktemp)
DELETE_JSON=$(mktemp)

cleanup() {
  rm -f "$PUT_JSON" "$GET_JSON" "$DELETE_JSON"
}
trap cleanup EXIT INT TERM

show_json() {
  path=$1
  if command -v jq >/dev/null 2>&1; then
    jq . "$path"
  else
    cat "$path"
  fi
}

say "PUT ${CONTROL_BASE}/api/memory/session"
curl -fsS \
  -H "$AUTH_HEADER" \
  -H "content-type: application/json" \
  -X PUT \
  -d "{\"session_key\":\"${SESSION_KEY}\",\"summary\":\"${SUMMARY}\",\"compressed_turn_count\":12,\"recent_turns\":[{\"role\":\"user\",\"content\":\"Remember the supply constraints.\"},{\"role\":\"assistant\",\"content\":\"Constraints captured in the durable summary.\"}]}" \
  "${CONTROL_BASE}/api/memory/session" \
  > "$PUT_JSON"

show_json "$PUT_JSON"

say ""
say "GET ${CONTROL_BASE}/api/memory/session?session_key=${SESSION_KEY}"
curl -fsS \
  -H "$AUTH_HEADER" \
  "${CONTROL_BASE}/api/memory/session?session_key=${SESSION_KEY}" \
  > "$GET_JSON"

show_json "$GET_JSON"

say ""
say "DELETE ${CONTROL_BASE}/api/memory/session?session_key=${SESSION_KEY}"
curl -fsS \
  -H "$AUTH_HEADER" \
  -X DELETE \
  "${CONTROL_BASE}/api/memory/session?session_key=${SESSION_KEY}" \
  > "$DELETE_JSON"

show_json "$DELETE_JSON"
