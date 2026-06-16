#!/bin/sh
# Build Alpenglow riscv64 cross-compiled components + initramfs
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/build/cross/riscv64"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }

mkdir -p "${OUT_DIR}"

echo "=== riscv64 cross-build ==="

# ── 1. Zig cross-compile ──────────────────────────────────────────
build_zig() {
  echo "→ Cross-compiling Zig init..."
  cd "${REPO_ROOT}/system/init"
  zig build-exe -target riscv64-linux-musl -O ReleaseSmall -fstrip \
    -femit-bin="${OUT_DIR}/zig-init" init.zig --name zig-init

  echo "→ Cross-compiling kernelctl-zig..."
  cd "${REPO_ROOT}/system/kernelctl-zig"
  zig build -Dtarget=riscv64-linux-musl -Drelease=true
  find .zig-cache -name "alpenglow-kernelctl" -type f \
    -exec cp {} "${OUT_DIR}/alpenglow-kernelctl" \;

  echo "→ Cross-compiling glowfsctl-zig..."
  cd "${REPO_ROOT}/system/glowfsctl-zig"
  zig build -Dtarget=riscv64-linux-musl -Drelease=true
  find .zig-cache -name "glowfsctl" -type f \
    -exec cp {} "${OUT_DIR}/glowfsctl" \; 2>/dev/null || true

  echo "  binaries:"
  file "${OUT_DIR}"/zig-init "${OUT_DIR}"/alpenglow-kernelctl 2>/dev/null
}

# ── 2. Fetch or build riscv64 kernel ──────────────────────────────
fetch_kernel() {
  if [ -f "${OUT_DIR}/vmlinuz" ]; then
    echo "  kernel exists: ${OUT_DIR}/vmlinuz"
    return
  fi

  echo "→ Fetching riscv64 kernel from Alpine U-Boot image..."
  UBOWL_TMP=$(mktemp -d)
  trap 'rm -rf "${UBOWL_TMP}"' EXIT

  curl -#fsSL \
    "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/riscv64/alpine-uboot-3.21.7-riscv64.tar.gz" \
    -o "${UBOWL_TMP}/alpine-uboot.tar.gz"

  tar -xzf "${UBOWL_TMP}/alpine-uboot.tar.gz" -C "${UBOWL_TMP}" boot/vmlinuz-lts 2>/dev/null
  if [ -f "${UBOWL_TMP}/boot/vmlinuz-lts" ]; then
    # Alpine kernel is gzip-compressed
    gunzip -c "${UBOWL_TMP}/boot/vmlinuz-lts" > "${OUT_DIR}/vmlinuz" 2>/dev/null || \
      cp "${UBOWL_TMP}/boot/vmlinuz-lts" "${OUT_DIR}/vmlinuz"
    echo "  kernel: ${OUT_DIR}/vmlinuz ($(du -sh "${OUT_DIR}/vmlinuz" | cut -f1))"
  else
    echo "  WARNING: could not fetch riscv64 kernel"
    echo "  Build manually: scripts/cross-build.sh riscv64-linux-musl"
  fi
  rm -rf "${UBOWL_TMP}"
  trap '' EXIT
}

# ── 3. Build initramfs ────────────────────────────────────────────
build_initramfs() {
  echo "→ Building initramfs..."
  local INITRAMFS_DIR=$(mktemp -d)
  trap 'rm -rf "${INITRAMFS_DIR}"' EXIT

  mkdir -p "${INITRAMFS_DIR}"/{bin,dev,etc,proc,sys,tmp}

  # Zig init as /init
  cp "${OUT_DIR}/zig-init" "${INITRAMFS_DIR}/init"
  chmod 755 "${INITRAMFS_DIR}/init"

  # Console device
  mknod -m 622 "${INITRAMFS_DIR}/dev/console" c 5 1 2>/dev/null || true

  # Pack
  cd "${INITRAMFS_DIR}"
  find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT_DIR}/initramfs.cpio.gz"
  echo "  initramfs: ${OUT_DIR}/initramfs.cpio.gz ($(du -sh "${OUT_DIR}/initramfs.cpio.gz" | cut -f1))"
}

# ── Main ──────────────────────────────────────────────────────────
if command -v zig >/dev/null 2>&1; then
  build_zig
else
  echo "ERROR: zig required" >&2
  exit 1
fi

fetch_kernel
build_initramfs

echo ""
echo "=== riscv64 cross-build complete ==="
ls -lh "${OUT_DIR}/" 2>/dev/null | grep -v kernel-src
