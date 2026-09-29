#!/bin/sh
# Build Alpenglow aarch64 components: Zig init + kernelctl + initramfs.
# Requires: zig, cpio, gzip
# For QEMU: qemu-system-aarch64
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_OUT="${REPO_ROOT}/build/cross/aarch64"
FORCE="${FORCE:-0}"
ALPENGLOW_AARCH64_KERNEL="${ALPENGLOW_AARCH64_KERNEL:-}"

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

# ── 2. Cross-compile alpenglow-ctl (kernel compat binary) ──────────
KERNELCTL="${BUILD_OUT}/alpenglow-kernelctl"
if [ ! -f "${KERNELCTL}" ] || [ "${FORCE}" = "1" ]; then
  echo "→ Cross-compiling alpenglow-ctl for aarch64-linux-musl..."
  require_cmd zig
  cd "${REPO_ROOT}/system/alpenglow-ctl"
  rm -rf zig-out .zig-cache
  zig build -Dtarget=aarch64-linux-musl -Drelease=true 2>&1
  cp zig-out/bin/alpenglow-kernelctl "${KERNELCTL}"
  rm -rf zig-out .zig-cache
  echo "  ${KERNELCTL}"
else
  echo "→ kernelctl exists (${KERNELCTL}), --force to rebuild"
fi
file "${KERNELCTL}" | grep -q aarch64 || { echo "ERROR: kernelctl not aarch64"; exit 1; }

# ── 3. Stage an aarch64 kernel if one was given ────────────────────
# Cross-compiling the kernel needs a toolchain this host does not have, so a
# missing kernel is not a build failure. qemu-boot-aarch64.sh checks for it.
KERNEL="${BUILD_OUT}/vmlinuz"
if [ -n "${ALPENGLOW_AARCH64_KERNEL}" ]; then
  cp "${ALPENGLOW_AARCH64_KERNEL}" "${KERNEL}"
  echo "  staged kernel ${KERNEL}"
elif [ -f "${KERNEL}" ]; then
  echo "→ Kernel exists (${KERNEL})"
else
  echo "  no kernel staged. Set ALPENGLOW_AARCH64_KERNEL=/path/to/Image to boot."
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
ls -lh "${BUILD_OUT}/zig-init" "${BUILD_OUT}/alpenglow-kernelctl" "${BUILD_OUT}/initramfs.cpio.gz"
[ -f "${BUILD_OUT}/vmlinuz" ] && ls -lh "${BUILD_OUT}/vmlinuz"
echo ""
echo "To boot in QEMU:"
echo "  ${REPO_ROOT}/scripts/qemu-boot-aarch64.sh"
