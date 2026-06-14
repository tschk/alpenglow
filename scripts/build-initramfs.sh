#!/bin/sh
# Build the Alpenglow initramfs cpio archive.
# Combines kernel image + initramfs for diskless boot.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
OUT_DIR="${ROOT_DIR}/build/appliance"
INITRAMFS_DIR="${OUT_DIR}/initramfs"
INITRAMFS_CPIO="${OUT_DIR}/initramfs.cpio.zst"
KERNEL_IMAGE="${OUT_DIR}/vmlinuz"
UKI_IMAGE="${OUT_DIR}/alpenglow.efi"

ALPENGLOW_ARCH="${ALPENGLOW_ARCH:-$(uname -m)}"
KERNEL_SRC="${KERNEL_SRC:-${ROOT_DIR}/system/alpine/kernel}"
KERNEL_CONFIG="${KERNEL_CONFIG:-${KERNEL_SRC}/alpenglow-internet-appliance.config}"
GLOWFS_IMAGE="${GLOWFS_IMAGE:-${OUT_DIR}/alpenglow-root.glowfs}"

mkdir -p "${INITRAMFS_DIR}" "${OUT_DIR}"

echo "Alpenglow initramfs build"
echo "  arch:    ${ALPENGLOW_ARCH}"
echo "  kernel:  ${KERNEL_CONFIG}"
echo "  image:   ${GLOWFS_IMAGE}"
echo ""

# ── Phase 1: Stage initramfs files ──────────────────────────────────
echo "→ Staging initramfs..."

# Base directories
for d in bin dev etc lib/modules mnt/root proc run sys sysroot tmp; do
  mkdir -p "${INITRAMFS_DIR}/${d}"
done

# Init script
cp "${BACKEND_DIR}/initramfs/init" "${INITRAMFS_DIR}/init"
chmod 755 "${INITRAMFS_DIR}/init"

# Busybox or toybox for initramfs utilities
if command -v busybox >/dev/null 2>&1; then
  cp "$(command -v busybox)" "${INITRAMFS_DIR}/bin/busybox"
  for applet in sh mount umount modprobe insmod ls cat cp mkdir ln switch_root sleep; do
    ln -sf busybox "${INITRAMFS_DIR}/bin/${applet}"
  done
elif command -v toybox >/dev/null 2>&1; then
  cp "$(command -v toybox)" "${INITRAMFS_DIR}/bin/toybox"
  ln -sf toybox "${INITRAMFS_DIR}/bin/sh"
  # toybox has symlinks for all applets via its multicall binary
fi

# Copy GlowFS kernel module if built
GLOWFS_KO="${ROOT_DIR}/target/release/glowfs.ko"
if [ -f "${GLOWFS_KO}" ]; then
  mkdir -p "${INITRAMFS_DIR}/lib/modules"
  cp "${GLOWFS_KO}" "${INITRAMFS_DIR}/lib/modules/"
fi

# ── Phase 2: Build kernel (if source available) ─────────────────────
if [ -d "${KERNEL_SRC}/linux" ]; then
  echo "→ Building kernel..."
  make -C "${KERNEL_SRC}/linux" \
    ARCH="${ALPENGLOW_ARCH}" \
    KCONFIG_CONFIG="${KERNEL_CONFIG}" \
    -j"$(nproc)" \
    bzImage 2>&1 | tail -5

  cp "${KERNEL_SRC}/linux/arch/${ALPENGLOW_ARCH}/boot/bzImage" "${KERNEL_IMAGE}"
  echo "  kernel: ${KERNEL_IMAGE}"
else
  echo "  (kernel source not at ${KERNEL_SRC}/linux — using prebuilt)"
  # Use prebuilt kernel if available
  if [ -f "${OUT_DIR}/vmlinuz" ]; then
    echo "  using existing: ${KERNEL_IMAGE}"
  else
    echo "  WARNING: no kernel image. Install kernel source at ${KERNEL_SRC}/linux" >&2
  fi
fi

# ── Phase 3: Build initramfs cpio ───────────────────────────────────
echo "→ Building initramfs cpio..."

cd "${INITRAMFS_DIR}"
find . -print0 | cpio --null -o --format=newc 2>/dev/null | zstd -19 -o "${INITRAMFS_CPIO}" -
echo "  initramfs: ${INITRAMFS_CPIO} ($(du -sh "${INITRAMFS_CPIO}" | cut -f1))"

# ── Phase 4: Build unified kernel image (optional) ──────────────────
if command -v ukify >/dev/null 2>&1 && [ -f "${KERNEL_IMAGE}" ] && [ -f "${GLOWFS_IMAGE}" ]; then
  echo "→ Building UKI..."
  ukify build \
    --linux="${KERNEL_IMAGE}" \
    --initrd="${INITRAMFS_CPIO}" \
    --cmdline="alpenglow.image=${GLOWFS_IMAGE} alpenglow.state=LABEL=alpenglow-state quiet" \
    --output="${UKI_IMAGE}"
  echo "  uki: ${UKI_IMAGE}"
fi

cd "${ROOT_DIR}"
echo ""
echo "✓ Build complete"
echo "  To boot (QEMU):"
echo "    qemu-system-${ALPENGLOW_ARCH} -m 4G -kernel ${KERNEL_IMAGE} -initrd ${INITRAMFS_CPIO} -append \"alpenglow.image=${GLOWFS_IMAGE} quiet\""
echo ""
echo "  To boot (UEFI, if UKI built):"
echo "    qemu-system-${ALPENGLOW_ARCH} -m 4G -bios /usr/share/edk2/x64/OVMF.fd -kernel ${UKI_IMAGE}"
