#!/bin/sh
# Build and boot Alpenglow native.
# Uses Docker for host-independent compilation.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/appliance"
OUT_DIR="${ROOT_DIR}/build/native"
ROOTFS_DIR="${OUT_DIR}/rootfs"
KERNEL_IMAGE="${OUT_DIR}/vmlinuz"
TOYBOX_VERSION="0.8.11"
DINIT_VERSION="0.19.2"
KERNEL_VERSION="${KERNEL_VERSION:-7.0.12}"
KERNEL_7="${KERNEL_7:-1}"
KERNEL_CONFIG="${KERNEL_CONFIG:-alpenglow-qemu-minimal}"
ARCH="${KERNEL_ARCH:-x86_64}"
BOOT_MODE="${BOOT_MODE:-diskless}"
ALPENGLOW_MODULE="${ROOT_DIR}/build/native/alpenglow_core.ko"
BUILD_PROFILE="${BUILD_PROFILE:-standard}"
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
  BUILD_SERVICES=1
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

# Graphical builds: cage (musl) + alpenglowed (glibc) + graphics libs
if [ "${GRAPHICAL}" = "1" ]; then
  echo "→ Building graphical stack (cage + alpenglowed + graphics libs)..."

  # cage + musl shared libs from Alpine
  if [ ! -f "${OUT_DIR}/cage/usr/bin/cage" ] || [ ! -f "${OUT_DIR}/cage/lib/ld-musl-x86_64.so.1" ] || [ -f "${OUT_DIR}/cage/usr/bin/Xwayland" ] || [ -f "${OUT_DIR}/cage/usr/lib/libLLVM.so.19.1" ] || [ -f "${OUT_DIR}/cage/usr/lib/gallium-pipe/pipe_radeonsi.so" ]; then
    rm -rf "${OUT_DIR}/cage"
    sh "${BACKEND_DIR}/scripts/build-cage.sh" "${OUT_DIR}"
  fi
  echo "  cage: ${OUT_DIR}/cage/usr/bin/cage"

  # alpenglowed with glibc dynamic linking
  ALPENGLOWED_GLIBC_BIN="${OUT_DIR}/alpenglowed-glibc/usr/bin/alpenglowed"
  if [ ! -f "${ALPENGLOWED_GLIBC_BIN}" ]; then
    sh "${BACKEND_DIR}/scripts/build-alpenglowed-glibc.sh" "${OUT_DIR}" "${ROOT_DIR}/../alpenglowed"
  fi
  echo "  alpenglowed: ${ALPENGLOWED_GLIBC_BIN}"

  # glibc Mesa/Vulkan/EGL libs from Debian
  if [ ! -f "${OUT_DIR}/glibc-libs/lib/x86_64-linux-gnu/libvulkan.so.1" ]; then
    sh "${BACKEND_DIR}/scripts/install-graphics-libs.sh" "${OUT_DIR}"
  fi
  echo "  graphics libs: ${OUT_DIR}/glibc-libs"
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
if [ -f "${OUT_DIR}/dinit" ]; then
  cp "${OUT_DIR}/dinit" "${ROOTFS_DIR}/sbin/dinit"
elif [ -f "${OUT_DIR}/dinit/dinit" ]; then
  cp "${OUT_DIR}/dinit/dinit" "${ROOTFS_DIR}/sbin/dinit"
fi
if [ -f "${OUT_DIR}/dinit-install/sbin/dinitctl" ]; then
  cp "${OUT_DIR}/dinit-install/sbin/dinitctl" "${ROOTFS_DIR}/sbin/"
fi

# Dinit service files — copy all, enable per profile
mkdir -p "${ROOTFS_DIR}/etc/dinit.d/boot.d"
for svc in "${BACKEND_DIR}/dinit/"*; do
  name=$(basename "${svc}")
  cp "${svc}" "${ROOTFS_DIR}/etc/dinit.d/${name}"
done

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

