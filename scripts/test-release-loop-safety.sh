#!/bin/sh
# A failed loop allocation must never reach a formatter.
set -eu
root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM
mkdir -p "${tmp}/scripts/lib" "${tmp}/build/native/rootfs/bin" "${tmp}/build/release/limine" "${tmp}/bin"
cp "${root}/scripts/build-release.sh" "${tmp}/scripts/"
cp "${root}/scripts/check-release-architecture.py" "${tmp}/scripts/"
cp "${root}/scripts/lib/initramfs-codec-identity.sh" "${tmp}/scripts/lib/"
python3 -c 'import sys; open(sys.argv[1], "wb").write(b"\x7fELF\x02\x01" + bytes(12) + b"\x3e\x00")' "${tmp}/build/native/rootfs/bin/true"
cat > "${tmp}/scripts/boot-native.sh" <<'EOF'
#!/bin/sh
[ "${TEST_BOOT_FAIL:-0}" = 0 ] || exit 71
[ "${TEST_MISSING_KERNEL:-0}" = 1 ] || python3 -c 'import sys; open(sys.argv[1], "wb").write(bytes(0x202) + b"HdrS")' "$(dirname "$0")/../build/native/vmlinuz"
[ "${TEST_WRONG_ARCH:-0}" = 0 ] || python3 -c 'import sys; open(sys.argv[1], "wb").write(b"\x7fELF\x02\x01" + bytes(12) + b"\xb7\x00")' "$(dirname "$0")/../build/native/rootfs/bin/wrong"
printf '\002\041\114\030new' > "${INITRAMFS:?release must choose an initramfs path}"
EOF
chmod +x "${tmp}/scripts/boot-native.sh"
touch "${tmp}/build/native/vmlinuz" "${tmp}/build/release/limine/limine"
printf '\037\213\010\000' > "${tmp}/build/native/initramfs.cpio.gz"
printf '\050\265\057\375stale' > "${tmp}/build/native/initramfs.cpio.zst"
printf '#!/bin/sh\nexit 0\n' > "${tmp}/bin/lz4"
printf '#!/bin/sh\nexit 0\n' > "${tmp}/bin/sgdisk"
printf '#!/bin/sh\nexit 0\n' > "${tmp}/bin/dd"
cat > "${tmp}/bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${TEST_SUDO_LOG}"
case "$1" in losetup) exit 1 ;; esac
exit 0
EOF
chmod +x "${tmp}/bin/sgdisk" "${tmp}/bin/dd" "${tmp}/bin/sudo" "${tmp}/bin/lz4"
export TEST_SUDO_LOG="${tmp}/sudo.log"
if PATH="${tmp}/bin:${PATH}" TEST_BOOT_FAIL=1 sh "${tmp}/scripts/build-release.sh" >"${tmp}/failure-output" 2>&1; then
  echo 'release build succeeded after boot build failed' >&2
  exit 1
fi
if [ -e "${TEST_SUDO_LOG}" ]; then
  echo 'release build continued to disk operations after boot build failed' >&2
  exit 1
fi
if PATH="${tmp}/bin:${PATH}" TEST_MISSING_KERNEL=1 sh "${tmp}/scripts/build-release.sh" >"${tmp}/missing-output" 2>&1; then
  echo 'release build accepted a missing newly built kernel' >&2
  exit 1
fi
if [ -e "${TEST_SUDO_LOG}" ]; then
  echo 'release build used a stale kernel after the build produced none' >&2
  exit 1
fi
if PATH="${tmp}/bin:${PATH}" TEST_WRONG_ARCH=1 sh "${tmp}/scripts/build-release.sh" >"${tmp}/architecture-output" 2>&1; then
  echo 'release build accepted the wrong architecture' >&2
  exit 1
fi
grep -q 'wrong ELF architecture' "${tmp}/architecture-output"
if [ -e "${TEST_SUDO_LOG}" ]; then
  echo 'release build reached disk operations with a wrong-architecture binary' >&2
  exit 1
fi
rm "${tmp}/build/native/rootfs/bin/wrong"
if PATH="${tmp}/bin:${PATH}" sh "${tmp}/scripts/build-release.sh" >"${tmp}/output" 2>&1; then
  echo 'release build succeeded after losetup failed' >&2
  exit 1
fi
grep -q '^losetup -fP --show ' "${TEST_SUDO_LOG}" || {
  echo 'release build did not reach loop allocation' >&2
  exit 1
}
if grep -Eq '^(mkfs\.|kpartx|mount )' "${TEST_SUDO_LOG}"; then
  echo 'release build attempted disk operations after losetup failed' >&2
  exit 1
fi
cmp "${tmp}/build/native/initramfs.cpio.lz4" "${tmp}/build/release/initramfs.cpio.lz4" || {
  echo 'release build did not select the fresh requested initramfs' >&2
  exit 1
}
echo 'release loop allocation failure stops before formatting'
