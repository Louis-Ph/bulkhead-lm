#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG_FILE=${BULKHEAD_LM_OLLAMA_CONFIG:-$ROOT_DIR/config/example.ollama_swarm.gateway.json}

export OLLAMA_API_KEY=${OLLAMA_API_KEY:-ollama}

exec "$ROOT_DIR/scripts/with_local_toolchain.sh" \
  dune exec ./bin/main.exe -- \
  --config "$CONFIG_FILE" \
  "$@"
