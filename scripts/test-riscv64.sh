#!/bin/sh
# QEMU riscv64 boot test with OpenSBI — builds cross components, boots, verifies init output
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/build/cross/riscv64"
TIMEOUT="${TIMEOUT:-20}"
EXPECTED="Alpenglow Zig init boot OK"

fail() { echo "FAIL: $1" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "missing: $1"; }

require_cmd qemu-system-riscv64
require_cmd zig

echo "=== riscv64 QEMU boot test (OpenSBI) ==="

# Find OpenSBI firmware
find_opensbi() {
  for p in \
    "/opt/homebrew/share/opensbi/lp64/generic/firmware/fw_dynamic.bin" \
    "/usr/share/opensbi/lp64/generic/firmware/fw_dynamic.bin" \
    "/usr/local/share/opensbi/lp64/generic/firmware/fw_dynamic.bin" \
    "${REPO_ROOT}/build/opensbi/fw_dynamic.bin"; do
    [ -f "$p" ] && echo "$p" && return
  done
  return 1
}

OPENSBI=$(find_opensbi || true)
if [ -z "${OPENSBI}" ]; then
  echo "→ OpenSBI not found — downloading..."
  mkdir -p "${REPO_ROOT}/build/opensbi"
  curl -#fsSL "https://github.com/riscv-software-src/opensbi/releases/download/v1.5/opensbi-1.5-rv-bin.tar.xz" \
    -o /tmp/opensbi.tar.xz 2>/dev/null && \
    tar -xJf /tmp/opensbi.tar.xz -C "${REPO_ROOT}/build/opensbi" --strip-components=1 2>/dev/null && \
    OPENSBI=$(find_opensbi || true)
  rm -f /tmp/opensbi.tar.xz
fi

if [ -z "${OPENSBI}" ]; then
  fail "OpenSBI firmware not found. Install it:\n  brew install opensbi\n  apt-get install opensbi\nOr download from https://github.com/riscv-software-src/opensbi/releases"
fi
echo "  OpenSBI: ${OPENSBI}"

# Build cross components + initramfs (if not already built)
if [ ! -f "${OUT_DIR}/initramfs.cpio.gz" ]; then
  "${REPO_ROOT}/scripts/build-riscv64.sh" 2>&1 | tail -3
fi

[ -f "${OUT_DIR}/init" ]             || fail "init binary not found — run build-riscv64.sh first"
[ -f "${OUT_DIR}/vmlinuz" ]          || fail "kernel not found — run build-riscv64.sh first"
[ -f "${OUT_DIR}/initramfs.cpio.gz" ]|| fail "initramfs not found — run build-riscv64.sh first"

echo "→ Booting QEMU riscv64 virt (timeout: ${TIMEOUT}s)..."

OUTPUT=$(timeout "${TIMEOUT}" qemu-system-riscv64 \
  -M virt -m 2G \
  -bios "${OPENSBI}" \
  -kernel "${OUT_DIR}/vmlinuz" \
  -initrd "${OUT_DIR}/initramfs.cpio.gz" \
  -append "console=ttyS0,115200 init=/init loglevel=8" \
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
