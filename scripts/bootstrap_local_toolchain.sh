#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT_DIR/scripts/toolchain_env.sh"
bulkhead_lm_unset_opam_env

OPAM_ONLY=0
ENSURE_DEPS=1

note() {
  printf '%s\n' "$*" >&2
}

fail() {
  note "$*"
  exit 1
}

usage() {
  cat <<EOF
Usage: ./scripts/bootstrap_local_toolchain.sh [options]

Options:
  --opam-only    Only ensure the local opam binary exists.
  --switch-only  Ensure opam, the local opam root, and the project switch, but skip deps.
  --help         Show this help.

Environment overrides:
  BULKHEAD_LM_LOCAL_OPAM_VERSION
  BULKHEAD_LM_LOCAL_PKGCONF_VERSION
  BULKHEAD_LM_LOCAL_GMP_VERSION
  BULKHEAD_LM_LOCAL_OCAML_COMPILER
  BULKHEAD_LM_LOCAL_OPAM_BIN
  BULKHEAD_LM_LOCAL_OPAM_ROOT
  BULKHEAD_LM_LOCAL_SWITCH
EOF
}

release_bootstrap_lock() {
  rm -f "$BULKHEAD_LM_LOCAL_BOOTSTRAP_LOCK_DIR/pid" 2>/dev/null || true
  rmdir "$BULKHEAD_LM_LOCAL_BOOTSTRAP_LOCK_DIR" 2>/dev/null || true
}

bootstrap_lock_is_stale() {
  pid_file=$BULKHEAD_LM_LOCAL_BOOTSTRAP_LOCK_DIR/pid
  [ -d "$BULKHEAD_LM_LOCAL_BOOTSTRAP_LOCK_DIR" ] || return 1
  if [ ! -f "$pid_file" ]; then
    return 0
  fi
  owner_pid=$(cat "$pid_file" 2>/dev/null || true)
  [ -n "$owner_pid" ] || return 0
  kill -0 "$owner_pid" 2>/dev/null && return 1
  return 0
}

acquire_bootstrap_lock() {
  mkdir -p "$BULKHEAD_LM_LOCAL_TOOLCHAIN_DIR"
  while ! mkdir "$BULKHEAD_LM_LOCAL_BOOTSTRAP_LOCK_DIR" 2>/dev/null; do
    if bootstrap_lock_is_stale; then
      note "Removing stale local toolchain bootstrap lock ..."
      release_bootstrap_lock
      continue
    fi
    note "Waiting for local toolchain bootstrap lock ..."
    sleep "$BULKHEAD_LM_LOCAL_BOOTSTRAP_LOCK_WAIT_SECONDS"
  done
  printf '%s\n' "$$" > "$BULKHEAD_LM_LOCAL_BOOTSTRAP_LOCK_DIR/pid"
  trap 'release_bootstrap_lock' EXIT INT TERM HUP
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --opam-only)
      OPAM_ONLY=1
      ENSURE_DEPS=0
      ;;
    --switch-only)
      ENSURE_DEPS=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required command for local toolchain bootstrap: $1"
  fi
}

local_pkg_config_available() {
  [ -x "$BULKHEAD_LM_LOCAL_PKG_CONFIG_BIN" ] || return 1
  PATH="$BULKHEAD_LM_LOCAL_BIN_DIR:$PATH" \
    PKG_CONFIG_PATH="$BULKHEAD_LM_LOCAL_PKGCONFIG_DIR${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    "$BULKHEAD_LM_LOCAL_PKG_CONFIG_BIN" --version >/dev/null 2>&1
}

sqlite3_pc_exists() {
  [ -f "$BULKHEAD_LM_LOCAL_PKGCONFIG_DIR/sqlite3.pc" ]
}

local_gmp_available() {
  [ -f "$BULKHEAD_LM_LOCAL_INCLUDE_DIR/gmp.h" ] || return 1
  [ -f "$BULKHEAD_LM_LOCAL_PKGCONFIG_DIR/gmp.pc" ] || return 1
}

local_opam_has_requested_version() {
  [ -x "$BULKHEAD_LM_LOCAL_OPAM_BIN" ] || return 1
  [ "$("$BULKHEAD_LM_LOCAL_OPAM_BIN" --version 2>/dev/null || true)" = "$BULKHEAD_LM_LOCAL_OPAM_VERSION" ]
}

