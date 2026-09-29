#!/bin/sh
# Build Alpenglow riscv64 userspace (Zig init + alpenglow-ctl) and an initramfs.
# The kernel is not built here: cross-compiling Linux needs a toolchain this
# host does not have. Point ALPENGLOW_RISCV64_KERNEL at an Image to stage one.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/build/cross/riscv64"
FORCE="${FORCE:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    *) echo "Usage: $0 [--force]" >&2; exit 1 ;;
  esac
  shift
done

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
require_cmd zig

mkdir -p "${OUT_DIR}"
echo "=== Alpenglow riscv64 build ==="

ZIG_INIT="${OUT_DIR}/zig-init"
if [ ! -f "${ZIG_INIT}" ] || [ "${FORCE}" = "1" ]; then
  echo "→ Cross-compiling Zig init for riscv64-linux-musl..."
  zig build-exe "${REPO_ROOT}/system/init/init.zig" \
    -target riscv64-linux-musl -O ReleaseSmall -fstrip \
    -femit-bin="${ZIG_INIT}"
fi
file "${ZIG_INIT}" | grep -q 'RISC-V' || { echo "ERROR: init not RISC-V" >&2; exit 1; }
echo "  ${ZIG_INIT}"

KERNELCTL="${OUT_DIR}/alpenglow-kernelctl"
if [ ! -f "${KERNELCTL}" ] || [ "${FORCE}" = "1" ]; then
  echo "→ Cross-compiling alpenglow-ctl for riscv64-linux-musl..."
  (
    cd "${REPO_ROOT}/system/alpenglow-ctl"
    rm -rf zig-out .zig-cache
    zig build -Dtarget=riscv64-linux-musl -Drelease=true
    cp zig-out/bin/alpenglow-kernelctl "${KERNELCTL}"
    rm -rf zig-out .zig-cache
  )
fi
file "${KERNELCTL}" | grep -q 'RISC-V' || { echo "ERROR: kernelctl not RISC-V" >&2; exit 1; }
echo "  ${KERNELCTL}"

KERNEL="${OUT_DIR}/Image"
if [ -n "${ALPENGLOW_RISCV64_KERNEL:-}" ]; then
  cp "${ALPENGLOW_RISCV64_KERNEL}" "${KERNEL}"
  echo "  staged kernel ${KERNEL}"
elif [ ! -f "${KERNEL}" ]; then
  echo "  no kernel staged. Set ALPENGLOW_RISCV64_KERNEL=/path/to/Image to boot."
fi

INITRAMFS="${OUT_DIR}/initramfs.cpio.gz"
if [ ! -f "${INITRAMFS}" ] || [ "${FORCE}" = "1" ]; then
  echo "→ Building initramfs..."
  INITRAMFS_DIR="$(mktemp -d)"
  cp "${ZIG_INIT}" "${INITRAMFS_DIR}/init"
  chmod 755 "${INITRAMFS_DIR}/init"
  (cd "${INITRAMFS_DIR}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${INITRAMFS}")
  rm -rf "${INITRAMFS_DIR}"
fi
echo "  ${INITRAMFS}"

echo ""
echo "=== riscv64 build complete ==="
ls -lh "${ZIG_INIT}" "${KERNELCTL}" "${INITRAMFS}"
echo "Boot (needs a staged kernel): ${REPO_ROOT}/scripts/qemu-boot-riscv64.sh"
