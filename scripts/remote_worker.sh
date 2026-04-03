#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/remote_common.sh"

CONFIG=${AEGISLM_REMOTE_CONFIG:-${AEGISLM_REMOTE_ROOT_DIR}/config/example.gateway.json}
JOBS=${AEGISLM_REMOTE_JOBS:-4}
AUTHORIZATION=${AEGISLM_REMOTE_AUTHORIZATION:-}
API_KEY=${AEGISLM_REMOTE_API_KEY:-}

print_help() {
  cat <<EOF
Usage: scripts/remote_worker.sh [wrapper options] [-- worker options]

Wrapper options:
  --config FILE         Worker config file. Default: ${CONFIG}
  --jobs N              Max in-flight jobs. Default: ${JOBS}
  --authorization VAL   Client authorization header or token
  --api-key TOKEN       Client API key token
  --switch NAME         opam switch to load before starting
  --help                Show this help

Typical SSH usage:
  ssh -T user@host '/path/to/aegis-lm/scripts/remote_worker.sh --config /etc/aegislm/gateway.json'

Use -T so stdout stays clean for JSONL traffic.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --config)
      [ "$#" -ge 2 ] || { aegislm_remote_note "--config requires a value"; exit 1; }
      CONFIG=$2
      shift 2
      ;;
    --jobs)
      [ "$#" -ge 2 ] || { aegislm_remote_note "--jobs requires a value"; exit 1; }
      JOBS=$2
      shift 2
      ;;
    --authorization)
      [ "$#" -ge 2 ] || { aegislm_remote_note "--authorization requires a value"; exit 1; }
      AUTHORIZATION=$2
      shift 2
      ;;
    --api-key)
      [ "$#" -ge 2 ] || { aegislm_remote_note "--api-key requires a value"; exit 1; }
      API_KEY=$2
      shift 2
      ;;
    --switch)
      [ "$#" -ge 2 ] || { aegislm_remote_note "--switch requires a value"; exit 1; }
      AEGISLM_REMOTE_SWITCH=$2
      export AEGISLM_REMOTE_SWITCH
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

aegislm_remote_load_opam_env

set -- worker --config "${CONFIG}" --jobs "${JOBS}" "$@"
if [ -n "${AUTHORIZATION}" ]; then
  set -- "$@" --authorization "${AUTHORIZATION}"
fi
if [ -n "${API_KEY}" ]; then
  set -- "$@" --api-key "${API_KEY}"
fi

exec aegislm_remote_exec_client "$@"
