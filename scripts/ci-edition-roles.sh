#!/bin/sh
# CI: public SKUs fast|minimal|potato|desktop|internet
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

fail() { printf 'ci-edition-roles: %s\n' "$1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1' ($3)"; }
assert_contains() { grep -E -q -e "${2}" "$1" || fail "${1} missing pattern: ${2}"; }
assert_not_contains() { ! grep -E -q -e "${2}" "$1" || fail "${1} unexpectedly matches ${2}"; }
assert_file() { [ -f "$1" ] || fail "missing: $1"; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM
unset SESSION ALPENGLOW_SESSION ALPENGLOW_SKU ALPENGLOW_EDITION ALPENGLOW_ROLE ALPENGLOWED_ROLE ARTIFACT LOCK_SESSION SHELL_LOGIN FLEET_AGENT WORLD_FILE ALPENGLOW_FLEET ALPENGLOW_KIOSK ALPENGLOW_ARTIFACT

list="$(sh scripts/edition-resolve.sh --list)"
for sku in fast minimal potato desktop internet; do
  printf '%s\n' "${list}" | grep -qx "${sku}" || fail "--list missing ${sku}"
done
for gone in standard embedded potatoes kiosk workstation desktop-full containers desktop-lite; do
  printf '%s\n' "${list}" | grep -qx "${gone}" && fail "--list leaked ${gone}"
done

demo_field() {
  ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION="$1" sh scripts/edition-resolve.sh --demo \
    | tr ' ' '\n' | sed -n "s/^$2=//p"
}

assert_eq "$(demo_field fast ALPENGLOW_SKU)" "fast" "fast sku"
assert_eq "$(demo_field fast SESSION)" "none" "fast session"
assert_eq "$(demo_field fast KERNEL_PROFILE)" "fast" "fast kernel"
assert_eq "$(demo_field fast WORLD_FILE)" "packages-minimal.txt" "fast world"
assert_eq "$(demo_field fast ALPENGLOWED_ROLE)" "none" "fast alpenglowed role"
assert_eq "$(demo_field minimal ALPENGLOW_SKU)" "minimal" "minimal sku"
assert_eq "$(demo_field minimal SESSION)" "none" "minimal session"
assert_eq "$(demo_field minimal KERNEL_PROFILE)" "minimal" "minimal kernel"
assert_eq "$(demo_field minimal WORLD_FILE)" "packages-minimal.txt" "minimal world"
assert_eq "$(demo_field potato ALPENGLOW_SKU)" "potato" "potato sku"
assert_eq "$(demo_field potato SESSION)" "alpenglowed" "potato session"
assert_eq "$(demo_field potato ALPENGLOWED_ROLE)" "potato" "potato role"
assert_eq "$(demo_field potato WORLD_FILE)" "packages-potato.txt" "potato world"
assert_eq "$(demo_field desktop ALPENGLOW_SKU)" "desktop" "desktop sku"
assert_eq "$(demo_field desktop WORLD_FILE)" "packages-runtime.txt" "desktop world"
assert_eq "$(demo_field internet SESSION)" "sold" "internet session"
assert_eq "$(demo_field standard ALPENGLOW_SKU)" "minimal" "standard→minimal"
assert_eq "$(demo_field standard BUILD_PROFILE)" "standard" "standard toolchain"
assert_eq "$(demo_field standard WORLD_FILE)" "packages-standard.txt" "standard world"
assert_eq "$(demo_field standard SESSION)" "none" "standard session"
assert_eq "$(demo_field kiosk ALPENGLOW_SKU)" "internet" "kiosk→internet"
assert_eq "$(demo_field kiosk SESSION)" "cage" "kiosk session"
assert_eq "$(
  unset ALPENGLOW_EDITION ALPENGLOW_SKU ALPENGLOW_ROLE
  ROOT_DIR="${REPO_ROOT}"
  export ROOT_DIR
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/scripts/edition-resolve.sh"
  printf '%s\n' "${ALPENGLOW_SKU}"
)" "potato" "default SKU is potato"

assert_file system/backends/appliance/packages-minimal.txt
assert_file system/backends/appliance/packages-potato.txt
assert_file system/backends/appliance/packages-internet.txt
assert_not_contains system/backends/appliance/packages-internet.txt '^alpenglowed$'
assert_file system/backends/appliance/dinit/sold
assert_file system/backends/appliance/dinit/cage

