#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
truncate -s 64M "$tmp/disk.img"
python3 - "$tmp/disk.img" <<'PY'
import struct, sys
with open(sys.argv[1], 'r+b') as image:
    image.seek(512)
    header = bytearray(512)
    header[:8] = b'EFI PART'
    struct.pack_into('<Q', header, 72, 2)
    image.write(header)
    entry = bytearray(128)
    struct.pack_into('<Q', entry, 32, 2048)
    image.write(entry)
PY
mformat -i "$tmp/disk.img@@1048576" ::
mmd -i "$tmp/disk.img@@1048576" ::/boot
printf 'expected initramfs bytes\n' > "$tmp/initramfs.cpio.lz4"
mcopy -i "$tmp/disk.img@@1048576" "$tmp/initramfs.cpio.lz4" ::/boot/
zstd -q -f "$tmp/disk.img" -o "$tmp/disk.img.zst"
sh "$root/scripts/check-compressed-initramfs.sh" "$tmp/disk.img.zst" "$tmp/initramfs.cpio.lz4" >/dev/null
printf 'tampered initramfs bytes\n' > "$tmp/initramfs.cpio.lz4"
if sh "$root/scripts/check-compressed-initramfs.sh" "$tmp/disk.img.zst" "$tmp/initramfs.cpio.lz4" >"$tmp/error" 2>&1; then
  echo 'compressed image with mismatching initramfs accepted' >&2
  exit 1
fi
grep -q 'compressed release initramfs mismatch' "$tmp/error"
echo 'compressed release initramfs mismatch rejected'
