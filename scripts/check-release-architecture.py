#!/usr/bin/env python3
"""Reject ELF files that do not match a release root filesystem's architecture."""

import gzip
import lzma
import os
import stat
import struct
import subprocess
import sys
import uuid
import zlib

MACHINES = {"x86_64": 62, "aarch64": 183}
ESP_GUID = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b").bytes_le
BIOS_GUID = uuid.UUID("21686148-6449-6e6f-744e-656564454649").bytes_le


def check_disk_image(path, firmware):
    with open(path, "rb") as image:
        image.seek(0, os.SEEK_END)
        size = image.tell()
        if firmware == "bios":
            image.seek(0)
            mbr = image.read(512)
            if len(mbr) != 512 or mbr[510:] != b"\x55\xaa" or not any(mbr[:440]):
                raise ValueError(f"missing BIOS MBR boot code: {path}")
        image.seek(512)
        header = image.read(512)
        if len(header) != 512 or header[:8] != b"EFI PART":
            raise ValueError(f"missing GPT on {firmware} image: {path}")
        header_size, header_crc = struct.unpack_from("<II", header, 12)
        if not 92 <= header_size <= 512:
            raise ValueError(f"invalid GPT header: {path}")
        header_copy = bytearray(header[:header_size])
        header_copy[16:20] = bytes(4)
        if zlib.crc32(header_copy) != header_crc:
            raise ValueError(f"invalid GPT header checksum: {path}")
        table_lba, count, entry_size, table_crc = struct.unpack_from("<QIII", header, 72)
        table_size = count * entry_size
        if not (0 < count <= 16384 and 128 <= entry_size <= 4096
                and table_lba * 512 + table_size <= size):
            raise ValueError(f"invalid GPT partition table: {path}")
        image.seek(table_lba * 512)
        table = image.read(table_size)
        if len(table) != table_size or zlib.crc32(table) != table_crc:
            raise ValueError(f"invalid GPT partition checksum: {path}")
        for offset in range(0, table_size, entry_size):
            entry = table[offset:offset + entry_size]
            if entry[:16] == (ESP_GUID if firmware == "uefi" else BIOS_GUID):
                first, last = struct.unpack_from("<QQ", entry, 32)
                if first > 0 and first <= last and (last + 1) * 512 <= size:
                    image.seek(first * 512)
                    if firmware == "bios":
                        if any(image.read(min((last - first + 1) * 512, 65536))):
                            return
                        continue
                    boot_sector = image.read(512)
                    if (len(boot_sector) == 512 and boot_sector[510:] == b"\x55\xaa"
                            and (boot_sector[82:90] == b"FAT32   " or boot_sector[54:62] == b"FAT16   ")):
                        return
        if firmware == "bios":
            raise ValueError(f"missing or empty GPT BIOS boot partition: {path}")
        raise ValueError(f"missing EFI System Partition in UEFI image: {path}")


def check_file(path, expected):
    if not stat.S_ISREG(os.lstat(path).st_mode):
        return
    module = path.endswith((".ko", ".ko.gz", ".ko.xz", ".ko.zst"))
    if path.endswith(".ko.gz"):
        with gzip.open(path, "rb") as stream:
            header = stream.read(20)
    elif path.endswith(".ko.xz"):
        with lzma.open(path, "rb") as stream:
            header = stream.read(20)
    elif path.endswith(".ko.zst"):
        result = subprocess.run(["zstd", "-dc", path], stdout=subprocess.PIPE, check=True)
        header = result.stdout[:20]
    else:
        with open(path, "rb") as stream:
            header = stream.read(20)
    if not header.startswith(b"\x7fELF"):
        if module:
            raise ValueError(f"invalid kernel module: {path}")
        return
    if len(header) < 20 or header[4] != 2 or header[5] != 1:
        raise ValueError(f"invalid or non-64-bit ELF: {path}")
    machine = struct.unpack_from("<H", header, 18)[0]
    if machine != expected:
        raise ValueError(f"wrong ELF architecture in {path}: e_machine={machine}, expected {expected}")


def main():
    if len(sys.argv) == 3 and sys.argv[1] in ("--uefi-image", "--bios-image"):
        check_disk_image(sys.argv[2], "uefi" if sys.argv[1] == "--uefi-image" else "bios")
        return
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in MACHINES or not os.path.isdir(sys.argv[2]):
        raise ValueError("usage: check-release-architecture.py x86_64|aarch64 ROOTFS [KERNEL] | --uefi-image|--bios-image IMAGE")
    expected = MACHINES[sys.argv[1]]
    for directory, _, names in os.walk(sys.argv[2], onerror=lambda error: (_ for _ in ()).throw(error)):
        for name in names:
            check_file(os.path.join(directory, name), expected)
    if len(sys.argv) == 4:
        with open(sys.argv[3], "rb") as stream:
            stream.seek(0x202 if sys.argv[1] == "x86_64" else 0x38)
            magic = stream.read(4)
        if magic != (b"HdrS" if sys.argv[1] == "x86_64" else b"ARM\x64"):
            raise ValueError(f"wrong or invalid {sys.argv[1]} kernel image: {sys.argv[3]}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"release architecture check failed: {error}", file=sys.stderr)
        sys.exit(1)
