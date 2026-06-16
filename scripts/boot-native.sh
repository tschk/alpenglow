#!/bin/sh
# Build and boot Alpenglow native — supports two modes:
#   Diskless (default): boot from initramfs, root in RAM
#   Rootfs:            boot from persistent rootfs partition
# Uses Docker for host-independent compilation.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
OUT_DIR="${ROOT_DIR}/build/native"
ROOTFS_DIR="${OUT_DIR}/rootfs"
INITRAMFS="${OUT_DIR}/initramfs.cpio.zst"
KERNEL_IMAGE="${OUT_DIR}/vmlinuz"
TOYBOX_VERSION="0.8.11"
DINIT_VERSION="0.19.2"
KERNEL_VERSION="${KERNEL_VERSION:-7.0}"
KERNEL_7="${KERNEL_7:-1}"  # 1=Linux 7.0 defconfig+rust, 0=Alpine pre-built
KERNEL_CONFIG="${KERNEL_CONFIG:-alpenglow-qemu-minimal}"
ARCH="${KERNEL_ARCH:-x86_64}"
BOOT_MODE="${BOOT_MODE:-diskless}"  # diskless or rootfs
ALPENGLOW_MODULE="${ROOT_DIR}/build/native/alpenglow_core.ko"
BUILD_PROFILE="${BUILD_PROFILE:-standard}"
MEMORY_MB="${MEMORY_MB:-2048}"
# Auto-detect acceleration: prefer KVM, then HVF (macOS), fall back TCG
ACCEL="${ACCEL:-}"
if [ -z "$ACCEL" ]; then
  if qemu-system-x86_64 -machine q35,accel=kvm -M none </dev/null 2>/dev/null; then
    ACCEL=kvm
  elif qemu-system-x86_64 -machine q35,accel=hvf -M none </dev/null 2>/dev/null; then
    ACCEL=hvf
  else
    ACCEL=tcg
  fi
fi
EFI="${EFI:-1}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }
mkdir -p "${OUT_DIR}" "${ROOTFS_DIR}"

