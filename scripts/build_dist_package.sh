#!/bin/sh
set -eu

ROOT_DIR=${AEGISLM_PACKAGE_ROOT_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
. "$ROOT_DIR/scripts/package_common.sh"

OS_NAME=auto
PACKAGE_NAME=aegislm
DISPLAY_NAME="AegisLM"
VERSION=""
MAINTAINER="AegisLM"
DESCRIPTION="AegisLM secure OCaml gateway."
INSTALL_ROOT=""
WRAPPER_DIR=""
ARTIFACT_DIR="$ROOT_DIR/dist"
CONFIG_SOURCE="$ROOT_DIR/config/example.gateway.json"
IDENTIFIER=""

print_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  --os VALUE            macos, ubuntu, freebsd, or auto
  --package-name NAME   System package name
  --display-name NAME   Human-friendly display name
  --version VALUE       Package version
  --maintainer NAME     Maintainer label
  --description TEXT    Short package description
  --install-root PATH   Installed application tree root
  --wrapper-dir PATH    Directory where CLI wrappers are installed
  --artifact-dir DIR    Output directory for built packages
  --config-source FILE  Gateway config file bundled into the package
  --identifier VALUE    Package identifier (used on macOS)
  --help                Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --os)
      OS_NAME=$2
      shift 2
      ;;
    --package-name)
      PACKAGE_NAME=$2
      shift 2
      ;;
    --display-name)
      DISPLAY_NAME=$2
      shift 2
      ;;
    --version)
      VERSION=$2
      shift 2
      ;;
    --maintainer)
      MAINTAINER=$2
      shift 2
      ;;
    --description)
      DESCRIPTION=$2
      shift 2
      ;;
    --install-root)
      INSTALL_ROOT=$2
      shift 2
      ;;
    --wrapper-dir)
      WRAPPER_DIR=$2
      shift 2
      ;;
    --artifact-dir)
      ARTIFACT_DIR=$2
      shift 2
      ;;
    --config-source)
      CONFIG_SOURCE=$2
      shift 2
      ;;
    --identifier)
      IDENTIFIER=$2
      shift 2
      ;;
    *)
      pkg_fail "Unknown option: $1"
      ;;
  esac
done

if [ "$OS_NAME" = "auto" ]; then
  case "$(uname -s 2>/dev/null || printf '%s' unknown)" in
    Darwin) OS_NAME=macos ;;
    Linux)
      if [ -r /etc/os-release ] && grep -qi ubuntu /etc/os-release; then
        OS_NAME=ubuntu
      else
        pkg_fail "Automatic packaging currently supports Ubuntu only on Linux."
      fi
      ;;
    FreeBSD) OS_NAME=freebsd ;;
    *) pkg_fail "Unsupported host OS for packaging." ;;
  esac
fi

case "$OS_NAME" in
  macos)
    [ -n "$INSTALL_ROOT" ] || INSTALL_ROOT=/opt/aegis-lm
    [ -n "$WRAPPER_DIR" ] || WRAPPER_DIR=/usr/local/bin
    [ -n "$IDENTIFIER" ] || IDENTIFIER=io.github.louis-ph.aegislm
    [ -n "$VERSION" ] || VERSION=0.1.0
    ARTIFACT_NAME="${PACKAGE_NAME}-${VERSION}-macos.pkg"
    ;;
  ubuntu)
    [ -n "$INSTALL_ROOT" ] || INSTALL_ROOT=/opt/aegis-lm
    [ -n "$WRAPPER_DIR" ] || WRAPPER_DIR=/usr/bin
    [ -n "$VERSION" ] || VERSION=0.1.0
    ARCHITECTURE=$(pkg_detect_ubuntu_arch)
    ARTIFACT_NAME="${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"
    ;;
  freebsd)
    [ -n "$INSTALL_ROOT" ] || INSTALL_ROOT=/usr/local/lib/aegis-lm
    [ -n "$WRAPPER_DIR" ] || WRAPPER_DIR=/usr/local/bin
    [ -n "$VERSION" ] || VERSION=0.1.0
    ARTIFACT_NAME="${PACKAGE_NAME}-${VERSION}.pkg"
    ;;
  *)
    pkg_fail "Unsupported package OS value: $OS_NAME"
    ;;
