#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

chmod +x \
  "$ROOT_DIR/run.sh" \
  "$ROOT_DIR/scripts/macos_starter.sh" \
  "$ROOT_DIR/start-macos-client.command" >/dev/null 2>&1 || true

if command -v zsh >/dev/null 2>&1; then
  exec zsh "$ROOT_DIR/scripts/macos_starter.sh" "$@"
fi

printf '%s\n' "zsh was not found." >&2
printf '%s\n' "On macOS, install the Xcode command line tools or zsh, then rerun ./run.sh." >&2
exit 1