echo "=== Alpenglow native boot ==="
echo "  init:    dinit v${DINIT_VERSION}"
echo "  shell:   toybox v${TOYBOX_VERSION}"
echo "  kernel:  $(if [ "${KERNEL_BUILD:-0}" = "1" ]; then echo "custom (${KERNEL_CONFIG})"; else echo "pre-built"; fi)"
echo "  arch:    ${ARCH}"
echo "  efi:     ${EFI}"
echo "  profile: ${BUILD_PROFILE}"
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
    sed -i "s/CONFIG_VI=y/# CONFIG_VI is not set/" .config 2>/dev/null || true
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
  if [ "${KERNEL_7}" = "1" ] && [ "${ARCH}" = "x86_64" ]; then
    echo "→ Building Linux 7.0 + CONFIG_RUST=y kernel..."
    KERNEL_SRC="${OUT_DIR}/linux-7.0"
    [ -d "${KERNEL_SRC}" ] || {
      curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.0.tar.xz" -o "${OUT_DIR}/linux-7.0.tar.xz"
      tar -xf "${OUT_DIR}/linux-7.0.tar.xz" -C "${OUT_DIR}"
    }
    cd "${KERNEL_SRC}"
    # GlowFS needs Linux 6.12 API — not in-tree for 7.0, built separately via ci-glowfs
    make ARCH=x86_64 defconfig 2>/dev/null
    make ARCH=x86_64 kvm_guest.config 2>/dev/null
    make ARCH=x86_64 rust.config 2>/dev/null
    scripts/config \
      --disable MODULE_SIG_FORMAT --disable MODULE_SIG --disable MODULE_SIG_ALL \
      --disable MODULE_COMPRESS --disable MODULE_COMPRESS_GZIP --disable MODULE_COMPRESS_ALL \
      --disable DEBUG_FS --disable DEBUG_KERNEL --disable DEBUG_INFO --disable FTRACE
    # Enable GlowFS in config
    sed -i 's/# CONFIG_GLOWFS is not set/CONFIG_GLOWFS=m/' .config 2>/dev/null || echo "CONFIG_GLOWFS=m" >> .config
    # Config overrides: LZ4 + virt drivers + gzip decompress
    cat "${ROOT_DIR}/system/backends/appliance/kernel/lz4.config" >> .config 2>/dev/null || true
    cat "${ROOT_DIR}/system/backends/appliance/kernel/virt.config" >> .config 2>/dev/null || true
    cat "${ROOT_DIR}/system/backends/appliance/kernel/minimal.config" >> .config 2>/dev/null || true
    make ARCH=x86_64 olddefconfig 2>/dev/null
    make -j"$(nproc)" ARCH=x86_64 bzImage 2>&1 | tail -3
    cp arch/x86/boot/bzImage "${KERNEL_IMAGE}"
    cd "${ROOT_DIR}"

    # Build alpenglow_core Rust module
    if command -v rustc >/dev/null 2>&1 && command -v bindgen >/dev/null 2>&1; then
      echo "→ Building alpenglow_core Rust kernel module..."
      MOD_SRC="${ROOT_DIR}/system/kernel-modules/alpenglow_core"
      export RUSTC=rustc BINDGEN=bindgen
      make -C "${KERNEL_SRC}" modules_prepare 2>/dev/null
      make -C "${MOD_SRC}" KERNEL_SRC="${KERNEL_SRC}" 2>&1 | tail -3
      cp "${MOD_SRC}/alpenglow_core.ko" "${OUT_DIR}/alpenglow_core.ko" 2>/dev/null || echo "  alpenglow_core: build failed (not fatal)"
    fi
  elif [ "${KERNEL_BUILD:-0}" = "1" ]; then
    echo "→ Building custom kernel (Linux ${KERNEL_VERSION})..."
    KERNEL_SRC="${OUT_DIR}/linux"
    [ -d "${KERNEL_SRC}" ] || {
      KERNEL_MAJOR="$(echo "${KERNEL_VERSION}" | cut -d. -f1)"
      curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz" -o "${OUT_DIR}/linux-${KERNEL_VERSION}.tar.xz"
      tar -xf "${OUT_DIR}/linux-${KERNEL_VERSION}.tar.xz" -C "${OUT_DIR}"
      mv "${OUT_DIR}/linux-${KERNEL_VERSION}" "${KERNEL_SRC}"
    }
    # Base stripped config (from 7.0.12, auto-adapted to whatever kernel version)
    cp "${ROOT_DIR}/system/backends/appliance/kernel/alpenglow-qemu-minimal.config" "${KERNEL_SRC}/.config"
    cat "${ROOT_DIR}/system/backends/appliance/kernel/lz4.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    cat "${ROOT_DIR}/system/backends/appliance/kernel/virt.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    make -C "${KERNEL_SRC}" ARCH=x86_64 olddefconfig >/dev/null 2>&1
    # Build kernel
    make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" -C "${KERNEL_SRC}" ARCH=x86_64 bzImage 2>&1 | tail -5
    cp "${KERNEL_SRC}/arch/x86/boot/bzImage" "${KERNEL_IMAGE}" 2>/dev/null || true
  else
    echo "→ Fetching pre-built kernel..."
    ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
    curl -#fsSL "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/netboot/vmlinuz-virt" -o "${KERNEL_IMAGE}"
  fi
  echo "  kernel: ${KERNEL_IMAGE}"
fi

# GlowFS module check
GLOWFS_KO="${OUT_DIR}/glowfs.ko"
if [ -f "${GLOWFS_KO}" ]; then
  echo "  glowfs: ${GLOWFS_KO}"
elif [ "${KERNEL_BUILD:-0}" != "1" ]; then
  echo "→ GlowFS requires KERNEL_BUILD=1 (skipping)"
fi
if [ -f "${ALPENGLOW_MODULE}" ]; then
  echo "  alpenglow-core: ${ALPENGLOW_MODULE}"
fi