# Graphical stack: cage (musl) + alpenglowed (glibc) + isolated libs
# Installed before BOOT_SERVICES so availability checks work
if [ "${GRAPHICAL}" = "1" ]; then
  if [ -d "${OUT_DIR}/cage" ]; then
    mkdir -p "${ROOTFS_DIR}/usr/bin" "${ROOTFS_DIR}/usr/lib/musl" "${ROOTFS_DIR}/lib"
    cp "${OUT_DIR}/cage/usr/bin/cage" "${ROOTFS_DIR}/usr/bin/"
    cp "${OUT_DIR}/cage/usr/bin/Xwayland" "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || true
    cp "${OUT_DIR}/cage/usr/bin/seatd" "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || true
    cp "${OUT_DIR}/cage/usr/bin/seatd-launch" "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || true
    cp "${OUT_DIR}/cage/lib/ld-musl-x86_64.so.1" "${ROOTFS_DIR}/lib/" 2>/dev/null || true
    # musl libc: ld-musl is the same binary, symlink the libc name
    ln -sf ld-musl-x86_64.so.1 "${ROOTFS_DIR}/lib/libc.musl-x86_64.so.1" 2>/dev/null || true
    cp "${OUT_DIR}/cage/usr/lib/lib"*.so* "${ROOTFS_DIR}/usr/lib/musl/" 2>/dev/null || true
    if [ -d "${OUT_DIR}/cage/usr/lib/dri" ]; then
      mkdir -p "${ROOTFS_DIR}/usr/lib/musl/dri"
      cp "${OUT_DIR}/cage/usr/lib/dri/"*.so "${ROOTFS_DIR}/usr/lib/musl/dri/" 2>/dev/null || true
    fi
    if [ -d "${OUT_DIR}/cage/usr/lib/gallium-pipe" ]; then
      mkdir -p "${ROOTFS_DIR}/usr/lib/musl/gallium-pipe"
      cp "${OUT_DIR}/cage/usr/lib/gallium-pipe/"*.so "${ROOTFS_DIR}/usr/lib/musl/gallium-pipe/" 2>/dev/null || true
    fi
    if [ -d "${OUT_DIR}/cage/usr/lib/gbm" ]; then
      mkdir -p "${ROOTFS_DIR}/usr/lib/musl/gbm"
      cp "${OUT_DIR}/cage/usr/lib/gbm/"*.so "${ROOTFS_DIR}/usr/lib/musl/gbm/" 2>/dev/null || true
    fi
  fi

  ALPENGLOWED_GLIBC_BIN="${OUT_DIR}/alpenglowed-glibc/usr/bin/alpenglowed"
  if [ -f "${ALPENGLOWED_GLIBC_BIN}" ]; then
    mkdir -p "${ROOTFS_DIR}/usr/bin"
    cp "${ALPENGLOWED_GLIBC_BIN}" "${ROOTFS_DIR}/usr/bin/alpenglowed-bin"
    chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglowed-bin"
  fi

  GREETER_GLIBC_BIN="${OUT_DIR}/alpenglow-greeter-glibc/usr/bin/alpenglow-greeter"
  if [ ! -f "${GREETER_GLIBC_BIN}" ] && [ -d "${ROOT_DIR}/../alpenglowed/alpenglow-greeter" ]; then
    sh "${BACKEND_DIR}/scripts/build-alpenglow-greeter-glibc.sh" "${OUT_DIR}" "${ROOT_DIR}/../alpenglowed"
  fi
  if [ -f "${GREETER_GLIBC_BIN}" ]; then
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

  cat > "${ROOTFS_DIR}/usr/bin/cage-run.sh" << 'CAGEWRAP'
#!/bin/sh
unset WAYLAND_DISPLAY
export XDG_RUNTIME_DIR=/run
export LIBSEAT_BACKEND=seatd
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER=pixman
export LD_LIBRARY_PATH=/usr/lib/musl
export LIBGL_DRIVERS_PATH=/usr/lib/musl/dri
export EGL_DRIVER=swrast
mkdir -p /run
chmod 700 /run
for i in 1 2 3 4 5 6 7 8 9 10; do
  [ -S /run/seatd.sock ] && break
  sleep 0.5
