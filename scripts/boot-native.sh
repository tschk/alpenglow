#!/bin/sh
# Build and boot Alpenglow native.
# Uses Docker for host-independent compilation.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
if [ -n "${ALPENGLOW_EDITION:-}" ]; then
  # shellcheck source=scripts/edition-resolve.sh
  . "${ROOT_DIR}/scripts/edition-resolve.sh"
fi
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
OUT_DIR="${ROOT_DIR}/build/native"
ROOTFS_DIR="${OUT_DIR}/rootfs"
KERNEL_IMAGE="${OUT_DIR}/vmlinuz"
TOYBOX_VERSION="0.8.11"
DINIT_VERSION="0.19.2"
KERNEL_VERSION="${KERNEL_VERSION:-7.1.3}"
KERNEL_7="${KERNEL_7:-1}"
KERNEL_CONFIG="${KERNEL_CONFIG:-alpenglow-qemu-minimal}"
ARCH="${KERNEL_ARCH:-x86_64}"
BOOT_MODE="${BOOT_MODE:-diskless}"
ALPENGLOW_MODULE="${ROOT_DIR}/build/native/alpenglow_core.ko"
BUILD_PROFILE="${BUILD_PROFILE:-standard}"
BUILD_ONLY="${BUILD_ONLY:-0}"
if [ "${INITRAMFS:-}" = "" ]; then
  if [ "${BUILD_PROFILE}" = "desktop" ]; then
    INITRAMFS="${OUT_DIR}/initramfs.cpio.zst"
  elif command -v lz4 >/dev/null 2>&1; then
    INITRAMFS="${OUT_DIR}/initramfs.cpio.lz4"
  else
    INITRAMFS="${OUT_DIR}/initramfs.cpio.zst"
  fi
fi
MEMORY_MB="${MEMORY_MB:-2048}"
QEMU_MACHINE="${QEMU_MACHINE:-q35}"
QEMU_CPU="${QEMU_CPU:-}"
# Auto-detect acceleration: prefer KVM, then HVF (macOS), fall back TCG
ACCEL="${ACCEL:-}"
if [ -z "$ACCEL" ]; then
  if [ -c /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    ACCEL=kvm
  elif timeout 2 qemu-system-x86_64 -machine ${QEMU_MACHINE},accel=hvf -M none </dev/null >/dev/null 2>&1; then
    ACCEL=hvf
  else
    ACCEL=tcg
  fi
fi
EFI="${EFI:-1}"
GRAPHICAL="${GRAPHICAL:-0}"
GRAPHICS_BACKEND="${GRAPHICS_BACKEND:-software}"
ALPENGLOW_DESKTOP_FULL="${ALPENGLOW_DESKTOP_FULL:-1}"
FAST="${FAST:-0}"
if [ "${FAST}" = "1" ]; then
  # SeaBIOS is faster than OVMF in this QEMU config; keep EFI off for speed.
  EFI=0
  KERNEL_FASTINIT=1
  BUILD_PROFILE=minimal
  GRAPHICAL=0
  BOOT_MODE=diskless
fi
for arg in "$@"; do
  case "$arg" in
    --graphical) GRAPHICAL=1 ;;
  esac
done
if [ "${GRAPHICAL}" = "1" ] && [ "${MEMORY_MB}" = "2048" ]; then
  MEMORY_MB=4096
fi
# virtio-gpu needs CONFIG_DRM_VIRTIO_GPU (virt.config)
KERNEL_VIRT_STAMP="${OUT_DIR}/.kernel-virtio-gpu.ok"
if [ "${GRAPHICAL}" = "1" ]; then
  BUILD_SERVICES="${BUILD_SERVICES:-1}"
  KERNEL_BUILD=1
  KERNEL_7=0
  if [ ! -f "${KERNEL_VIRT_STAMP}" ] || [ ! -f "${KERNEL_IMAGE}" ]; then
    rm -f "${KERNEL_IMAGE}"
    echo "→ graphical: need kernel with virtio-gpu (minimal+virt.config)"
  fi
