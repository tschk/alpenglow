#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

usage() {
  cat <<'EOF'
usage: ./install.sh [--check] [--prepare-rootfs]

  --check           Run install readiness gates.
  --prepare-rootfs  Build the appliance rootfs.
EOF
}

check_ready() {
  "${ROOT_DIR}/scripts/ci-os-appliance.sh"
  "${ROOT_DIR}/scripts/ci-glowfs-kernel-module.sh"
  "${ROOT_DIR}/scripts/ci-rust-core.sh"
}

prepare_rootfs() {
  "${ROOT_DIR}/system/backends/appliance/scripts/build-rootfs.sh"
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
    --usage|-h)
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
