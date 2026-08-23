#!/bin/sh
# Export a userspace-only Alpenglow artifact (rootfs tarball + optional OCI layout).
# This is not a bootable image: no kernel, firmware, eudev, initramfs, or Limine.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
ARCH="${ALPENGLOW_ARCH:-$(uname -m)}"
case "${ARCH}" in
  amd64) ARCH=x86_64 ;;
  arm64) ARCH=aarch64 ;;
esac

VERSION="${ALPENGLOW_VERSION:-dev}"
OUT_DIR="${2:-${ROOT_DIR}/build/containers}"
ROOTFS="${1:-}"

if [ -z "${ROOTFS}" ]; then
  export ALPENGLOW_EDITION="${ALPENGLOW_EDITION:-containers}"
  # shellcheck source=scripts/edition-resolve.sh
  . "${ROOT_DIR}/scripts/edition-resolve.sh"
  ROOTFS="${OUT_DIR}/rootfs"
  mkdir -p "${ROOTFS}"
  for dir in bin sbin etc dev proc sys tmp run; do
    mkdir -p "${ROOTFS}/${dir}"
  done
  BUILD_PROFILE="${BUILD_PROFILE}" \
    WORLD_FILE="${WORLD_FILE}" \
    SESSION="${SESSION}" \
    ALPENGLOW_ROLE="${ALPENGLOW_ROLE}" \
    ARTIFACT="${ARTIFACT}" \
    "${ROOT_DIR}/system/backends/appliance/scripts/configure-rootfs.sh" "${ROOTFS}"
fi

if [ ! -d "${ROOTFS}" ]; then
  echo "usage: $0 [rootfs-dir] [output-dir]" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
STAGE="${OUT_DIR}/stage"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cp -R "${ROOTFS}/." "${STAGE}/"

# Strip boot-image pieces if a full rootfs was passed in.
rm -rf \
  "${STAGE}/boot" \
  "${STAGE}/lib/modules" \
  "${STAGE}/lib/firmware" \
  "${STAGE}/usr/lib/firmware" \
  "${STAGE}/usr/lib/modules" \
  "${STAGE}/limine" \
  "${STAGE}/sysroot"
find "${STAGE}" \( \
  -name 'vmlinu*' -o -name 'initramfs*' -o -name 'initrd*' -o -name 'limine*' \
\) -exec rm -rf {} + 2>/dev/null || true

ASSET_BASE="alpenglow-${VERSION}-containers-${ARCH}"
TARBALL="${OUT_DIR}/${ASSET_BASE}.tar"
(
  CDPATH='' cd -- "${STAGE}"
  tar -cf "${TARBALL}" .
)

OCI_DIR="${OUT_DIR}/oci"
rm -rf "${OCI_DIR}"
mkdir -p "${OCI_DIR}/blobs/sha256"
printf '%s\n' '{"imageLayoutVersion":"1.0.0"}' > "${OCI_DIR}/oci-layout"

LAYER_HASH="$(sha256sum "${TARBALL}" | awk '{ print $1 }')"
cp "${TARBALL}" "${OCI_DIR}/blobs/sha256/${LAYER_HASH}"
LAYER_SIZE="$(wc -c < "${TARBALL}" | tr -d ' ')"

CONFIG_JSON="$(printf '{"architecture":"%s","os":"linux","rootfs":{"type":"layers","diff_ids":["sha256:%s"]},"config":{"Env":["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],"Cmd":["/usr/bin/oksh"]}}' "${ARCH}" "${LAYER_HASH}")"
CONFIG_FILE="${OUT_DIR}/.oci-config.json"
printf '%s\n' "${CONFIG_JSON}" > "${CONFIG_FILE}"
CONFIG_HASH="$(sha256sum "${CONFIG_FILE}" | awk '{ print $1 }')"
CONFIG_SIZE="$(wc -c < "${CONFIG_FILE}" | tr -d ' ')"
cp "${CONFIG_FILE}" "${OCI_DIR}/blobs/sha256/${CONFIG_HASH}"
rm -f "${CONFIG_FILE}"

MANIFEST_JSON="$(printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:%s","size":%s},"layers":[{"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:%s","size":%s}]}' "${CONFIG_HASH}" "${CONFIG_SIZE}" "${LAYER_HASH}" "${LAYER_SIZE}")"
MANIFEST_FILE="${OUT_DIR}/.oci-manifest.json"
printf '%s\n' "${MANIFEST_JSON}" > "${MANIFEST_FILE}"
MANIFEST_HASH="$(sha256sum "${MANIFEST_FILE}" | awk '{ print $1 }')"
MANIFEST_SIZE="$(wc -c < "${MANIFEST_FILE}" | tr -d ' ')"
cp "${MANIFEST_FILE}" "${OCI_DIR}/blobs/sha256/${MANIFEST_HASH}"
rm -f "${MANIFEST_FILE}"

printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:%s","size":%s,"platform":{"architecture":"%s","os":"linux"}}]}\n' \
  "${MANIFEST_HASH}" "${MANIFEST_SIZE}" "${ARCH}" > "${OCI_DIR}/index.json"

printf 'container export: %s\n' "${TARBALL}"
printf 'oci layout: %s\n' "${OCI_DIR}"
