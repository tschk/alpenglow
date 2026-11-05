#!/bin/sh
# Exercise destructive installer paths only against disposable loop devices.
set -eu
export LC_ALL=C
root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
mounted_loop=""
small_loop=""
cleanup() {
  if mountpoint -q "${tmp}/mnt"; then sudo umount "${tmp}/mnt"; fi
  if [ -n "${mounted_loop}" ]; then sudo losetup -d "${mounted_loop}"; fi
  if [ -n "${small_loop}" ]; then sudo losetup -d "${small_loop}"; fi
  rm -rf "${tmp}"
}
trap cleanup EXIT INT TERM
mkdir "${tmp}/mnt"
chmod 755 "${tmp}"
failed=0
cargo build --manifest-path "${root}/system/installer/Cargo.toml" --bin alpenglow-install
installer="${root}/target/debug/alpenglow-install"
truncate -s 32M "${tmp}/mounted.img"
python3 - "${tmp}/mounted.img" <<'PY'
import struct, sys
with open(sys.argv[1], "r+b") as disk:
    mbr = bytearray(512)
    mbr[450] = 0x83
    struct.pack_into("<II", mbr, 454, 2048, 32768)
    mbr[510:512] = b"\x55\xaa"
    disk.write(mbr)
PY
mounted_loop="$(sudo losetup --find --partscan --show "${tmp}/mounted.img")"
device="$(cat "/sys/class/block/${mounted_loop##*/}p1/dev")"
sudo mknod "${tmp}/partition" b "${device%:*}" "${device#*:}"
sudo mkfs.ext4 -q "${tmp}/partition"
sudo mount "${tmp}/partition" "${tmp}/mnt"
printf 'installer safety fixture\n' > "${tmp}/source.img"
if sudo "${installer}" "${tmp}/source.img" "${mounted_loop}" >"${tmp}/mounted.log" 2>&1; then
  echo 'installer accepted a disk with a mounted partition' >&2
  failed=1
elif ! grep -q 'Device or resource busy' "${tmp}/mounted.log"; then
  cat "${tmp}/mounted.log" >&2
  echo 'installer failed for a reason other than the mounted partition' >&2
  failed=1
fi
sudo cp "${tmp}/source.img" "${tmp}/mnt/source.img"
if sudo "${installer}" "${tmp}/mnt/source.img" "${mounted_loop}" >"${tmp}/source-disk.log" 2>&1; then
  echo 'installer accepted the disk containing its source image' >&2
  failed=1
elif ! grep -q 'Device or resource busy' "${tmp}/source-disk.log"; then
  cat "${tmp}/source-disk.log" >&2
  failed=1
fi
sudo umount "${tmp}/mnt"
if sudo "${installer}" "${tmp}/partition" "${mounted_loop}" >"${tmp}/source-partition.log" 2>&1; then
  echo 'installer accepted a source partition on the target disk' >&2
  failed=1
elif ! grep -q 'source must be a regular image file' "${tmp}/source-partition.log"; then
  cat "${tmp}/source-partition.log" >&2
  failed=1
fi
head -c 4096 /dev/urandom > "${tmp}/small.img"
cp "${tmp}/small.img" "${tmp}/before.img"
small_loop="$(sudo losetup --find --show "${tmp}/small.img")"
dd if=/dev/zero of="${tmp}/large.img" bs=5000 count=1 status=none
zstd -q -f "${tmp}/large.img" -o "${tmp}/large.img.zst"
if sudo "${installer}" "${tmp}/large.img" "${small_loop}" >"${tmp}/small.log" 2>&1; then
  echo 'installer accepted an oversized raw image' >&2
  failed=1
elif ! grep -q 'image requires' "${tmp}/small.log"; then
  cat "${tmp}/small.log" >&2
  failed=1
fi
cmp "${tmp}/before.img" "${tmp}/small.img" || { echo 'oversized raw image modified the target' >&2; failed=1; }
if sudo "${installer}" "${tmp}/large.img.zst" "${small_loop}" >"${tmp}/compressed.log" 2>&1; then
  echo 'installer reported success writing an oversized compressed image' >&2
  failed=1
elif ! grep -q 'image requires' "${tmp}/compressed.log"; then
  cat "${tmp}/compressed.log" >&2
  failed=1
fi
cmp "${tmp}/before.img" "${tmp}/small.img" || { echo 'oversized compressed image modified the target' >&2; failed=1; }
sudo "${installer}" "${tmp}/source.img" "${small_loop}" >"${tmp}/success.log" 2>&1
sudo dd if="${small_loop}" of="${tmp}/written.img" bs=1 count="$(wc -c < "${tmp}/source.img")" status=none
cmp "${tmp}/source.img" "${tmp}/written.img"
zstd -q -f "${tmp}/source.img" -o "${tmp}/source.img.zst"
sudo "${installer}" "${tmp}/source.img.zst" "${small_loop}" >"${tmp}/success-compressed.log" 2>&1
sudo dd if="${small_loop}" of="${tmp}/written.img" bs=1 count="$(wc -c < "${tmp}/source.img")" status=none
cmp "${tmp}/source.img" "${tmp}/written.img"
for syscall in write fsync; do
  if sudo strace -qq -e "trace=${syscall}" -e "inject=${syscall}:error=EIO:when=1" \
      -o "${tmp}/${syscall}.trace" "${installer}" "${tmp}/source.img.zst" "${small_loop}" \
      >"${tmp}/${syscall}.log" 2>&1; then
    echo "installer reported success after ${syscall} failed" >&2
    failed=1
  elif ! grep -q 'INJECTED' "${tmp}/${syscall}.trace" || ! grep -q 'Input/output error' "${tmp}/${syscall}.log"; then
    echo "${syscall} fault injection did not reach the installer" >&2
    failed=1
  fi
done
[ "${failed}" -eq 0 ] || exit 1
echo 'installer rejects unsafe targets and reports write and sync failures'
