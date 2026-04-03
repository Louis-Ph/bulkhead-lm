#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/remote_common.sh"

MODE=
ORIGIN=${AEGISLM_INSTALL_ORIGIN:-}
DEFAULT_TARGET=${AEGISLM_REMOTE_INSTALL_DEFAULT_TARGET}
SELF_PATH="${SCRIPT_DIR}/remote_install.sh"

print_help() {
  cat <<EOF
Usage:
  scripts/remote_install.sh --archive
  scripts/remote_install.sh --emit-installer --origin user@host [--default-target EXPR]

Modes:
  --archive           Stream a filtered tar.gz snapshot of this AegisLM repo to stdout
  --emit-installer    Emit a local installer shell script to stdout

Options:
  --origin DEST       SSH destination that the emitted installer should call back
  --default-target EXPR
                      Default local install target expression. Default: ${DEFAULT_TARGET}
  --help              Show this help

Examples:
  ssh user@host '${SELF_PATH} --emit-installer --origin user@host' | sh
  ssh user@host '${SELF_PATH} --archive' | tar -xzf - -C "\$HOME/opt/aegis-lm"
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --archive)
      [ -z "${MODE}" ] || { aegislm_remote_note "Choose only one mode."; exit 1; }
      MODE=archive
      shift
      ;;
    --emit-installer)
      [ -z "${MODE}" ] || { aegislm_remote_note "Choose only one mode."; exit 1; }
      MODE=installer
      shift
      ;;
    --origin)
      [ "$#" -ge 2 ] || { aegislm_remote_note "--origin requires a value"; exit 1; }
      ORIGIN=$2
      shift 2
      ;;
    --default-target)
      [ "$#" -ge 2 ] || { aegislm_remote_note "--default-target requires a value"; exit 1; }
      DEFAULT_TARGET=$2
      shift 2
      ;;
    *)
      aegislm_remote_note "Unknown option: $1"
      exit 1
      ;;
  esac
done

case "${MODE}" in
  archive)
    aegislm_remote_stream_archive
    ;;
  installer)
    if [ -z "${ORIGIN}" ]; then
      aegislm_remote_note "--origin is required with --emit-installer."
      exit 1
    fi
    aegislm_remote_emit_local_installer "${ORIGIN}" "${SELF_PATH}" "${DEFAULT_TARGET}"
    ;;
  *)
    print_help >&2
    exit 1
    ;;
esac
