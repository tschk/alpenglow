#!/bin/sh
# Build U-Boot for a Rockchip RK3566 board.
#
# Select the board with BOARD=<id> (default: quartz64-a).
# Uses Docker with Ubuntu 20.04 (OpenSSL 1.1) if docker is available,
# otherwise falls back to a native build (requires OpenSSL 1.1 headers).
set -eu

BOARD="${BOARD:-quartz64-a}"
U_BOOT_TAG="${U_BOOT_TAG:-v2025.04}"
U_BOOT_DIR="${U_BOOT_DIR:-build/u-boot}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
U_BOOT_ABS="${REPO_ROOT}/${U_BOOT_DIR}"
OUT_ABS="${REPO_ROOT}/build/uboot-rk3566/${BOARD}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }

# Board-specific U-Boot defconfig and device-tree blob.
case "${BOARD}" in
  quartz64-a)
    DEFCONFIG="quartz64-a-rk3566_defconfig"
    DTB="rk3566-quartz64-a.dtb"
    ;;
  quartz64-b)
    DEFCONFIG="quartz64-b-rk3566_defconfig"
    DTB="rk3566-quartz64-b.dtb"
    ;;
  soquartz-model-a)
    DEFCONFIG="soquartz-model-a-rk3566_defconfig"
    DTB="rk3566-soquartz-model-a.dtb"
    ;;
  orangepi-3b)
    DEFCONFIG="orangepi-3b-rk3566_defconfig"
    DTB="rk3566-orangepi-3b.dtb"
    ;;
  *)
    echo "unknown RK3566 board: ${BOARD}" >&2
    echo "supported: quartz64-a, quartz64-b, soquartz-model-a, orangepi-3b" >&2
    exit 1
    ;;
esac

NPROC="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

require_cmd git
require_cmd make

echo "=== U-Boot RK3566 build ==="
echo "  board:   ${BOARD}"
echo "  defconfig: ${DEFCONFIG}"
echo "  dtb:     ${DTB}"
echo "  tag:     ${U_BOOT_TAG}"
echo "  out:     ${OUT_ABS}"
echo "  cc:      ${CROSS_COMPILE}gcc"
echo ""

# Clone or fetch U-Boot
if [ -d "${U_BOOT_ABS}/.git" ]; then
  echo "→ U-Boot already cloned at ${U_BOOT_ABS}"
  cd "${U_BOOT_ABS}"
  git fetch --tags origin 2>/dev/null || true
else
  echo "→ Cloning U-Boot ${U_BOOT_TAG}..."
  rm -rf "${U_BOOT_ABS}"
  mkdir -p "${U_BOOT_ABS}"
  git clone --depth 1 --branch "${U_BOOT_TAG}" \
    https://source.denx.de/u-boot/u-boot.git "${U_BOOT_ABS}" 2>&1 || {
    echo "  Tag ${U_BOOT_TAG} not found, cloning default branch..."
    rm -rf "${U_BOOT_ABS}"
    git clone --depth 1 https://source.denx.de/u-boot/u-boot.git "${U_BOOT_ABS}"
  }
fi

rm -rf "${OUT_ABS}"
mkdir -p "${OUT_ABS}/spl"

if command -v docker >/dev/null 2>&1; then
  echo "→ Building in Docker (Ubuntu 20.04 with OpenSSL 1.1)..."

  docker run --rm \
    -v "${U_BOOT_ABS}:/u-boot" \
    -v "${OUT_ABS}:/out" \
    ubuntu:20.04 sh -c "
      set -eu
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq >/dev/null 2>&1
      apt-get install -y -qq build-essential gcc-aarch64-linux-gnu \
        bison flex libssl-dev libgnutls28-dev \
        swig python3-dev python3-setuptools python3-distutils bc git >/dev/null 2>&1
      cd /u-boot
      make ${DEFCONFIG} CROSS_COMPILE=${CROSS_COMPILE}
      make -j\$(nproc) CROSS_COMPILE=${CROSS_COMPILE} 2>&1 | tail -10
      for f in u-boot.bin u-boot.itb; do
        [ -f \$f ] && cp \$f /out/
      done
      [ -f spl/u-boot-spl.bin ] && cp spl/u-boot-spl.bin /out/spl/
      [ -f arch/arm/dts/${DTB} ] && cp arch/arm/dts/${DTB} /out/
    " 2>&1 | tail -15

else
  if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
    echo "ERROR: cross toolchain not found: ${CROSS_COMPILE}gcc" >&2
    echo "Install an aarch64-linux-gnu cross toolchain, e.g.:" >&2
    echo "" >&2
    echo "  macOS (wax):" >&2
    echo "    wax install aarch64-linux-gnu-gcc" >&2
    echo "  Debian/Ubuntu:" >&2
    echo "    apt-get install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu" >&2
    echo "  Fedora:" >&2
    echo "    dnf install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu" >&2
    exit 1
  fi

  if ! [ -f /usr/include/openssl/engine.h ] 2>/dev/null && \
     ! [ -f /usr/local/include/openssl/engine.h ] 2>/dev/null; then
    echo "WARNING: openssl/engine.h not found (OpenSSL 3.x removed it)." >&2
    echo "  U-Boot host tools need OpenSSL 1.1. Install docker or a compat package." >&2
  fi

  cd "${U_BOOT_ABS}"
  echo "→ Configuring ${DEFCONFIG}..."
  make "${DEFCONFIG}" CROSS_COMPILE="${CROSS_COMPILE}"

  echo "→ Building (this takes a few minutes)..."
  make -j"${NPROC}" CROSS_COMPILE="${CROSS_COMPILE}" 2>&1 | tail -10

  echo "→ Collecting build artifacts..."
  for f in u-boot.bin u-boot.itb; do
    if [ -f "${U_BOOT_ABS}/${f}" ]; then
      cp "${U_BOOT_ABS}/${f}" "${OUT_ABS}/"
      echo "  ${f}: $(du -h "${OUT_ABS}/${f}" | cut -f1)"
    else
      echo "  WARNING: ${f} not found" >&2
    fi
  done

  if [ -f "${U_BOOT_ABS}/spl/u-boot-spl.bin" ]; then
    cp "${U_BOOT_ABS}/spl/u-boot-spl.bin" "${OUT_ABS}/spl/"
    echo "  spl/u-boot-spl.bin: $(du -h "${OUT_ABS}/spl/u-boot-spl.bin" | cut -f1)"
  fi

  DTB_DIR="${U_BOOT_ABS}/arch/arm/dts"
  if [ -f "${DTB_DIR}/${DTB}" ]; then
    cp "${DTB_DIR}/${DTB}" "${OUT_ABS}/"
    echo "  ${DTB}: $(du -h "${OUT_ABS}/${DTB}" | cut -f1)"
  else
    echo "  WARNING: ${DTB} not found" >&2
  fi
fi

echo ""
echo "=== U-Boot build complete ==="
echo "  Artifacts in: ${OUT_ABS}"
ls -lh "${OUT_ABS}/" "${OUT_ABS}/spl/" 2>/dev/null