download_local_opam() {
  require_command curl
  require_command install
  require_command find
  require_command mktemp

  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/bulkhead-lm-opam.XXXXXX")
  cleanup() {
    rm -rf "$tmpdir"
  }
  trap cleanup EXIT INT TERM

  note "Downloading local opam $BULKHEAD_LM_LOCAL_OPAM_VERSION into $BULKHEAD_LM_LOCAL_BIN_DIR ..."
  mkdir -p "$BULKHEAD_LM_LOCAL_BIN_DIR"
  (
    cd "$tmpdir"
    curl -fsSL https://opam.ocaml.org/install.sh \
      | sh -s -- --download-only --version "$BULKHEAD_LM_LOCAL_OPAM_VERSION" >/dev/null
  )

  downloaded_bin=$(find "$tmpdir" -maxdepth 1 -type f -name 'opam-*' | head -n 1)
  [ -n "$downloaded_bin" ] || fail "Could not find the downloaded opam binary."
  install -m 755 "$downloaded_bin" "$BULKHEAD_LM_LOCAL_OPAM_BIN"

  trap - EXIT INT TERM
  cleanup
}

ensure_local_opam() {
  if local_opam_has_requested_version; then
    return 0
  fi
  download_local_opam
}

run_local_opam() {
  env \
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
    "$BULKHEAD_LM_LOCAL_OPAM_BIN" "$@"
}

run_local_switch_opam() {
  env \
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
    "$BULKHEAD_LM_LOCAL_OPAM_BIN" "$@"
}

install_local_pkgconf() {
  require_command curl
  require_command tar
  require_command make
  require_command install
  require_command mktemp
  require_command find

  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/bulkhead-lm-pkgconf.XXXXXX")
  cleanup() {
    rm -rf "$tmpdir"
  }
  trap cleanup EXIT INT TERM

  tarball="$tmpdir/pkgconf.tar.xz"
  note "Building local pkgconf $BULKHEAD_LM_LOCAL_PKGCONF_VERSION ..."
  curl -fsSL \
    "https://distfiles.dereferenced.org/pkgconf/pkgconf-$BULKHEAD_LM_LOCAL_PKGCONF_VERSION.tar.xz" \
    -o "$tarball"
  tar -xf "$tarball" -C "$tmpdir"
  srcdir=$(find "$tmpdir" -maxdepth 1 -type d -name "pkgconf-*" | head -n 1)
  [ -n "$srcdir" ] || fail "Could not unpack pkgconf sources."

  mkdir -p "$BULKHEAD_LM_LOCAL_TOOLCHAIN_DIR"
  (
    cd "$srcdir"
    ./configure --prefix="$BULKHEAD_LM_LOCAL_TOOLCHAIN_DIR" >/dev/null
    make >/dev/null
    make install >/dev/null
  )
  ln -sf pkgconf "$BULKHEAD_LM_LOCAL_PKG_CONFIG_BIN"

  trap - EXIT INT TERM
  cleanup
}

install_local_gmp() {
  require_command curl
  require_command tar
  require_command make
  require_command install
  require_command mktemp
  require_command find

  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/bulkhead-lm-gmp.XXXXXX")
  cleanup() {
    rm -rf "$tmpdir"
  }
  trap cleanup EXIT INT TERM

  tarball="$tmpdir/gmp.tar.xz"
  note "Building local gmp $BULKHEAD_LM_LOCAL_GMP_VERSION ..."
  curl -fsSL \
    "https://ftp.gnu.org/gnu/gmp/gmp-$BULKHEAD_LM_LOCAL_GMP_VERSION.tar.xz" \
    -o "$tarball"
  tar -xf "$tarball" -C "$tmpdir"
  srcdir=$(find "$tmpdir" -maxdepth 1 -type d -name "gmp-*" | head -n 1)
  [ -n "$srcdir" ] || fail "Could not unpack gmp sources."

  mkdir -p "$BULKHEAD_LM_LOCAL_TOOLCHAIN_DIR"
  (
    cd "$srcdir"
    ./configure --prefix="$BULKHEAD_LM_LOCAL_TOOLCHAIN_DIR" --enable-cxx=no >/dev/null
    make >/dev/null
    make install >/dev/null
  )

  trap - EXIT INT TERM
  cleanup
}

write_macos_sqlite3_pc() {
  [ "$(uname -s)" = "Darwin" ] || return 0
  sqlite_header=$(/usr/bin/xcrun --show-sdk-path 2>/dev/null || true)
  [ -n "$sqlite_header" ] || return 0

  mkdir -p "$BULKHEAD_LM_LOCAL_PKGCONFIG_DIR"
  set +e
  sqlite_version=$(
    grep '^#define SQLITE_VERSION ' "$sqlite_header/usr/include/sqlite3.h" 2>/dev/null \
      | sed 's/^#define SQLITE_VERSION "\(.*\)"$/\1/' \
      | head -n 1
  )
  set -e
  if [ -z "$sqlite_version" ]; then
    sqlite_version="3"
  fi

  cat >"$BULKHEAD_LM_LOCAL_PKGCONFIG_DIR/sqlite3.pc" <<EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=$sqlite_header/usr/include

Name: sqlite3
Description: SQLite 3 dynamic library (SDK shim)
Version: $sqlite_version
Libs: -L\${libdir} -lsqlite3
Cflags: -I\${includedir}
EOF
}

