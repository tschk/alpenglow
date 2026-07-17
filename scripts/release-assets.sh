#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${1:-${ALPENGLOW_VERSION:-$(date +%Y%m%d)}}"
ARCH="${ALPENGLOW_ARCH:-$(uname -m)}"
export ALPENGLOW_EDITION="${ALPENGLOW_EDITION:-${BUILD_PROFILE:-standard}}"
. "${ROOT_DIR}/scripts/edition-resolve.sh"
EDITION="${ALPENGLOW_EDITION}"
OUT_DIR="${ROOT_DIR}/build/release"
ASSET_DIR="${OUT_DIR}/assets"
IMAGE="${OUT_DIR}/alpenglow.img"
KERNEL="${OUT_DIR}/vmlinuz"
INITRAMFS="${OUT_DIR}/initramfs.cpio.gz"
LIMINE_DIR="${OUT_DIR}/limine"

case "${ARCH}" in
  amd64) ARCH=x86_64 ;;
  arm64) ARCH=aarch64 ;;
esac

case "${ARCH}" in
  x86_64) RUST_TARGET=x86_64-unknown-linux-musl ;;
  aarch64) RUST_TARGET=aarch64-unknown-linux-musl ;;
  *) RUST_TARGET="" ;;
esac

export KERNEL_ARCH="${ARCH}"
export KERNEL_7=0

ASSET_BASE="alpenglow-${VERSION}-${EDITION}-${ARCH}"
COMPRESSED_IMAGE="${ASSET_DIR}/${ASSET_BASE}.img.zst"
if [ -n "${RUST_TARGET}" ]; then
  INSTALLER_DIR="${ROOT_DIR}/target/${RUST_TARGET}/release"
else
  INSTALLER_DIR="${ROOT_DIR}/target/release"
fi
GUI_INSTALLER=""

export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER:-rust-lld}"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER="${CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER:-rust-lld}"

if [ "${RUST_TARGET}" = "x86_64-unknown-linux-musl" ]; then
  export CC_x86_64_unknown_linux_musl="${ROOT_DIR}/scripts/x86_64-linux-musl-zigcc"
  export CXX_x86_64_unknown_linux_musl="${ROOT_DIR}/scripts/x86_64-linux-musl-zigcxx"
fi

if [ "${BUILD_PROFILE}" = "desktop" ] && [ "${RUST_TARGET}" = "aarch64-unknown-linux-musl" ]; then
  GUI_SYSROOT="$(ALPENGLOW_AARCH64_GUI_SYSROOT="${ALPENGLOW_AARCH64_GUI_SYSROOT:-}" sh "${ROOT_DIR}/scripts/build-aarch64-gui-sysroot.sh")"
  export CC_aarch64_unknown_linux_musl="${ROOT_DIR}/scripts/aarch64-linux-musl-zigcc"
  export CXX_aarch64_unknown_linux_musl="${ROOT_DIR}/scripts/aarch64-linux-musl-zigcxx"
  export RUSTFLAGS="${RUSTFLAGS:-} -L native=${GUI_SYSROOT}/usr/lib -L native=${GUI_SYSROOT}/lib"
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing: $1" >&2
    exit 1
  }
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" > "$1.sha256"
  else
    shasum -a 256 "$1" > "$1.sha256"
  fi
}

require_cmd zstd

if [ "${ARCH}" = "aarch64" ] && [ "${BUILD_PROFILE}" = "desktop" ]; then
  cargo build --release --target "${RUST_TARGET}" --manifest-path "${ROOT_DIR}/system/installer/Cargo.toml" \
    --target-dir "${ROOT_DIR}/target" --bin alpenglow-install
  sh "${ROOT_DIR}/scripts/build-aarch64-efi-release.sh" "${EDITION}" "${VERSION}" "${INSTALLER_DIR}/alpenglow-install"
  exit 0
fi

build_installer() {
  if [ -n "${RUST_TARGET}" ]; then
    cargo build --release --target "${RUST_TARGET}" --manifest-path "${ROOT_DIR}/system/installer/Cargo.toml" \
      --target-dir "${ROOT_DIR}/target" "$@"
  else
    cargo build --release --manifest-path "${ROOT_DIR}/system/installer/Cargo.toml" \
      --target-dir "${ROOT_DIR}/target" "$@"
  fi
}

build_host_gui_installer() {
  cargo build --release --manifest-path "${ROOT_DIR}/system/installer/Cargo.toml" \
    --target-dir "${ROOT_DIR}/target" --features gui --bin alpenglow-install-gui
  GUI_INSTALLER="${ROOT_DIR}/target/release/alpenglow-install-gui"
}

ALPENGLOW_VERSION="${VERSION}" ALPENGLOW_ARCH="${ARCH}" sh "${ROOT_DIR}/scripts/build-release.sh"
build_installer --bin alpenglow-install --bin alpenglow-install-tui
if [ "${EDITION}" = "desktop-full" ] && [ "${ARCH}" = "x86_64" ]; then
  build_host_gui_installer
fi
if [ "${EDITION}" = "standard" ] && [ "${ARCH}" = "x86_64" ]; then
  ALPENGLOW_WSL_ROOTFS="${ROOT_DIR}/build/native/rootfs" sh "${ROOT_DIR}/scripts/build-wsl.sh" "${VERSION}"
