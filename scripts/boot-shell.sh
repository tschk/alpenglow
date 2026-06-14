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

  if command -v docker >/dev/null 2>&1; then
    require_cmd docker
    echo "  (using docker to bootstrap rootfs)"
    docker run --rm --platform linux/amd64 -v "${ROOTFS_DIR}:/rootfs" "alpine:${ALPINE_VERSION}" sh -c "
      mkdir -p /rootfs/etc/apk
      mkdir -p /rootfs/etc/apk/keys
      echo 'https://dl-cdn.alpinelinux.org/alpine/v3.21/main' > /rootfs/etc/apk/repositories
      echo 'https://dl-cdn.alpinelinux.org/alpine/v3.21/community' >> /rootfs/etc/apk/repositories
      cp -a /etc/apk/keys/. /rootfs/etc/apk/keys/ 2>/dev/null || true
      cd /rootfs && apk add --root /rootfs --initdb --update-cache alpine-baselayout busybox busybox-openrc 2>&1
    "
  elif command -v apk >/dev/null 2>&1; then
    apk --root \"${ROOTFS_DIR}\" --initdb add \\
  else
    echo "ERROR: need docker or apk to build rootfs" >&2
    exit 1
  fi

# Remove default init, install busybox init + shell
  rm -f "${ROOTFS_DIR}/sbin/init" 2>/dev/null || true
  # Create /init for the kernel to run
  cat > "${ROOTFS_DIR}/init" << 'INIT'
#!/bin/busybox sh
exec /bin/busybox init
INIT
  chmod 755 "${ROOTFS_DIR}/init"

  cat > "${ROOTFS_DIR}/etc/inittab" << 'INITTAB'
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/hostname -F /etc/hostname 2>/dev/null
ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100
tty1::respawn:/sbin/getty 38400 tty1
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::restart:/sbin/init
INITTAB
  echo "alpenglow" > "${ROOTFS_DIR}/etc/hostname"
  # Ensure busybox init knows about inittab
  ln -sf /bin/busybox "${ROOTFS_DIR}/sbin/init" 2>/dev/null || true
  # Ensure /dev/console exists
  mknod -m 622 "${ROOTFS_DIR}/dev/console" c 5 1 2>/dev/null || true
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
  -append "console=ttyS0 init=/init quiet"

echo ""
echo "QEMU exited."
