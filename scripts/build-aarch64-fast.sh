#!/bin/sh
# Build a proper Alpenglow aarch64 initramfs for the FAST config.
# Uses a static toybox binary and builds dinit in an arm64 Alpine container.
# Requires: docker, curl, qemu-system-aarch64 (for the macOS arm64 host)
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BACKEND_DIR="${REPO_ROOT}/system/backends/appliance"
BUILD_OUT="${REPO_ROOT}/build/cross/aarch64"
mkdir -p "${BUILD_OUT}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
require_cmd docker
require_cmd curl

# Toybox: download pre-built static musl binary
TOYBOX_BIN="${BUILD_OUT}/toybox-aarch64"
if [ ! -f "${TOYBOX_BIN}" ]; then
  echo "→ Downloading static toybox aarch64..."
  curl -fsSL -o "${TOYBOX_BIN}" "https://landley.net/bin/toybox/latest/toybox-aarch64"
  chmod +x "${TOYBOX_BIN}"
  file "${TOYBOX_BIN}" | grep -q aarch64 || { echo "ERROR: toybox not aarch64"; exit 1; }
  echo "  ${TOYBOX_BIN}"
fi

# Dinit: build in arm64 Alpine container
DINIT_VERSION="0.19.2"
DINIT_BIN="${BUILD_OUT}/dinit-aarch64"
LD_MUSL="${BUILD_OUT}/ld-musl-aarch64.so.1"
if [ ! -f "${DINIT_BIN}" ] || [ ! -f "${LD_MUSL}" ]; then
  echo "→ Building dinit ${DINIT_VERSION} for aarch64..."
  docker run --rm --platform linux/arm64 -v "${BUILD_OUT}:/out" alpine:3.21 sh -c "
    apk add --no-cache g++ make linux-headers git >/dev/null
    cd /tmp
    git clone --depth 1 --branch v${DINIT_VERSION} https://github.com/davmac314/dinit.git >/dev/null 2>&1
    cd dinit
    LDFLAGS="-static" ./configure --prefix=/usr --sbindir=/out --disable-shutdown >/dev/null
    LDFLAGS="-static" make -j\$(nproc) all >/dev/null 2>&1
    cp src/dinit /out/dinit-aarch64
    cp /lib/ld-musl-aarch64.so.1 /out/ld-musl-aarch64.so.1
  " 2>&1
  chmod +x "${DINIT_BIN}"
  file "${DINIT_BIN}" | grep -q aarch64 || { echo "ERROR: dinit not aarch64"; exit 1; }
  echo "  ${DINIT_BIN}"
fi

# Stage kernel if missing
if [ ! -f "${BUILD_OUT}/vmlinuz" ]; then
  echo "ERROR: ${BUILD_OUT}/vmlinuz not found. Set ALPENGLOW_AARCH64_KERNEL and run build-aarch64.sh first." >&2
  exit 1
fi

# Compose rootfs
ROOTFS_DIR="$(mktemp -d)"
mkdir -p "${ROOTFS_DIR}/bin" "${ROOTFS_DIR}/sbin" "${ROOTFS_DIR}/etc/dinit.d/boot.d" \
         "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/run" \
         "${ROOTFS_DIR}/tmp" "${ROOTFS_DIR}/root"

# Toybox applets as /bin/toybox and a symlink shell
ln -sf /bin/toybox "${ROOTFS_DIR}/bin/sh"
cp "${TOYBOX_BIN}" "${ROOTFS_DIR}/bin/toybox"

# Dinit + musl dynamic linker
cp "${DINIT_BIN}" "${ROOTFS_DIR}/sbin/dinit"
mkdir -p "${ROOTFS_DIR}/lib"
cp "${LD_MUSL}" "${ROOTFS_DIR}/lib/ld-musl-aarch64.so.1"

# Init script (same as x86 FAST config, adapted for toybox)
cat > "${ROOTFS_DIR}/init" <<'INIT'
#!/bin/sh
/bin/toybox mount -t proc proc /proc
/bin/toybox mount -t sysfs sysfs /sys
/bin/toybox mount -t devtmpfs devtmpfs /dev
/bin/toybox mount -t tmpfs tmpfs /run
/bin/toybox mkdir -p /dev/shm 2>/dev/null
/bin/toybox mount -t tmpfs -o mode=1777,size=256m tmpfs /dev/shm
/bin/toybox mkdir -p /run/user/0
/bin/toybox chmod 700 /run/user/0
/bin/toybox mkdir -p /state
echo ""
echo "Alpenglow boot"
echo ""
if [ -f /proc/meminfo ]; then
  /bin/toybox grep -E 'MemTotal|MemFree' /proc/meminfo 2>/dev/null
fi
exec /sbin/dinit -d /etc/dinit.d -s -t boot
INIT
chmod +x "${ROOTFS_DIR}/init"

# Dinit services
cat > "${ROOTFS_DIR}/etc/dinit.d/boot" <<'SVC'
type = internal
waits-for.d = boot.d
SVC

cat > "${ROOTFS_DIR}/etc/dinit.d/mount-filesystems" <<'SVC'
type = scripted
command = /bin/toybox sh -c "/bin/toybox mount -t proc proc /proc; /bin/toybox mount -t sysfs sysfs /sys; /bin/toybox mount -t devtmpfs devtmpfs /dev; /bin/toybox mount -t tmpfs tmpfs /run"
restart = no
SVC

cat > "${ROOTFS_DIR}/etc/dinit.d/shell-ttyAMA0" <<'SVC'
type = process
command = /bin/toybox sh -c "while true; do printf 'login: \\n' >/dev/console; /bin/toybox sh </dev/console >/dev/console 2>&1; done"
restart = yes
depends-on = mount-filesystems
SVC

ln -sf /etc/dinit.d/shell-ttyAMA0 "${ROOTFS_DIR}/etc/dinit.d/boot.d/shell-ttyAMA0"
ln -sf /etc/dinit.d/mount-filesystems "${ROOTFS_DIR}/etc/dinit.d/boot.d/mount-filesystems"

# Build initramfs
INITRAMFS="${BUILD_OUT}/initramfs-proper.cpio.gz"
echo "→ Building initramfs..."
(cd "${ROOTFS_DIR}" && find . -print | cpio -o -H newc 2>/dev/null | gzip -1 > "${INITRAMFS}")
rm -rf "${ROOTFS_DIR}"

SIZE_KB=$(( $(stat -f%z "${INITRAMFS}" 2>/dev/null || stat -c%s "${INITRAMFS}") / 1024 ))
echo "  ${INITRAMFS} (${SIZE_KB}K)"

echo ""
echo "To boot the proper aarch64 initramfs:"
echo "  qemu-system-aarch64 -M virt -cpu max -m 512 -smp 2 -nographic -no-reboot \\"
echo "    -kernel ${BUILD_OUT}/vmlinuz \\"
echo "    -initrd ${INITRAMFS} \\"
echo "    -append \"console=ttyAMA0,115200 init=/init quiet\""