done
exec /usr/bin/cage /usr/bin/alpenglowed-run.sh
CAGEWRAP
  chmod 755 "${ROOTFS_DIR}/usr/bin/cage-run.sh"

  cat > "${ROOTFS_DIR}/usr/bin/alpenglowed-run.sh" << 'ALPWRAP'
#!/bin/sh
export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
export LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json
exec /usr/bin/alpenglowed-bin "$@"
ALPWRAP
  chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglowed-run.sh"

  cat > "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-run.sh" << 'GWRAP'
#!/bin/sh
export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
export LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json
exec /usr/bin/alpenglow-greeter-bin "$@"
GWRAP
  chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-run.sh"

  cat > "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-cage.sh" << 'GCAGE'
#!/bin/sh
unset WAYLAND_DISPLAY
export XDG_RUNTIME_DIR=/run
export LIBSEAT_BACKEND=seatd
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER=pixman
export LD_LIBRARY_PATH=/usr/lib/musl
export LIBGL_DRIVERS_PATH=/usr/lib/musl/dri
export EGL_DRIVER=swrast
mkdir -p /run
chmod 700 /run
for i in 1 2 3 4 5 6 7 8 9 10; do
  [ -S /run/seatd.sock ] && break
  sleep 0.5
done
exec /usr/bin/cage /usr/bin/alpenglow-greeter-run.sh
GCAGE
  chmod 755 "${ROOTFS_DIR}/usr/bin/alpenglow-greeter-cage.sh"

  # Override seatd service: run as root with musl LD_LIBRARY_PATH
  cat > "${ROOTFS_DIR}/etc/dinit.d/seatd" << 'SEATD'
# Seat management daemon
type = process
command = /usr/bin/seatd -g seat
restart = yes
run-as = root
SEATD

  cat > "${ROOTFS_DIR}/etc/dinit.d/velox" << 'VELUX'
# cage — Wayland compositor (wlroots-based kiosk)
type = process
command = /usr/bin/cage-run.sh
restart = yes
depends-on = seatd
VELUX
  cat > "${ROOTFS_DIR}/etc/dinit.d/alpenglowed" << 'ALPENGLOW'
type = process
command = /usr/bin/alpenglowed-run.sh
restart = yes
depends-on = velox
ALPENGLOW
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

# Define enabled services per profile
# Only include services whose binaries actually exist in the rootfs
case "${BUILD_PROFILE}" in
  minimal)
    # Headless serial-only: only run the two services required to reach login.
    BOOT_SERVICES="shell-ttyS0 mount-filesystems"
    ;;
  standard)
    BOOT_SERVICES="shell-ttyS0 mount-filesystems networking syslogd crond"
    [ -f "${ROOTFS_DIR}/usr/bin/dropbear" ] && BOOT_SERVICES="${BOOT_SERVICES} dropbear"
    [ -f "${ROOTFS_DIR}/usr/sbin/chronyd" ] && BOOT_SERVICES="${BOOT_SERVICES} chronyd"
    [ -f "${ROOTFS_DIR}/usr/sbin/dnsmasq" ] && BOOT_SERVICES="${BOOT_SERVICES} dnsmasq"
    ;;
  desktop)
    BOOT_SERVICES="shell-ttyS0 mount-filesystems"
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
restart = yes
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
{
  echo "type = scripted"
  echo "command = /bin/true"
  echo "restart = no"
  for svc in ${BOOT_SERVICES}; do
    echo "depends-on = ${svc}"
  done
} > "${ROOTFS_DIR}/etc/dinit.d/boot"

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
seatd:x:772:772:seatd:/var/empty:/sbin/nologin
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
if [ -f "${ALPENGLOW_MODULE}" ]; then
  cp "${ALPENGLOW_MODULE}" "${ROOTFS_DIR}/lib/modules/"
