#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/remote_common.sh"

CONFIG=${BULKHEAD_LM_REMOTE_CONFIG:-${BULKHEAD_LM_REMOTE_ROOT_DIR}/config/example.gateway.json}
STARTER_OUTPUT=${BULKHEAD_LM_REMOTE_STARTER_OUTPUT:-${BULKHEAD_LM_REMOTE_ROOT_DIR}/config/starter.gateway.json}

print_help() {
  cat <<EOF
Usage: scripts/remote_starter.sh [wrapper options] [-- starter options]

Wrapper options:
  --config FILE          Starter config file. Default: ${CONFIG}
  --starter-output FILE  Starter output config file. Default: ${STARTER_OUTPUT}
  --switch NAME          opam switch to load before starting
  --help                 Show this help

Typical SSH usage:
  ssh -t user@host '/path/to/bulkhead-lm/scripts/remote_starter.sh'

Use -t so the remote starter receives a pseudo-terminal.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --config)
      [ "$#" -ge 2 ] || { bulkhead_lm_remote_note "--config requires a value"; exit 1; }
      CONFIG=$2
      shift 2
      ;;
    --starter-output)
      [ "$#" -ge 2 ] || { bulkhead_lm_remote_note "--starter-output requires a value"; exit 1; }
      STARTER_OUTPUT=$2
      shift 2
      ;;
    --switch)
      [ "$#" -ge 2 ] || { bulkhead_lm_remote_note "--switch requires a value"; exit 1; }
      BULKHEAD_LM_REMOTE_SWITCH=$2
      export BULKHEAD_LM_REMOTE_SWITCH
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if [ ! -t 0 ] || [ ! -t 1 ]; then
  bulkhead_lm_remote_note "remote_starter requires an interactive TTY."
  bulkhead_lm_remote_note "Use ssh -t user@host '/path/to/bulkhead-lm/scripts/remote_starter.sh'"
  exit 1
fi

bulkhead_lm_remote_load_opam_env
exec bulkhead_lm_remote_exec_client starter --config "${CONFIG}" --starter-output "${STARTER_OUTPUT}" "$@"
