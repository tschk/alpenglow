#!/bin/sh
# Build + boot Alpenglow to a shell.
# Requires: apk (Alpine) or docker, qemu-system-x86_64, curl.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/build/shell"
ROOTFS_DIR="${OUT_DIR}/rootfs"
QEMU_DIR="${OUT_DIR}/qemu"
KERNEL="${QEMU_DIR}/vmlinuz-virt"
INITRAMFS="${QEMU_DIR}/rootfs.cpio.gz"

ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
ARCH="${QEMU_ARCH:-x86_64}"
MEMORY_MB="${MEMORY_MB:-2048}"
ACCEL="${ACCEL:-tcg}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }
}

mkdir -p "${OUT_DIR}" "${ROOTFS_DIR}" "${QEMU_DIR}"

echo "=== Alpenglow shell boot ==="
echo ""

# ── 1. Fetch kernel ────────────────────────────────────────────────
if [ ! -f "${KERNEL}" ]; then
  require_cmd curl
  echo "→ Fetching Alpine virt kernel..."
  BASE="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/netboot"
  curl -#fsSL "${BASE}/vmlinuz-virt" -o "${KERNEL}"
else
  echo "→ Kernel exists: ${KERNEL}"
fi

# ── 2. Build minimal rootfs ────────────────────────────────────────
if [ ! -f "${ROOTFS_DIR}/bin/busybox" ]; then
  echo "→ Building minimal rootfs..."
  rm -rf "${ROOTFS_DIR}"
  mkdir -p "${ROOTFS_DIR}"

  if command -v apk >/dev/null 2>&1; then
    apk --root "${ROOTFS_DIR}" --initdb add \
      --arch "${ARCH}" \
      --repository "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main" \
      alpine-baselayout busybox
  elif command -v docker >/dev/null 2>&1; then
    require_cmd docker
    docker run --rm -v "${ROOTFS_DIR}:/rootfs" "alpine:${ALPINE_VERSION}" sh -c "
      apk add --root /rootfs --initdb alpine-baselayout busybox
    "
  else
    echo "ERROR: need apk or docker to build rootfs" >&2
    exit 1
  fi

  # Remove default init, install our shell launcher
  rm -f "${ROOTFS_DIR}/sbin/init"
  cat > "${ROOTFS_DIR}/etc/inittab" << 'INITTAB'
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev
::wait:/bin/sh -l
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/halt
INITTAB

  # Ensure /dev/console exists for the serial console
  mkdir -p "${ROOTFS_DIR}/dev"
  mknod -m 622 "${ROOTFS_DIR}/dev/console" c 5 1 2>/dev/null || true

  rm -f "${ROOTFS_DIR}/init"
else
  echo "→ Rootfs exists: ${ROOTFS_DIR}"
fi

# ── 3. Build initramfs ─────────────────────────────────────────────
echo "→ Building initramfs..."
(
  cd "${ROOTFS_DIR}"
  find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "${INITRAMFS}"
)
echo "  Size: $(du -sh "${INITRAMFS}" | cut -f1)"

# ── 4. Boot QEMU ───────────────────────────────────────────────────
require_cmd qemu-system-x86_64
echo ""
echo "→ Launching QEMU (console on stdio)..."
echo "  kernel:   ${KERNEL}"
echo "  memory:   ${MEMORY_MB}MB"
echo "  accel:    ${ACCEL}"
echo ""
echo "  Type Ctrl-A X to quit QEMU."
echo ""

qemu-system-x86_64 \
  -machine q35,accel="${ACCEL}" \
  -m "${MEMORY_MB}" \
  -smp 2 \
  -serial mon:stdio \
  -nographic \
  -no-reboot \
  -kernel "${KERNEL}" \
  -initrd "${INITRAMFS}" \
  -append "console=ttyS0 quiet"

echo ""
echo "QEMU exited."
