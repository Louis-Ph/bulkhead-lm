#!/bin/sh

BULKHEAD_LM_PACKAGE_ROOT_DIR=${BULKHEAD_LM_PACKAGE_ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

pkg_note() {
  printf '%s\n' "$*"
}

pkg_err() {
  printf '%s\n' "$*" >&2
}

pkg_fail() {
  pkg_err "$*"
  exit 1
}

pkg_require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    pkg_fail "Missing required command: $1"
  fi
}

pkg_ensure_dir() {
  mkdir -p "$1"
}

pkg_remove_path() {
  if [ -e "$1" ]; then
    rm -rf "$1"
  fi
}

pkg_copy_tree_if_present() {
  src=$1
  dst=$2
  if [ -e "$src" ]; then
    pkg_ensure_dir "$(dirname "$dst")"
    cp -R "$src" "$dst"
  fi
}

pkg_copy_file_if_present() {
  src=$1
  dst=$2
  if [ -f "$src" ]; then
    pkg_ensure_dir "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
}

pkg_make_wrapper() {
  path=$1
  target=$2
  pkg_ensure_dir "$(dirname "$path")"
  cat >"$path" <<EOF
#!/bin/sh
exec "$target" "\$@"
EOF
  chmod 0755 "$path"
}

pkg_detect_ubuntu_arch() {
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --print-architecture
    return
  fi
  case "$(uname -m 2>/dev/null || printf '%s' unknown)" in
    x86_64) printf '%s\n' "amd64" ;;
    aarch64|arm64) printf '%s\n' "arm64" ;;
    *) uname -m 2>/dev/null || printf '%s\n' "unknown" ;;
  esac
}

pkg_detect_freebsd_abi() {
  if command -v pkg >/dev/null 2>&1; then
    pkg config ABI 2>/dev/null || true
  fi
}

pkg_prepare_binaries() {
  root_dir=$1

  if [ -x "$root_dir/bin/bulkhead-lm" ] && [ -x "$root_dir/bin/bulkhead-lm-client" ]; then
    MAIN_BIN="$root_dir/bin/bulkhead-lm"
    CLIENT_BIN="$root_dir/bin/bulkhead-lm-client"
    pkg_note "Using prebuilt binaries from installed tree."
    export MAIN_BIN CLIENT_BIN
    return 0
  fi

  if [ -x "$root_dir/_build/default/bin/main.exe" ] && [ -x "$root_dir/_build/default/bin/client.exe" ]; then
    MAIN_BIN="$root_dir/_build/default/bin/main.exe"
    CLIENT_BIN="$root_dir/_build/default/bin/client.exe"
    pkg_note "Using existing dune build artifacts."
    export MAIN_BIN CLIENT_BIN
    return 0
  fi

  if [ ! -f "$root_dir/dune-project" ]; then
    pkg_fail "No prebuilt binaries were found and this tree is not a buildable source checkout."
  fi

  pkg_require_command dune
  pkg_note "Building BulkheadLM binaries with dune..."
  (
    cd "$root_dir"
    dune build @install bin/main.exe bin/client.exe
  ) || pkg_fail "dune build failed while preparing package binaries."

  MAIN_BIN="$root_dir/_build/default/bin/main.exe"
  CLIENT_BIN="$root_dir/_build/default/bin/client.exe"
  export MAIN_BIN CLIENT_BIN
}

pkg_stage_runtime_tree() {
  root_dir=$1
  payload_root=$2
  install_root=$3
  config_source=$4

  app_root="$payload_root$install_root"
  pkg_ensure_dir "$app_root/bin"
  pkg_ensure_dir "$app_root/var"

  cp "$MAIN_BIN" "$app_root/bin/bulkhead-lm"
  cp "$CLIENT_BIN" "$app_root/bin/bulkhead-lm-client"
  chmod 0755 "$app_root/bin/bulkhead-lm" "$app_root/bin/bulkhead-lm-client"

  pkg_copy_tree_if_present "$root_dir/config" "$app_root/config"
  pkg_copy_tree_if_present "$root_dir/scripts" "$app_root/scripts"
  pkg_copy_tree_if_present "$root_dir/docs" "$app_root/docs"

  pkg_copy_file_if_present "$root_dir/run.sh" "$app_root/run.sh"
  pkg_copy_file_if_present "$root_dir/start-macos-client.command" "$app_root/start-macos-client.command"
  pkg_copy_file_if_present "$root_dir/README.md" "$app_root/README.md"
  pkg_copy_file_if_present "$root_dir/LICENSE" "$app_root/LICENSE"
  pkg_copy_file_if_present "$root_dir/SECURITY.md" "$app_root/SECURITY.md"
  pkg_copy_file_if_present "$root_dir/SUPPORT.md" "$app_root/SUPPORT.md"

  if [ -f "$config_source" ]; then
    pkg_copy_file_if_present "$config_source" "$app_root/config/package.gateway.json"
  else
    pkg_fail "Config file to bundle was not found: $config_source"
  fi
}
