#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

fail() { printf 'ci-profile-matrix: %s\n' "$1" >&2; exit 1; }
assert_contains() { grep -Eq "${2}" "$1" || fail "${1} missing pattern: ${2}"; }
assert_not_contains() { ! grep -Eq "${2}" "$1" || fail "${1} unexpectedly matches ${2}"; }

tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT INT TERM
unset SESSION ALPENGLOW_SESSION ALPENGLOW_SKU ALPENGLOW_EDITION ALPENGLOW_ROLE ALPENGLOWED_ROLE ARTIFACT LOCK_SESSION SHELL_LOGIN FLEET_AGENT WORLD_FILE ALPENGLOW_DESKTOP_FULL ALPENGLOW_FLEET ALPENGLOW_KIOSK ALPENGLOW_ARTIFACT

run_profile() {
  profile="$1"
  root="${tmp_root}/${profile}"
  for dir in bin sbin etc dev proc sys tmp run; do
    mkdir -p "${root}/${dir}"
  done
  BUILD_PROFILE="${profile}" system/backends/appliance/scripts/configure-rootfs.sh "${root}" >/dev/null
  case "${profile}" in
    minimal)
      assert_not_contains "${root}/etc/alpenglow/world" '^alpenglowed$'
      assert_not_contains "${root}/etc/alpenglow/world" '^pipewire$'
      assert_not_contains "${root}/etc/alpenglow/world" '^iwd$'
      assert_not_contains "${root}/etc/alpenglow/world" '^greetd$'
      ;;
    standard)
      assert_contains "${root}/etc/alpenglow/system.json" '"profile": "standard"'
      assert_not_contains "${root}/etc/alpenglow/world" '^alpenglowed$'
      assert_not_contains "${root}/etc/alpenglow/world" '^pipewire$'
      assert_not_contains "${root}/etc/alpenglow/world" '^iwd$'
      assert_not_contains "${root}/etc/alpenglow/world" '^greetd$'
      ;;
    desktop)
      assert_contains "${root}/etc/alpenglow/system.json" '"profile": "desktop"'
      assert_contains "${root}/etc/alpenglow/world" '^alpenglowed$'
      assert_contains "${root}/etc/alpenglow/world" '^pipewire$'
      assert_contains "${root}/etc/alpenglow/world" '^iwd$'
      assert_contains "${root}/etc/alpenglow/world" '^greetd$'
      assert_contains "${root}/etc/dinit.d/greetd" '^depends-on = state-mount$'
      assert_contains "${root}/etc/dinit.d/alpenglowed" '^depends-on = state-mount$'
      assert_contains "${root}/etc/dinit.d/alpenglow-session" '^depends-on = state-mount$'
      ;;
  esac
}

run_profile minimal
run_profile standard
run_profile desktop

lite="${tmp_root}/desktop-lite"
for dir in bin sbin etc dev proc sys tmp run; do
  mkdir -p "${lite}/${dir}"
done
ALPENGLOW_DESKTOP_FULL=0 BUILD_PROFILE=desktop \
  system/backends/appliance/scripts/configure-rootfs.sh "${lite}" >/dev/null
assert_contains "${lite}/etc/dinit.d/alpenglowed-lite" '^depends-on = state-mount$'

userspace="${tmp_root}/desktop-userspace"
for dir in bin sbin etc dev proc sys tmp run; do
  mkdir -p "${userspace}/${dir}"
done
ARTIFACT=userspace BUILD_PROFILE=desktop SESSION=alpenglowed \
  system/backends/appliance/scripts/configure-rootfs.sh "${userspace}" >/dev/null
assert_contains "${userspace}/etc/dinit.d/boot" '^depends-on = alpenglowed$'
assert_not_contains "${userspace}/etc/dinit.d/boot" '^depends-on = state-mount$'
assert_not_contains "${userspace}/etc/dinit.d/greetd" '^depends-on = state-mount$'
assert_not_contains "${userspace}/etc/dinit.d/alpenglowed" '^depends-on = state-mount$'
assert_not_contains "${userspace}/etc/dinit.d/alpenglow-session" '^depends-on = state-mount$'

