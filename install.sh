#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
BACKEND="${ALPENGLOW_BACKEND:-${ALPENGLOW_BACKEND:-void-musl-runit}}"

usage() {
  cat <<'EOF'
usage: ./install.sh [--check] [--prepare-rootfs] [--qemu-reference]

  --check           Run install readiness gates.
  --prepare-rootfs  Build the selected backend rootfs.
  --qemu-reference  Run the current Alpine reference QEMU flow.
EOF
}

check_ready() {
  "${ROOT_DIR}/scripts/ci-os-appliance.sh"
  "${ROOT_DIR}/scripts/ci-glowfs-kernel-module.sh"
  "${ROOT_DIR}/scripts/ci-rust-core.sh"
}

prepare_rootfs() {
  case "${BACKEND}" in
    void|void-musl-runit)
      "${ROOT_DIR}/system/backends/void/scripts/build-rootfs.sh"
      ;;
    alpine|alpine-openrc)
      "${ROOT_DIR}/system/alpine/scripts/build-rootfs.sh"
      ;;
    *)
      echo "unknown backend: ${BACKEND}" >&2
      exit 1
      ;;
  esac
}

if [ "$#" -eq 0 ]; then
  prepare_rootfs
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      check_ready
      ;;
    --prepare-rootfs)
      prepare_rootfs
      ;;
    --qemu-reference)
      "${ROOT_DIR}/system/alpine/scripts/qemu-v0.sh"
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done
