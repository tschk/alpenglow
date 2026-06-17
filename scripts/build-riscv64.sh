#!/bin/sh
# Build Alpenglow riscv64 cross-compiled components + initramfs
# Uses Alpenglow's in-house kernel (not Alpine pre-built)
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/build/cross/riscv64"
KERNEL_VERSION="${KERNEL_VERSION:-7.0}"
KERNEL_MAJOR="$(echo "${KERNEL_VERSION}" | cut -d. -f1)"

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

# ── 2. Build Alpenglow kernel for riscv64 ─────────────────────────
build_kernel() {
  if [ -f "${OUT_DIR}/Image" ]; then
    echo "  kernel exists: ${OUT_DIR}/Image"
    return
  fi

  echo "→ Building Alpenglow kernel (Linux ${KERNEL_VERSION}) for riscv64..."

  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker required for cross-compilation" >&2
    exit 1
  fi

  docker run --rm -i \
    -v "${OUT_DIR}:/build" \
    --platform linux/arm64 \
    debian:bookworm-slim sh -c '
      set -eu
      echo "  installing cross-toolchain..."
      apt-get update -qq 2>/dev/null
      apt-get install -y -qq gcc-riscv64-linux-gnu make flex bison bc \
        libelf-dev curl tar xz-utils python3 cpio zstd 2>&1 | tail -3

      KERNEL_VERSION="'${KERNEL_VERSION}'"
      KERNEL_MAJOR="'${KERNEL_MAJOR}'"
      KERNEL_SRC="/tmp/linux-${KERNEL_VERSION}"

      if [ ! -d "${KERNEL_SRC}" ]; then
        echo "  fetching kernel source..."
        cd /tmp
        curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz" -o linux.tar.xz
        tar -xf linux.tar.xz
      fi

      cd "${KERNEL_SRC}"

      echo "  configuring..."
      # RISC-V arch is "riscv" in kernel, not "riscv64"
      make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- defconfig 2>&1
      # Merge 64-bit config on top of defconfig (defconfig is 32-bit)
      make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- 64-bit.config 2>&1

      # Enable virt drivers for QEMU
      scripts/config --enable VIRTIO_MENU
      scripts/config --enable VIRTIO
      scripts/config --enable VIRTIO_PCI
      scripts/config --enable VIRTIO_BLK
      scripts/config --enable VIRTIO_CONSOLE
      scripts/config --enable VIRTIO_NET
      scripts/config --enable VIRTIO_MMIO
      scripts/config --enable VIRTIO_MMIO_CMDLINE_DEVICES
      scripts/config --enable SERIAL_8250
      scripts/config --enable SERIAL_8250_CONSOLE
      scripts/config --enable SERIAL_OF_PLATFORM
      scripts/config --enable SERIAL_EARLYCON_RISCV_SBI
      scripts/config --enable SERIAL_EARLYCON_SEMIHOST
      scripts/config --enable BLK_DEV_INITRD
      scripts/config --enable DEVTMPFS
      scripts/config --enable DEVTMPFS_MOUNT
      scripts/config --enable PRINTK
      scripts/config --enable EARLY_PRINTK
      scripts/config --enable RISCV_SBI_V02

      # Strip unnecessary drivers (minimal profile)
      for d in WLAN WIRELESS SOUND HID USB_SUPPORT DRM FB \
        BACKLIGHT_CLASS_DEVICE INPUT_MOUSE INPUT_JOYSTICK \
        INPUT_TABLET INPUT_TOUCHSCREEN INPUT_MISC NFC BT RFKILL MAC80211 \
        SECURITY_SELINUX SECURITY_SMACK SECURITY_TOMOYO SECURITY_YAMA \
        SECURITY_SAFESETID MODULE_SIG MODULE_SIG_ALL MODULE_SIG_FORMAT \
        DEBUG_FS DEBUG_KERNEL DEBUG_INFO FTRACE; do
        scripts/config --disable "$d" 2>/dev/null || true
      done

      make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- olddefconfig 2>&1

      echo "  building (this takes a while)..."
      if make -j"$(nproc)" ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- Image 2>&1; then
        # cp directly to bind mount can fail on macOS Docker; use cat instead
        cat arch/riscv/boot/Image > /build/Image
        echo "  kernel: /build/Image ($(ls -lh /build/Image | awk "{print \$5}"))"
      else
        echo "ERROR: kernel build failed" >&2
        exit 1
      fi
    '
}

# ── 3. Build initramfs ────────────────────────────────────────────
build_initramfs() {
  echo "→ Building initramfs..."
  local INITRAMFS_DIR=
  INITRAMFS_DIR="$(mktemp -d)"
  trap 'rm -rf "${INITRAMFS_DIR:-}"' EXIT

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

build_kernel
build_initramfs

echo ""
echo "=== riscv64 cross-build complete ==="
ls -lh "${OUT_DIR}/" 2>/dev/null | grep -v kernel-src
