#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 compressed-image expected-initramfs" >&2
  exit 2
fi
image=$1
expected=$2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
zstd -dc -- "$image" > "$tmp/disk.img"
offset=$(python3 - "$tmp/disk.img" <<'PY'
import struct, sys
with open(sys.argv[1], 'rb') as image:
    image.seek(512)
    header = image.read(92)
    if header[:8] != b'EFI PART':
        raise SystemExit('missing GPT in compressed release image')
    table = struct.unpack_from('<Q', header, 72)[0]
    image.seek(table * 512)
    entry = image.read(128)
    start = struct.unpack_from('<Q', entry, 32)[0]
    if not start:
        raise SystemExit('missing boot partition in compressed release image')
    print(start * 512)
PY
)
mcopy -i "$tmp/disk.img@@$offset" "::/boot/${expected##*/}" "$tmp/initramfs"
expected_size=$(wc -c < "$expected" | tr -d ' ')
actual_size=$(wc -c < "$tmp/initramfs" | tr -d ' ')
expected_hash=$(sha256sum "$expected" | cut -d ' ' -f 1)
actual_hash=$(sha256sum "$tmp/initramfs" | cut -d ' ' -f 1)
if [ "$expected_size" != "$actual_size" ] || [ "$expected_hash" != "$actual_hash" ]; then
  echo "compressed release initramfs mismatch: expected $expected_size bytes $expected_hash; got $actual_size bytes $actual_hash" >&2
  exit 1
fi
echo "compressed release initramfs verified: $actual_size bytes sha256 $actual_hash"