fi

NPROC="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
MAKE_CMD="make"
if command -v gmake >/dev/null 2>&1; then
  MAKE_CMD="gmake"
fi

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

# Zig init (replaces /bin/toybox sh /init)
ZIG="${ZIG:-zig}"
if ! command -v "${ZIG}" >/dev/null 2>&1; then
  if command -v /usr/local/bin/zig >/dev/null 2>&1; then
    ZIG=/usr/local/bin/zig
  elif command -v /opt/homebrew/Cellar/zig/0.16.0_1/bin/zig >/dev/null 2>&1; then
    ZIG=/opt/homebrew/Cellar/zig/0.16.0_1/bin/zig
  fi
fi
if [ "${ZIG_INIT:-0}" = "1" ] && command -v "${ZIG}" >/dev/null 2>&1; then
  echo "→ Building Zig init..."
  "${ZIG}" build-exe "${ROOT_DIR}/system/init/init.zig" \
    -target x86_64-linux-musl -O ReleaseSmall -fstrip \
    -femit-bin="${OUT_DIR}/alpenglow-init" 2>&1 | tail -5
  if [ -f "${OUT_DIR}/alpenglow-init" ]; then
    file "${OUT_DIR}/alpenglow-init" | grep -q x86-64 || { echo "ERROR: init not x86_64"; exit 1; }
    echo "  init: ${OUT_DIR}/alpenglow-init"
  fi
fi
if command -v "${ZIG}" >/dev/null 2>&1; then
  if [ ! -f "${OUT_DIR}/alpenglow-ctl/bin/alpenglow-ctl" ]; then
    echo "→ Building alpenglow-ctl..."
    (cd "${ROOT_DIR}/system/alpenglow-ctl" && "${ZIG}" build -Drelease=true -Dtarget=x86_64-linux-musl --prefix "${OUT_DIR}/alpenglow-ctl") 2>&1 | tail -5
  fi
fi

# Kernel
if [ "${FAST}" = "1" ] && [ "${ARCH}" = "x86_64" ]; then
  # FAST path: build a tiny kernel with embedded initramfs after initramfs is ready.
  : # placeholder; build happens after initramfs