# Build userspace services
BUILD_SERVICES="${BUILD_SERVICES:-0}"
if [ "${BUILD_SERVICES}" = "1" ]; then
  echo "→ Building userspace services..."
  # iwd — modern WiFi daemon (static musl)
  docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache gcc musl-dev make curl tar xz linux-headers pkgconf >/dev/null 2>&1
    IWD_VERSION="2.18"
    cd /tmp
    curl -fsSL "https://www.kernel.org/pub/linux/network/wireless/iwd-${IWD_VERSION}.tar.xz" -o iwd.tar.xz 2>/dev/null
    tar -xf iwd.tar.xz
    cd "iwd-${IWD_VERSION}"
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
      --disable-systemd --disable-dbus --enable-static --disable-shared \
      --enable-wired --enable-tools=no \
      CC="gcc" CFLAGS="-static -Os -s" >/dev/null 2>&1
    make -j$(nproc) >/dev/null 2>&1
    make install DESTDIR=/out/iwd >/dev/null 2>&1
  ' 2>&1 | tail -1
  if [ -f "${OUT_DIR}/iwd/usr/libexec/iwd" ]; then
    echo "  iwd: ${OUT_DIR}/iwd/usr/libexec/iwd"
  fi

  # greetd — login greeter (Rust, static musl)
  docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" -v "${ROOT_DIR}/..:/host" alpine:3.21 sh -c '
    apk add --no-cache curl tar xz gcc musl-dev rust cargo >/dev/null 2>&1
    GRETD_VERSION="0.10.3"
    cd /tmp
    curl -fsSL "https://gitlab.com/mobian1/greetd/-/archive/v${GRETD_VERSION}/greetd-v${GRETD_VERSION}.tar.gz" -o greetd.tar.gz 2>/dev/null
    tar -xf greetd.tar.gz
    cd "greetd-v${GRETD_VERSION}"
    RUSTFLAGS="-C target-feature=+crt-static -C link-self-contained=yes" \
    cargo build --release --target x86_64-unknown-linux-musl 2>/dev/null || true
    if [ -f "target/x86_64-unknown-linux-musl/release/greetd" ]; then
      mkdir -p /out/greetd/usr/bin
      cp target/x86_64-unknown-linux-musl/release/greetd /out/greetd/usr/bin/
    fi
  ' 2>&1 | tail -1
  if [ -f "${OUT_DIR}/greetd/usr/bin/greetd" ]; then
    echo "  greetd: ${OUT_DIR}/greetd/usr/bin/greetd"
  fi

  # dropbear — SSH server (static musl)
  docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache gcc musl-dev make curl tar xz linux-headers >/dev/null 2>&1
    DROPBEAR_VERSION="2024.85"
    cd /tmp
    curl -fsSL "https://matt.ucc.asn.au/dropbear/releases/dropbear-${DROPBEAR_VERSION}.tar.xz" -o dropbear.tar.xz 2>/dev/null || \
      curl -fsSL "https://github.com/mkj/dropbear/archive/refs/tags/DROPBEAR_${DROPBEAR_VERSION}.tar.gz" -o dropbear.tar.gz 2>/dev/null
    if [ -f dropbear.tar.xz ]; then
      tar -xf dropbear.tar.xz
      cd "dropbear-${DROPBEAR_VERSION}"
    elif [ -f dropbear.tar.gz ]; then
      tar -xf dropbear.tar.gz
      cd "dropbear-DROPBEAR_${DROPBEAR_VERSION}"
    else
      echo "dropbear download failed" >&2
      exit 1
    fi
    ./configure --prefix=/usr --disable-zlib --enable-static \
      CC="gcc" CFLAGS="-static -Os -s" >/dev/null 2>&1
    make -j$(nproc) PROGRAMS="dropbear dropbearkey dropbearconvert" >/dev/null 2>&1
    make install DESTDIR=/out/dropbear >/dev/null 2>&1
  ' 2>&1 | tail -1
  if [ -f "${OUT_DIR}/dropbear/usr/bin/dropbear" ]; then
    echo "  dropbear: ${OUT_DIR}/dropbear/usr/bin/dropbear"
  fi

  # chrony — NTP daemon (static musl)
  docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache gcc musl-dev make curl tar xz >/dev/null 2>&1
    CHRONY_VERSION="4.5"
    cd /tmp
    curl -fsSL "https://chrony-project.org/releases/chrony-${CHRONY_VERSION}.tar.gz" -o chrony.tar.gz 2>/dev/null || exit 0
    tar -xf chrony.tar.gz
    cd "chrony-${CHRONY_VERSION}"
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
      --disable-ntp-signd --disable-sechash \
      CC="gcc" CFLAGS="-static -Os -s" >/dev/null 2>&1
    make -j$(nproc) >/dev/null 2>&1
    make install DESTDIR=/out/chrony >/dev/null 2>&1
  ' 2>&1 | tail -1
  if [ -f "${OUT_DIR}/chrony/usr/sbin/chronyd" ]; then
    echo "  chronyd: ${OUT_DIR}/chrony/usr/sbin/chronyd"
  fi

  # dnsmasq — local DNS caching resolver (static musl)
  docker run --rm --platform linux/amd64 -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache gcc musl-dev make curl tar xz linux-headers >/dev/null 2>&1
    DNSMASQ_VERSION="2.90"
    cd /tmp
    curl -fsSL "https://thekelleys.org.uk/dnsmasq/dnsmasq-${DNSMASQ_VERSION}.tar.xz" -o dnsmasq.tar.xz 2>/dev/null || exit 0
    tar -xf dnsmasq.tar.xz
    cd "dnsmasq-${DNSMASQ_VERSION}"
    make -j$(nproc) CC="gcc" CFLAGS="-static -Os -s" PREFIX=/usr >/dev/null 2>&1
    make install DESTDIR=/out/dnsmasq PREFIX=/usr >/dev/null 2>&1
  ' 2>&1 | tail -1
  if [ -f "${OUT_DIR}/dnsmasq/usr/sbin/dnsmasq" ]; then
    echo "  dnsmasq: ${OUT_DIR}/dnsmasq/usr/sbin/dnsmasq"
  fi
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
  dmesg modprobe insmod switch_root getty login more less tar gzip gunzip zcat bzcat \
  date cal reboot halt poweroff passwd syslogd crond logger; do
  ln -sf /bin/toybox "${ROOTFS_DIR}/bin/${applet}" 2>/dev/null || true