fi

# Init — dinit as primary PID 1, manages all services.
# Use the Zig init binary if available; otherwise fall back to shell.
if [ "${ZIG_INIT:-0}" = "1" ] && [ -f "${OUT_DIR}/alpenglow-init" ]; then
  cp "${OUT_DIR}/alpenglow-init" "${ROOTFS_DIR}/init"
  chmod 755 "${ROOTFS_DIR}/init"
else
  cat > "${ROOTFS_DIR}/init" << 'INIT'
#!/bin/toybox sh
/bin/toybox mount -t proc proc /proc
/bin/toybox mount -t sysfs sysfs /sys
/bin/toybox mount -t devtmpfs devtmpfs /dev
exec </dev/ttyS0 >/dev/ttyS0 2>&1
/bin/toybox mount -t tmpfs tmpfs /run
/bin/toybox mkdir -p /dev/shm 2>/dev/null
/bin/toybox mount -t tmpfs -o mode=1777,size=256m tmpfs /dev/shm
/bin/toybox mkdir -p /run/user/0
/bin/toybox chmod 700 /run/user/0
/bin/toybox mkdir -p /state
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
  /bin/toybox mount -t bcachefs -o rw,nosuid,nodev "$state_dev" /state 2>/dev/null && echo "Mounted state: $state_dev"
fi
echo ""
echo "Alpenglow boot"
echo ""
# Log memory at boot for benchmark
if [ -f /proc/meminfo ]; then
  /bin/toybox grep -E 'MemTotal|MemFree' /proc/meminfo 2>/dev/null
fi
exec /sbin/dinit -d /etc/dinit.d -s -t boot
INIT
  chmod 755 "${ROOTFS_DIR}/init"
fi

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

# Boot
require_cmd qemu-system-x86_64
echo "→ Booting Alpenglow..."
echo "  kernel:    ${KERNEL_IMAGE}"
echo "  initramfs: ${INITRAMFS}"
echo "  mode:      ${BOOT_MODE}"
echo "  efi:       ${EFI}"
if [ "${GRAPHICAL}" = "1" ]; then
  echo "  display:   graphical (virtio-gpu)"
fi
echo "  (Ctrl-A X to quit)"
echo ""

if [ "${GRAPHICAL}" = "1" ]; then
  # Pick a display backend available on this host
  QEMU_DISPLAY="${QEMU_DISPLAY:-}"
  if [ -z "${QEMU_DISPLAY}" ]; then
    for backend in gtk sdl cocoa; do
      if timeout 2 qemu-system-x86_64 -display ${backend},show-cursor=off -M none </dev/null >/dev/null 2>&1; then
        QEMU_DISPLAY="${backend}"
        break
      fi
    done
  fi
  QEMU_DISPLAY="${QEMU_DISPLAY:-none}"
  QEMU_OPTS="-machine ${QEMU_MACHINE},accel=${ACCEL} -m ${MEMORY_MB} -smp 2 -no-reboot"
  if [ "${QEMU_DISPLAY}" = "none" ]; then
    QEMU_OPTS="${QEMU_OPTS} -display none"
  else
    QEMU_OPTS="${QEMU_OPTS} -display ${QEMU_DISPLAY}"
  fi
  if [ -f "${KERNEL_VIRT_STAMP}" ]; then
    QEMU_OPTS="${QEMU_OPTS} -device virtio-gpu-pci"
  else
    QEMU_OPTS="${QEMU_OPTS} -vga std"
  fi
  QEMU_OPTS="${QEMU_OPTS} -chardev stdio,id=char0,mux=on,signal=off -serial chardev:char0 -mon chardev=char0 -boot order=n -device e1000,romfile=,netdev=net0 -netdev user,id=net0"
  KERNEL_CMDLINE="console=ttyS0 console=tty0 init=/init"