elif [ ! -f "${KERNEL_IMAGE}" ]; then
  if [ "${GRAPHICAL}" = "1" ] && [ "${KERNEL_BUILD:-0}" = "1" ] && [ "${ARCH}" = "x86_64" ]; then
    sh "${BACKEND_DIR}/scripts/build-kernel-qemu-graphical.sh" "${OUT_DIR}" "${ROOT_DIR}"
  elif [ "${KERNEL_7}" = "1" ] && [ "${ARCH}" = "x86_64" ]; then
    echo "→ Building Linux ${KERNEL_VERSION} + CONFIG_RUST=y kernel..."
    KERNEL_SRC="${OUT_DIR}/linux-${KERNEL_VERSION}"
    [ -d "${KERNEL_SRC}" ] || {
      KERNEL_MAJOR_MINOR="$(echo "${KERNEL_VERSION}" | cut -d. -f1).$(echo "${KERNEL_VERSION}" | cut -d. -f2)"
      curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${KERNEL_VERSION}.tar.xz" -o "${OUT_DIR}/linux-${KERNEL_VERSION}.tar.xz"
      tar -xf "${OUT_DIR}/linux-${KERNEL_VERSION}.tar.xz" -C "${OUT_DIR}"
    }
    cd "${KERNEL_SRC}"
    if [ -f "${BACKEND_DIR}/kernel/${KERNEL_CONFIG}.config" ]; then
      cp "${BACKEND_DIR}/kernel/${KERNEL_CONFIG}.config" .config
      make ARCH=x86_64 olddefconfig 2>/dev/null
    else
      make ARCH=x86_64 defconfig 2>/dev/null
      make ARCH=x86_64 kvm_guest.config 2>/dev/null
      make ARCH=x86_64 rust.config 2>/dev/null
    fi
    scripts/config \
      --disable MODULE_SIG_FORMAT --disable MODULE_SIG --disable MODULE_SIG_ALL \
      --disable MODULE_COMPRESS --disable MODULE_COMPRESS_GZIP --disable MODULE_COMPRESS_ALL \
      --disable DEBUG_FS --disable DEBUG_KERNEL --disable DEBUG_INFO --disable FTRACE
    if [ "${EFI:-1}" = "0" ]; then
      scripts/config --disable EFI --disable EFI_STUB --disable RUST
    fi
    # Config overrides: LZ4 + virt drivers + minimal + EFI (for OVMF) + optional fast boot
    cat "${ROOT_DIR}/system/backends/appliance/kernel/lz4.config" >> .config 2>/dev/null || true
    cat "${ROOT_DIR}/system/backends/appliance/kernel/virt.config" >> .config 2>/dev/null || true
    cat "${ROOT_DIR}/system/backends/appliance/kernel/strip-down.config" >> .config 2>/dev/null || true
    if [ "${BUILD_PROFILE}" = "desktop" ]; then
      cat "${ROOT_DIR}/system/backends/appliance/kernel/desktop.config" >> .config 2>/dev/null || true
    else
      cat "${ROOT_DIR}/system/backends/appliance/kernel/minimal.config" >> .config 2>/dev/null || true
    fi
    if [ "${EFI:-1}" = "1" ]; then
      cat "${ROOT_DIR}/system/backends/appliance/kernel/efi.config" >> .config 2>/dev/null || true
    fi
    if [ "${KERNEL_UNCOMPRESSED:-0}" = "1" ]; then
      cat "${ROOT_DIR}/system/backends/appliance/kernel/uncompressed.config" >> .config 2>/dev/null || true
    fi
    if [ "${KERNEL_FASTINIT:-0}" = "1" ]; then
      cat "${ROOT_DIR}/system/backends/appliance/kernel/fastinit.config" >> .config 2>/dev/null || true
    fi
    ${MAKE_CMD} ARCH=x86_64 olddefconfig 2>/dev/null
    echo "→ compiling bzImage (this can take several minutes)..."
    ${MAKE_CMD} -j"${NPROC}" ARCH=x86_64 bzImage
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
    # Base stripped config (auto-adapted to whatever kernel version)
    cp "${ROOT_DIR}/system/backends/appliance/kernel/alpenglow-qemu-minimal.config" "${KERNEL_SRC}/.config"
    cat "${ROOT_DIR}/system/backends/appliance/kernel/lz4.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    cat "${ROOT_DIR}/system/backends/appliance/kernel/virt.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    cat "${ROOT_DIR}/system/backends/appliance/kernel/strip-down.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    if [ "${BUILD_PROFILE}" = "desktop" ]; then
      cat "${ROOT_DIR}/system/backends/appliance/kernel/desktop.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    else
      cat "${ROOT_DIR}/system/backends/appliance/kernel/minimal.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    fi
    if [ "${EFI:-1}" = "1" ]; then
      cat "${ROOT_DIR}/system/backends/appliance/kernel/efi.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    fi
    if [ "${KERNEL_UNCOMPRESSED:-0}" = "1" ]; then
      cat "${ROOT_DIR}/system/backends/appliance/kernel/uncompressed.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    fi
    if [ "${KERNEL_FASTINIT:-0}" = "1" ]; then
      cat "${ROOT_DIR}/system/backends/appliance/kernel/fastinit.config" >> "${KERNEL_SRC}/.config" 2>/dev/null || true
    fi
    ${MAKE_CMD} -C "${KERNEL_SRC}" ARCH=x86_64 olddefconfig >/dev/null 2>&1
    echo "→ compiling bzImage (this can take several minutes)..."
    ${MAKE_CMD} -j"${NPROC}" -C "${KERNEL_SRC}" ARCH=x86_64 bzImage
    cp "${KERNEL_SRC}/arch/x86/boot/bzImage" "${KERNEL_IMAGE}"
    if [ "${GRAPHICAL}" = "1" ]; then
      touch "${KERNEL_VIRT_STAMP}"
    fi
  else
    echo "KERNEL_7=0 requires KERNEL_BUILD=1; no distro netboot kernel fallback is used." >&2
    exit 1
  fi
  echo "  kernel: ${KERNEL_IMAGE}"
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
    tar -xf greetd.tar.gz 2>/dev/null || exit 0
    [ -d "greetd-v${GRETD_VERSION}" ] || exit 0
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
    echo "19fe1d9f4664d445a69a96c71e8fdb60bcd8df24c73d1386e02287f7366ad422  chrony.tar.gz" | sha256sum -c - || exit 1
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