done
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/init"
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/getty"
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/modprobe"
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/poweroff"
ln -sf /bin/toybox "${ROOTFS_DIR}/sbin/reboot"

# Vro editor (replaces toybox vi)
VRO_SRC="${ROOT_DIR}/system/backends/appliance/vro/vro"
if [ -f "${VRO_SRC}" ]; then
  cp "${VRO_SRC}" "${ROOTFS_DIR}/usr/local/bin/vro"
  chmod 755 "${ROOTFS_DIR}/usr/local/bin/vro"
  ln -sf /usr/local/bin/vro "${ROOTFS_DIR}/usr/local/bin/vi" 2>/dev/null || true
fi

# Dinit
cp "${OUT_DIR}/dinit" "${ROOTFS_DIR}/sbin/dinit"
if [ -f "${OUT_DIR}/dinit-install/sbin/dinitctl" ]; then
  cp "${OUT_DIR}/dinit-install/sbin/dinitctl" "${ROOTFS_DIR}/sbin/"
fi

# Dinit service files — copy all, enable per profile
mkdir -p "${ROOTFS_DIR}/etc/dinit.d/boot.d"
for svc in "${BACKEND_DIR}/dinit/"*; do
  name=$(basename "${svc}")
  cp "${svc}" "${ROOTFS_DIR}/etc/dinit.d/${name}"
done

