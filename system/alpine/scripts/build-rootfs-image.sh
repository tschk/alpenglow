#!/bin/sh
set -eu

ROOTFS_DIR="${1:-build/alpine/rootfs}"
OUT_DIR="${2:-build/alpine/images}"
FORMAT="${SOLILOQUY_ROOTFS_FORMAT:-erofs}"

case "${FORMAT}" in
  solfs|erofs|squashfs)
    ;;
  *)
    echo "unsupported rootfs format: ${FORMAT}" >&2
    exit 1
    ;;
esac

if [ ! -d "${ROOTFS_DIR}" ]; then
  echo "rootfs directory not found: ${ROOTFS_DIR}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

if [ "${FORMAT}" = "solfs" ]; then
  OUT_IMG="${OUT_DIR}/soliloquy-rootfs.solfs"
  rm -f "${OUT_IMG}"
  if command -v solfsctl >/dev/null 2>&1; then
    solfsctl mkfs "${ROOTFS_DIR}" "${OUT_IMG}"
  else
    (cd "$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)" && cargo run --package solfsctl --quiet -- mkfs "${ROOTFS_DIR}" "${OUT_IMG}")
  fi
elif [ "${FORMAT}" = "erofs" ]; then
  command -v mkfs.erofs >/dev/null 2>&1 || {
    echo "missing required tool: mkfs.erofs" >&2
    exit 1
  }
  OUT_IMG="${OUT_DIR}/soliloquy-rootfs.erofs"
  rm -f "${OUT_IMG}"
  mkfs.erofs -zlz4hc "${OUT_IMG}" "${ROOTFS_DIR}"
else
  command -v mksquashfs >/dev/null 2>&1 || {
    echo "missing required tool: mksquashfs" >&2
    exit 1
  }
  OUT_IMG="${OUT_DIR}/soliloquy-rootfs.squashfs"
  rm -f "${OUT_IMG}"
  mksquashfs "${ROOTFS_DIR}" "${OUT_IMG}" -noappend -comp zstd
fi

printf 'Built rootfs image: %s\n' "${OUT_IMG}"
