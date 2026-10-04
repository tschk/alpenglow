#!/bin/sh
# Verify the live-root glibc bundle covers the installer GUI's shared-library needs.
# Usage: test-installer-gui-libs.sh [path/to/alpenglow-install-gui]
# Uses only temp fixtures; no image builds, downloads, or guest boots.
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
BIN="${1:-${ROOT_DIR}/target/debug/alpenglow-install-gui}"
BUNDLE_SCRIPT="${ROOT_DIR}/system/backends/appliance/scripts/install-graphics-libs.sh"
BOOT_SCRIPT="${ROOT_DIR}/scripts/boot-native.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT HUP INT TERM

fail() { printf 'test-installer-gui-libs: FAIL: %s\n' "$1" >&2; exit 1; }

test -f "${BIN}" || fail "missing GUI binary: ${BIN} (build with --features gui)"
command -v readelf >/dev/null 2>&1 || fail "missing: readelf"

# 1. Every direct DT_NEEDED soname must be copied by the bundle script.
needed="$(readelf -d "${BIN}" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')"
test -n "${needed}" || fail "no NEEDED entries read from ${BIN}"
for lib in ${needed}; do
  case "${lib}" in
    ld-linux-*) continue ;;
  esac
  grep -qw -- "${lib}" "${BUNDLE_SCRIPT}" || fail "${lib} is needed by the GUI but not bundled by install-graphics-libs.sh"
done

# 2. The Debian packages providing the X11 xkb libs must be installed in the bundle build.
grep -qw libxkbcommon-x11-0 "${BUNDLE_SCRIPT}" || fail "libxkbcommon-x11-0 not installed by bundle script"
grep -qw libxcb-xkb1 "${BUNDLE_SCRIPT}" || fail "libxcb-xkb1 not installed by bundle script"

# 3. boot-native.sh must rebuild a cached bundle that lacks those libs.
extract_cache_check() {
  sed -n '/graphics-backend" 2>\/dev\/null/,/; then$/p' "${BOOT_SCRIPT}"
}
check="$(extract_cache_check)"
for lib in libxkbcommon-x11.so.0 libxcb-xkb.so.1; do
  printf '%s\n' "${check}" | grep -qF "${lib}" || fail "boot-native.sh cache check ignores ${lib}"
done

# Simulate the cache condition against an old-style and a refreshed bundle.
cache_stale() {
  dir="$1"
  [ ! -f "${dir}/lib/x86_64-linux-gnu/libvulkan.so.1" ] ||
    [ ! -f "${dir}/lib/x86_64-linux-gnu/libxkbcommon-x11.so.0" ] ||
    [ ! -f "${dir}/lib/x86_64-linux-gnu/libxcb-xkb.so.1" ]
}
mkdir -p "${TMP}/old/lib/x86_64-linux-gnu" "${TMP}/new/lib/x86_64-linux-gnu"
touch "${TMP}/old/lib/x86_64-linux-gnu/libvulkan.so.1" "${TMP}/new/lib/x86_64-linux-gnu/libvulkan.so.1" \
  "${TMP}/new/lib/x86_64-linux-gnu/libxkbcommon-x11.so.0" "${TMP}/new/lib/x86_64-linux-gnu/libxcb-xkb.so.1"
cache_stale "${TMP}/old" || fail "pre-fix bundle cache would not be rebuilt"
! cache_stale "${TMP}/new" || fail "refreshed bundle cache would be rebuilt needlessly"

# 4. Loader check: a root laid out like the live root (no LD_LIBRARY_PATH, no ld.so.cache)
#    must resolve every library through the loader's own search path. Needs root for chroot.
if [ "$(id -u)" = 0 ] && command -v chroot >/dev/null 2>&1 && command -v ldd >/dev/null 2>&1; then
  root="${TMP}/live"
  mkdir -p "${root}/usr/bin" "${root}/lib/x86_64-linux-gnu" "${root}/lib64"
  cp "${BIN}" "${root}/usr/bin/alpenglow-install-gui"
  ldd "${BIN}" | awk '$3 ~ /^\// {print $3}' | while read -r dep; do
    cp -L "${dep}" "${root}/lib/x86_64-linux-gnu/"
  done
  loader="$(ldd "${BIN}" | awk '/ld-linux/ {print $1}')"
  cp -L "${loader}" "${root}/lib64/ld-linux-x86-64.so.2"
  out="$(env -u LD_LIBRARY_PATH chroot "${root}" /lib64/ld-linux-x86-64.so.2 --inhibit-cache --list /usr/bin/alpenglow-install-gui 2>&1)" ||
    fail "loader could not list dependencies: ${out}"
  case "${out}" in
    *"not found"*) fail "unresolved libraries in live-root layout: ${out}" ;;
  esac
  # And prove the check is meaningful: dropping the xkb libs must make it fail.
  rm -f "${root}/lib/x86_64-linux-gnu/libxkbcommon-x11.so.0" "${root}/lib/x86_64-linux-gnu/libxcb-xkb.so.1"
  if out="$(env -u LD_LIBRARY_PATH chroot "${root}" /lib64/ld-linux-x86-64.so.2 --inhibit-cache --list /usr/bin/alpenglow-install-gui 2>&1)"; then
    case "${out}" in *"not found"*) ;; *) fail "loader check did not detect missing xkb libs" ;; esac
  fi
else
  printf 'test-installer-gui-libs: skipping loader check (needs root, chroot, ldd)\n'
fi

printf 'test-installer-gui-libs: ok\n'