esac

WORK_DIR="$ARTIFACT_DIR/.work/${PACKAGE_NAME}-${VERSION}-${OS_NAME}"
PAYLOAD_ROOT="$WORK_DIR/root"
ARTIFACT_PATH="$ARTIFACT_DIR/$ARTIFACT_NAME"

pkg_note "Preparing package build for $OS_NAME"
pkg_note "Root directory: $ROOT_DIR"
pkg_note "Bundled config: $CONFIG_SOURCE"
pkg_ensure_dir "$ARTIFACT_DIR"
pkg_remove_path "$WORK_DIR"
pkg_remove_path "$ARTIFACT_PATH"
pkg_ensure_dir "$PAYLOAD_ROOT"

pkg_prepare_binaries "$ROOT_DIR"
pkg_stage_runtime_tree "$ROOT_DIR" "$PAYLOAD_ROOT" "$INSTALL_ROOT" "$CONFIG_SOURCE"

pkg_make_wrapper "$PAYLOAD_ROOT$WRAPPER_DIR/aegislm" "$INSTALL_ROOT/bin/aegislm"
pkg_make_wrapper "$PAYLOAD_ROOT$WRAPPER_DIR/aegislm-client" "$INSTALL_ROOT/bin/aegislm-client"
pkg_make_wrapper "$PAYLOAD_ROOT$WRAPPER_DIR/aegislm-starter" "$INSTALL_ROOT/run.sh"

case "$OS_NAME" in
  macos)
    pkg_require_command pkgbuild
    pkg_note "Building macOS installer package..."
    pkgbuild \
      --root "$PAYLOAD_ROOT" \
      --identifier "$IDENTIFIER" \
      --version "$VERSION" \
      --install-location / \
      "$ARTIFACT_PATH" >/dev/null
    ;;
  ubuntu)
    pkg_require_command dpkg-deb
    DEBIAN_DIR="$PAYLOAD_ROOT/DEBIAN"
    pkg_ensure_dir "$DEBIAN_DIR"
    cat >"$DEBIAN_DIR/control" <<EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Homepage: https://github.com/Louis-Ph/aegis-lm
Description: $DESCRIPTION
EOF
    pkg_note "Building Ubuntu .deb package..."
    dpkg-deb --build "$PAYLOAD_ROOT" "$ARTIFACT_PATH" >/dev/null
    ;;
  freebsd)
    pkg_require_command pkg
    METADATA_DIR="$WORK_DIR/metadata"
    PLIST_FILE="$WORK_DIR/pkg-plist"
    ABI=$(pkg_detect_freebsd_abi)
    [ -n "$ABI" ] || ABI="$(uname -s):$(uname -r):$(uname -m)"
    pkg_ensure_dir "$METADATA_DIR"
    cat >"$METADATA_DIR/+MANIFEST" <<EOF
name: $PACKAGE_NAME
version: "$VERSION"
origin: local/$PACKAGE_NAME
comment: "$DISPLAY_NAME"
maintainer: "$MAINTAINER"
www: "https://github.com/Louis-Ph/aegis-lm"
abi: "$ABI"
prefix: /
desc: <<EOD
$DESCRIPTION
EOD
EOF
    (
      cd "$PAYLOAD_ROOT"
      find . -type f -o -type l | sed 's#^./##' | sort >"$PLIST_FILE"
    )
    pkg_note "Building FreeBSD package..."
    pkg create -m "$METADATA_DIR" -r "$PAYLOAD_ROOT" -p "$PLIST_FILE" -o "$ARTIFACT_DIR" >/dev/null
    if [ ! -f "$ARTIFACT_PATH" ]; then
      GENERATED=$(find "$ARTIFACT_DIR" -maxdepth 1 -type f -name "${PACKAGE_NAME}-*.pkg" | head -n 1)
      if [ -n "$GENERATED" ]; then
        mv "$GENERATED" "$ARTIFACT_PATH"
      fi
    fi
    ;;
esac

[ -f "$ARTIFACT_PATH" ] || pkg_fail "Package tool did not produce the expected artifact."
pkg_note "ARTIFACT: $ARTIFACT_PATH"
