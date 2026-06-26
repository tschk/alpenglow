#!/bin/sh
# Cross-build Alpenglow components for aarch64 and riscv64
# Uses Zig as primary cross-compiler for C/Zig, Rust target for Rust crates.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET="${1:-aarch64-linux-musl}"
BUILD_OUT="${REPO_ROOT}/build/cross/${TARGET}"
NPROC="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

case "${TARGET}" in
  aarch64-linux-musl) ARCH=arm64 KARCH=aarch64 KERNEL_TARGET=Image;;
  riscv64-linux-musl) ARCH=riscv KARCH=riscv64 KERNEL_TARGET=Image;;
  *) echo "Usage: $0 {aarch64-linux-musl|riscv64-linux-musl}"; exit 1;;
esac

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1"; exit 1; }; }

echo "=== Cross-build: ${TARGET} ==="
mkdir -p "${BUILD_OUT}"

# 1. Kernel (Linux 7.0 + Rust + minimal config)
build_kernel() {
  local KD="${BUILD_OUT}/kernel-src"
  if [ ! -d "${KD}" ]; then
    curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.0.tar.xz" | tar -xJ -C "${BUILD_OUT}"
    mv "${BUILD_OUT}/linux-7.0" "${KD}"
  fi

  cd "${KD}"
  make ARCH="${ARCH}" CROSS_COMPILE="${KARCH}-linux-musl-" defconfig
  make ARCH="${ARCH}" CROSS_COMPILE="${KARCH}-linux-musl-" kvm_guest.config 2>/dev/null || true
  make ARCH="${ARCH}" CROSS_COMPILE="${KARCH}-linux-musl-" rust.config 2>/dev/null || true

  # Apply Alpenglow minimal config overrides
  scripts/config \
    --disable MODULE_SIG_FORMAT --disable MODULE_SIG --disable MODULE_SIG_ALL \
    --disable MODULE_COMPRESS --disable MODULE_COMPRESS_GZIP --disable MODULE_COMPRESS_ALL \
    --disable DEBUG_FS --disable DEBUG_KERNEL --disable DEBUG_INFO --disable FTRACE \
    --disable STACKTRACE --disable SCHED_DEBUG --disable MAGIC_SYSRQ

  make ARCH="${ARCH}" CROSS_COMPILE="${KARCH}-linux-musl-" olddefconfig 2>/dev/null

  # Build
  make -j"${NPROC}" ARCH="${ARCH}" CROSS_COMPILE="${KARCH}-linux-musl-" ${KERNEL_TARGET} 2>&1 | tail -5

  cp "arch/${ARCH}/boot/${KERNEL_TARGET}" "${BUILD_OUT}/vmlinuz"
  echo "  kernel: ${BUILD_OUT}/vmlinuz"
}

# 2. Zig components (kernelctl, glowfsctl, init)
build_zig() {
  echo "→ Building Zig components..."
  require_cmd zig

  for dir in system/kernelctl-zig system/glowfsctl-zig system/init; do
    name="$(basename "${dir}")"
    echo "  ${name}..."
    cd "${REPO_ROOT}/${dir}"
    zig build -Dtarget="${TARGET}" -Doptimize=ReleaseSmall -Drelease=true 2>/dev/null || \
      zig build-exe -target "${TARGET}" -O ReleaseSmall -fstrip src/main.zig 2>/dev/null || {
        echo "  skipping ${name} (zig build not configured, trying direct)"
        zig build-exe -target "${TARGET}" -O ReleaseSmall -fstrip src/main.zig -o "${BUILD_OUT}/${name}" 2>/dev/null && \
          echo "  ${name}: ${BUILD_OUT}/${name}" || echo "  ${name}: build failed"
      }
  done
}

# 3. Toybox
build_toybox() {
  echo "→ Building toybox..."
  require_cmd docker
  TOYBOX_VER="0.8.11"

  docker run --rm -v "${BUILD_OUT}:/out" alpine:3.21 sh -c "
    apk add --no-cache make gcc musl-dev curl tar xz bash linux-headers >/dev/null
    curl -fsSL https://github.com/landley/toybox/archive/refs/tags/${TOYBOX_VER}.tar.gz -o /tmp/tb.tar.gz
    tar -xzf /tmp/tb.tar.gz -C /tmp
    cd /tmp/toybox-${TOYBOX_VER}
    make defconfig >/dev/null 2>&1
    sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/# CONFIG_SH is not set/CONFIG_SH=y/' .config
    sed -i 's/# CONFIG_GETTY is not set/CONFIG_GETTY=y/' .config
    sed -i 's/CONFIG_VI=y/# CONFIG_VI is not set/' .config 2>/dev/null || true
    make -j\$(nproc) CROSS_COMPILE=${KARCH}-linux-musl- LDFLAGS='-static' >/dev/null 2>&1
    cp toybox /out/toybox
  " 2>&1 | tail -1
  echo "  toybox: ${BUILD_OUT}/toybox"
}

# 4. Dinit
build_dinit() {
  echo "→ Building dinit..."
  require_cmd docker
  DINIT_VER="0.19.2"

  docker run --rm -v "${BUILD_OUT}:/out" alpine:3.21 sh -c "
    apk add --no-cache g++ make curl tar xz musl-dev bash >/dev/null
    curl -fsSL https://github.com/davmac314/dinit/releases/download/v${DINIT_VER}/dinit-${DINIT_VER}.tar.xz -o /tmp/dinit.tar.xz
    tar -xf /tmp/dinit.tar.xz -C /tmp
    cd /tmp/dinit-${DINIT_VER}
    ./configure --host=${KARCH}-linux-musl --static >/dev/null 2>&1
    make -j\$(nproc) CXX=${KARCH}-linux-musl-g++ CXXFLAGS='-static' LDFLAGS='-static' >/dev/null 2>&1
    make install DESTDIR=/out/dinit-install >/dev/null 2>&1
    cp /out/dinit-install/sbin/dinit /out/dinit
  " 2>&1 | tail -1
  echo "  dinit: ${BUILD_OUT}/dinit"
}

# 5. Oil (Rust native package manager)
build_oil() {
  echo "→ Building Oil..."
  require_cmd rustup
  require_cmd cargo

  rustup target add "${TARGET}" 2>/dev/null || true

  cd "${REPO_ROOT}/system/oil"
  RUSTFLAGS="-C target-feature=+crt-static" \
    cargo build --release --target "${TARGET}" 2>&1 | tail -1 || \
    echo "  Oil: cross-build failed (try with musl-cross)"
  cp "target/${TARGET}/release/oil" "${BUILD_OUT}/oil" 2>/dev/null || true
  echo "  oil: ${BUILD_OUT}/oil"
}

case "${TARGET}" in
  aarch64-linux-musl)
    build_kernel
    if command -v zig >/dev/null 2>&1; then build_zig; fi
    if command -v docker >/dev/null 2>&1; then
      build_toybox
      build_dinit
    fi
    if command -v cargo >/dev/null 2>&1; then build_oil; fi
    ;;
  riscv64-linux-musl)
    build_kernel
    if command -v zig >/dev/null 2>&1; then build_zig; fi
    # RISC-V cross toolchain harder to set up; try Zig cc
    echo "  Note: toybox/dinit RISC-V cross-build requires musl-cross"
    echo "  Try: https://github.com/richfelker/musl-cross-make"
    ;;
esac

echo ""
echo "=== Cross-build complete ==="
ls -lh "${BUILD_OUT}/" 2>/dev/null