run_sku() {
  sku="$1"
  root="${tmp}/${sku}"
  for dir in bin sbin etc dev proc sys tmp run; do
    mkdir -p "${root}/${dir}"
  done
  unset SESSION ALPENGLOW_SESSION ALPENGLOW_ROLE ALPENGLOW_SKU ALPENGLOWED_ROLE ARTIFACT LOCK_SESSION SHELL_LOGIN FLEET_AGENT WORLD_FILE ALPENGLOW_FLEET ALPENGLOW_KIOSK ALPENGLOW_ARTIFACT
  ROOT_DIR="${REPO_ROOT}"
  ALPENGLOW_EDITION="${sku}"
  export ROOT_DIR ALPENGLOW_EDITION
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/scripts/edition-resolve.sh"
  BUILD_PROFILE="${BUILD_PROFILE}" WORLD_FILE="${WORLD_FILE}" SESSION="${SESSION}" \
    ALPENGLOW_ROLE="${ALPENGLOW_ROLE}" ALPENGLOW_SKU="${ALPENGLOW_SKU}" \
    ARTIFACT="${ARTIFACT}" LOCK_SESSION="${LOCK_SESSION}" SHELL_LOGIN="${SHELL_LOGIN}" \
    ALPENGLOW_KIOSK="${ALPENGLOW_KIOSK}" ALPENGLOWED_ROLE="${ALPENGLOWED_ROLE}" \
    ALPENGLOW_DESKTOP_FULL="${ALPENGLOW_DESKTOP_FULL}" ALPENGLOW_EDITION="${ALPENGLOW_EDITION}" \
    system/backends/appliance/scripts/configure-rootfs.sh "${root}" >/dev/null
}

run_sku fast
assert_contains "${tmp}/fast/etc/alpenglow/edition" '^fast$'
assert_contains "${tmp}/fast/etc/alpenglow/system.json" '"sku": "fast"'
assert_contains "${tmp}/fast/etc/alpenglow/role" '^none$'
assert_not_contains "${tmp}/fast/etc/dinit.d/boot" 'depends-on = alpenglowed'
assert_not_contains "${tmp}/fast/etc/alpenglow/world" '^alpenglowed$'

run_sku minimal
assert_contains "${tmp}/minimal/etc/alpenglow/edition" '^minimal$'
assert_contains "${tmp}/minimal/etc/alpenglow/system.json" '"sku": "minimal"'
assert_contains "${tmp}/minimal/etc/alpenglow/role" '^none$'
assert_contains "${tmp}/minimal/etc/dinit.d/boot" 'depends-on = dropbear'
assert_contains "${tmp}/minimal/etc/dinit.d/boot" 'depends-on = chronyd'
assert_not_contains "${tmp}/minimal/etc/dinit.d/boot" 'depends-on = alpenglowed'
assert_not_contains "${tmp}/minimal/etc/alpenglow/world" '^alpenglowed$'

run_sku potato
assert_contains "${tmp}/potato/etc/alpenglow/role" '^potato$'
assert_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = alpenglowed-lite'
assert_not_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = alpenglowed$'

run_sku desktop
assert_contains "${tmp}/desktop/etc/alpenglow/role" '^desktop$'
assert_contains "${tmp}/desktop/etc/dinit.d/boot" 'depends-on = alpenglowed$'

run_sku internet
assert_contains "${tmp}/internet/etc/dinit.d/boot" 'depends-on = sold'
assert_not_contains "${tmp}/internet/etc/alpenglow/world" '^alpenglowed$'

run_sku kiosk
assert_contains "${tmp}/kiosk/etc/dinit.d/boot" 'depends-on = cage'
assert_file "${tmp}/kiosk/etc/alpenglow/session-lock.json"
assert_contains "${tmp}/kiosk/etc/alpenglow/role" '^internet$'

run_sku standard
assert_contains "${tmp}/standard/etc/alpenglow/edition" '^standard$'
assert_contains "${tmp}/standard/etc/alpenglow/system.json" '"sku": "minimal"'
assert_contains "${tmp}/standard/etc/alpenglow/system.json" '"profile": "standard"'
assert_not_contains "${tmp}/standard/etc/dinit.d/boot" 'depends-on = alpenglowed'

sh scripts/export-container.sh "${tmp}/potato" "${tmp}/oci-out" >/dev/null
assert_file "${tmp}/oci-out/alpenglow-dev-potato-$(uname -m).tar"

printf 'ci-edition-roles: ok\n'
