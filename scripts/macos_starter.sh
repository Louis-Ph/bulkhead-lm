#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
DEFAULT_CONFIG="${AEGISLM_BASE_CONFIG:-$ROOT_DIR/config/example.gateway.json}"
STARTER_OUTPUT="${AEGISLM_STARTER_OUTPUT:-$ROOT_DIR/config/starter.gateway.json}"
DEFAULT_OCAML_COMPILER="${AEGISLM_OCAML_COMPILER:-ocaml-base-compiler.5.2.1}"
USE_GLOBAL_SWITCH="${AEGISLM_USE_GLOBAL_SWITCH:-0}"
BUILD_LOG="$ROOT_DIR/var/macos_starter.build.log"
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

manual_setup_commands() {
  cat <<EOF
Manual setup commands:
  brew install opam
  opam init --yes
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
  if ! "$OPAM_BIN" init --yes >"$BUILD_LOG" 2>&1; then
    say_err "opam init failed."
    say_err "See $BUILD_LOG for details."
    manual_setup_commands >&2
    exit 1
  fi
}

ensure_switch_environment() {
  if [[ "$USE_GLOBAL_SWITCH" == "1" ]]; then
    if [[ -n "${OPAMSWITCH:-}" ]]; then
      eval "$("$OPAM_BIN" env --switch="$OPAMSWITCH" --set-switch)"
    else
      eval "$("$OPAM_BIN" env --set-switch)"
    fi
    return
  fi

  if [[ ! -d "$ROOT_DIR/_opam" ]]; then
    say "Creating a project-local opam switch in $ROOT_DIR/_opam ..."
    if ! "$OPAM_BIN" switch create "$ROOT_DIR" "$DEFAULT_OCAML_COMPILER" --yes >"$BUILD_LOG" 2>&1; then
      say_err "Local switch creation failed."
      say_err "See $BUILD_LOG for details."
      manual_setup_commands >&2
      exit 1
    fi
  fi

  eval "$("$OPAM_BIN" env --switch="$ROOT_DIR" --set-switch)"
}

ensure_project_buildable() {
  mkdir -p "$ROOT_DIR/var"
  if (cd "$ROOT_DIR" && dune build bin/client.exe >"$BUILD_LOG" 2>&1); then
    rm -f "$BUILD_LOG"
    return
  fi

  say "The local OCaml environment is not ready yet."
  if ! prompt_yes_no "Install project dependencies in the active switch now?" "Y"; then
    manual_setup_commands >&2
    exit 1
  fi

  if ! (cd "$ROOT_DIR" && "$OPAM_BIN" install . --deps-only --yes >"$BUILD_LOG" 2>&1); then
    say_err "Automatic dependency installation failed."
    say_err "See $BUILD_LOG for details."
    manual_setup_commands >&2
    exit 1
  fi

  if ! (cd "$ROOT_DIR" && dune build bin/client.exe >"$BUILD_LOG" 2>&1); then
    say_err "The client still does not build after installing dependencies."
    say_err "See $BUILD_LOG for details."
    exit 1
  fi

  rm -f "$BUILD_LOG"
}

ensure_exec_bits
load_secret_files

if [[ "$(uname -s)" != "Darwin" ]]; then
  say_err "This starter is currently tailored for macOS. Use aegislm-client starter directly on other systems."
fi

ensure_opam
ensure_opam_initialized
ensure_switch_environment
ensure_project_buildable

exec dune exec aegislm-client -- starter \
  --config "$DEFAULT_CONFIG" \
  --starter-output "$STARTER_OUTPUT" \
  "$@"