# Graphical builds: alpenglowed (glibc) + graphics libs
if [ "${GRAPHICAL}" = "1" ]; then
  echo "→ Building graphical stack (alpenglowed + graphics libs)..."

  # alpenglowed with glibc dynamic linking
  ALPENGLOWED_GLIBC_BIN="${OUT_DIR}/alpenglowed-glibc/usr/bin/alpenglowed"
  if [ ! -f "${ALPENGLOWED_GLIBC_BIN}" ]; then
    sh "${BACKEND_DIR}/scripts/build-alpenglowed-glibc.sh" "${OUT_DIR}" "${ROOT_DIR}/../alpenglowed"
  fi
  echo "  alpenglowed: ${ALPENGLOWED_GLIBC_BIN}"

  # glibc Mesa/Vulkan/EGL libs from Debian
  if [ ! -f "${OUT_DIR}/glibc-libs/lib/x86_64-linux-gnu/libvulkan.so.1" ] || [ "$(cat "${OUT_DIR}/glibc-libs/.graphics-backend" 2>/dev/null || true)" != "${GRAPHICS_BACKEND}" ]; then
    sh "${BACKEND_DIR}/scripts/install-graphics-libs.sh" "${OUT_DIR}" "${GRAPHICS_BACKEND}"
  fi
  echo "  graphics libs: ${OUT_DIR}/glibc-libs (${GRAPHICS_BACKEND})"
fi

# Compose rootfs
echo "→ Composing rootfs..."
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}/bin" "${ROOTFS_DIR}/sbin" "${ROOTFS_DIR}/etc" "${ROOTFS_DIR}/dev" "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/tmp" "${ROOTFS_DIR}/run" "${ROOTFS_DIR}/usr/local/bin"

# Toybox
cp "${OUT_DIR}/toybox" "${ROOTFS_DIR}/bin/toybox"
for applet in sh ls cat cp mv rm mkdir rmdir ln mount umount ps kill sleep echo test \
  basename dirname chmod chown touch clear printf yes false true head tail sort wc cut \
  tr od strings uniq diff sed grep find xargs dd df du stat id whoami hostname \
  dmesg modprobe insmod switch_root getty login more less tar gzip gunzip zcat bzcat \
  date cal reboot halt poweroff passwd syslogd crond logger; do
  ln -sf /bin/toybox "${ROOTFS_DIR}/bin/${applet}" 2>/dev/null || true
done
toybox_has() { "${OUT_DIR}/toybox" "$1" --help >/dev/null 2>&1; }
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
if [ -f "${OUT_DIR}/dinit" ]; then
  cp "${OUT_DIR}/dinit" "${ROOTFS_DIR}/sbin/dinit"
elif [ -f "${OUT_DIR}/dinit/dinit" ]; then
  cp "${OUT_DIR}/dinit/dinit" "${ROOTFS_DIR}/sbin/dinit"
fi
if [ -f "${OUT_DIR}/dinit-install/sbin/dinitctl" ]; then
  cp "${OUT_DIR}/dinit-install/sbin/dinitctl" "${ROOTFS_DIR}/sbin/"
fi

# Install userspace services (if built via BUILD_SERVICES=1)
if [ -d "${OUT_DIR}/dropbear" ]; then
  cp -R "${OUT_DIR}/dropbear/" "${ROOTFS_DIR}/"
  mkdir -p "${ROOTFS_DIR}/etc/dropbear"
