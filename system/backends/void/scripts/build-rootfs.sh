#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../../.." && pwd)"
BACKEND_DIR="${ROOT_DIR}/system/backends/void"
OIL_INSTALLER="${ROOT_DIR}/system/appliance/scripts/oil-installer.sh"
OUT_DIR="${ROOT_DIR}/build/void"
ROOTFS_DIR="${OUT_DIR}/rootfs"
ROOTFS_TARBALL="${VOID_ROOTFS_TARBALL:-}"
XBPS_ARCH="${XBPS_ARCH:-x86_64-musl}"
XBPS_REPOSITORY="${XBPS_REPOSITORY:-https://repo-default.voidlinux.org/current/musl}"

mkdir -p "${OUT_DIR}"
rm -rf "${ROOTFS_DIR}"
mkdir -p "${ROOTFS_DIR}"

if [ -n "${ROOTFS_TARBALL}" ]; then
  tar -xpf "${ROOTFS_TARBALL}" --no-same-owner -C "${ROOTFS_DIR}"
elif command -v xbps-install >/dev/null 2>&1; then
  xbps-install -S -R "${XBPS_REPOSITORY}" -r "${ROOTFS_DIR}" -A "${XBPS_ARCH}" base-minimal runit
else
  echo "set VOID_ROOTFS_TARBALL or install static xbps-install" >&2
  exit 1
fi

"${BACKEND_DIR}/scripts/configure-rootfs.sh" "${ROOTFS_DIR}"
if [ -n "${SOLILOQUY_OIL_SYSTEM_PACKAGES:-}" ]; then
  set -- ${SOLILOQUY_OIL_SYSTEM_PACKAGES}
  "${OIL_INSTALLER}" system-add "${ROOTFS_DIR}" "$@"
fi
tar -czf "${OUT_DIR}/rootfs.tar.gz" -C "${OUT_DIR}" rootfs
printf 'Void rootfs staged in %s\n' "${OUT_DIR}"
