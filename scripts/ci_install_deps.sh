#!/bin/sh
set -eu

note() {
  printf '%s\n' "$*" >&2
}

INSTALL_ATTEMPTS=${BULKHEAD_LM_CI_OPAM_INSTALL_ATTEMPTS:-4}
DOWNLOAD_JOBS=${BULKHEAD_LM_CI_OPAM_DOWNLOAD_JOBS:-1}
BACKOFF_SECONDS=${BULKHEAD_LM_CI_OPAM_RETRY_BACKOFF_SECONDS:-15}

attempt=1
while :; do
  note "CI dependency install attempt ${attempt}/${INSTALL_ATTEMPTS} with OPAMDOWNLOADJOBS=${DOWNLOAD_JOBS}"
  if OPAMDOWNLOADJOBS="$DOWNLOAD_JOBS" opam install . --deps-only --with-test; then
    note "CI dependency install completed."
    exit 0
  fi

  if [ "$attempt" -ge "$INSTALL_ATTEMPTS" ]; then
    note "CI dependency install failed after ${INSTALL_ATTEMPTS} attempts."
    exit 1
  fi

  sleep_seconds=$((BACKOFF_SECONDS * attempt))
  note "Transient opam fetch/build failure detected. Retrying in ${sleep_seconds}s ..."
  sleep "$sleep_seconds"
  attempt=$((attempt + 1))
done
