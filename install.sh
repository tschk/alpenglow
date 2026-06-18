#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

usage() {
  cat <<'EOF'
usage: ./install.sh [--check] [--doctor] [--prepare-rootfs] [--qemu-appliance] [--qemu-reference]

  --check            Static CI gates (no QEMU).
  --doctor           Report host tools and key repo paths.
  --prepare-rootfs   Build the appliance rootfs.
  --qemu-appliance   Headless QEMU boot smoke (ci-qemu-appliance).
  --qemu-reference   Legacy Alpine cpio QEMU (not appliance).
EOF
}

doctor() {
  ok=0
  miss=0
  note() { printf '  [ok] %s\n' "$1"; ok=$((ok + 1)); }
  bad() { printf '  [!!] %s\n' "$1"; miss=$((miss + 1)); }

  echo "Alpenglow doctor"
  echo ""
  for t in cargo docker qemu-system-x86_64; do
    command -v "$t" >/dev/null 2>&1 && note "$t" || bad "$t"
  done
  echo ""
  for p in \
    system/backends/appliance/backend.json \
    system/backends/appliance/scripts/qemu.sh \
    scripts/boot-native.sh \
    scripts/ci-qemu-appliance.sh \
    system/backends/appliance/kernel/alpenglow-internet-appliance.config
  do
    [ -f "${ROOT_DIR}/${p}" ] && note "${p}" || bad "${p}"
  done
  echo ""
  if [ "${miss}" -gt 0 ]; then
    echo "doctor: ${ok} ok, ${miss} missing"
    exit 1
  fi
  echo "doctor: ok (${ok} checks)"
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
    --doctor)
      doctor
      ;;
    --prepare-rootfs)
      prepare_rootfs
      ;;
    --qemu-appliance)
      "${ROOT_DIR}/scripts/ci-qemu-appliance.sh"
      ;;
    --qemu-reference)
      "${ROOT_DIR}/system/alpine/scripts/qemu-v0.sh"
      ;;
    --help|-h|--usage)
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
