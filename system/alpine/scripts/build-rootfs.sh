#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
ALPINE_DIR="${ROOT_DIR}/system/alpine"
OUT_DIR="${ROOT_DIR}/build/alpine"
ROOTFS_TAR="${OUT_DIR}/rootfs.tar.gz"
ROOTFS_DIR="${OUT_DIR}/rootfs"
FORCE_ROOTFS_REBUILD="${FORCE_ROOTFS_REBUILD:-0}"

rootfs_manifest_changed() {
  [ ! -f "${ROOTFS_TAR}" ] && return 1
  for manifest in \
    "${ALPINE_DIR}/packages-v0.txt" \
    "${ALPINE_DIR}/docker/rootfs.Dockerfile" \
    "${ALPINE_DIR}/filesystems/rootfs-layout.json" \
    "${ALPINE_DIR}/filesystems/state-mounts.json" \
    "${ALPINE_DIR}/rootfs-overlay/init" \
    "${ALPINE_DIR}/scripts/configure-rootfs.sh" \
    "${ALPINE_DIR}/scripts/alpenglow-session-start" \
  do
    [ "${manifest}" -nt "${ROOTFS_TAR}" ] && return 0
  done
  return 1
}

if [ "${FORCE_ROOTFS_REBUILD}" = "1" ] || rootfs_manifest_changed; then
  rm -f "${ROOTFS_TAR}"
  rm -rf "${ROOTFS_DIR}"
fi

if [ -d "${ROOTFS_DIR}" ]; then
  "${ALPINE_DIR}/scripts/configure-rootfs.sh" "${ROOTFS_DIR}"
  echo "Reusing staged Alpine rootfs at ${ROOTFS_DIR}"
  exit 0
fi

if [ -f "${ROOTFS_TAR}" ]; then
  mkdir -p "${OUT_DIR}"
  tar -xzf "${ROOTFS_TAR}" --no-same-owner -C "${OUT_DIR}"
  if [ -d "${ROOTFS_DIR}" ]; then
    "${ALPINE_DIR}/scripts/configure-rootfs.sh" "${ROOTFS_DIR}"
    echo "Restored staged Alpine rootfs at ${ROOTFS_DIR}"
    exit 0
  fi
fi

"${ALPINE_DIR}/scripts/build-rootfs-in-docker.sh"