# Define enabled services per profile
case "${BUILD_PROFILE}" in
  minimal)
    BOOT_SERVICES="shell-ttyS0 mount-filesystems networking syslogd crond dropbear chronyd dnsmasq"
    ;;
  standard)
    BOOT_SERVICES="shell-ttyS0 mount-filesystems networking syslogd crond dropbear chronyd dnsmasq glowfs-mount state-mount elogind seatd alpenglow-kernel-policy alpenglow-netd alpenglow-zram alpenglow-pressure alpenglow-power iwd pipewire wireplumber greetd velox foot"
    ;;
esac

# Getty login on serial console
cat > "${ROOTFS_DIR}/etc/dinit.d/shell-ttyS0" << 'SHELL'
type = process
command = /bin/toybox getty -L 115200 ttyS0 vt100
restart = yes
depends-on = mount-filesystems
SHELL

# Mount filesystems
cat > "${ROOTFS_DIR}/etc/dinit.d/mount-filesystems" << 'MOUNT'
type = scripted
command = /bin/toybox sh -c "/bin/toybox mount -t proc proc /proc; /bin/toybox mount -t sysfs sysfs /sys; /bin/toybox mount -t devtmpfs devtmpfs /dev; /bin/toybox mount -t tmpfs tmpfs /run"
restart = no
MOUNT

# Network — DHCP client
cat > "${ROOTFS_DIR}/etc/dinit.d/networking" << 'NET'
type = scripted
command = /bin/toybox udhcpc -i eth0 -s /bin/toybox -q
restart = yes
depends-on = mount-filesystems
NET

# Syslogd — system logging
cat > "${ROOTFS_DIR}/etc/dinit.d/syslogd" << 'SYSLOG'
type = process
command = /bin/toybox syslogd -n
restart = always
depends-on = mount-filesystems
SYSLOG

# Crond — scheduled tasks
cat > "${ROOTFS_DIR}/etc/dinit.d/crond" << 'CROND'
type = process
command = /bin/toybox crond -n
restart = yes
depends-on = syslogd
CROND

# Dropbear — SSH server
cat > "${ROOTFS_DIR}/etc/dinit.d/dropbear" << 'DROP'
type = process
command = /usr/bin/dropbear -F -R
restart = yes
depends-on = networking
DROP

# Chronyd — NTP daemon
cat > "${ROOTFS_DIR}/etc/dinit.d/chronyd" << 'CHRON'
type = process
command = /usr/sbin/chronyd -d -s
restart = yes
depends-on = networking
CHRON

# Dnsmasq — local DNS caching resolver
cat > "${ROOTFS_DIR}/etc/dinit.d/dnsmasq" << 'DNSQ'
type = process
command = /usr/sbin/dnsmasq -k
restart = yes
depends-on = networking
DNSQ

# Enable boot services for this profile
for svc in ${BOOT_SERVICES}; do
  ln -sf "/etc/dinit.d/${svc}" "${ROOTFS_DIR}/etc/dinit.d/boot.d/${svc}" 2>/dev/null || true
done

# Oil (native package manager)
OIL_BIN="${ROOT_DIR}/build/native/oil"
OIL_SRC="${ROOT_DIR}/system/oil"
if [ -f "${OIL_BIN}" ]; then
  cp "${OIL_BIN}" "${ROOTFS_DIR}/usr/local/bin/oil"
elif [ -d "${OIL_SRC}" ]; then
  echo "→ Building Oil (native package manager)..."
  docker run --rm --platform linux/amd64 -v "${OIL_SRC}:/oil-src" -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache rust cargo make gcc musl-dev >/dev/null
    cd /oil-src
    cargo build --release --no-default-features --features system-apk 2>/dev/null
    cp target/release/oil /out/oil 2>/dev/null
  ' 2>&1 | tail -1
  if [ -f "${OUT_DIR}/oil" ]; then
    cp "${OUT_DIR}/oil" "${ROOTFS_DIR}/usr/local/bin/oil"
    chmod 755 "${ROOTFS_DIR}/usr/local/bin/oil"
    echo "  oil: ${ROOTFS_DIR}/usr/local/bin/oil"
  fi
