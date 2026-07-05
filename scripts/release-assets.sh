#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${1:-${ALPENGLOW_VERSION:-$(date +%Y%m%d)}}"
ARCH="${ALPENGLOW_ARCH:-$(uname -m)}"
OUT_DIR="${ROOT_DIR}/build/release"
ASSET_DIR="${OUT_DIR}/assets"
IMAGE="${OUT_DIR}/alpenglow.img"
ASSET_BASE="alpenglow-${VERSION}-${ARCH}"
COMPRESSED_IMAGE="${ASSET_DIR}/${ASSET_BASE}.img.zst"

case "${ARCH}" in
  amd64) ARCH=x86_64 ;;
  arm64) ARCH=aarch64 ;;
esac

ASSET_BASE="alpenglow-${VERSION}-${ARCH}"
COMPRESSED_IMAGE="${ASSET_DIR}/${ASSET_BASE}.img.zst"

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

ALPENGLOW_VERSION="${VERSION}" ALPENGLOW_ARCH="${ARCH}" "${ROOT_DIR}/scripts/build-release.sh"

test -f "${IMAGE}" || {
  echo "missing built image: ${IMAGE}" >&2
  exit 1
}

mkdir -p "${ASSET_DIR}"
rm -f "${COMPRESSED_IMAGE}" "${COMPRESSED_IMAGE}.sha256"
zstd -T0 -19 -f "${IMAGE}" -o "${COMPRESSED_IMAGE}"
sha256_file "${COMPRESSED_IMAGE}"

if command -v xorriso >/dev/null 2>&1; then
  ISO_ROOT="${OUT_DIR}/iso-root"
  ISO="${ASSET_DIR}/${ASSET_BASE}.iso"
  rm -rf "${ISO_ROOT}" "${ISO}" "${ISO}.sha256"
  mkdir -p "${ISO_ROOT}"
  cp "${COMPRESSED_IMAGE}" "${COMPRESSED_IMAGE}.sha256" "${ISO_ROOT}/"
  cp "${ROOT_DIR}/install.sh" "${ISO_ROOT}/" 2>/dev/null || true
  cp "${ROOT_DIR}/readme.md" "${ISO_ROOT}/" 2>/dev/null || true
  xorriso -as mkisofs -o "${ISO}" -V ALPENGLOW -r -J "${ISO_ROOT}" >/dev/null
  sha256_file "${ISO}"
fi

printf '%s\n' "${COMPRESSED_IMAGE}"
