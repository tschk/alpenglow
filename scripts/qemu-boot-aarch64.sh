#!/bin/sh
# Boot Alpenglow aarch64 in QEMU virt.
# Requires: build-aarch64.sh run first, qemu-system-aarch64
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_OUT="${REPO_ROOT}/build/cross/aarch64"
MEMORY_MB="${MEMORY_MB:-512}"
ACCEL="${ACCEL:-hvf}"
CPU="${CPU:-}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
require_cmd qemu-system-aarch64

for f in vmlinuz initramfs.cpio.gz; do
  if [ ! -f "${BUILD_OUT}/${f}" ]; then
    echo "ERROR: ${BUILD_OUT}/${f} not found. Run scripts/build-aarch64.sh first." >&2
    exit 1
  fi
done

echo "=== Alpenglow aarch64 QEMU boot ==="
INITRAMFS="${INITRAMFS:-${BUILD_OUT}/initramfs-proper.cpio.gz}"
[ -f "${INITRAMFS}" ] || INITRAMFS="${BUILD_OUT}/initramfs.cpio.gz"
echo "  kernel:    ${BUILD_OUT}/vmlinuz"
echo "  initramfs: ${INITRAMFS}"
echo "  memory:    ${MEMORY_MB}MB"
echo "  Ctrl-A X  to quit QEMU"
echo ""

QEMU_CPU=""
if [ -z "${CPU}" ]; then
  QEMU_CPU="-cpu max"
elif [ -n "${CPU}" ]; then
  QEMU_CPU="-cpu ${CPU}"
fi

qemu-system-aarch64 \
  -M virt \
  -accel "${ACCEL}" \
  ${QEMU_CPU} \
  -m "${MEMORY_MB}" \
  -smp 2 \
  -nographic \
  -no-reboot \
  -kernel "${BUILD_OUT}/vmlinuz" \
  -initrd "${INITRAMFS}" \
  -append "console=ttyAMA0,115200 init=/init quiet"

echo ""
echo "QEMU exited."
