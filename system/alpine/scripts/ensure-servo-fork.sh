#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
SERVO_DIR="${ROOT_DIR}/third_party/servo"
SERVO_BIN="${SERVO_DIR}/target/release/servoshell"
SERVO_FORK_URL="${SERVO_FORK_URL:-}"
SERVO_FORK_BRANCH="${SERVO_FORK_BRANCH:-main}"
SERVO_BUILD="${SERVO_BUILD:-1}"
SERVO_FORCE_REBUILD="${SERVO_FORCE_REBUILD:-0}"
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

ensure_servo_macos_deps() {
  if [ "$(uname -s)" != "Darwin" ]; then
    return
  fi

  if [ -d "${GSTREAMER_ROOT}" ]; then
    return
  fi

  echo "Installing Servo macOS GStreamer dependencies..."
  tmp_dir="$(mktemp -d)"
  libs_pkg="${tmp_dir}/gstreamer-1.0-1.22.3-universal.pkg"
  devel_pkg="${tmp_dir}/gstreamer-1.0-devel-1.22.3-universal.pkg"
  curl -L -o "${libs_pkg}" "${GSTREAMER_LIBS_PKG}"
  curl -L -o "${devel_pkg}" "${GSTREAMER_DEVEL_PKG}"
  sudo installer -pkg "${libs_pkg}" -target /
  sudo installer -pkg "${devel_pkg}" -target /
}

if [ ! -d "${SERVO_DIR}/.git" ]; then
  if [ -z "${SERVO_FORK_URL}" ]; then
    echo "missing Servo fork checkout at ${SERVO_DIR}" >&2
    echo "set SERVO_FORK_URL to clone your fork, e.g.:" >&2
    echo "  SERVO_FORK_URL=https://github.com/<org-or-user>/servo.git ./system/alpine/scripts/qemu-v0.sh" >&2
    exit 1
  fi
  git clone --depth 1 --branch "${SERVO_FORK_BRANCH}" "${SERVO_FORK_URL}" "${SERVO_DIR}"
fi

if [ "${SERVO_BUILD}" = "1" ] && { [ "${SERVO_FORCE_REBUILD}" = "1" ] || [ ! -x "${SERVO_BIN}" ]; }; then
  prepend_user_bin
  if [ ! -x "${SERVO_DIR}/mach" ]; then
    echo "Servo source exists but build entrypoint not found: ${SERVO_DIR}/mach" >&2
    exit 1
  fi
  if ! command -v uv >/dev/null 2>&1; then
    if command -v python3 >/dev/null 2>&1; then
      python3 -m ensurepip --user >/dev/null 2>&1 || true
      python3 -m pip install --user uv >/dev/null 2>&1 || true
      export PATH="${HOME}/.local/bin:${PATH}"
    fi
  fi
  if ! command -v uv >/dev/null 2>&1; then
    echo "uv is required to run Servo's mach build." >&2
    echo "install with: python3 -m pip install --user uv" >&2
    exit 1
  fi
  ensure_servo_macos_deps
  echo "Building Servo fork (release)..."
  (
    cd "${SERVO_DIR}"
    ./mach build --release
  )
fi

if [ ! -x "${SERVO_BIN}" ]; then
  echo "servoshell binary missing: ${SERVO_BIN}" >&2
  echo "build your fork with ./mach build --release (in third_party/servo), then rerun." >&2
  exit 1
fi

echo "Servo fork ready: ${SERVO_BIN}"
