#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
ALPINE_DIR="${ROOT_DIR}/system/alpine"
OUT_DIR="${ROOT_DIR}/build/alpine"
IMAGE_TAG="alpenglow-alpine-rootfs:latest"
QEMU_ARCH="${QEMU_ARCH:-x86_64}"

case "${QEMU_ARCH}" in
  x86_64) DOCKER_PLATFORM="linux/amd64" ;;
  aarch64|arm64) DOCKER_PLATFORM="linux/arm64" ;;
  *)
    echo "unsupported QEMU_ARCH: ${QEMU_ARCH} (expected x86_64 or aarch64)" >&2
    exit 1
    ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for this script" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

docker build \
  --platform "${DOCKER_PLATFORM}" \
  -f "${ALPINE_DIR}/docker/rootfs.Dockerfile" \
  -t "${IMAGE_TAG}" \
  "${ROOT_DIR}"

CID="$(docker create "${IMAGE_TAG}")"
trap 'docker rm -f "${CID}" >/dev/null 2>&1 || true' EXIT

docker cp "${CID}:/out/rootfs.tar.gz" "${OUT_DIR}/rootfs.tar.gz"
rm -rf "${OUT_DIR}/rootfs"
mkdir -p "${OUT_DIR}/rootfs"
tar -xzf "${OUT_DIR}/rootfs.tar.gz" --no-same-owner -C "${OUT_DIR}"

echo "Alpine rootfs staged in ${OUT_DIR}"
