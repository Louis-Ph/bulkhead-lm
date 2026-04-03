#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
DEFAULT_CONFIG="${AEGISLM_BASE_CONFIG:-$ROOT_DIR/config/example.gateway.json}"
STARTER_OUTPUT="${AEGISLM_STARTER_OUTPUT:-$ROOT_DIR/config/starter.gateway.json}"
DEFAULT_OCAML_COMPILER="${AEGISLM_OCAML_COMPILER:-ocaml-base-compiler.5.2.1}"
USE_GLOBAL_SWITCH="${AEGISLM_USE_GLOBAL_SWITCH:-0}"
FORCE_LOCAL_SWITCH="${AEGISLM_FORCE_LOCAL_SWITCH:-0}"
BUILD_LOG=""
OPAM_BIN=""

say() {
  print -- "$1"
}

say_err() {
  print -u2 -- "$1"
}

prompt_yes_no() {
  local label="$1"
  local default_answer="${2:-Y}"
  local prompt_suffix="y/N"
  if [[ "$default_answer" == "Y" ]]; then
    prompt_suffix="Y/n"
  fi
  printf "%s [%s]: " "$label" "$prompt_suffix"
  local answer=""
  if ! read -r answer; then
    answer=""
  fi
  answer="${answer:l}"
  if [[ -z "$answer" ]]; then
    [[ "$default_answer" == "Y" ]]
    return
  fi
  [[ "$answer" == "y" || "$answer" == "yes" ]]
}

ensure_build_log() {
  if [[ -z "$BUILD_LOG" ]]; then
    BUILD_LOG="$(mktemp -t aegislm-macos-starter)"
  fi
}

cleanup_temp_files() {
  if [[ -n "$BUILD_LOG" && -e "$BUILD_LOG" ]]; then
    rm -f "$BUILD_LOG"
  fi
}

manual_setup_commands() {
  cat <<EOF
Manual setup options:
  Reuse the current switch:
    eval "\$(opam env --set-switch)"
    opam install . --deps-only --yes
    dune build bin/client.exe
    ./run.sh

  Or create a project-local fallback:
    cd "$ROOT_DIR"
    opam switch create . "$DEFAULT_OCAML_COMPILER" --yes
    eval "\$(opam env --switch . --set-switch)"
    opam install . --deps-only --yes
    ./run.sh
EOF
}

ensure_exec_bits() {
  chmod +x "$ROOT_DIR/run.sh" "$0" "$ROOT_DIR/start-macos-client.command" 2>/dev/null || true
}

load_secret_files() {
  local secret_file
  for secret_file in "$HOME/.zshrc.secret" "$HOME/.zshrc.secrets"; do
    if [[ -r "$secret_file" ]]; then
      source "$secret_file"
    fi
  done
}

find_opam() {
  if [[ -x "/opt/homebrew/bin/opam" ]]; then
    OPAM_BIN="/opt/homebrew/bin/opam"
  elif command -v opam >/dev/null 2>&1; then
    OPAM_BIN="$(command -v opam)"
  fi
}

ensure_opam() {
  find_opam
  if [[ -n "$OPAM_BIN" ]]; then
    return
  fi

  say_err "opam was not found."
  if command -v brew >/dev/null 2>&1; then
    if prompt_yes_no "Install opam with Homebrew now?" "Y"; then
      if ! brew install opam; then
        say_err "Automatic Homebrew installation failed."
        manual_setup_commands >&2
        exit 1
      fi
      find_opam
    else
      manual_setup_commands >&2
      exit 1
    fi
  else
    say_err "Homebrew was not found."
    manual_setup_commands >&2
    exit 1
  fi
}

ensure_opam_initialized() {
  if [[ -f "$HOME/.opam/config" ]]; then
    return
  fi

  say "Initializing opam for first use..."
  ensure_build_log
  if ! "$OPAM_BIN" init --yes >"$BUILD_LOG" 2>&1; then
    say_err "opam init failed."
    say_err "See $BUILD_LOG for details."
    manual_setup_commands >&2
    exit 1
  fi
}

current_switch_name() {
  if [[ -n "${OPAMSWITCH:-}" ]]; then
    print -- "$OPAMSWITCH"
  else
    "$OPAM_BIN" switch show 2>/dev/null || true
  fi
}

