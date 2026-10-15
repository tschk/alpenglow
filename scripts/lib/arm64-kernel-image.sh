#!/bin/sh

# Limine's aarch64 Linux loader expects the uncompressed Image header.
arm64_kernel_image_has_magic() {
  [ -s "$1" ] && [ "$(dd if="$1" bs=1 skip=56 count=4 2>/dev/null)" = ARMd ]
}

arm64_kernel_image_unpack_gzip() (
  temporary="$(mktemp "${2}.XXXXXX")" || exit 1
  trap 'rm -f "${temporary}"' EXIT HUP INT TERM
  gzip -dc "$1" > "${temporary}" || exit 1
  arm64_kernel_image_has_magic "${temporary}" || {
    echo "invalid aarch64 kernel Image header: $1" >&2
    exit 1
  }
  chmod 644 "${temporary}"
  mv "${temporary}" "$2"
)
