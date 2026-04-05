#!/bin/sh

. "$ROOT_DIR/scripts/toolchain_env.sh"
bulkhead_lm_unset_opam_env

DEFAULT_CONFIG=${BULKHEAD_LM_BASE_CONFIG:-$ROOT_DIR/config/example.gateway.json}
STARTER_OUTPUT=${BULKHEAD_LM_STARTER_OUTPUT:-$ROOT_DIR/config/starter.gateway.json}
DEFAULT_OCAML_COMPILER=${BULKHEAD_LM_OCAML_COMPILER:-$BULKHEAD_LM_LOCAL_OCAML_COMPILER}
USE_GLOBAL_SWITCH=${BULKHEAD_LM_USE_GLOBAL_SWITCH:-0}
FORCE_LOCAL_SWITCH=${BULKHEAD_LM_FORCE_LOCAL_SWITCH:-0}
DEFAULT_ENV_FILES="$HOME/.zshrc.secret:$HOME/.zshrc.secrets:$HOME/.bashrc.secret:$HOME/.bashrc.secrets:$HOME/.profile.secret:$HOME/.profile.secrets:$HOME/.config/bulkhead-lm/env"
STARTER_ENV_FILES=${BULKHEAD_LM_STARTER_ENV_FILES:-$DEFAULT_ENV_FILES}
BUILD_LOG=""
OPAM_BIN=""

say() {
  printf '%s\n' "$1"
}

say_err() {
  printf '%s\n' "$1" >&2
}

has_hook() {
  command -v "$1" >/dev/null 2>&1
}

prompt_yes_no() {
  label=$1
  default_answer=${2:-Y}
  prompt_suffix="y/N"
  if [ "$default_answer" = "Y" ]; then
    prompt_suffix="Y/n"
  fi

  printf "%s [%s]: " "$label" "$prompt_suffix"
  answer=""
  if ! read -r answer; then
    answer=""
  fi
  answer=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')
  if [ -z "$answer" ]; then
    [ "$default_answer" = "Y" ]
    return
  fi
  [ "$answer" = "y" ] || [ "$answer" = "yes" ]
}

ensure_build_log() {
  if [ -z "$BUILD_LOG" ]; then
    BUILD_LOG=$(mktemp "${TMPDIR:-/tmp}/bulkhead-lm-starter.XXXXXX")
  fi
}

cleanup_temp_files() {
  if [ -n "$BUILD_LOG" ] && [ -e "$BUILD_LOG" ]; then
    rm -f "$BUILD_LOG"
  fi
}

manual_setup_commands() {
  if has_hook platform_manual_setup_commands; then
    platform_manual_setup_commands
    return
  fi

  cat <<EOF
Manual setup options:
  Bootstrap a project-local toolchain:
    cd "$ROOT_DIR"
    ./scripts/bootstrap_local_toolchain.sh
    ./run.sh

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
  chmod +x "$ROOT_DIR/run.sh" "$STARTER_SCRIPT_PATH" 2>/dev/null || true
  if [ -n "${STARTER_EXTRA_EXECUTABLE:-}" ]; then
    chmod +x "$STARTER_EXTRA_EXECUTABLE" 2>/dev/null || true
  fi
}

load_secret_file() {
  secret_file=$1
  [ -r "$secret_file" ] || return 0

  set +e
  set +u
  set -a
  . "$secret_file" >/dev/null 2>&1
  status=$?
  set +a
  set -eu

  if [ "$status" -ne 0 ]; then
    say_err "Warning: could not load $secret_file under /bin/sh; continuing."
  fi
}

load_secret_files() {
  old_ifs=$IFS
  IFS=:
  for secret_file in $STARTER_ENV_FILES; do
    load_secret_file "$secret_file"
  done
  IFS=$old_ifs
}

find_opam() {
  if [ -x "$BULKHEAD_LM_LOCAL_OPAM_BIN" ]; then
    OPAM_BIN=$BULKHEAD_LM_LOCAL_OPAM_BIN
    OPAMROOT=${OPAMROOT:-$BULKHEAD_LM_LOCAL_OPAM_ROOT}
    export OPAMROOT
    return
  fi

  if [ -n "${BULKHEAD_LM_OPAM_BIN:-}" ] && [ -x "${BULKHEAD_LM_OPAM_BIN}" ]; then
    OPAM_BIN=${BULKHEAD_LM_OPAM_BIN}
    return
  fi

  if command -v opam >/dev/null 2>&1; then
    OPAM_BIN=$(command -v opam)
    return
  fi

  if has_hook platform_find_opam; then
    candidate=$(platform_find_opam || true)
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      OPAM_BIN=$candidate
      return
    fi
  fi
}

run_privileged() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi
  if command -v doas >/dev/null 2>&1; then
    doas "$@"
    return
  fi
  say_err "Neither sudo nor doas was found."
  return 1
}

ensure_opam() {
  find_opam
  if [ -n "$OPAM_BIN" ]; then
    return
  fi

  if [ -x "$ROOT_DIR/scripts/bootstrap_local_toolchain.sh" ]; then
    say "Bootstrapping a repo-local opam binary ..."
    if "$ROOT_DIR/scripts/bootstrap_local_toolchain.sh" --opam-only >/dev/null 2>&1; then
      find_opam
      if [ -n "$OPAM_BIN" ]; then
        return
      fi
    fi
  fi

  say_err "opam was not found."
  if ! has_hook platform_install_opam; then
    manual_setup_commands >&2
    exit 1
  fi

  if ! platform_install_opam; then
    manual_setup_commands >&2
    exit 1
  fi

  find_opam
  if [ -z "$OPAM_BIN" ]; then
    say_err "opam is still not available after the install step."
    manual_setup_commands >&2
    exit 1
  fi
}

