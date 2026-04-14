#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

OS_NAME=$(uname -s 2>/dev/null || printf '%s' unknown)
case "$OS_NAME" in
  Darwin)
    STARTER_SCRIPT="$ROOT_DIR/scripts/macos_starter.sh"
    ;;
  Linux)
    STARTER_SCRIPT="$ROOT_DIR/scripts/linux_starter.sh"
    ;;
  FreeBSD)
    STARTER_SCRIPT="$ROOT_DIR/scripts/freebsd_starter.sh"
    ;;
  *)
    printf '%s\n' "Unsupported host OS: $OS_NAME" >&2
    printf '%s\n' "Use dune exec bulkhead-lm-client -- starter directly on this system." >&2
    exit 1
    ;;
esac

chmod +x \
  "$ROOT_DIR/run.sh" \
  "$ROOT_DIR/scripts/macos_starter.sh" \
  "$ROOT_DIR/scripts/linux_starter.sh" \
  "$ROOT_DIR/scripts/ubuntu_starter.sh" \
  "$ROOT_DIR/scripts/freebsd_starter.sh" \
  "$ROOT_DIR/start-macos-client.command" >/dev/null 2>&1 || true

exec /bin/sh "$STARTER_SCRIPT" "$@"