fi

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
audio:x:29:pipewire
video:x:44:seatd
input:x:777:
seatd:x:772:
iwd:x:773:
pipewire:x:774:
GROUP
# root home
mkdir -p "${ROOTFS_DIR}/root"
mkdir -p "${ROOTFS_DIR}/lib/modules"
if [ -f "${GLOWFS_KO}" ]; then
  cp "${GLOWFS_KO}" "${ROOTFS_DIR}/lib/modules/"
fi
if [ -f "${ALPENGLOW_MODULE}" ]; then
  cp "${ALPENGLOW_MODULE}" "${ROOTFS_DIR}/lib/modules/"
fi

# Userspace services (if built)
if [ -d "${OUT_DIR}/iwd" ]; then
  cp -R "${OUT_DIR}/iwd/" "${ROOTFS_DIR}/"
  mkdir -p "${ROOTFS_DIR}/etc/iwd"
  cp "${BACKEND_DIR}/rootfs-overlay/etc/iwd/main.conf" "${ROOTFS_DIR}/etc/iwd/" 2>/dev/null || true
fi
if [ -d "${OUT_DIR}/greetd" ]; then
  cp -R "${OUT_DIR}/greetd/" "${ROOTFS_DIR}/"
  mkdir -p "${ROOTFS_DIR}/etc/greetd"
  cp "${BACKEND_DIR}/rootfs-overlay/etc/greetd/config.toml" "${ROOTFS_DIR}/etc/greetd/" 2>/dev/null || true
fi
if [ -d "${OUT_DIR}/dropbear" ]; then
  cp -R "${OUT_DIR}/dropbear/" "${ROOTFS_DIR}/"
  mkdir -p "${ROOTFS_DIR}/etc/dropbear"
fi
if [ -d "${OUT_DIR}/chrony" ]; then
  cp -R "${OUT_DIR}/chrony/" "${ROOTFS_DIR}/"
  mkdir -p "${ROOTFS_DIR}/etc/chrony"
fi
if [ -d "${OUT_DIR}/dnsmasq" ]; then
  cp -R "${OUT_DIR}/dnsmasq/" "${ROOTFS_DIR}/"
fi

# Init — dinit as primary PID 1, manages all services
cat > "${ROOTFS_DIR}/init" << 'INIT'
#!/bin/toybox sh
/bin/toybox mount -t proc proc /proc
/bin/toybox mount -t sysfs sysfs /sys
/bin/toybox mount -t devtmpfs devtmpfs /dev
/bin/toybox mount -t tmpfs tmpfs /run
/bin/toybox mkdir -p /dev/shm 2>/dev/null
/bin/toybox mount -t tmpfs -o mode=1777,size=256m tmpfs /dev/shm
mkdir -p /run/user/0
chmod 700 /run/user/0
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
# Log memory at boot for benchmark
if [ -f /proc/meminfo ]; then
  grep -E 'MemTotal|MemFree' /proc/meminfo 2>/dev/null
fi
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

# /etc/hosts
cat > "${ROOTFS_DIR}/etc/hosts" << 'HOSTS'
127.0.0.1 localhost
127.0.1.1 alpenglow
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
HOSTS

# Chrony config
mkdir -p "${ROOTFS_DIR}/etc/chrony"
cat > "${ROOTFS_DIR}/etc/chrony/chrony.conf" << 'CHRONY'
pool pool.ntp.org iburst
makestep 1.0 3
rtcsync
cmdport 0
bindcmdaddress 127.0.0.1
bindcmdaddress ::1
CHRONY

# Dnsmasq config
cat > "${ROOTFS_DIR}/etc/dnsmasq.conf" << 'DNSMASQ'
port=53
domain-needed
bogus-priv
no-resolv
server=1.1.1.1
server=8.8.8.8
cache-size=1000
DNSMASQ

# User cron
mkdir -p "${ROOTFS_DIR}/etc/crontabs"
cat > "${ROOTFS_DIR}/etc/crontabs/root" << 'CRONT'
0 0 * * * /usr/local/bin/logrotate.sh >/dev/null 2>&1
CRONT
chmod 600 "${ROOTFS_DIR}/etc/crontabs/root"

