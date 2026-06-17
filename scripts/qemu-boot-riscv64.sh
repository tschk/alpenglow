#!/bin/sh
# QEMU riscv64 boot test with OpenSBI — builds cross components, boots, verifies init output
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/build/cross/riscv64"
TIMEOUT_SEC="${TIMEOUT:-30}"
EXPECTED="Alpenglow Zig init boot OK"

fail() { echo "FAIL: $1" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "missing: $1"; }

require_cmd qemu-system-riscv64
require_cmd zig

echo "=== riscv64 QEMU boot test (OpenSBI) ==="

# ── 1. Find OpenSBI firmware ─────────────────────────────────────
find_opensbi() {
  for p in \
    "/opt/homebrew/share/qemu/opensbi-riscv64-generic-fw_dynamic.bin" \
    "/usr/share/qemu/opensbi-riscv64-generic-fw_dynamic.bin" \
    "/opt/homebrew/share/opensbi/lp64/generic/firmware/fw_dynamic.bin" \
    "/usr/share/opensbi/lp64/generic/firmware/fw_dynamic.bin" \
    "/usr/local/share/opensbi/lp64/generic/firmware/fw_dynamic.bin"; do
    [ -f "$p" ] && echo "$p" && return
  done
  return 1
}

OPENSBI=$(find_opensbi || true)
if [ -z "${OPENSBI}" ]; then
  echo "→ OpenSBI not found — downloading..."
  mkdir -p "${REPO_ROOT}/build/opensbi"
  curl -#fsSL \
    "https://github.com/riscv-software-src/opensbi/releases/download/v1.5/opensbi-1.5-rv-bin.tar.xz" \
    -o /tmp/opensbi.tar.xz 2>/dev/null && \
    tar -xJf /tmp/opensbi.tar.xz -C "${REPO_ROOT}/build/opensbi" --strip-components=1 2>/dev/null && \
    OPENSBI=$(find_opensbi || true)
  rm -f /tmp/opensbi.tar.xz
fi

if [ -z "${OPENSBI}" ]; then
  fail "OpenSBI firmware not found. Try: brew install opensbi (macOS) or apt install opensbi (Debian)"
fi
echo "  OpenSBI: ${OPENSBI}"

# ── 2. Build components if needed ────────────────────────────────
if [ ! -f "${OUT_DIR}/initramfs.cpio.gz" ] || [ ! -f "${OUT_DIR}/Image" ]; then
  echo "→ Building cross components..."
  "${REPO_ROOT}/scripts/build-riscv64.sh" 2>&1 | tail -3
fi

[ -f "${OUT_DIR}/zig-init" ]          || fail "init not found — run build-riscv64.sh first"
[ -f "${OUT_DIR}/Image" ]            || fail "kernel not found — run build-riscv64.sh first"
[ -f "${OUT_DIR}/initramfs.cpio.gz" ] || fail "initramfs not found — run build-riscv64.sh first"

# ── 3. Boot and verify ───────────────────────────────────────────
echo "→ Booting QEMU riscv64 virt (timeout: ${TIMEOUT_SEC}s)..."
echo "  kernel:    ${OUT_DIR}/Image"
echo "  initramfs: ${OUT_DIR}/initramfs.cpio.gz"
echo ""

OUTPUT=$(gtimeout "${TIMEOUT_SEC}" qemu-system-riscv64 \
  -M virt \
  -cpu max \
  -m 2G \
  -smp 2 \
  -bios "${OPENSBI}" \
  -kernel "${OUT_DIR}/Image" \
  -initrd "${OUT_DIR}/initramfs.cpio.gz" \
  -append "earlycon=sbi console=ttyS0,115200 init=/init loglevel=8" \
  -nographic \
  -no-reboot \
  2>&1) || true

if echo "${OUTPUT}" | grep -q "${EXPECTED}"; then
  echo "✓ PASS: '${EXPECTED}' found in serial output"
  echo ""
  echo "  Boot trace (last 8 lines):"
  echo "${OUTPUT}" | grep -E "(Run /init|Alpenglow|login:|reboot)" 
  exit 0
fi

echo "✗ FAIL: '${EXPECTED}' not found"
echo "  Last 30 lines of serial output:"
echo "${OUTPUT}" | tail -30
exit 1