else
  QEMU_OPTS="-machine ${QEMU_MACHINE},accel=${ACCEL} -m ${MEMORY_MB} -smp 2 -nographic -no-reboot"
  if [ -z "${QEMU_CPU}" ] && [ "${ACCEL}" = "kvm" ]; then
    QEMU_OPTS="${QEMU_OPTS} -cpu host"
  elif [ -n "${QEMU_CPU}" ]; then
    QEMU_OPTS="${QEMU_OPTS} -cpu ${QEMU_CPU}"
  fi
  QEMU_OPTS="${QEMU_OPTS} -boot order=n -device e1000,romfile=,netdev=net0 -netdev user,id=net0"
  KERNEL_CMDLINE="quiet console=ttyS0 init=/init"
fi

EMBEDDED_INITRAMFS=""
if [ "${FAST}" = "1" ] && [ -f "${OUT_DIR}/.kernel-fast.ok" ] && [ "${KERNEL_IMAGE}" = "${OUT_DIR}/vmlinuz" ]; then
  EMBEDDED_INITRAMFS="1"
fi

if [ "${EFI}" = "1" ]; then
  # UEFI boot via OVMF pflash (available, but measured slower than SeaBIOS)
  OVMF_CODE=""
  for p in /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/local/share/qemu/edk2-x86_64-code.fd /opt/homebrew/share/qemu/edk2-x86_64-code.fd /opt/homebrew/Cellar/qemu/*/share/qemu/edk2-x86_64-code.fd; do
    [ -f "$p" ] && { OVMF_CODE="$p"; break; }
  done
  if [ -n "${OVMF_CODE}" ]; then
    OVMF_VARS="${OUT_DIR}/ovmf-vars.fd"
    OVMF_VARS_TEMPLATE=""
    for p in \
      "${OVMF_CODE%CODE.fd}VARS.fd" \
      "${OVMF_CODE%CODE.4m.fd}VARS.4m.fd" \
      "$(dirname "${OVMF_CODE}")/edk2-x86_64-vars.fd" \
      /opt/homebrew/share/qemu/edk2-x86_64-vars.fd \
      /usr/share/OVMF/OVMF_VARS.fd \
      /usr/share/edk2/x64/OVMF_VARS.4m.fd; do
      [ -f "$p" ] && { OVMF_VARS_TEMPLATE="$p"; break; }
    done
    if [ -n "${OVMF_VARS_TEMPLATE}" ]; then
      cp "${OVMF_VARS_TEMPLATE}" "${OVMF_VARS}"
    elif [ ! -f "${OVMF_VARS}" ]; then
      cp "${OVMF_CODE}" "${OVMF_VARS}" 2>/dev/null || true
    fi
    if [ -n "${EMBEDDED_INITRAMFS}" ]; then
      exec qemu-system-x86_64 \
        ${QEMU_OPTS} \
        -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
        -drive if=pflash,format=raw,file="${OVMF_VARS}" \
        -kernel "${KERNEL_IMAGE}" \
        -append "${KERNEL_CMDLINE}"
    else
      exec qemu-system-x86_64 \
        ${QEMU_OPTS} \
        -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
        -drive if=pflash,format=raw,file="${OVMF_VARS}" \
        -kernel "${KERNEL_IMAGE}" \
        -initrd "${INITRAMFS}" \
        -append "${KERNEL_CMDLINE}"
    fi
  fi
  echo "  → OVMF not found, falling back to SeaBIOS"
fi

# Legacy BIOS boot
if [ -n "${EMBEDDED_INITRAMFS}" ]; then
  exec qemu-system-x86_64 \
    ${QEMU_OPTS} \
    -kernel "${KERNEL_IMAGE}" \
    -append "${KERNEL_CMDLINE}"
else
  exec qemu-system-x86_64 \
    ${QEMU_OPTS} \
    -kernel "${KERNEL_IMAGE}" \
    -initrd "${INITRAMFS}" \
    -append "${KERNEL_CMDLINE}"
fi
