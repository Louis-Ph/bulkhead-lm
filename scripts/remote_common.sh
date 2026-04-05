BULKHEAD_LM_REMOTE_ROOT_DIR=${BULKHEAD_LM_REMOTE_ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
BULKHEAD_LM_REMOTE_INSTALL_DEFAULT_TARGET=${BULKHEAD_LM_REMOTE_INSTALL_DEFAULT_TARGET:-'${HOME}/opt/bulkhead-lm'}

. "${BULKHEAD_LM_REMOTE_ROOT_DIR}/scripts/toolchain_env.sh"

bulkhead_lm_remote_note() {
  printf '%s\n' "$*" >&2
}

bulkhead_lm_remote_find_tar() {
  if command -v tar >/dev/null 2>&1; then
    command -v tar
    return 0
  fi
  if [ -x "/usr/bin/tar" ]; then
    printf '%s\n' "/usr/bin/tar"
    return 0
  fi
  if [ -x "/bin/tar" ]; then
    printf '%s\n' "/bin/tar"
    return 0
  fi
  return 1
}

bulkhead_lm_remote_find_opam() {
  if [ -x "${BULKHEAD_LM_REMOTE_ROOT_DIR}/.bulkhead-tools/bin/opam" ]; then
    printf '%s\n' "${BULKHEAD_LM_REMOTE_ROOT_DIR}/.bulkhead-tools/bin/opam"
    return 0
  fi
  if [ -n "${BULKHEAD_LM_OPAM_BIN:-}" ] && [ -x "${BULKHEAD_LM_OPAM_BIN}" ]; then
    printf '%s\n' "${BULKHEAD_LM_OPAM_BIN}"
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

bulkhead_lm_remote_resolve_switch() {
  if [ -n "${BULKHEAD_LM_REMOTE_SWITCH:-}" ]; then
    printf '%s\n' "${BULKHEAD_LM_REMOTE_SWITCH}"
  elif [ -d "${BULKHEAD_LM_REMOTE_ROOT_DIR}/_opam" ]; then
    printf '%s\n' "${BULKHEAD_LM_REMOTE_ROOT_DIR}"
  elif [ -n "${OPAMSWITCH:-}" ]; then
    printf '%s\n' "${OPAMSWITCH}"
  else
    printf '%s\n' ""
  fi
}

bulkhead_lm_remote_load_opam_env() {
  bulkhead_lm_unset_opam_env
  opam_bin=$(bulkhead_lm_remote_find_opam || true)
  if [ -z "${opam_bin}" ]; then
    return 0
  fi
  if [ -z "${OPAMROOT:-}" ] && [ -f "${BULKHEAD_LM_REMOTE_ROOT_DIR}/.opam-root/config" ]; then
    OPAMROOT="${BULKHEAD_LM_REMOTE_ROOT_DIR}/.opam-root"
    export OPAMROOT
  fi
  switch_name=$(bulkhead_lm_remote_resolve_switch)
  if [ -n "${switch_name}" ]; then
    eval "$("${opam_bin}" env --switch="${switch_name}" --set-switch)"
  else
    eval "$("${opam_bin}" env --set-switch)"
  fi
}

bulkhead_lm_remote_find_client_runner() {
  if [ -n "${BULKHEAD_LM_REMOTE_CLIENT_BIN:-}" ] && [ -x "${BULKHEAD_LM_REMOTE_CLIENT_BIN}" ]; then
    printf 'bin:%s\n' "${BULKHEAD_LM_REMOTE_CLIENT_BIN}"
    return 0
  fi
  if [ -x "${BULKHEAD_LM_REMOTE_ROOT_DIR}/bin/bulkhead-lm-client" ]; then
    printf 'bin:%s\n' "${BULKHEAD_LM_REMOTE_ROOT_DIR}/bin/bulkhead-lm-client"
    return 0
  fi
  if [ -x "${BULKHEAD_LM_REMOTE_ROOT_DIR}/_build/default/bin/client.exe" ]; then
    printf 'bin:%s\n' "${BULKHEAD_LM_REMOTE_ROOT_DIR}/_build/default/bin/client.exe"
    return 0
  fi
  if command -v bulkhead-lm-client >/dev/null 2>&1; then
    printf 'bin:%s\n' "$(command -v bulkhead-lm-client)"
    return 0
  fi
  if command -v dune >/dev/null 2>&1; then
    printf '%s\n' "dune"
    return 0
  fi
  return 1
}

bulkhead_lm_remote_exec_client() {
  runner=$(bulkhead_lm_remote_find_client_runner || true)
  if [ -z "${runner}" ]; then
    bulkhead_lm_remote_note "No BulkheadLM client runner was found."
    bulkhead_lm_remote_note "Expected one of:"
    bulkhead_lm_remote_note "  - ${BULKHEAD_LM_REMOTE_ROOT_DIR}/_build/default/bin/client.exe"
    bulkhead_lm_remote_note "  - bulkhead-lm-client in PATH"
    bulkhead_lm_remote_note "  - dune in PATH"
    return 1
  fi

  cd "${BULKHEAD_LM_REMOTE_ROOT_DIR}"
  case "${runner}" in
    bin:*)
      exec "${runner#bin:}" "$@"
      ;;
    dune)
      exec dune exec bulkhead-lm-client -- "$@"
      ;;
    *)
      bulkhead_lm_remote_note "Unsupported client runner descriptor: ${runner}"
      return 1
      ;;
  esac
}