fi
if [ "${BUILD_PROFILE}" != "minimal" ]; then
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
  if [ -d "${OUT_DIR}/chrony" ]; then
    cp -R "${OUT_DIR}/chrony/" "${ROOTFS_DIR}/"
    mkdir -p "${ROOTFS_DIR}/etc/chrony"
  fi
  if [ -d "${OUT_DIR}/dnsmasq" ]; then
    cp -R "${OUT_DIR}/dnsmasq/" "${ROOTFS_DIR}/"
  fi
fi

# Graphical stack: alpenglowed (glibc) + isolated libs
# Installed before BOOT_SERVICES so availability checks work
if [ "${GRAPHICAL}" = "1" ]; then
  ALPENGLOWED_GLIBC_BIN="${OUT_DIR}/alpenglowed-glibc/usr/bin/alpenglowed"
  if [ -f "${ALPENGLOWED_GLIBC_BIN}" ]; then
    mkdir -p "${ROOTFS_DIR}/usr/bin"
    cp "${ALPENGLOWED_GLIBC_BIN}" "${ROOTFS_DIR}/usr/bin/alpenglowed-bin"
    chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglowed-bin"
  fi

  GREETER_GLIBC_BIN=""
  if [ "${ALPENGLOW_DESKTOP_FULL}" = "1" ]; then
    GREETER_GLIBC_BIN="${OUT_DIR}/alpenglow-greeter-glibc/usr/bin/alpenglow-greeter"
    if [ ! -f "${GREETER_GLIBC_BIN}" ] && [ -d "${ROOT_DIR}/../alpenglowed/alpenglow-greeter" ]; then
      sh "${BACKEND_DIR}/scripts/build-alpenglow-greeter-glibc.sh" "${OUT_DIR}" "${ROOT_DIR}/../alpenglowed"
    fi
  fi
  if [ -n "${GREETER_GLIBC_BIN}" ] && [ -f "${GREETER_GLIBC_BIN}" ]; then
    cp "${GREETER_GLIBC_BIN}" "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-bin"
    chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-bin"
  else
    ALPENGLOW_AUTOLOGIN=1
  fi

  mkdir -p "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}/etc/alpenglow" "${ROOTFS_DIR}/etc/greetd"
  cp "${BACKEND_DIR}/scripts/alpenglow-session-start" "${ROOTFS_DIR}/usr/local/bin/"
  chmod 755 "${ROOTFS_DIR}/usr/local/bin/alpenglow-session-start"
  cp "${BACKEND_DIR}/rootfs-overlay/etc/alpenglow/greeter-default-user" "${ROOTFS_DIR}/etc/alpenglow/" 2>/dev/null || true
  cp "${BACKEND_DIR}/rootfs-overlay/etc/greetd/config.toml" "${ROOTFS_DIR}/etc/greetd/" 2>/dev/null || true
  cp "${BACKEND_DIR}/rootfs-overlay/etc/greetd/config-autologin.toml" "${ROOTFS_DIR}/etc/greetd/" 2>/dev/null || true
  if [ "${ALPENGLOW_AUTOLOGIN:-0}" = "1" ]; then
    ln -sf config-autologin.toml "${ROOTFS_DIR}/etc/greetd/config.toml"
  fi

  if [ -d "${OUT_DIR}/glibc-libs" ]; then
    mkdir -p "${ROOTFS_DIR}/lib/x86_64-linux-gnu" "${ROOTFS_DIR}/lib64"
    cp "${OUT_DIR}/glibc-libs/lib/x86_64-linux-gnu/"lib*.so* "${ROOTFS_DIR}/lib/x86_64-linux-gnu/" 2>/dev/null || true
    cp "${OUT_DIR}/glibc-libs/lib64/ld-linux-x86-64.so.2" "${ROOTFS_DIR}/lib64/" 2>/dev/null || true
    if [ -d "${OUT_DIR}/glibc-libs/usr/lib/x86_64-linux-gnu/dri" ]; then
      mkdir -p "${ROOTFS_DIR}/usr/lib/x86_64-linux-gnu/dri"
      cp "${OUT_DIR}/glibc-libs/usr/lib/x86_64-linux-gnu/dri/"*.so "${ROOTFS_DIR}/usr/lib/x86_64-linux-gnu/dri/" 2>/dev/null || true
    fi
    if [ -d "${OUT_DIR}/glibc-libs/usr/share/vulkan/icd.d" ]; then
      mkdir -p "${ROOTFS_DIR}/usr/share/vulkan/icd.d"
      cp "${OUT_DIR}/glibc-libs/usr/share/vulkan/icd.d/"*.json "${ROOTFS_DIR}/usr/share/vulkan/icd.d/" 2>/dev/null || true
    fi
  fi

  if [ "${GRAPHICS_BACKEND}" = "software" ]; then
    cat > "${ROOTFS_DIR}/usr/bin/alpenglowed-run.sh" << 'ALPWRAP'
