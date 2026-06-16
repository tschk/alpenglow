#!/bin/sh
# Build U-Boot for PINE64 Quartz64 Model A (rk3566_quartz64_defconfig)
set -eu

OUT_DIR="${OUT_DIR:-build/uboot-rk3566}"
U_BOOT_TAG="${U_BOOT_TAG:-v2025.04}"
U_BOOT_DIR="${U_BOOT_DIR:-build/u-boot}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
U_BOOT_ABS="${REPO_ROOT}/${U_BOOT_DIR}"
OUT_ABS="${REPO_ROOT}/${OUT_DIR}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }

echo "=== U-Boot rk3566 build ==="
echo "  target:  rk3566_quartz64_defconfig"
echo "  tag:     ${U_BOOT_TAG}"
echo "  out:     ${OUT_ABS}"
echo "  cc:      ${CROSS_COMPILE}gcc"
echo ""

# Check cross toolchain
TOOLCHAIN_OK=0
if command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
  TOOLCHAIN_OK=1
  echo "→ Cross toolchain found: ${CROSS_COMPILE}gcc"
else
  echo "→ Cross toolchain not found: ${CROSS_COMPILE}gcc"
  echo "  Trying zig cc as alternative..."
  if command -v zig >/dev/null 2>&1; then
    echo "  NOTE: U-Boot requires gcc/binutils (zig cc won't work for U-Boot)"
    echo "  Install aarch64 cross toolchain:"
    echo ""
    echo "  macOS (Homebrew):"
    echo "    brew install aarch64-linux-gnu-binutils aarch64-linux-gnu-gcc"
    echo ""
    echo "  Debian/Ubuntu:"
    echo "    apt-get install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu"
    echo ""
    echo "  Fedora:"
    echo "    dnf install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu"
    echo ""
    echo "  musl-cross-make:"
    echo "    git clone https://github.com/richfelker/musl-cross-make"
    echo "    make TARGET=aarch64-linux-musl -j\$(nproc)"
    exit 1
  fi
  exit 1
fi

# Clone or fetch U-Boot
if [ -d "${U_BOOT_ABS}/.git" ]; then
  echo "→ U-Boot already cloned at ${U_BOOT_ABS}"
  cd "${U_BOOT_ABS}"
  git fetch --tags origin 2>/dev/null || true
else
  echo "→ Cloning U-Boot ${U_BOOT_TAG}..."
  mkdir -p "${U_BOOT_ABS}"
  git clone --depth 1 --branch "${U_BOOT_TAG}" \
    https://source.denx.de/u-boot/u-boot.git "${U_BOOT_ABS}" 2>&1 || {
    echo "  Tag ${U_BOOT_TAG} not found, cloning without branch..."
    rm -rf "${U_BOOT_ABS}"
    git clone --depth 1 https://source.denx.de/u-boot/u-boot.git "${U_BOOT_ABS}"
  }
fi

# Configure
echo "→ Configuring rk3566_quartz64_defconfig..."
cd "${U_BOOT_ABS}"
make rk3566_quartz64_defconfig CROSS_COMPILE="${CROSS_COMPILE}"

# Build
echo "→ Building (this takes a few minutes)..."
make -j"$(nproc)" CROSS_COMPILE="${CROSS_COMPILE}" 2>&1 | tail -10

# Collect outputs
echo "→ Collecting build artifacts..."
mkdir -p "${OUT_ABS}"

for f in u-boot.bin u-boot.itb spl/u-boot-spl.bin; do
  if [ -f "${U_BOOT_ABS}/${f}" ]; then
    cp "${U_BOOT_ABS}/${f}" "${OUT_ABS}/"
    echo "  ${f}: $(du -h "${OUT_ABS}/$(basename ${f})" | cut -f1)"
  else
    echo "  WARNING: ${f} not found"
  fi
done

# Copy device tree blobs
DTB_DIR="${U_BOOT_ABS}/arch/arm/dts"
for dtb in rk3566-quartz64-a.dtb rk3566-soquartz.dtb rk3566-roc-pc.dtb; do
  if [ -f "${DTB_DIR}/${dtb}" ]; then
    cp "${DTB_DIR}/${dtb}" "${OUT_ABS}/"
    echo "  ${dtb}: $(du -h "${OUT_ABS}/${dtb}" | cut -f1)"
  fi
done

echo ""
echo "=== U-Boot build complete ==="
echo "  Artifacts in: ${OUT_ABS}"
ls -lh "${OUT_ABS}/"
