#!/bin/sh
# Capacity regression for desktop payloads larger than the former 64 MiB ESP.
set -eu
ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=scripts/lib/fat-image-capacity.sh
. "${ROOT_DIR}/scripts/lib/fat-image-capacity.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM
fail() { printf 'test-fat-image-capacity: %s\n' "$1" >&2; exit 1; }

[ "$(fat_image_size_mb 0)" -eq 64 ] || fail 'minimum FAT32 image size'
truncate -s 8M "${TMP_DIR}/kernel"
truncate -s 80M "${TMP_DIR}/live initramfs"
payload="$(fat_image_payload_bytes "${TMP_DIR}/kernel" "${TMP_DIR}/live initramfs")"
[ "${payload}" -eq $((88 * 1024 * 1024)) ] || fail 'payload file sizes'
size_mb="$(fat_image_size_mb "${payload}")"
[ "${size_mb}" -gt 64 ] || fail 'large desktop payload still uses 64 MiB'
[ $((size_mb * 1024 * 1024)) -ge $((payload + payload / 20 + 16 * 1024 * 1024)) ] \
  || fail 'payload and filesystem reserve do not fit'
if fat_image_payload_bytes "${TMP_DIR}/missing" >/dev/null 2>&1; then
  fail 'missing payload was accepted'
fi
if fat_image_size_mb invalid >/dev/null 2>&1; then
  fail 'invalid payload size was accepted'
fi
truncate -s 4G "${TMP_DIR}/oversize"
if fat_image_payload_bytes "${TMP_DIR}/oversize" >/dev/null 2>&1; then
  fail 'payload beyond the FAT file limit was accepted'
fi
printf 'test-fat-image-capacity: ok\n'
