#!/bin/sh
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${ROOT_DIR}"
sh scripts/build-v86-initramfs.sh
test -f public/v86/alpenglow-v86-initrd.cpio.gz
test -f public/v86/alpenglow-v86-vmlinuz
gzip -dc public/v86/alpenglow-v86-initrd.cpio.gz | cpio -t 2>/dev/null | grep -qE '^(\./)?init$'
echo "v86 initramfs ok"