#!/bin/sh
export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
export LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json
if [ -f /run/alpenglow/alpenglow.img.zst ]; then
  export ALPENGLOWED_INSTALLER_SOURCE=/run/alpenglow/alpenglow.img.zst
fi
if [ -z "${ALPENGLOWED_INSTALLER_TARGET:-}" ]; then
  for dev in /dev/vda /dev/sda /dev/nvme0n1 /dev/mmcblk0; do
    [ -b "$dev" ] && { export ALPENGLOWED_INSTALLER_TARGET="$dev"; break; }
  done
fi
exec /usr/bin/alpenglowed-bin --compositor "$@"
ALPWRAP
    cat > "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-run.sh" << 'GWRAP'
#!/bin/sh
export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
export LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json
exec /usr/bin/alpenglow-greeter-bin "$@"
GWRAP
  else
    cat > "${ROOTFS_DIR}/usr/bin/alpenglowed-run.sh" << 'ALPWRAP'
#!/bin/sh
export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
export LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
if [ -f /run/alpenglow/alpenglow.img.zst ]; then
  export ALPENGLOWED_INSTALLER_SOURCE=/run/alpenglow/alpenglow.img.zst
fi
if [ -z "${ALPENGLOWED_INSTALLER_TARGET:-}" ]; then
  for dev in /dev/vda /dev/sda /dev/nvme0n1 /dev/mmcblk0; do
    [ -b "$dev" ] && { export ALPENGLOWED_INSTALLER_TARGET="$dev"; break; }
  done
fi
exec /usr/bin/alpenglowed-bin --compositor "$@"
ALPWRAP
    cat > "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-run.sh" << 'GWRAP'
#!/bin/sh
export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
export LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
exec /usr/bin/alpenglow-greeter-bin "$@"
GWRAP
  fi
  chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglowed-run.sh"
  chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-run.sh"
else
  ALPENGLOWED_BIN="${ALPENGLOWED_BIN:-}"
  if [ -z "${ALPENGLOWED_BIN}" ]; then
    for candidate in \
      "${ROOT_DIR}/../alpenglowed/target/x86_64-unknown-linux-musl/release/alpenglowed" \
      "${ROOT_DIR}/../alpenglowed/target/release/alpenglowed" \
      "${ROOT_DIR}/../alpenglowed/target/debug/alpenglowed"
    do
      [ -x "${candidate}" ] && { ALPENGLOWED_BIN="${candidate}"; break; }
    done
  fi
  if [ "${BUILD_PROFILE}" != "minimal" ] && [ -n "${ALPENGLOWED_BIN}" ] && [ -x "${ALPENGLOWED_BIN}" ]; then
    mkdir -p "${ROOTFS_DIR}/usr/bin"
    cp "${ALPENGLOWED_BIN}" "${ROOTFS_DIR}/usr/bin/alpenglowed"
    chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglowed"
  fi
fi

