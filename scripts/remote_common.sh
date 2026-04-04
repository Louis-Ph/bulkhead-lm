AEGISLM_REMOTE_ROOT_DIR=${AEGISLM_REMOTE_ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
AEGISLM_REMOTE_INSTALL_DEFAULT_TARGET=${AEGISLM_REMOTE_INSTALL_DEFAULT_TARGET:-'${HOME}/opt/aegis-lm'}

aegislm_remote_note() {
  printf '%s\n' "$*" >&2
}

aegislm_remote_find_tar() {
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
  if [ -x "${AEGISLM_REMOTE_ROOT_DIR}/bin/aegislm-client" ]; then
    printf 'bin:%s\n' "${AEGISLM_REMOTE_ROOT_DIR}/bin/aegislm-client"
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

aegislm_remote_stream_archive() {
  tar_bin=$(aegislm_remote_find_tar || true)
  if [ -z "${tar_bin}" ]; then
    aegislm_remote_note "No tar executable was found on the remote machine."
    return 1
  fi

  cd "${AEGISLM_REMOTE_ROOT_DIR}"
  "${tar_bin}" \
    -czf - \
    --exclude=".git" \
    --exclude="_build" \
    --exclude="_opam" \
    --exclude="var" \
    --exclude=".DS_Store" \
    .
}

aegislm_remote_emit_local_installer() {
  origin=$1
  remote_install_script=$2
  default_target_expr=$3

  cat <<EOF
#!/bin/sh
set -eu

AEGISLM_INSTALL_ORIGIN='${origin}'
AEGISLM_INSTALL_REMOTE_SCRIPT='${remote_install_script}'
AEGISLM_INSTALL_TARGET_DEFAULT='${default_target_expr}'

note() {
  printf '%s\n' "\$*" >&2
}

print_help() {
  cat <<HELP
Usage: sh aegislm-install.sh [options]

Options:
  --target DIR   Local install directory. Default: \${AEGISLM_INSTALL_TARGET_DEFAULT}
  --start        Launch ./run.sh after a successful install
  --help         Show this help

Environment overrides:
  AEGISLM_INSTALL_DIR         Same as --target
  AEGISLM_INSTALL_SSH_BIN     SSH executable. Default: ssh
  AEGISLM_INSTALL_SSH_ARGS    Extra SSH options for the archive fetch
  AEGISLM_INSTALL_ARCHIVE_CMD Override the archive fetch command entirely

Examples:
  ssh user@host '${remote_install_script} --emit-installer --origin user@host' | sh
  ssh user@host '${remote_install_script} --emit-installer --origin user@host' | sh -s -- --target "\$HOME/aegis-lm"
HELP
}

TARGET=\${AEGISLM_INSTALL_DIR:-\${AEGISLM_INSTALL_TARGET_DEFAULT}}
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
  note "tar is required on the local machine to install AegisLM."
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
tmpdir=\$(mktemp -d 2>/dev/null || mktemp -d -t aegislm-install)
archive="\${tmpdir}/aegislm.tar.gz"
cleanup() {
  rm -rf "\${tmpdir}"
}
trap cleanup EXIT HUP INT TERM

archive_cmd=\${AEGISLM_INSTALL_ARCHIVE_CMD:-}
if [ -n "\${archive_cmd}" ]; then
  sh -c "\${archive_cmd}" > "\${archive}"
else
  ssh_bin=\${AEGISLM_INSTALL_SSH_BIN:-ssh}
  ssh_args=\${AEGISLM_INSTALL_SSH_ARGS:-}
  remote_cmd="\${AEGISLM_INSTALL_REMOTE_SCRIPT} --archive"
  # Intentionally word-splitting SSH args so callers can pass flags in one variable.
  # shellcheck disable=SC2086
  "\${ssh_bin}" \${ssh_args} "\${AEGISLM_INSTALL_ORIGIN}" "\${remote_cmd}" > "\${archive}"
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

note "AegisLM was installed to \${TARGET}"
note "Next step: cd \${TARGET} && ./run.sh"

if [ "\${START_AFTER}" = "1" ] && [ -x "\${TARGET}/run.sh" ]; then
  cd "\${TARGET}"
  exec ./run.sh
fi
EOF
}
