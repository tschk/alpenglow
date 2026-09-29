#!/bin/sh
# Boot Alpenglow riscv64 in QEMU virt with OpenSBI.
# Builds userspace on demand. Needs a staged kernel at
# build/cross/riscv64/Image (see build-riscv64.sh).
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/build/cross/riscv64"
MEMORY_MB="${MEMORY_MB:-512}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
require_cmd qemu-system-riscv64

if [ ! -f "${OUT_DIR}/initramfs.cpio.gz" ]; then
  echo "→ no initramfs, building userspace..."
  "${REPO_ROOT}/scripts/build-riscv64.sh"
fi

KERNEL="${OUT_DIR}/Image"
if [ ! -f "${KERNEL}" ]; then
  echo "ERROR: ${KERNEL} not found." >&2
  echo "Cross-compiling the kernel needs a riscv64 toolchain. Stage one with:" >&2
  echo "  ALPENGLOW_RISCV64_KERNEL=/path/to/Image scripts/build-riscv64.sh" >&2
  exit 1
fi

OPENSBI=""
for p in \
  /opt/homebrew/share/qemu/opensbi-riscv64-generic-fw_dynamic.bin \
  /usr/share/qemu/opensbi-riscv64-generic-fw_dynamic.bin \
  /usr/share/opensbi/lp64/generic/firmware/fw_dynamic.bin; do
  [ -f "$p" ] && { OPENSBI="$p"; break; }
done
if [ -z "${OPENSBI}" ]; then
  echo "ERROR: OpenSBI firmware not found (ships with QEMU)." >&2
  exit 1
fi

echo "=== Alpenglow riscv64 QEMU boot ==="
echo "  kernel:    ${KERNEL}"
echo "  initramfs: ${OUT_DIR}/initramfs.cpio.gz"
echo "  opensbi:   ${OPENSBI}"
echo "  Ctrl-A X to quit"
echo ""

exec qemu-system-riscv64 \
  -M virt \
  -cpu max \
  -m "${MEMORY_MB}" \
  -smp 2 \
  -bios "${OPENSBI}" \
  -kernel "${KERNEL}" \
  -initrd "${OUT_DIR}/initramfs.cpio.gz" \
  -append "earlycon=sbi console=ttyS0,115200 init=/init" \
  -nographic \
  -no-reboot
