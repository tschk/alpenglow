#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${1:-${ALPENGLOW_VERSION:-$(date +%Y%m%d)}}"
ARCH="${ALPENGLOW_ARCH:-x86_64}"
EDITION="${ALPENGLOW_EDITION:-standard}"
ROOTFS="${ALPENGLOW_WSL_ROOTFS:-${ROOT_DIR}/build/native/rootfs}"
OUT_DIR="${ROOT_DIR}/build/release/assets"

case "${ARCH}" in
  amd64) ARCH=x86_64 ;;
  arm64) ARCH=aarch64 ;;
esac

ASSET="${OUT_DIR}/alpenglow-${VERSION}-${EDITION}-${ARCH}-wsl.tar"

if [ "${ARCH}" != "x86_64" ]; then
  echo "WSL import builds currently require ALPENGLOW_ARCH=x86_64." >&2
  exit 1
fi

if [ ! -d "${ROOTFS}" ]; then
  echo "missing rootfs: ${ROOTFS}" >&2
  echo "run: BUILD_PROFILE=${EDITION} BUILD_ONLY=1 ./scripts/boot-native.sh" >&2
  echo "or set ALPENGLOW_WSL_ROOTFS=/path/to/rootfs" >&2
  exit 1
fi

command -v tar >/dev/null 2>&1 || {
  echo "missing: tar" >&2
  exit 1
}

export COPYFILE_DISABLE=1

STAGING="$(mktemp -d)"
cleanup() {
  rm -rf "${STAGING}"
}
trap cleanup EXIT INT TERM

mkdir -p "${STAGING}"
(cd "${ROOTFS}" && tar -cf - .) | (cd "${STAGING}" && tar -xf -)
mkdir -p "${STAGING}/etc" "${STAGING}/root"

cat > "${STAGING}/etc/wsl.conf" <<'EOF'
[user]
default=root
EOF

mkdir -p "${OUT_DIR}"
rm -f "${ASSET}" "${ASSET}.sha256"
tar -cf "${ASSET}" -C "${STAGING}" .

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${ASSET}" > "${ASSET}.sha256"
else
  shasum -a 256 "${ASSET}" > "${ASSET}.sha256"
fi

printf '%s\n' "${ASSET}"
