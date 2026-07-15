#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
EDITION="${1:-desktop}"
ACCEL="${ACCEL:-}"
MEMORY_MB="${MEMORY_MB:-4096}"
SMP="${SMP:-4}"

case "${EDITION}" in
  desktop|desktop-full) ;;
  *) echo "usage: $0 [desktop|desktop-full]" >&2; exit 1 ;;
esac

command -v qemu-system-aarch64 >/dev/null 2>&1 || { echo "missing: qemu-system-aarch64" >&2; exit 1; }

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
