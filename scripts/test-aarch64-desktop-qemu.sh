#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
KILL_EXISTING=0
if [ "${1:-}" = --kill-existing ]; then
  KILL_EXISTING=1
  shift
fi
EDITION="${1:-desktop}"
ACCEL="${ACCEL:-}"
MEMORY_MB="${MEMORY_MB:-4096}"
SMP="${SMP:-4}"

case "${EDITION}" in
  desktop|desktop-full) ;;
  *) echo "usage: $0 [--kill-existing] [desktop|desktop-full]" >&2; exit 1 ;;
esac

command -v qemu-system-aarch64 >/dev/null 2>&1 || { echo "missing: qemu-system-aarch64" >&2; exit 1; }

if [ "${KILL_EXISTING}" = 1 ]; then
  docker ps -q --filter label=alpenglow.aarch64-build=1 | while IFS= read -r cid; do
    [ -z "${cid}" ] || docker stop "${cid}" >/dev/null 2>&1 || true
  done
  pkill -f "${ROOT_DIR}/scripts/build-aarch64-desktop.sh" 2>/dev/null || true
  pkill -f "${ROOT_DIR}/system/backends/appliance/scripts/build-kernel-aarch64.sh" 2>/dev/null || true
  rm -rf "${ROOT_DIR}/build/cross/aarch64/.kernel-aarch64.lock"
fi

if [ -z "${ACCEL}" ]; then
  if timeout 2 qemu-system-aarch64 -M none -accel hvf >/dev/null 2>&1; then
    ACCEL=hvf
  else
    ACCEL=tcg
  fi
fi

if [ "${ACCEL}" = hvf ]; then
  CPU=host
else
  CPU=max
fi

OUT_DIR="${ROOT_DIR}/build/cross/aarch64"
KERNEL="${OUT_DIR}/vmlinuz-${EDITION}"
INITRAMFS="${OUT_DIR}/initramfs-${EDITION}.cpio.gz"

if [ ! -s "${KERNEL}" ] || [ ! -s "${INITRAMFS}" ]; then
  sh "${ROOT_DIR}/scripts/build-aarch64-desktop.sh" "${EDITION}"
fi

test -s "${KERNEL}"
test -s "${INITRAMFS}"
file "${KERNEL}" | grep -q aarch64

exec qemu-system-aarch64 \
  -M virt -accel "${ACCEL}" -cpu "${CPU}" -m "${MEMORY_MB}" -smp "${SMP}" \
  -display cocoa -device virtio-gpu-pci -device virtio-keyboard-pci -device virtio-mouse-pci \
  -chardev stdio,id=char0,mux=on,signal=off -serial chardev:char0 -mon chardev=char0 \
  -no-reboot -kernel "${KERNEL}" -initrd "${INITRAMFS}" \
  -append 'console=ttyAMA0,115200 console=tty0 init=/init'
