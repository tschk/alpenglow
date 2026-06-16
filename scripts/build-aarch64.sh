#!/bin/sh
# Build Alpenglow aarch64 components: Zig init + kernelctl, kernel fetch, initramfs.
# Requires: zig, curl, cpio, gzip
# For QEMU: qemu-system-aarch64
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_OUT="${REPO_ROOT}/build/cross/aarch64"
FORCE="${FORCE:-0}"
ALPINE_VERSION="${ALPINE_VERSION:-3.21}"

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    *) echo "Usage: $0 [--force]"; exit 1 ;;
  esac
  shift
done

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }

mkdir -p "${BUILD_OUT}"

echo "=== Alpenglow aarch64 build ==="

# ── 1. Cross-compile Zig init ─────────────────────────────────────
ZIG_INIT="${BUILD_OUT}/zig-init"
if [ ! -f "${ZIG_INIT}" ] || [ "${FORCE}" = "1" ]; then
  echo "→ Cross-compiling Zig init for aarch64-linux-musl..."
  require_cmd zig
  cd "${REPO_ROOT}/system/init"
  zig build-exe init.zig -target aarch64-linux-musl -O ReleaseSmall -fstrip -femit-bin="${ZIG_INIT}" 2>&1
  echo "  ${ZIG_INIT}"
else
  echo "→ Zig init exists (${ZIG_INIT}), --force to rebuild"
fi
file "${ZIG_INIT}" | grep -q aarch64 || { echo "ERROR: init not aarch64"; exit 1; }

# ── 2. Cross-compile kernelctl-zig ─────────────────────────────────
KERNELCTL="${BUILD_OUT}/alpenglow-kernelctl"
if [ ! -f "${KERNELCTL}" ] || [ "${FORCE}" = "1" ]; then
  echo "→ Cross-compiling kernelctl-zig for aarch64-linux-musl..."
  require_cmd zig
  cd "${REPO_ROOT}/system/kernelctl-zig"
  rm -rf zig-out .zig-cache
  zig build -Dtarget=aarch64-linux-musl -Drelease=true 2>&1
  cp zig-out/bin/alpenglow-kernelctl "${KERNELCTL}"
  rm -rf zig-out .zig-cache
  echo "  ${KERNELCTL}"
else
  echo "→ kernelctl exists (${KERNELCTL}), --force to rebuild"
fi
file "${KERNELCTL}" | grep -q aarch64 || { echo "ERROR: kernelctl not aarch64"; exit 1; }

# ── 3. Fetch Alpine aarch64 virt kernel ────────────────────────────
KERNEL="${BUILD_OUT}/vmlinuz-virt"
if [ ! -f "${KERNEL}" ] || [ "${FORCE}" = "1" ]; then
  echo "→ Fetching Alpine aarch64 virt kernel..."
  require_cmd curl
  KERNEL_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/aarch64/netboot/vmlinuz-virt"
  curl -#fSL "${KERNEL_URL}" -o "${KERNEL}"
  echo "  ${KERNEL}"
else
  echo "→ Kernel exists (${KERNEL}), --force to re-fetch"
fi

# ── 4. Build initramfs ────────────────────────────────────────────
INITRAMFS="${BUILD_OUT}/initramfs.cpio.gz"
if [ ! -f "${INITRAMFS}" ] || [ "${FORCE}" = "1" ]; then
  echo "→ Building initramfs..."
  INITRAMFS_DIR=$(mktemp -d)
  cp "${ZIG_INIT}" "${INITRAMFS_DIR}/init"
  chmod 755 "${INITRAMFS_DIR}/init"
  cd "${INITRAMFS_DIR}"
  find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${INITRAMFS}"
  rm -rf "${INITRAMFS_DIR}"
  echo "  ${INITRAMFS}"
else
  echo "→ Initramfs exists (${INITRAMFS}), --force to rebuild"
fi

echo ""
echo "=== Build complete ==="
ls -lh "${BUILD_OUT}/zig-init" "${BUILD_OUT}/alpenglow-kernelctl" "${BUILD_OUT}/vmlinuz-virt" "${BUILD_OUT}/initramfs.cpio.gz"
echo ""
echo "To boot in QEMU:"
echo "  ${REPO_ROOT}/scripts/qemu-boot-aarch64.sh"
