#!/bin/sh
# Cross-build alpenglow-install-gui for aarch64-unknown-linux-musl against the Alpine GUI
# sysroot (build-aarch64-gui-sysroot.sh). Prints the output binary path on stdout.
#
# The binary is linked dynamically (-crt-static off): wayland-client and wgpu dlopen
# libwayland-client/libvulkan, which a static musl executable cannot do. Its runtime needs
# musl, libgcc_s, libxcb, libxkbcommon-x11, libwayland-client and a Vulkan loader + driver.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET_DIR="${ALPENGLOW_AARCH64_GUI_TARGET_DIR:-${ROOT_DIR}/target}"

GUI_SYSROOT="$(ALPENGLOW_AARCH64_GUI_SYSROOT="${ALPENGLOW_AARCH64_GUI_SYSROOT:-}" sh "${ROOT_DIR}/scripts/build-aarch64-gui-sysroot.sh")"
CC_aarch64_unknown_linux_musl="${ROOT_DIR}/scripts/aarch64-linux-musl-zigcc" \
CXX_aarch64_unknown_linux_musl="${ROOT_DIR}/scripts/aarch64-linux-musl-zigcxx" \
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="${CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER:-rust-lld}" \
RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=-crt-static -L native=${GUI_SYSROOT}/usr/lib -L native=${GUI_SYSROOT}/lib" \
PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_SYSROOT_DIR="${GUI_SYSROOT}" PKG_CONFIG_LIBDIR="${GUI_SYSROOT}/usr/lib/pkgconfig" \
  cargo build --release --target aarch64-unknown-linux-musl --manifest-path "${ROOT_DIR}/system/installer/Cargo.toml" \
  --target-dir "${TARGET_DIR}" --features gui --bin alpenglow-install-gui >&2

printf '%s\n' "${TARGET_DIR}/aarch64-unknown-linux-musl/release/alpenglow-install-gui"
