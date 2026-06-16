#!/bin/sh
# QEMU aarch64 boot test — builds cross components, boots in virt, verifies init output
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/build/cross/aarch64"
TIMEOUT="${TIMEOUT:-15}"
EXPECTED="Alpenglow Zig init boot OK"

fail() { echo "FAIL: $1" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "missing: $1"; }

require_cmd qemu-system-aarch64
require_cmd zig

echo "=== aarch64 QEMU boot test ==="

# Build cross components + initramfs (if not already built)
if [ ! -f "${OUT_DIR}/initramfs.cpio.gz" ]; then
  "${REPO_ROOT}/scripts/build-aarch64.sh" 2>&1 | tail -3
fi

# build-aarch64.sh outputs zig-init, alpenglow-kernelctl, vmlinuz-virt, initramfs.cpio.gz
[ -f "${OUT_DIR}/zig-init" ]         || fail "init binary not found — run build-aarch64.sh first"
[ -f "${OUT_DIR}/vmlinuz-virt" ]    || fail "kernel not found — run build-aarch64.sh first"
[ -f "${OUT_DIR}/initramfs.cpio.gz" ]|| fail "initramfs not found — run build-aarch64.sh first"

echo "→ Booting QEMU aarch64 virt (timeout: ${TIMEOUT}s)..."

OUTPUT=$(timeout "${TIMEOUT}" qemu-system-aarch64 \
  -M virt -cpu max -m 2G \
  -kernel "${OUT_DIR}/vmlinuz-virt" \
  -initrd "${OUT_DIR}/initramfs.cpio.gz" \
  -append "console=ttyAMA0,115200 init=/init loglevel=8" \
  -nographic -no-reboot \
  2>&1) || true

echo "${OUTPUT}" | grep -q "${EXPECTED}" && {
  echo "✓ PASS: '${EXPECTED}' found in serial output"
  exit 0
}

echo "✗ FAIL: '${EXPECTED}' not found"
echo "  Last 30 lines of serial output:"
echo "${OUTPUT}" | tail -30
exit 1
