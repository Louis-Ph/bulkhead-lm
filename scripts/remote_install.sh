#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/remote_common.sh"

MODE=
ORIGIN=${BULKHEAD_LM_INSTALL_ORIGIN:-}
DEFAULT_TARGET=${BULKHEAD_LM_REMOTE_INSTALL_DEFAULT_TARGET}
SELF_PATH="${SCRIPT_DIR}/remote_install.sh"

print_help() {
  cat <<EOF
Usage:
  scripts/remote_install.sh --archive
  scripts/remote_install.sh --emit-installer --origin user@host [--default-target EXPR]

Modes:
  --archive           Stream a filtered tar.gz snapshot of this BulkheadLM repo to stdout
  --emit-installer    Emit a local installer shell script to stdout

Options:
  --origin DEST       SSH destination that the emitted installer should call back
  --default-target EXPR
                      Default local install target expression. Default: ${DEFAULT_TARGET}
  --help              Show this help

Examples:
  ssh user@host '${SELF_PATH} --emit-installer --origin user@host' | sh
  ssh user@host '${SELF_PATH} --archive' | tar -xzf - -C "\$HOME/opt/bulkhead-lm"
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --archive)
      [ -z "${MODE}" ] || { bulkhead_lm_remote_note "Choose only one mode."; exit 1; }
      MODE=archive
      shift
      ;;
    --emit-installer)
      [ -z "${MODE}" ] || { bulkhead_lm_remote_note "Choose only one mode."; exit 1; }
      MODE=installer
      shift
      ;;
    --origin)
      [ "$#" -ge 2 ] || { bulkhead_lm_remote_note "--origin requires a value"; exit 1; }
      ORIGIN=$2
      shift 2
      ;;
    --default-target)
      [ "$#" -ge 2 ] || { bulkhead_lm_remote_note "--default-target requires a value"; exit 1; }
      DEFAULT_TARGET=$2
      shift 2
      ;;
    *)
      bulkhead_lm_remote_note "Unknown option: $1"
      exit 1
      ;;
  esac
done

case "${MODE}" in
  archive)
    bulkhead_lm_remote_stream_archive
    ;;
  installer)
    if [ -z "${ORIGIN}" ]; then
      bulkhead_lm_remote_note "--origin is required with --emit-installer."
      exit 1
    fi
    bulkhead_lm_remote_emit_local_installer "${ORIGIN}" "${SELF_PATH}" "${DEFAULT_TARGET}"
    ;;
  *)
    print_help >&2
    exit 1
    ;;
esac
