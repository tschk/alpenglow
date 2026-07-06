#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

fail() { printf 'ci-profile-matrix: %s\n' "$1" >&2; exit 1; }
assert_contains() { grep -Eq "${2}" "$1" || fail "${1} missing pattern: ${2}"; }
assert_not_contains() { ! grep -Eq "${2}" "$1" || fail "${1} unexpectedly matches ${2}"; }

tmp_root="$(mktemp -d)"
trap 'rm -rf "${tmp_root}"' EXIT INT TERM

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
      ;;
  esac
}

run_profile minimal
run_profile standard
run_profile desktop

printf 'ci-profile-matrix: ok\n'