native="${tmp_root}/native"
mkdir -p "${native}/bin" "${native}/dev" "${native}/etc" "${native}/usr/local/bin"
cp /bin/true "${native}/bin/toybox"
ln -s /bin/toybox "${native}/bin/sh"
ln -s /bin/toybox "${native}/bin/true"
(
  ROOTFS_DIR="${native}" OUT_DIR="${tmp_root}" ROOT_DIR="${REPO_ROOT}"
  BACKEND_DIR="${REPO_ROOT}/system/backends/appliance" BUILD_PROFILE=standard FAST=0
  ALPENGLOW_MODULE="${tmp_root}/missing-module"
  toybox_has() { case "$1" in sh|getty|mount) return 0 ;; *) return 1 ;; esac; }
  . "${REPO_ROOT}/scripts/lib/assemble-rootfs.sh"
  assemble_rootfs_config >/dev/null
)
assert_contains "${native}/etc/dinit.d/boot" '^depends-on = state-mount$'
assert_contains "${native}/etc/dinit.d/boot" '^depends-on = shell-ttyS0$'
assert_not_contains "${native}/etc/dinit.d/boot" '^depends-on = (alpenglow-kernel-policy|alpenglow-netd|alpenglow-zram|alpenglow-pressure|alpenglow-power|networking|earlyoom|dropbear|chronyd|syslogd|crond|dnsmasq)$'
[ ! -e "${native}/etc/dinit.d/boot.d/alpenglow-kernel-policy" ] || fail 'unavailable service remains enabled'
(
  ROOTFS_DIR="${native}"
  toybox_has() { return 0; }
  . "${REPO_ROOT}/scripts/lib/assemble-rootfs.sh"
  rm "${native}/usr/local/bin/mount-state.sh"
  if _assemble_native_validate_services 2>/dev/null; then
    fail 'validation accepted a missing required service command'
  fi
)

native_full="${tmp_root}/native-full"
mkdir -p "${native_full}/bin" "${native_full}/dev" "${native_full}/etc" "${native_full}/usr/local/bin"
cp /bin/true "${native_full}/bin/toybox"
ln -s /bin/toybox "${native_full}/bin/sh"
ln -s /bin/toybox "${native_full}/bin/true"
for executable in alpenglow-kernelctl alpenglow-netd alpenglow-zramctl-zig alpenglow-pressurectl-zig; do
  cp /bin/true "${native_full}/usr/local/bin/${executable}"
done
(
  ROOTFS_DIR="${native_full}" OUT_DIR="${tmp_root}" ROOT_DIR="${REPO_ROOT}"
  BACKEND_DIR="${REPO_ROOT}/system/backends/appliance" BUILD_PROFILE=standard FAST=0
  ALPENGLOW_MODULE="${tmp_root}/missing-module"
  toybox_has() { return 0; }
  . "${REPO_ROOT}/scripts/lib/assemble-rootfs.sh"
  assemble_rootfs_config >/dev/null
)
for service in state-mount alpenglow-kernel-policy alpenglow-netd alpenglow-zram alpenglow-pressure networking syslogd crond; do
  assert_contains "${native_full}/etc/dinit.d/boot" "^depends-on = ${service}$"
done
assert_contains "${native_full}/etc/dinit.d/networking" '/usr/share/udhcpc/default.script'
(
  ROOTFS_DIR="${native_full}"
  toybox_has() { return 0; }
  . "${REPO_ROOT}/scripts/lib/assemble-rootfs.sh"
  sed -i '/^depends-on = alpenglow-kernel-policy$/d' "${native_full}/etc/dinit.d/boot"
  rm "${native_full}/usr/local/bin/alpenglow-kernelctl"
  if _assemble_native_validate_services 2>/dev/null; then
    fail 'validation accepted a missing transitive dependency command'
  fi
)

printf 'ci-profile-matrix: ok\n'
