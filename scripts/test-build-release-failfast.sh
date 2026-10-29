#!/bin/sh
# build-release.sh must stop when the kernel/initramfs build fails, even with
# stale artifacts from an earlier build lying around, and must stop when the
# composed rootfs misses what its edition promises. Runs a copy of the script
# with boot-native.sh stubbed and no network, disk or sudo access.
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM
fail() { printf 'test-build-release-failfast: %s\n' "$1" >&2; exit 1; }

root="${tmp}/repo"
mkdir -p "${root}/scripts" "${root}/system/backends/appliance" "${tmp}/bin"
cp -R "${REPO_ROOT}/scripts/lib" "${root}/scripts/"
cp "${REPO_ROOT}/scripts/build-release.sh" "${REPO_ROOT}/scripts/edition-resolve.sh" \
  "${REPO_ROOT}/scripts/check-release-rootfs.sh" "${root}/scripts/"
cp "${REPO_ROOT}/editions.toml" "${root}/"
cp "${REPO_ROOT}"/system/backends/appliance/packages-*.txt "${root}/system/backends/appliance/"

# Anything past the kernel step touches the network or the disk: record it.
for tool in curl sudo sgdisk dd; do
  printf '#!/bin/sh\necho %s >> "%s/reached"\nexit 1\n' "${tool}" "${tmp}" > "${tmp}/bin/${tool}"
  chmod 755 "${tmp}/bin/${tool}"
done

# stub_boot_native <exit-status>: leaves a plausible kernel + initramfs from
# "an earlier build" and a rootfs without any services.
stub_boot_native() {
  cat > "${root}/scripts/boot-native.sh" << EOF
#!/bin/sh
mkdir -p "${root}/build/native/rootfs/etc/dinit.d"
echo stale > "${root}/build/native/vmlinuz"
printf 'stale' | gzip > "${root}/build/native/initramfs.cpio.gz"
echo "boot-native: kernel build failed" >&2
exit $1
EOF
  chmod 755 "${root}/scripts/boot-native.sh"
}

run_release() {
  rm -f "${tmp}/reached"
  PATH="${tmp}/bin:${PATH}" IMAGE_SIZE_MB=1 ALPENGLOW_EDITION=potato \
    sh "${root}/scripts/build-release.sh" > "${tmp}/out" 2>&1
}

stub_boot_native 1
if run_release; then fail "failed kernel build produced a release"; fi
[ ! -e "${tmp}/reached" ] || fail "continued past a failed kernel build: $(cat "${tmp}/reached")"
grep -q 'boot-native: kernel build failed' "${tmp}/out" || fail "build error output was hidden"

stub_boot_native 0
if run_release; then fail "rootfs without editions.toml services produced a release"; fi
[ ! -e "${tmp}/reached" ] || fail "continued past the rootfs check: $(cat "${tmp}/reached")"
grep -q 'check-release-rootfs: potato image does not match editions.toml' "${tmp}/out" ||
  fail "rootfs check did not run"

printf 'test-build-release-failfast: ok\n'
