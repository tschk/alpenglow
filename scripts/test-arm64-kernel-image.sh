#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "${ROOT_DIR}/scripts/lib/arm64-kernel-image.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT HUP INT TERM

dd if=/dev/zero of="${TMP_DIR}/Image" bs=64 count=1 2>/dev/null
printf ARMd | dd of="${TMP_DIR}/Image" bs=1 seek=56 conv=notrunc 2>/dev/null
arm64_kernel_image_has_magic "${TMP_DIR}/Image"
gzip -c "${TMP_DIR}/Image" > "${TMP_DIR}/Image.gz"
arm64_kernel_image_unpack_gzip "${TMP_DIR}/Image.gz" "${TMP_DIR}/unpacked"
cmp "${TMP_DIR}/Image" "${TMP_DIR}/unpacked"
arm64_kernel_image_unpack_gzip "${TMP_DIR}/Image.gz" "${TMP_DIR}/Image.gz"
cmp "${TMP_DIR}/Image" "${TMP_DIR}/Image.gz"

printf 'existing\n' > "${TMP_DIR}/unpacked"
printf 'invalid\n' | gzip > "${TMP_DIR}/bad.gz"
if arm64_kernel_image_unpack_gzip "${TMP_DIR}/bad.gz" "${TMP_DIR}/unpacked" 2>/dev/null; then
  echo 'invalid ARM64 image was accepted' >&2
  exit 1
fi
[ "$(cat "${TMP_DIR}/unpacked")" = existing ]

printf 'truncated' > "${TMP_DIR}/bad.gz"
if arm64_kernel_image_unpack_gzip "${TMP_DIR}/bad.gz" "${TMP_DIR}/unpacked" 2>/dev/null; then
  echo 'invalid gzip was accepted' >&2
  exit 1
fi
[ "$(cat "${TMP_DIR}/unpacked")" = existing ]

echo 'test-arm64-kernel-image: ok'
