#!/bin/sh
# Build Alpenglow riscv64 cross-compiled components + initramfs
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/build/cross/riscv64"
ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
ALPINE_BASE="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/riscv64/netboot"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }

mkdir -p "${OUT_DIR}"

echo "=== riscv64 cross-build ==="

# 1. Zig cross-compile
if command -v zig >/dev/null 2>&1; then
  echo "→ Cross-compiling Zig init..."
  zig build-exe -target riscv64-linux-musl -O ReleaseSmall -fstrip \
    -femit-bin="${OUT_DIR}/init" \
    "${REPO_ROOT}/system/init/init.zig"

  echo "→ Cross-compiling kernelctl-zig..."
  (cd "${REPO_ROOT}/system/kernelctl-zig" && \
    zig build -Dtarget=riscv64-linux-musl -Drelease=true && \
    cp zig-out/bin/alpenglow-kernelctl "${OUT_DIR}/kernelctl")

  echo "→ Cross-compiling glowfsctl-zig..."
  (cd "${REPO_ROOT}/system/glowfsctl-zig" && \
    zig build -Dtarget=riscv64-linux-musl -Drelease=true && \
    cp zig-out/bin/glowfsctl "${OUT_DIR}/glowfsctl")

  echo "  binaries:"
  file "${OUT_DIR}"/init "${OUT_DIR}"/kernelctl "${OUT_DIR}"/glowfsctl 2>/dev/null
else
  echo "  zig not installed — skipping Zig components"
fi

# 2. Fetch riscv64 kernel
echo "→ Fetching riscv64 virt kernel..."
if [ ! -f "${OUT_DIR}/vmlinuz" ]; then
  # Try Alpine first, then Fedora, then build from source
  curl -#fsSL "${ALPINE_BASE}/vmlinuz-virt" -o "${OUT_DIR}/vmlinuz" 2>/dev/null || {
    echo "  Alpine kernel not available — trying Fedora..."
    curl -#fsSL "https://kojipkgs.fedoraproject.org/packages/kernel/6.8/1.riscv64.fc40/images/kernel-vmlinuz" \
      -o "${OUT_DIR}/vmlinuz" 2>/dev/null || {
      echo "  WARNING: could not fetch prebuilt riscv64 kernel"
      echo "  Build manually: scripts/cross-build.sh riscv64-linux-musl"
      rm -f "${OUT_DIR}/vmlinuz"
    }
  }
else
  echo "  exists: ${OUT_DIR}/vmlinuz"
fi

# 3. Fetch riscv64 busybox (try Alpine APK or fall back)
echo "→ Looking for riscv64 busybox..."
if [ ! -f "${OUT_DIR}/busybox" ]; then
  # Try Alpine's busybox-static APK for riscv64
  APK_INDEX="${ALPINE_BASE}/APKINDEX.tar.gz"
  APK_TMP=$(mktemp -d)
  if curl -#fsSL "${APK_INDEX}" -o "${APK_TMP}/APKINDEX.tar.gz" 2>/dev/null; then
    tar -xzf "${APK_TMP}/APKINDEX.tar.gz" -C "${APK_TMP}" 2>/dev/null || true
    PKG=$(grep -l 'P:busybox-static' "${APK_TMP}"/*.PKGINFO 2>/dev/null | head -1)
    if [ -n "${PKG}" ]; then
      VER=$(sed -n 's/^V://p' "${PKG}" | tr -d ' ')
      curl -#fsSL "${ALPINE_BASE}/busybox-static-${VER}.apk" -o "${APK_TMP}/bb.apk" && \
        tar -xzf "${APK_TMP}/bb.apk" -C "${APK_TMP}" && \
        cp "${APK_TMP}/bin/busybox-static" "${OUT_DIR}/busybox" && \
        chmod 755 "${OUT_DIR}/busybox"
    fi
  fi
  rm -rf "${APK_TMP}"
  if [ ! -f "${OUT_DIR}/busybox" ]; then
    echo "  (no riscv64 busybox available — initramfs will have Zig init only)"
  fi
else
  echo "  exists: ${OUT_DIR}/busybox"
fi

# 4. Build initramfs
echo "→ Building initramfs..."
INITRAMFS_DIR=$(mktemp -d)
trap 'rm -rf "${INITRAMFS_DIR}"' EXIT

mkdir -p "${INITRAMFS_DIR}/bin" "${INITRAMFS_DIR}/dev" "${INITRAMFS_DIR}/etc" "${INITRAMFS_DIR}/proc" "${INITRAMFS_DIR}/sys" "${INITRAMFS_DIR}/tmp"

# Zig init as /init
cp "${OUT_DIR}/init" "${INITRAMFS_DIR}/init"
chmod 755 "${INITRAMFS_DIR}/init"

# Busybox if available
if [ -f "${OUT_DIR}/busybox" ]; then
  cp "${OUT_DIR}/busybox" "${INITRAMFS_DIR}/bin/busybox"
  for applet in sh mount umount cat ls mkdir ln switch_root modprobe; do
    ln -sf busybox "${INITRAMFS_DIR}/bin/${applet}"
  done
fi

# Console device
mknod -m 622 "${INITRAMFS_DIR}/dev/console" c 5 1 2>/dev/null || true

# Pack
cd "${INITRAMFS_DIR}"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${OUT_DIR}/initramfs.cpio.gz"
echo "  initramfs: ${OUT_DIR}/initramfs.cpio.gz ($(du -sh "${OUT_DIR}/initramfs.cpio.gz" | cut -f1))"

echo ""
echo "=== riscv64 cross-build complete ==="
ls -lh "${OUT_DIR}/" 2>/dev/null