# Naive logrotate
cat > "${ROOTFS_DIR}/usr/local/bin/logrotate.sh" << 'LOGX'
#!/bin/toybox sh
for log in /var/log/alpenglow/*.log; do
  [ -f "${log}" ] || continue
  mv "${log}" "${log}.old" 2>/dev/null || true
done
LOGX
chmod 755 "${ROOTFS_DIR}/usr/local/bin/logrotate.sh"

# Root SSH authorized_keys placeholder
mkdir -p "${ROOTFS_DIR}/root/.ssh"
chmod 700 "${ROOTFS_DIR}/root/.ssh"

# Build initramfs
echo "→ Building initramfs..."
(cd "${ROOTFS_DIR}" && find . -print | cpio -o -H newc 2>/dev/null | gzip -1 > "${INITRAMFS}")
echo "  initramfs: ${INITRAMFS} ($(du -sh "${INITRAMFS}" | cut -f1))"
echo ""

# Boot
require_cmd qemu-system-x86_64
echo "→ Booting Alpenglow..."
echo "  kernel:    ${KERNEL_IMAGE}"
echo "  initramfs: ${INITRAMFS}"
echo "  mode:      ${BOOT_MODE}"
echo "  efi:       ${EFI}"
echo "  (Ctrl-A X to quit)"
echo ""

QEMU_OPTS="-machine q35,accel=${ACCEL} -m ${MEMORY_MB} -smp 2 -nographic -no-reboot"

# Kernel cmdline args
KERNEL_CMDLINE="quiet console=ttyS0 init=/init"

if [ "${BOOT_MODE}" = "rootfs" ]; then
  # Rootfs mode: boot from a disk image with alpenglow-root label
  ROOTFS_IMAGE="${OUT_DIR}/rootfs.img"
  if [ ! -f "${ROOTFS_IMAGE}" ]; then
    echo "→ Creating rootfs image..."
    dd if=/dev/zero of="${ROOTFS_IMAGE}" bs=1M count=1024 2>/dev/null
    mkfs.ext4 -L alpenglow-root "${ROOTFS_IMAGE}" 2>/dev/null
    # Populate rootfs from built rootfs directory if exists
    if [ -d "${ROOTFS_DIR}" ]; then
      TMPMNT=$(mktemp -d)
      mount -o loop "${ROOTFS_IMAGE}" "${TMPMNT}" 2>/dev/null
      cp -a "${ROOTFS_DIR}/." "${TMPMNT}/" 2>/dev/null || true
      umount "${TMPMNT}" 2>/dev/null || true
      rmdir "${TMPMNT}" 2>/dev/null || true
    fi
    echo "  rootfs: ${ROOTFS_IMAGE}"
  fi
  QEMU_OPTS="${QEMU_OPTS} -drive file=${ROOTFS_IMAGE},format=raw,if=virtio"
  KERNEL_CMDLINE="${KERNEL_CMDLINE} alpenglow.root=/dev/vda"
fi

if [ "${EFI}" = "1" ]; then
  # UEFI boot via kernel EFI stub (saves ~200ms vs SeaBIOS)
  OVMF_CODE=""
  for p in /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/local/share/qemu/edk2-x86_64-code.fd /opt/homebrew/share/qemu/edk2-x86_64-code.fd; do
    [ -f "$p" ] && { OVMF_CODE="$p"; break; }
  done
  if [ -n "${OVMF_CODE}" ]; then
    exec qemu-system-x86_64 \
      ${QEMU_OPTS} \
      -bios "${OVMF_CODE}" \
      -kernel "${KERNEL_IMAGE}" \
      -initrd "${INITRAMFS}" \
      -append "${KERNEL_CMDLINE}"
  fi
  echo "  → OVMF not found, falling back to SeaBIOS"
fi

# Legacy BIOS boot
exec qemu-system-x86_64 \
  ${QEMU_OPTS} \
  -kernel "${KERNEL_IMAGE}" \
  -initrd "${INITRAMFS}" \
  -append "${KERNEL_CMDLINE}"
