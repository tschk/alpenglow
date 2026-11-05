#!/bin/sh
# A failed loop allocation must never reach a formatter.
set -eu
root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM
mkdir -p "${tmp}/scripts/lib" "${tmp}/build/native" "${tmp}/build/release/limine" "${tmp}/bin"
cp "${root}/scripts/build-release.sh" "${tmp}/scripts/"
cp "${root}/scripts/lib/initramfs-codec-identity.sh" "${tmp}/scripts/lib/"
printf '#!/bin/sh\nexit 0\n' > "${tmp}/scripts/boot-native.sh"
chmod +x "${tmp}/scripts/boot-native.sh"
touch "${tmp}/build/native/vmlinuz" "${tmp}/build/release/limine/limine"
printf '\037\213\010\000' > "${tmp}/build/native/initramfs.cpio.gz"
printf '#!/bin/sh\nexit 0\n' > "${tmp}/bin/sgdisk"
printf '#!/bin/sh\nexit 0\n' > "${tmp}/bin/dd"
cat > "${tmp}/bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${TEST_SUDO_LOG}"
case "$1" in losetup) exit 1 ;; esac
exit 0
EOF
chmod +x "${tmp}/bin/sgdisk" "${tmp}/bin/dd" "${tmp}/bin/sudo"
export TEST_SUDO_LOG="${tmp}/sudo.log"
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
echo 'release loop allocation failure stops before formatting'