fi

test -f "${IMAGE}" || {
  echo "missing built image: ${IMAGE}" >&2
  exit 1
}

mkdir -p "${ASSET_DIR}"
rm -f "${COMPRESSED_IMAGE}" "${COMPRESSED_IMAGE}.sha256"
zstd -T0 -19 -f "${IMAGE}" -o "${COMPRESSED_IMAGE}"
sha256_file "${COMPRESSED_IMAGE}"

if [ -d "${ROOT_DIR}/build/native/rootfs" ]; then
  LIVE_ROOT="${ROOT_DIR}/build/native/rootfs"
  mkdir -p "${LIVE_ROOT}/run/alpenglow" "${LIVE_ROOT}/usr/bin"
  cp "${COMPRESSED_IMAGE}" "${LIVE_ROOT}/run/alpenglow/alpenglow.img.zst"
  cp "${INSTALLER_DIR}/alpenglow-install" "${LIVE_ROOT}/usr/bin/"
  cp "${INSTALLER_DIR}/alpenglow-install-tui" "${LIVE_ROOT}/usr/bin/"
  if [ -n "${GUI_INSTALLER}" ] && [ -f "${GUI_INSTALLER}" ]; then
    cp "${GUI_INSTALLER}" "${LIVE_ROOT}/usr/bin/"
  fi
  (cd "${LIVE_ROOT}" && find . -print | cpio -o -H newc 2>/dev/null | zstd -6 -T0 > "${INITRAMFS}")
fi

if command -v xorriso >/dev/null 2>&1; then
  ISO_ROOT="${OUT_DIR}/iso-root"
  ISO="${ASSET_DIR}/${ASSET_BASE}.iso"
  rm -rf "${ISO_ROOT}" "${ISO}" "${ISO}.sha256"
  mkdir -p "${ISO_ROOT}/boot/limine" "${ISO_ROOT}/run/alpenglow" "${ISO_ROOT}/usr/bin"
  cp "${COMPRESSED_IMAGE}" "${COMPRESSED_IMAGE}.sha256" "${ISO_ROOT}/run/alpenglow/"
  cp "${COMPRESSED_IMAGE}" "${ISO_ROOT}/run/alpenglow/alpenglow.img.zst"
  cp "${INSTALLER_DIR}/alpenglow-install" "${ISO_ROOT}/usr/bin/"
  cp "${INSTALLER_DIR}/alpenglow-install-tui" "${ISO_ROOT}/usr/bin/"
  if [ -n "${GUI_INSTALLER}" ] && [ -f "${GUI_INSTALLER}" ]; then
    cp "${GUI_INSTALLER}" "${ISO_ROOT}/usr/bin/"
  fi
  if [ -f "${KERNEL}" ] && [ -f "${INITRAMFS}" ]; then
    cp "${KERNEL}" "${ISO_ROOT}/boot/vmlinuz"
    cp "${INITRAMFS}" "${ISO_ROOT}/boot/initramfs.cpio.gz"
  fi
  cat > "${ISO_ROOT}/install-alpenglow.sh" <<EOF
#!/bin/sh
set -eu
exec /usr/bin/alpenglow-install --tui /run/alpenglow/${ASSET_BASE}.img.zst "\${1:?target disk required}"
EOF
  chmod +x "${ISO_ROOT}/install-alpenglow.sh"
  cp "${ROOT_DIR}/readme.md" "${ISO_ROOT}/" 2>/dev/null || true
  if [ -f "${LIMINE_DIR}/limine-bios.sys" ]; then
    cp "${LIMINE_DIR}/limine-bios.sys" "${ISO_ROOT}/boot/limine/"
  fi
  if [ -f "${LIMINE_DIR}/limine-bios-cd.bin" ] && [ -f "${LIMINE_DIR}/limine-uefi-cd.bin" ]; then
    cp "${LIMINE_DIR}/limine-bios-cd.bin" "${ISO_ROOT}/boot/limine/"
    cp "${LIMINE_DIR}/limine-uefi-cd.bin" "${ISO_ROOT}/boot/limine/"
    cat > "${ISO_ROOT}/boot/limine/limine.conf" <<EOF
timeout: 5
verbose: no

/Alpenglow live
  protocol: linux
  path: boot():/boot/vmlinuz
  cmdline: console=tty0 console=ttyS0 init=/init alpenglow.live=1
  module_path: boot():/boot/initramfs.cpio.gz
EOF
    xorriso -as mkisofs -o "${ISO}" -V ALPENGLOW -r -J \
      -b boot/limine/limine-bios-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table \
      --efi-boot boot/limine/limine-uefi-cd.bin -efi-boot-part --efi-boot-image --protective-msdos-label \
      "${ISO_ROOT}" >/dev/null
    "${LIMINE_DIR}/limine" bios-install "${ISO}" >/dev/null 2>&1 || true
  else
    xorriso -as mkisofs -o "${ISO}" -V ALPENGLOW -r -J "${ISO_ROOT}" >/dev/null
  fi
  sha256_file "${ISO}"
fi

printf '%s\n' "${COMPRESSED_IMAGE}"
