#!/bin/sh
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT HUP INT TERM
mkdir -p "${tmp}/root/bin" "${tmp}/root/usr/lib"
python3 - "${tmp}/root" <<'PY'
import pathlib, struct, sys

root = pathlib.Path(sys.argv[1])
def elf(path, machine):
    path.write_bytes(b'\x7fELF' + bytes([2, 1, 1, 0]) + bytes(8)
                     + struct.pack('<HH', 2, machine) + bytes(44))
elf(root / 'bin' / 'toybox', 183)
elf(root / 'usr' / 'lib' / 'libexample.so', 183)
elf(root / 'wrong', 62)
(root / 'bin' / 'script').write_text('#!/bin/sh\n')
(root.parent / 'arm-kernel').write_bytes(bytes(56) + b'ARM\x64')
(root.parent / 'x86-kernel').write_bytes(bytes(0x202) + b'HdrS')
PY
mv "${tmp}/root/wrong" "${tmp}/wrong"
python3 "${root}/scripts/check-release-architecture.py" aarch64 "${tmp}/root" "${tmp}/arm-kernel"
if python3 "${root}/scripts/check-release-architecture.py" aarch64 "${tmp}/root" "${tmp}/x86-kernel" >"${tmp}/error" 2>&1; then
  echo 'wrong-architecture kernel accepted' >&2
  exit 1
fi
grep -q 'kernel' "${tmp}/error"
mv "${tmp}/wrong" "${tmp}/root/usr/lib/libwrong.so"
if python3 "${root}/scripts/check-release-architecture.py" aarch64 "${tmp}/root" >"${tmp}/error" 2>&1; then
  echo 'wrong-architecture ELF accepted' >&2
  exit 1
fi
grep -q 'libwrong.so' "${tmp}/error"
rm "${tmp}/root/usr/lib/libwrong.so"
python3 - "${tmp}/root/usr/lib/wrong.ko.gz" <<'PY'
import gzip, struct, sys
with gzip.open(sys.argv[1], 'wb') as stream:
    stream.write(b'\x7fELF' + bytes([2, 1, 1, 0]) + bytes(8)
                 + struct.pack('<HH', 1, 62) + bytes(44))
PY
if python3 "${root}/scripts/check-release-architecture.py" aarch64 "${tmp}/root" >"${tmp}/error" 2>&1; then
  echo 'wrong-architecture compressed module accepted' >&2
  exit 1
fi
grep -q 'wrong.ko.gz' "${tmp}/error"
if python3 "${root}/scripts/check-release-architecture.py" x86_64 "${tmp}/root" >"${tmp}/error" 2>&1; then
  echo 'wrong-architecture ELF accepted for x86_64' >&2
  exit 1
fi
python3 - "${tmp}" <<'PY'
import pathlib, struct, sys, uuid, zlib
root = pathlib.Path(sys.argv[1])
for name, guid in [('esp', 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'),
                   ('no-esp', '0fc63daf-8483-4772-8e79-3d69d8477de4')]:
    table = bytearray(128 * 128)
    table[:16] = uuid.UUID(guid).bytes_le
    struct.pack_into('<QQ', table, 32, 34, 80)
    header = bytearray(512)
    header[:8] = b'EFI PART'
    struct.pack_into('<II', header, 8, 0x10000, 92)
    struct.pack_into('<QIII', header, 72, 2, 128, 128, zlib.crc32(table))
    struct.pack_into('<I', header, 16, zlib.crc32(header[:92]))
    image = bytearray(512 * 100)
    image[512:1024] = header
    image[1024:1024 + len(table)] = table
    image[34 * 512 + 82:34 * 512 + 90] = b'FAT32   '
    image[34 * 512 + 510:35 * 512] = b'\x55\xaa'
    (root / name).write_bytes(image)
    if name == 'esp':
        image[34 * 512 + 82:34 * 512 + 90] = bytes(8)
        (root / 'esp-without-fat').write_bytes(image)
PY
python3 "${root}/scripts/check-release-architecture.py" --uefi-image "${tmp}/esp"
for image in no-esp esp-without-fat; do
  if python3 "${root}/scripts/check-release-architecture.py" --uefi-image "${tmp}/${image}" >"${tmp}/error" 2>&1; then
    echo "invalid UEFI image accepted: ${image}" >&2
    exit 1
  fi
  grep -q 'missing EFI System Partition' "${tmp}/error"
done
echo 'release architecture rejects mixed binaries and missing ESPs'
