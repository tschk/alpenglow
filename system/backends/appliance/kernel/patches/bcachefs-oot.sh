#!/bin/sh
# Graft out-of-tree bcachefs into a kernel tree as fs/bcachefs.
# bcachefs left mainline in 6.18; Linux 7.x has no fs/bcachefs, so
# CONFIG_BCACHEFS_FS=y is dropped by olddefconfig unless this runs first.
# Source: the kernel module tree bcachefs-tools ships for DKMS (fs/), pinned.
# Usage: bcachefs-oot.sh <kernel-src-dir>
# Env: BCACHEFS_TOOLS_TARBALL=/path/to/v<ver>.tar.gz to skip the download.
set -eu

KSRC="${1:?kernel source dir}"
VERSION="1.39.7"
SHA256="0d2d6f9689212cd1056137f932c6f786bc0c88ad569618b481ace52803c4e990"
URL="https://github.com/koverstreet/bcachefs-tools/archive/refs/tags/v${VERSION}.tar.gz"

if [ -f "${KSRC}/fs/bcachefs/.alpenglow-oot-${VERSION}" ]; then
  exit 0
fi
if [ -d "${KSRC}/fs/bcachefs" ]; then
  echo "bcachefs-oot: ${KSRC}/fs/bcachefs exists and is not v${VERSION}; refusing to overwrite" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT INT TERM
tarball="${BCACHEFS_TOOLS_TARBALL:-${work}/bcachefs-tools.tar.gz}"
if [ ! -f "${tarball}" ]; then
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${URL}" -o "${tarball}"
  else
    wget -q "${URL}" -O "${tarball}"
  fi
fi
got="$( (sha256sum "${tarball}" 2>/dev/null || shasum -a 256 "${tarball}") | cut -d' ' -f1)"
if [ "${got}" != "${SHA256}" ]; then
  echo "bcachefs-oot: sha256 mismatch for ${tarball}: ${got}" >&2
  exit 1
fi
tar -xzf "${tarball}" -C "${work}"
src="${work}/bcachefs-tools-${VERSION}"

cp -R "${src}/fs" "${KSRC}/fs/bcachefs"
cp "${src}/dkms/module-version.c" "${KSRC}/fs/bcachefs/module-version.c"
printf '#define bcachefs_version "v%s"\n' "${VERSION}" > "${KSRC}/fs/bcachefs/version.h"
# C-only build: alpenglow kernels have CONFIG_RUST=n and no bindgen in the
# build containers. The module supports this explicitly (BCACHEFS_RUST=0).
{
  printf 'BCACHEFS_RUST ?= 0\n'
  cat "${KSRC}/fs/bcachefs/Makefile"
} > "${KSRC}/fs/bcachefs/Makefile.new"
mv "${KSRC}/fs/bcachefs/Makefile.new" "${KSRC}/fs/bcachefs/Makefile"

if ! grep -q 'fs/bcachefs/Kconfig' "${KSRC}/fs/Kconfig"; then
  awk '{ print } $0 == "source \"fs/btrfs/Kconfig\"" { print "source \"fs/bcachefs/Kconfig\"" }' \
    "${KSRC}/fs/Kconfig" > "${KSRC}/fs/Kconfig.new"
  mv "${KSRC}/fs/Kconfig.new" "${KSRC}/fs/Kconfig"
fi
grep -q 'fs/bcachefs/Kconfig' "${KSRC}/fs/Kconfig" || {
  echo "bcachefs-oot: could not hook fs/Kconfig" >&2
  exit 1
}
grep -q 'CONFIG_BCACHEFS_FS' "${KSRC}/fs/Makefile" || \
  printf 'obj-$(CONFIG_BCACHEFS_FS)\t\t+= bcachefs/\n' >> "${KSRC}/fs/Makefile"
touch "${KSRC}/fs/bcachefs/.alpenglow-oot-${VERSION}"
echo "bcachefs-oot: grafted bcachefs v${VERSION} into ${KSRC}/fs/bcachefs"
