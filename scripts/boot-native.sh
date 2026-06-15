#!/bin/sh
# Build and boot Alpenglow native — our kernel, toybox, dinit, GlowFS.
# Uses Docker for host-independent compilation.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
OUT_DIR="${ROOT_DIR}/build/native"
ROOTFS_DIR="${OUT_DIR}/rootfs"
INITRAMFS="${OUT_DIR}/initramfs.cpio.gz"
KERNEL_IMAGE="${OUT_DIR}/vmlinuz"
TOYBOX_VERSION="0.8.11"
DINIT_VERSION="0.19.2"
ARCH="${KERNEL_ARCH:-x86_64}"
MEMORY_MB="${MEMORY_MB:-2048}"
ACCEL="${ACCEL:-tcg}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
mkdir -p "${OUT_DIR}" "${ROOTFS_DIR}"

echo "=== Alpenglow native boot ==="
echo "  init:   dinit v${DINIT_VERSION}"
echo "  shell:  toybox v${TOYBOX_VERSION}"
echo "  kernel: $(if [ "${KERNEL_BUILD:-0}" = "1" ]; then echo "custom build"; else echo "pre-built"; fi)"
echo "  arch:   ${ARCH}"
echo ""

build_toybox() {
  require_cmd docker
  echo "→ Building toybox ${TOYBOX_VERSION}..."
  docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache make gcc musl-dev curl tar xz bash linux-headers >/dev/null
    curl -fsSL https://github.com/landley/toybox/archive/refs/tags/'"${TOYBOX_VERSION}"'.tar.gz -o /tmp/toybox.tar.gz
    tar -xzf /tmp/toybox.tar.gz -C /tmp
    cd /tmp/toybox-'"${TOYBOX_VERSION}"'
    make defconfig >/dev/null 2>&1
    sed -i "s/# CONFIG_STATIC is not set/CONFIG_STATIC=y/" .config
    sed -i "s/# CONFIG_SH is not set/CONFIG_SH=y/" .config
    sed -i "s/# CONFIG_GETTY is not set/CONFIG_GETTY=y/" .config
    make -j$(nproc) LDFLAGS="-static" >/dev/null 2>&1
    cp toybox /out/toybox
  ' 2>&1
  echo "  toybox: ${OUT_DIR}/toybox"
}

build_dinit() {
  require_cmd docker
  echo "→ Building dinit ${DINIT_VERSION}..."
  docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache g++ make curl tar xz musl-dev bash >/dev/null
    curl -fsSL https://github.com/davmac314/dinit/releases/download/v'"${DINIT_VERSION}"'/dinit-'"${DINIT_VERSION}"'.tar.xz -o /tmp/dinit.tar.xz
    tar -xf /tmp/dinit.tar.xz -C /tmp
    cd /tmp/dinit-'"${DINIT_VERSION}"'
    ./configure --static >/dev/null 2>&1
    make -j$(nproc) CXXFLAGS="-static" LDFLAGS="-static" >/dev/null 2>&1
    make install DESTDIR=/out/dinit-install >/dev/null 2>&1
    cp /out/dinit-install/sbin/dinit /out/dinit
  ' 2>&1
  echo "  dinit: ${OUT_DIR}/dinit"
}

[ -f "${OUT_DIR}/toybox" ] || build_toybox
[ -f "${OUT_DIR}/dinit" ] || build_dinit

# Kernel
if [ ! -f "${KERNEL_IMAGE}" ]; then
  if [ "${KERNEL_BUILD:-0}" = "1" ]; then
    echo "→ Building custom kernel..."
    KERNEL_SRC="${OUT_DIR}/linux"
    KERNEL_CONFIG="${ROOT_DIR}/system/alpine/kernel/alpenglow-internet-appliance.config"
    [ -d "${KERNEL_SRC}" ] || {
      curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.tar.xz" -o "${OUT_DIR}/linux-6.12.tar.xz"
      tar -xf "${OUT_DIR}/linux-6.12.tar.xz" -C "${OUT_DIR}"
      mv "${OUT_DIR}/linux-6.12" "${KERNEL_SRC}"
    }
    cp "${KERNEL_CONFIG}" "${KERNEL_SRC}/.config"
    cd "${KERNEL_SRC}"
    make olddefconfig >/dev/null 2>&1
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" bzImage 2>&1 | tail -3
    cp arch/x86/boot/bzImage "${KERNEL_IMAGE}"
    cd "${ROOT_DIR}"
  else
    echo "→ Fetching pre-built kernel..."
    ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
    curl -#fsSL "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/netboot/vmlinuz-virt" -o "${KERNEL_IMAGE}"
  fi
  echo "  kernel: ${KERNEL_IMAGE}"
fi