bulkhead_lm_remote_stream_archive() {
  tar_bin=$(bulkhead_lm_remote_find_tar || true)
  if [ -z "${tar_bin}" ]; then
    bulkhead_lm_remote_note "No tar executable was found on the remote machine."
    return 1
  fi

  cd "${BULKHEAD_LM_REMOTE_ROOT_DIR}"
  "${tar_bin}" \
    -czf - \
    --exclude=".git" \
    --exclude="_build" \
    --exclude="_opam" \
    --exclude="var" \
    --exclude=".DS_Store" \
    .
}

bulkhead_lm_remote_emit_local_installer() {
  origin=$1
  remote_install_script=$2
  default_target_expr=$3

  cat <<EOF
#!/bin/sh
set -eu

BULKHEAD_LM_INSTALL_ORIGIN='${origin}'
BULKHEAD_LM_INSTALL_REMOTE_SCRIPT='${remote_install_script}'
BULKHEAD_LM_INSTALL_TARGET_DEFAULT='${default_target_expr}'

note() {
  printf '%s\n' "\$*" >&2
}

print_help() {
  cat <<HELP
Usage: sh bulkhead-lm-install.sh [options]

Options:
  --target DIR   Local install directory. Default: \${BULKHEAD_LM_INSTALL_TARGET_DEFAULT}
  --start        Launch ./run.sh after a successful install
  --help         Show this help

Environment overrides:
  BULKHEAD_LM_INSTALL_DIR         Same as --target
  BULKHEAD_LM_INSTALL_SSH_BIN     SSH executable. Default: ssh
  BULKHEAD_LM_INSTALL_SSH_ARGS    Extra SSH options for the archive fetch
  BULKHEAD_LM_INSTALL_ARCHIVE_CMD Override the archive fetch command entirely

Examples:
  ssh user@host '${remote_install_script} --emit-installer --origin user@host' | sh
  ssh user@host '${remote_install_script} --emit-installer --origin user@host' | sh -s -- --target "\$HOME/bulkhead-lm"
HELP
}

TARGET=\${BULKHEAD_LM_INSTALL_DIR:-\${BULKHEAD_LM_INSTALL_TARGET_DEFAULT}}
START_AFTER=0

while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --target)
      [ "\$#" -ge 2 ] || { note "--target requires a value"; exit 1; }
      TARGET=\$2
      shift 2
      ;;
    --start)
      START_AFTER=1
      shift
      ;;
    *)
      note "Unknown installer option: \$1"
      exit 1
      ;;
  esac
done

if ! command -v tar >/dev/null 2>&1; then
  note "tar is required on the local machine to install BulkheadLM."
  exit 1
fi

if [ -e "\${TARGET}" ] && [ ! -d "\${TARGET}" ]; then
  note "Install target exists and is not a directory: \${TARGET}"
  exit 1
fi

if [ -d "\${TARGET}" ] && [ -n "\$(ls -A "\${TARGET}" 2>/dev/null || true)" ]; then
  note "Install target is not empty: \${TARGET}"
  note "Choose another directory with --target or empty the target first."
  exit 1
fi

mkdir -p "\${TARGET}"
tmpdir=\$(mktemp -d 2>/dev/null || mktemp -d -t bulkhead-lm-install)
archive="\${tmpdir}/bulkhead-lm.tar.gz"
cleanup() {
  rm -rf "\${tmpdir}"
}
trap cleanup EXIT HUP INT TERM

archive_cmd=\${BULKHEAD_LM_INSTALL_ARCHIVE_CMD:-}
if [ -n "\${archive_cmd}" ]; then
  sh -c "\${archive_cmd}" > "\${archive}"
else
  ssh_bin=\${BULKHEAD_LM_INSTALL_SSH_BIN:-ssh}
  ssh_args=\${BULKHEAD_LM_INSTALL_SSH_ARGS:-}
  remote_cmd="\${BULKHEAD_LM_INSTALL_REMOTE_SCRIPT} --archive"
  # Intentionally word-splitting SSH args so callers can pass flags in one variable.
  # shellcheck disable=SC2086
  "\${ssh_bin}" \${ssh_args} "\${BULKHEAD_LM_INSTALL_ORIGIN}" "\${remote_cmd}" > "\${archive}"
fi

tar -xzf "\${archive}" -C "\${TARGET}"

if [ -f "\${TARGET}/run.sh" ]; then
  chmod +x "\${TARGET}/run.sh"
fi
if [ -f "\${TARGET}/start-macos-client.command" ]; then
  chmod +x "\${TARGET}/start-macos-client.command"
fi
if [ -d "\${TARGET}/scripts" ]; then
  find "\${TARGET}/scripts" -type f -name '*.sh' -exec chmod +x {} \;
fi

note "BulkheadLM was installed to \${TARGET}"
note "Next step: cd \${TARGET} && ./run.sh"

if [ "\${START_AFTER}" = "1" ] && [ -x "\${TARGET}/run.sh" ]; then
  cd "\${TARGET}"
  exec ./run.sh
fi
EOF
}