mkdir -p "${ROOTFS_DIR}/usr/local/bin"
mkdir -p "${ROOTFS_DIR}/etc/alpenglow"
cp "${BACKEND_DIR}/kernel-policy.json" "${ROOTFS_DIR}/etc/alpenglow/kernel-policy.json"
for pair in \
  "alpenglow-ctl/alpenglow-kernelctl:alpenglow-kernelctl" \
  "alpenglow-ctl/alpenglow-netd-zig:alpenglow-netd" \
  "alpenglow-ctl/alpenglow-zramctl-zig:alpenglow-zramctl-zig" \
  "alpenglow-ctl/alpenglow-pressurectl-zig:alpenglow-pressurectl-zig"
do
  src="${pair%%:*}"
  dst="${pair##*:}"
  if [ -f "${OUT_DIR}/${src%/*}/bin/${src#*/}" ]; then
    cp "${OUT_DIR}/${src%/*}/bin/${src#*/}" "${ROOTFS_DIR}/usr/local/bin/${dst}"
    chmod 755 "${ROOTFS_DIR}/usr/local/bin/${dst}"
  fi
done

# shellcheck source=scripts/lib/assemble-rootfs.sh
. "${ROOT_DIR}/scripts/lib/assemble-rootfs.sh"
assemble_rootfs_config

if [ "${GRAPHICAL}" = "1" ]; then
  cat > "${ROOTFS_DIR}/etc/dinit.d/alpenglowed" << 'ALPENGLOW'
type = process
command = /usr/bin/alpenglowed-run.sh
restart = yes
ALPENGLOW
fi

# Oil (native package manager)
OIL_BIN="${ROOT_DIR}/build/native/oil"
OIL_SRC="${ROOT_DIR}/system/oil"
if [ "${BUILD_PROFILE}" != "minimal" ] && [ -f "${OIL_BIN}" ]; then
  cp "${OIL_BIN}" "${ROOTFS_DIR}/usr/local/bin/oil"
elif [ "${BUILD_PROFILE}" != "minimal" ] && [ -d "${OIL_SRC}" ]; then
  echo "→ Building Oil (native package manager)..."
  docker run --rm --platform linux/amd64 -v "${OIL_SRC}:/oil-src" -v "${OUT_DIR}:/out" alpine:3.21 sh -c '
    apk add --no-cache rust cargo make gcc musl-dev >/dev/null
    cd /oil-src
    cargo build --release --no-default-features --features wax 2>/dev/null
    cp target/release/oil /out/oil 2>/dev/null
  ' 2>&1 | tail -1
  if [ -f "${OUT_DIR}/oil" ]; then
    cp "${OUT_DIR}/oil" "${ROOTFS_DIR}/usr/local/bin/oil"
    chmod 755 "${ROOTFS_DIR}/usr/local/bin/oil"
    echo "  oil: ${ROOTFS_DIR}/usr/local/bin/oil"
  fi
fi

# Build initramfs
echo "→ Building initramfs..."
case "${INITRAMFS}" in
  *.zst)
  (cd "${ROOTFS_DIR}" && find . -print | cpio -o -H newc 2>/dev/null | zstd -6 -T0 > "${INITRAMFS}")
  ;;
  *)
  (cd "${ROOTFS_DIR}" && find . -print | cpio -o -H newc 2>/dev/null | lz4 -l -9 -c > "${INITRAMFS}")
  ;;
esac
echo "  initramfs: ${INITRAMFS} ($(du -sh "${INITRAMFS}" | cut -f1))"
echo ""

# FAST kernel: tiny kernel with embedded initramfs
if [ "${FAST}" = "1" ] && [ "${ARCH}" = "x86_64" ]; then
  KERNEL_PROFILE=fast sh "${BACKEND_DIR}/scripts/build-kernel-fast.sh" "${OUT_DIR}" "${ROOT_DIR}"
fi

if [ "${BUILD_ONLY}" = "1" ]; then
  exit 0
fi

# shellcheck source=scripts/lib/qemu-boot-x86_64.sh
. "${ROOT_DIR}/scripts/lib/qemu-boot-x86_64.sh"
qemu_boot_x86_64