# GlowFS module (only with custom kernel)
GLOWFS_KO="${OUT_DIR}/glowfs.ko"
if [ ! -f "${GLOWFS_KO}" ] && [ -d "${ROOT_DIR}/system/glowfs" ] && [ "${KERNEL_BUILD:-0}" = "1" ]; then
  echo "→ Building GlowFS kernel module..."
  KERNEL_SRC="${OUT_DIR}/linux"
  cd "${KERNEL_SRC}"
  make modules_prepare >/dev/null 2>&1
  cd "${ROOT_DIR}/system/glowfs"
  make -C "${KERNEL_SRC}" M="$(pwd)" modules 2>&1 | tail -1
  cp glowfs.ko "${GLOWFS_KO}" 2>/dev/null || true
  cd "${ROOT_DIR}"
fi

# Compose rootfs
echo "→ Composing rootfs..."
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"/{bin,sbin,etc,dev,proc,sys,tmp,run,usr/local/bin}

# Toybox
cp "${OUT_DIR}/toybox" "${ROOTFS_DIR}/bin/toybox"
for applet in sh ls cat cp mv rm mkdir rmdir ln mount umount ps kill sleep echo test \
  basename dirname chmod chown touch clear printf yes false true head tail sort wc cut \
  tr od strings uniq diff sed grep find xargs dd df du stat id whoami hostname \
  dmesg modprobe insmod switch_root getty login vi more less tar gzip gunzip zcat bzcat \
  date cal reboot halt poweroff; do
  ln -sf /bin/toybox "${ROOTFS_DIR}/bin/${applet}" 2>/dev/null || true
done
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/init"
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/getty"
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/modprobe"
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/poweroff"
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/reboot"

# Dinit
cp "${OUT_DIR}/dinit" "${ROOTFS_DIR}/sbin/dinit"
if [ -f "${OUT_DIR}/dinit-install/sbin/dinitctl" ]; then
  cp "${OUT_DIR}/dinit-install/sbin/dinitctl" "${ROOTFS_DIR}/sbin/"
fi

# Dinit service files
mkdir -p "${ROOTFS_DIR}/etc/dinit.d/boot.d"
for svc in "${BACKEND_DIR}/dinit/"*; do
  name=$(basename "${svc}")
  cp "${svc}" "${ROOTFS_DIR}/etc/dinit.d/${name}"
  ln -sf "/etc/dinit.d/${name}" "${ROOTFS_DIR}/etc/dinit.d/boot.d/${name}" 2>/dev/null || true
done

# Getty login on serial console (with /etc/passwd support)
cat > "${ROOTFS_DIR}/etc/dinit.d/shell-ttyS0" << 'SHELL'
type = process
command = /bin/toybox getty -L 115200 ttyS0 vt100
restart = yes
depends-on = mount-filesystems
SHELL
ln -sf /etc/dinit.d/shell-ttyS0 "${ROOTFS_DIR}/etc/dinit.d/boot.d/shell-ttyS0"

# Mount filesystems (runs before other services)
cat > "${ROOTFS_DIR}/etc/dinit.d/mount-filesystems" << 'MOUNT'
type = scripted
command = /bin/toybox sh -c "/bin/toybox mount -t proc proc /proc; /bin/toybox mount -t sysfs sysfs /sys; /bin/toybox mount -t devtmpfs devtmpfs /dev; /bin/toybox mount -t tmpfs tmpfs /run"
restart = no
MOUNT
ln -sf /etc/dinit.d/mount-filesystems "${ROOTFS_DIR}/etc/dinit.d/boot.d/mount-filesystems"

# Oil (native package manager)
OIL_BIN="${ROOT_DIR}/build/native/oil"
OIL_SRC="${ROOT_DIR}/../oil"
if [ -f "${OIL_BIN}" ]; then
  cp "${OIL_BIN}" "${ROOTFS_DIR}/usr/local/bin/oil"
elif [ -d "${OIL_SRC}" ]; then
  echo "→ Building Oil (native package manager)..."
  docker run --rm --platform linux/amd64 -v "${OIL_SRC}:/oil-src" -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache rust cargo make gcc musl-dev >/dev/null
    cd /oil-src
    cargo build --release --no-default-features 2>/dev/null
    cp target/release/oil /out/oil 2>/dev/null
  ' 2>&1 | tail -1
  if [ -f "${OUT_DIR}/oil" ]; then
    cp "${OUT_DIR}/oil" "${ROOTFS_DIR}/usr/local/bin/oil"
    chmod 755 "${ROOTFS_DIR}/usr/local/bin/oil"
    echo "  oil: ${ROOTFS_DIR}/usr/local/bin/oil"
  fi
fi

# Network — DHCP client (toybox udhcpc)
cat > "${ROOTFS_DIR}/etc/dinit.d/networking" << 'NET'
type = scripted
command = /bin/toybox udhcpc -i eth0 -s /bin/toybox -q
restart = yes
depends-on = mount-filesystems
NET
ln -sf /etc/dinit.d/networking "${ROOTFS_DIR}/etc/dinit.d/boot.d/networking"