ensure_opam_initialized() {
  active_opam_root=${OPAMROOT:-$HOME/.opam}
  if [ -f "$active_opam_root/config" ]; then
    return
  fi

  say "Initializing opam root in $active_opam_root ..."
  ensure_build_log
  if [ "$active_opam_root" = "$BULKHEAD_LM_LOCAL_OPAM_ROOT" ]; then
    if ! "$OPAM_BIN" init \
         --yes \
         --bare \
         --no-setup \
         --disable-sandboxing \
         default https://opam.ocaml.org >"$BUILD_LOG" 2>&1; then
      say_err "opam init failed."
      say_err "See $BUILD_LOG for details."
      manual_setup_commands >&2
      exit 1
    fi
    return
  fi
  if ! "$OPAM_BIN" init --yes >"$BUILD_LOG" 2>&1; then
    say_err "opam init failed."
    say_err "See $BUILD_LOG for details."
    manual_setup_commands >&2
    exit 1
  fi
}

current_switch_name() {
  if [ -d "$BULKHEAD_LM_LOCAL_SWITCH_DIR" ]; then
    printf '%s\n' "$ROOT_DIR"
  elif [ -n "${OPAMSWITCH:-}" ]; then
    printf '%s\n' "$OPAMSWITCH"
  else
    "$OPAM_BIN" switch show 2>/dev/null || true
  fi
}

apply_current_switch_environment() {
  if [ -d "$BULKHEAD_LM_LOCAL_SWITCH_DIR" ]; then
    eval "$(OPAMROOT="$BULKHEAD_LM_LOCAL_OPAM_ROOT" "$OPAM_BIN" env --switch="$ROOT_DIR" --set-switch)"
  elif [ -n "${OPAMSWITCH:-}" ]; then
    eval "$("$OPAM_BIN" env --switch="$OPAMSWITCH" --set-switch)"
  else
    eval "$("$OPAM_BIN" env --set-switch)"
  fi
}

apply_local_switch_environment() {
  eval "$(OPAMROOT="$BULKHEAD_LM_LOCAL_OPAM_ROOT" "$OPAM_BIN" env --switch="$ROOT_DIR" --set-switch)"
}

describe_active_toolchain() {
  switch_name=$(current_switch_name)
  prefix=$("$OPAM_BIN" var prefix 2>/dev/null || true)
  say "Checking OCaml toolchain in switch: ${switch_name:-unknown}"
  if [ -n "$prefix" ]; then
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

reset_build_log() {
  rm -f "$BUILD_LOG"
  BUILD_LOG=""
}

find_packaged_client_runner() {
  if [ -x "$ROOT_DIR/bin/bulkhead-lm-client" ]; then
    printf '%s\n' "$ROOT_DIR/bin/bulkhead-lm-client"
    return 0
  fi
  return 1
}

find_built_client_runner() {
  if [ -x "$ROOT_DIR/_build/default/bin/client.exe" ]; then
    printf '%s\n' "$ROOT_DIR/_build/default/bin/client.exe"
    return 0
  fi
  return 1
}

find_local_client_runner() {
  find_built_client_runner || find_packaged_client_runner
}

ensure_project_buildable() {
  install_prompt=$1
  if build_client; then
    reset_build_log
    return 0
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

  reset_build_log
  return 0
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
  if [ -d "$ROOT_DIR/_opam" ]; then
    say "Reusing existing project-local switch in $ROOT_DIR/_opam."
    return 0
  fi

  if [ "$FORCE_LOCAL_SWITCH" = "1" ]; then
    create_local_switch || return 1
    return 0
  fi

  if ! prompt_yes_no "Create a project-local fallback switch in $ROOT_DIR/_opam?" "N"; then
    return 1
  fi

  create_local_switch || return 1
  return 0
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

starter_exec_client() {
  cd "$ROOT_DIR"
  client_runner=$(find_built_client_runner || true)
  if [ -n "$client_runner" ]; then
    exec "$client_runner" starter \
      --config "$DEFAULT_CONFIG" \
      --starter-output "$STARTER_OUTPUT" \
      "$@"
  fi
  client_runner=$(find_packaged_client_runner || true)
  if [ -n "$client_runner" ]; then
    exec "$client_runner" starter \
      --config "$DEFAULT_CONFIG" \
      --starter-output "$STARTER_OUTPUT" \
      "$@"
  fi
  exec dune exec bulkhead-lm-client -- starter \
    --config "$DEFAULT_CONFIG" \
    --starter-output "$STARTER_OUTPUT" \
    "$@"
}

starter_main() {
  ensure_exec_bits
  load_secret_files
  trap cleanup_temp_files EXIT INT TERM

  if has_hook platform_validate_host; then
    platform_validate_host || exit 1
  fi

  if find_packaged_client_runner >/dev/null 2>&1; then
    starter_exec_client "$@"
  fi

  ensure_opam
  ensure_opam_initialized

  if [ "$FORCE_LOCAL_SWITCH" = "1" ]; then
    if ! run_with_local_switch; then
      manual_setup_commands >&2
      exit 1
    fi
  elif run_with_current_switch; then
    :
  elif [ "$USE_GLOBAL_SWITCH" = "1" ]; then
    say_err "The current switch could not build this repository."
    if [ -n "$BUILD_LOG" ]; then
      say_err "See $BUILD_LOG for details."
    fi
    manual_setup_commands >&2
    exit 1
  elif ! run_with_local_switch; then
    say_err "No working OCaml environment was prepared for this repository."
    if [ -n "$BUILD_LOG" ]; then
      say_err "See $BUILD_LOG for details."
    fi
    manual_setup_commands >&2
    exit 1
  fi

  starter_exec_client "$@"
}
