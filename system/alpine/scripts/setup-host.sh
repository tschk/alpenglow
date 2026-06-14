#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
WAX_DIR="${ROOT_DIR}/third_party/wax"
DRY_RUN="${DRY_RUN:-0}"
GSTREAMER_ROOT="/Library/Frameworks/GStreamer.framework/Versions/1.0"
GSTREAMER_URL_BASE="https://github.com/servo/servo-build-deps/releases/download/macOS"
GSTREAMER_LIBS_PKG="${GSTREAMER_URL_BASE}/gstreamer-1.0-1.22.3-universal.pkg"
GSTREAMER_DEVEL_PKG="${GSTREAMER_URL_BASE}/gstreamer-1.0-devel-1.22.3-universal.pkg"

prepend_user_bin() {
  if command -v python3 >/dev/null 2>&1; then
    USER_BIN="$(python3 - <<'PY'
import sysconfig
print(sysconfig.get_path("scripts", scheme="posix_user"))
PY
)"
    case ":$PATH:" in
      *":${USER_BIN}:"*) ;;
      *)
        PATH="${USER_BIN}:${PATH}"
        export PATH
        ;;
    esac
  fi
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *)
      PATH="$HOME/.local/bin:$PATH"
      export PATH
      ;;
  esac
}

run() {
  if [ "${DRY_RUN}" = "1" ]; then
    echo "[dry-run] $*"
  else
    sh -lc "$*"
  fi
}

have() {
  command -v "$1" >/dev/null 2>&1
}

bootstrap_with_apt() {
  run "sudo apt-get update"
  run "sudo apt-get install -y git curl python3 python3-pip"
}

bootstrap_with_apk() {
  run "sudo apk add --no-cache git curl python3 py3-pip"
}

bootstrap_with_dnf() {
  run "sudo dnf install -y git curl python3 python3-pip"
}

bootstrap_prereqs_for_wax() {
  if have brew; then
    run "brew list git >/dev/null 2>&1 || brew install git"
    run "brew list curl >/dev/null 2>&1 || brew install curl"
    run "brew list python@3.13 >/dev/null 2>&1 || brew install python@3.13"
    return
  fi
  if have apt-get; then
    bootstrap_with_apt
    return
  fi
  if have apk; then
    bootstrap_with_apk
    return
  fi
  if have dnf; then
    bootstrap_with_dnf
    return
  fi
  echo "No supported package manager found (brew/apt/apk/dnf)." >&2
  exit 1
}

ensure_wax_available() {
  if have wax; then
    return
  fi

  echo "wax not found; bootstrapping minimal prerequisites..."
  bootstrap_prereqs_for_wax
  ensure_wax

  ensure_wax_path
  if ! have wax; then
    echo "wax binary not found after install (expected in ~/.local/bin/wax)" >&2
    exit 1
  fi
}

ensure_uv() {
  if ! have uv; then
    run "python3 -m ensurepip --user || true"
    run "python3 -m pip install --user uv"
  fi
}

ensure_servo_macos_deps() {
  if [ "$(uname -s)" != "Darwin" ]; then
    return
  fi

  run "wax install cmake pkg-config"

  if [ -d "${GSTREAMER_ROOT}" ]; then
    return
  fi

  if [ "${DRY_RUN}" = "1" ]; then
    run "curl -L -o /tmp/gstreamer-1.0-1.22.3-universal.pkg ${GSTREAMER_LIBS_PKG}"
    run "curl -L -o /tmp/gstreamer-1.0-devel-1.22.3-universal.pkg ${GSTREAMER_DEVEL_PKG}"
    run "sudo installer -pkg /tmp/gstreamer-1.0-1.22.3-universal.pkg -target /"
    run "sudo installer -pkg /tmp/gstreamer-1.0-devel-1.22.3-universal.pkg -target /"
    return
  fi

  tmp_dir="$(mktemp -d)"
  libs_pkg="${tmp_dir}/gstreamer-1.0-1.22.3-universal.pkg"
  devel_pkg="${tmp_dir}/gstreamer-1.0-devel-1.22.3-universal.pkg"
  curl -L -o "${libs_pkg}" "${GSTREAMER_LIBS_PKG}"
  curl -L -o "${devel_pkg}" "${GSTREAMER_DEVEL_PKG}"
  sudo installer -pkg "${libs_pkg}" -target /
  sudo installer -pkg "${devel_pkg}" -target /
}

ensure_wax() {
  if [ ! -d "${WAX_DIR}/.git" ]; then
    run "git clone https://github.com/semitechnological/wax.git ${WAX_DIR}"
  else
    run "git -C ${WAX_DIR} fetch --all --tags"
    run "git -C ${WAX_DIR} pull --ff-only"
  fi
  run "cd ${WAX_DIR} && ./install.sh"
}

ensure_wax_path() {
  if have wax; then
    return
  fi
  export PATH="${HOME}/.local/bin:${PATH}"
}

install_with_wax() {
  ensure_wax_path
  if [ "${DRY_RUN}" = "1" ]; then
    run "wax install git curl qemu gh docker"
    return
  fi
  # wax is a drop-in replacement for brew; use it for host package installs.
  run "wax install git curl qemu gh docker"
}

ensure_rust_toolchain() {
  ensure_wax_path
  if [ "${DRY_RUN}" = "1" ]; then
    run "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    return
  fi
  if ! have cargo; then
    if have rustup-init; then
      run "rustup-init -y"
    else
      run "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    fi
  fi
}

ensure_path_hint() {
  if [ "${DRY_RUN}" = "1" ]; then
    echo "[dry-run] PATH hint: export PATH=\"\$HOME/.local/bin:\$PATH\""
    return
  fi
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *)
      echo "Add to your shell profile if needed:"
      echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
      ;;
  esac
}

echo "Setting up host dependencies for Alpenglow (QEMU + Servo build)..."
prepend_user_bin
ensure_wax_available
install_with_wax
ensure_rust_toolchain
ensure_uv
ensure_servo_macos_deps
ensure_path_hint
echo "Host setup complete."