# Default route via DHCP
mkdir -p "${ROOTFS_DIR}/usr/share/udhcpc"
cat > "${ROOTFS_DIR}/usr/share/udhcpc/default.script" << 'SCRIPT'
#!/bin/toybox sh
case "$1" in
  bound|renew) /sbin/ifconfig $interface $ip netmask $subnet; route add default gw $router 2>/dev/null;;
  deconfig) /sbin/ifconfig $interface 0.0.0.0;;
esac
SCRIPT
chmod 755 "${ROOTFS_DIR}/usr/share/udhcpc/default.script"

# User management — root with no password (can login via getty)
mkdir -p "${ROOTFS_DIR}/etc"
cat > "${ROOTFS_DIR}/etc/passwd" << 'PASSWD'
root:x:0:0:root:/root:/bin/toybox sh
PASSWD
cat > "${ROOTFS_DIR}/etc/shadow" << 'SHADOW'
root::19999:0:99999:7:::
SHADOW
cat > "${ROOTFS_DIR}/etc/group" << 'GROUP'
root:x:0:
wheel:x:10:
daemon:x:1:
bin:x:2:
sys:x:3:
adm:x:4:
tty:x:5:
disk:x:6:
lp:x:7:
mail:x:8:
news:x:9:
uucp:x:10:
man:x:12:
proxy:x:13:
kmem:x:15:
dialout:x:20:
fax:x:21:
voice:x:22:
cdrom:x:24:
floppy:x:25:
tape:x:26:
sudo:x:27:
audio:x:29:
video:x:44:
GROUP
# root home
mkdir -p "${ROOTFS_DIR}/root"
  mkdir -p "${ROOTFS_DIR}/lib/modules"
  cp "${GLOWFS_KO}" "${ROOTFS_DIR}/lib/modules/"
fi

# Init — dinit as primary PID 1, manages all services
cat > "${ROOTFS_DIR}/init" << 'INIT'
#!/bin/toybox sh
/bin/toybox mount -t proc proc /proc
/bin/toybox mount -t sysfs sysfs /sys
/bin/toybox mount -t devtmpfs devtmpfs /dev
/bin/toybox mount -t tmpfs tmpfs /run
mkdir -p /state
# Try to mount state partition (if available)
state_dev=""
for arg in $(cat /proc/cmdline); do
  case "$arg" in
    alpenglow.state=LABEL=*) state_dev="/dev/disk/by-label/${arg#alpenglow.state=LABEL=}" ;;
    alpenglow.state=*) state_dev="${arg#alpenglow.state=}" ;;
  esac
done
if [ -z "$state_dev" ]; then
  state_dev="/dev/disk/by-label/alpenglow-state"
fi
if [ -b "$state_dev" ]; then
  /bin/toybox mount -t ext4 -o rw,nosuid,nodev "$state_dev" /state 2>/dev/null && echo "Mounted state: $state_dev"
fi
echo ""
echo "Alpenglow boot"
echo ""
exec /sbin/dinit -d /etc/dinit.d -s -t shell-ttyS0
INIT
chmod 755 "${ROOTFS_DIR}/init"

# Devices
mknod -m 622 "${ROOTFS_DIR}/dev/console" c 5 1 2>/dev/null || true
mknod -m 666 "${ROOTFS_DIR}/dev/null" c 1 3 2>/dev/null || true
mknod -m 666 "${ROOTFS_DIR}/dev/zero" c 1 5 2>/dev/null || true
mknod -m 444 "${ROOTFS_DIR}/dev/random" c 1 8 2>/dev/null || true
mknod -m 444 "${ROOTFS_DIR}/dev/urandom" c 1 9 2>/dev/null || true

echo "alpenglow" > "${ROOTFS_DIR}/etc/hostname"

# Build initramfs
echo "→ Building initramfs..."
(cd "${ROOTFS_DIR}" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9 > "${INITRAMFS}")
echo "  initramfs: ${INITRAMFS} ($(du -sh "${INITRAMFS}" | cut -f1))"
echo ""

# Boot
require_cmd qemu-system-x86_64
echo "→ Booting Alpenglow..."
echo "  kernel:    ${KERNEL_IMAGE}"
echo "  initramfs: ${INITRAMFS}"
echo "  (Ctrl-A X to quit)"
echo ""

qemu-system-x86_64 \
  -machine q35,accel="${ACCEL}" \
  -m "${MEMORY_MB}" \
  -smp 2 \
  -nographic \
  -no-reboot \
  -kernel "${KERNEL_IMAGE}" \
  -initrd "${INITRAMFS}" \
  -append "console=ttyS0 init=/init"
