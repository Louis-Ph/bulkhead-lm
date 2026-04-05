#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT_DIR/scripts/toolchain_env.sh"
bulkhead_lm_unset_opam_env

if [ "$#" -eq 0 ]; then
  printf '%s\n' "Usage: ./scripts/with_local_toolchain.sh COMMAND [ARGS...]" >&2
  exit 1
fi

"$ROOT_DIR/scripts/bootstrap_local_toolchain.sh"

exec env \
  -u OPAMSWITCH \
  -u OPAM_SWITCH_PREFIX \
  -u OPAM_LAST_ENV \
  -u CAML_LD_LIBRARY_PATH \
  -u OCAML_TOPLEVEL_PATH \
  -u OCAMLTOP_INCLUDE_PATH \
  PATH="$BULKHEAD_LM_LOCAL_BIN_DIR:$PATH" \
  PKG_CONFIG_PATH="$BULKHEAD_LM_LOCAL_PKGCONFIG_DIR${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
  CPPFLAGS="-I$BULKHEAD_LM_LOCAL_INCLUDE_DIR${CPPFLAGS:+ $CPPFLAGS}" \
  CFLAGS="-I$BULKHEAD_LM_LOCAL_INCLUDE_DIR${CFLAGS:+ $CFLAGS}" \
  LDFLAGS="-L$BULKHEAD_LM_LOCAL_LIB_DIR${LDFLAGS:+ $LDFLAGS}" \
  OPAMROOT="$BULKHEAD_LM_LOCAL_OPAM_ROOT" \
  OPAMSWITCH="$BULKHEAD_LM_LOCAL_SWITCH" \
  "$BULKHEAD_LM_LOCAL_OPAM_BIN" exec -- "$@"