ensure_local_pkg_config() {
  if ! local_pkg_config_available; then
    install_local_pkgconf
  fi
  if [ ! -e "$BULKHEAD_LM_LOCAL_PKG_CONFIG_BIN" ] && [ -x "$BULKHEAD_LM_LOCAL_BIN_DIR/pkgconf" ]; then
    ln -sf pkgconf "$BULKHEAD_LM_LOCAL_PKG_CONFIG_BIN"
  fi
  if [ "$(uname -s)" = "Darwin" ] && ! sqlite3_pc_exists; then
    write_macos_sqlite3_pc
  fi
}

ensure_local_gmp() {
  if local_gmp_available; then
    return 0
  fi
  install_local_gmp
}

ensure_local_root() {
  if [ -f "$BULKHEAD_LM_LOCAL_OPAM_ROOT/config" ]; then
    return 0
  fi

  note "Initializing project-local opam root in $BULKHEAD_LM_LOCAL_OPAM_ROOT ..."
  mkdir -p "$BULKHEAD_LM_LOCAL_OPAM_ROOT"
  run_local_opam init \
    --yes \
    --bare \
    --no-setup \
    --disable-sandboxing \
    default https://opam.ocaml.org
}

configure_local_root() {
  if [ "$(uname -s)" = "Darwin" ]; then
    run_local_opam option --global depext=false >/dev/null 2>&1 || true
  fi
}

local_switch_ready() {
  [ -f "$BULKHEAD_LM_LOCAL_SWITCH_DIR/.opam-switch/switch-config" ] || return 1
  [ -f "$BULKHEAD_LM_LOCAL_SWITCH_DIR/.opam-switch/switch-state" ] || return 1
  prefix=$(run_local_switch_opam var prefix 2>/dev/null || true)
  [ "$prefix" = "$BULKHEAD_LM_LOCAL_SWITCH_DIR" ] || return 1
  run_local_switch_opam exec -- ocamlc -version >/dev/null 2>&1
}

repair_local_switch() {
  if [ ! -d "$BULKHEAD_LM_LOCAL_SWITCH_DIR" ]; then
    return 0
  fi

  note "Repairing broken project-local switch in $BULKHEAD_LM_LOCAL_SWITCH_DIR ..."
  run_local_opam switch remove "$BULKHEAD_LM_LOCAL_SWITCH" --yes >/dev/null 2>&1 || true
  rm -rf "$BULKHEAD_LM_LOCAL_SWITCH_DIR"
}

ensure_local_switch() {
  if local_switch_ready; then
    return 0
  fi

  repair_local_switch

  note "Creating project-local switch in $BULKHEAD_LM_LOCAL_SWITCH_DIR with $BULKHEAD_LM_LOCAL_OCAML_COMPILER ..."
  run_local_opam switch create \
    "$BULKHEAD_LM_LOCAL_SWITCH" \
    "$BULKHEAD_LM_LOCAL_OCAML_COMPILER" \
    --no-install \
    --yes
}

ensure_local_path_pin() {
  note "Pinning $BULKHEAD_LM_PACKAGE_NAME to the current working tree ..."
  run_local_switch_opam pin add "$BULKHEAD_LM_PACKAGE_NAME" "$ROOT_DIR" --kind=path --no-action --yes
}

ensure_project_deps() {
  note "Installing project dependencies into the local switch ..."
  (
    cd "$ROOT_DIR"
    run_local_switch_opam install \
      "$BULKHEAD_LM_PACKAGE_NAME" \
      --deps-only \
      --with-test \
      --working-dir \
      --no-depexts \
      --yes
  )
}

acquire_bootstrap_lock
ensure_local_opam

if [ "$OPAM_ONLY" -eq 1 ]; then
  note "Local opam ready at $BULKHEAD_LM_LOCAL_OPAM_BIN"
  exit 0
fi

ensure_local_pkg_config
ensure_local_gmp
ensure_local_root
configure_local_root
ensure_local_switch
ensure_local_path_pin

if [ "$ENSURE_DEPS" -eq 1 ]; then
  ensure_project_deps
fi

note "Project-local toolchain ready."
