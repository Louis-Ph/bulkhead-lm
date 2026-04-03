AEGISLM_REMOTE_ROOT_DIR=${AEGISLM_REMOTE_ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

aegislm_remote_note() {
  printf '%s\n' "$*" >&2
}

aegislm_remote_find_opam() {
  if [ -n "${AEGISLM_OPAM_BIN:-}" ] && [ -x "${AEGISLM_OPAM_BIN}" ]; then
    printf '%s\n' "${AEGISLM_OPAM_BIN}"
    return 0
  fi
  if command -v opam >/dev/null 2>&1; then
    command -v opam
    return 0
  fi
  if [ -x "/usr/local/bin/opam" ]; then
    printf '%s\n' "/usr/local/bin/opam"
    return 0
  fi
  if [ -x "/opt/homebrew/bin/opam" ]; then
    printf '%s\n' "/opt/homebrew/bin/opam"
    return 0
  fi
  return 1
}

aegislm_remote_resolve_switch() {
  if [ -n "${AEGISLM_REMOTE_SWITCH:-}" ]; then
    printf '%s\n' "${AEGISLM_REMOTE_SWITCH}"
  elif [ -n "${OPAMSWITCH:-}" ]; then
    printf '%s\n' "${OPAMSWITCH}"
  elif [ -d "${AEGISLM_REMOTE_ROOT_DIR}/_opam" ]; then
    printf '%s\n' "${AEGISLM_REMOTE_ROOT_DIR}"
  else
    printf '%s\n' ""
  fi
}

aegislm_remote_load_opam_env() {
  opam_bin=$(aegislm_remote_find_opam || true)
  if [ -z "${opam_bin}" ]; then
    return 0
  fi
  switch_name=$(aegislm_remote_resolve_switch)
  if [ -n "${switch_name}" ]; then
    eval "$("${opam_bin}" env --switch="${switch_name}" --set-switch)"
  else
    eval "$("${opam_bin}" env --set-switch)"
  fi
}

aegislm_remote_find_client_runner() {
  if [ -n "${AEGISLM_REMOTE_CLIENT_BIN:-}" ] && [ -x "${AEGISLM_REMOTE_CLIENT_BIN}" ]; then
    printf 'bin:%s\n' "${AEGISLM_REMOTE_CLIENT_BIN}"
    return 0
  fi
  if [ -x "${AEGISLM_REMOTE_ROOT_DIR}/_build/default/bin/client.exe" ]; then
    printf 'bin:%s\n' "${AEGISLM_REMOTE_ROOT_DIR}/_build/default/bin/client.exe"
    return 0
  fi
  if command -v aegislm-client >/dev/null 2>&1; then
    printf 'bin:%s\n' "$(command -v aegislm-client)"
    return 0
  fi
  if command -v dune >/dev/null 2>&1; then
    printf '%s\n' "dune"
    return 0
  fi
  return 1
}

aegislm_remote_exec_client() {
  runner=$(aegislm_remote_find_client_runner || true)
  if [ -z "${runner}" ]; then
    aegislm_remote_note "No AegisLM client runner was found."
    aegislm_remote_note "Expected one of:"
    aegislm_remote_note "  - ${AEGISLM_REMOTE_ROOT_DIR}/_build/default/bin/client.exe"
    aegislm_remote_note "  - aegislm-client in PATH"
    aegislm_remote_note "  - dune in PATH"
    return 1
  fi

  cd "${AEGISLM_REMOTE_ROOT_DIR}"
  case "${runner}" in
    bin:*)
      exec "${runner#bin:}" "$@"
      ;;
    dune)
      exec dune exec aegislm-client -- "$@"
      ;;
    *)
      aegislm_remote_note "Unsupported client runner descriptor: ${runner}"
      return 1
      ;;
  esac
}
