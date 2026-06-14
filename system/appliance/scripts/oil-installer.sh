#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
OIL_ROOT="${OIL_ROOT:-${ROOT_DIR}/../oil}"
OIL_BIN="${OIL_BIN:-}"
ACTION="${1:-bin}"

resolve_oil_bin() {
  if [ -n "${OIL_BIN}" ]; then
    [ -x "${OIL_BIN}" ] || {
      echo "OIL_BIN is not executable: ${OIL_BIN}" >&2
      exit 1
    }
    printf '%s\n' "${OIL_BIN}"
    return
  fi

  if [ -x "${OIL_ROOT}/target/release/wax" ]; then
    printf '%s\n' "${OIL_ROOT}/target/release/wax"
    return
  fi

  if [ "${OIL_BUILD:-0}" = "1" ]; then
    cargo build --release --manifest-path "${OIL_ROOT}/Cargo.toml"
    printf '%s\n' "${OIL_ROOT}/target/release/wax"
    return
  fi

  echo "oil installer binary not found; set OIL_BIN or OIL_BUILD=1" >&2
  exit 1
}

case "${ACTION}" in
  bin)
    resolve_oil_bin
    ;;
  system-add)
    ROOTFS="${2:-}"
    shift 2 || true
    if [ -z "${ROOTFS}" ] || [ "$#" -eq 0 ]; then
      echo "usage: $0 system-add <rootfs-dir> <package>..." >&2
      exit 1
    fi
    OIL="$(resolve_oil_bin)"
    mkdir -p "${ROOTFS}/var/lib/soliloquy/oil"
    HOME="${ROOTFS}/var/lib/soliloquy/oil" \
      WAX_SYSTEM_PREFIX="${ROOTFS}" \
      "${OIL}" system add --no-script "$@"
    ;;
  system-sync)
    ROOTFS="${2:-}"
    if [ -z "${ROOTFS}" ]; then
      echo "usage: $0 system-sync <rootfs-dir>" >&2
      exit 1
    fi
    OIL="$(resolve_oil_bin)"
    mkdir -p "${ROOTFS}/var/lib/soliloquy/oil"
    HOME="${ROOTFS}/var/lib/soliloquy/oil" \
      WAX_SYSTEM_PREFIX="${ROOTFS}" \
      "${OIL}" system sync
    ;;
  *)
    echo "unknown oil installer action: ${ACTION}" >&2
    exit 1
    ;;
esac