apply_current_switch_environment() {
  if [[ -n "${OPAMSWITCH:-}" ]]; then
    eval "$("$OPAM_BIN" env --switch="$OPAMSWITCH" --set-switch)"
  else
    eval "$("$OPAM_BIN" env --set-switch)"
  fi
}

apply_local_switch_environment() {
  eval "$("$OPAM_BIN" env --switch="$ROOT_DIR" --set-switch)"
}

describe_active_toolchain() {
  local switch_name
  switch_name="$(current_switch_name)"
  local prefix
  prefix="$("$OPAM_BIN" var prefix 2>/dev/null || true)"
  say "Checking OCaml toolchain in switch: ${switch_name:-unknown}"
  if [[ -n "$prefix" ]]; then
    say "Active prefix: $prefix"
  fi
}

build_client() {
  ensure_build_log
  (cd "$ROOT_DIR" && dune build bin/client.exe >"$BUILD_LOG" 2>&1)
}

install_project_deps() {
  ensure_build_log
  (cd "$ROOT_DIR" && "$OPAM_BIN" install . --deps-only --yes >"$BUILD_LOG" 2>&1)
}

ensure_project_buildable() {
  local install_prompt="$1"
  if build_client; then
    rm -f "$BUILD_LOG"
    BUILD_LOG=""
    return
  fi

  if ! command -v ocamlc >/dev/null 2>&1; then
    say_err "ocamlc is not available in the active switch."
  fi
  if ! command -v dune >/dev/null 2>&1; then
    say_err "dune is not available in the active switch."
  fi

  say "The active switch is not coherent for this repository yet."
  if ! prompt_yes_no "$install_prompt" "Y"; then
    return 1
  fi

  if ! install_project_deps; then
    say_err "Automatic dependency installation failed."
    say_err "See $BUILD_LOG for details."
    return 1
  fi

  if ! build_client; then
    say_err "The repository still does not build in the active switch."
    say_err "See $BUILD_LOG for details."
    return 1
  fi

  rm -f "$BUILD_LOG"
  BUILD_LOG=""
}

create_local_switch() {
  say "Creating a project-local opam switch in $ROOT_DIR/_opam ..."
  ensure_build_log
  if ! "$OPAM_BIN" switch create "$ROOT_DIR" "$DEFAULT_OCAML_COMPILER" --yes >"$BUILD_LOG" 2>&1; then
    say_err "Local switch creation failed."
    say_err "See $BUILD_LOG for details."
    return 1
  fi
}

ensure_local_switch_requested() {
  if [[ -d "$ROOT_DIR/_opam" ]]; then
    say "Reusing existing project-local switch in $ROOT_DIR/_opam."
    return
  fi

  if [[ "$FORCE_LOCAL_SWITCH" == "1" ]]; then
    create_local_switch || return 1
    return
  fi

  if ! prompt_yes_no "Create a project-local fallback switch in $ROOT_DIR/_opam?" "N"; then
    return 1
  fi

  create_local_switch || return 1
}

run_with_current_switch() {
  apply_current_switch_environment
  describe_active_toolchain
  ensure_project_buildable "Install missing project dependencies in the current switch now?"
}

run_with_local_switch() {
  ensure_local_switch_requested || return 1
  apply_local_switch_environment
  describe_active_toolchain
  ensure_project_buildable "Install missing project dependencies in the project-local fallback switch now?"
}

ensure_exec_bits
load_secret_files
trap cleanup_temp_files EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  say_err "This starter is currently tailored for macOS. Use aegislm-client starter directly on other systems."
fi

ensure_opam
ensure_opam_initialized

if [[ "$FORCE_LOCAL_SWITCH" == "1" ]]; then
  if ! run_with_local_switch; then
    manual_setup_commands >&2
    exit 1
  fi
elif run_with_current_switch; then
  :
elif [[ "$USE_GLOBAL_SWITCH" == "1" ]]; then
  say_err "The current switch could not build this repository."
  if [[ -n "$BUILD_LOG" ]]; then
    say_err "See $BUILD_LOG for details."
  fi
  manual_setup_commands >&2
  exit 1
elif ! run_with_local_switch; then
  say_err "No working OCaml environment was prepared for this repository."
  if [[ -n "$BUILD_LOG" ]]; then
    say_err "See $BUILD_LOG for details."
  fi
  manual_setup_commands >&2
  exit 1
fi

exec dune exec aegislm-client -- starter \
  --config "$DEFAULT_CONFIG" \
  --starter-output "$STARTER_OUTPUT" \
  "$@"
