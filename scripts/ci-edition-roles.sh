#!/bin/sh
# CI: public SKUs fast|potato|desktop|internet
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
for sku in fast potato desktop internet; do
  printf '%s\n' "${list}" | grep -qx "${sku}" || fail "--list missing ${sku}"
done
for gone in minimal standard embedded potatoes kiosk workstation desktop-full containers desktop-lite; do
  printf '%s\n' "${list}" | grep -qx "${gone}" && fail "--list leaked ${gone}"
done

demo_field() {
  ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION="$1" sh scripts/edition-resolve.sh --demo \
    | tr ' ' '\n' | sed -n "s/^$2=//p"
}

assert_eq "$(demo_field potato ALPENGLOW_SKU)" "potato" "potato sku"
assert_eq "$(demo_field potato SESSION)" "none" "potato session"
assert_eq "$(demo_field potato KERNEL_PROFILE)" "minimal" "potato kernel"
assert_eq "$(demo_field potato FAST)" "0" "potato is not FAST"
assert_eq "$(demo_field potato WORLD_FILE)" "packages-potato.txt" "potato world"
assert_eq "$(demo_field potato STATE_COMPRESSION)" "lz4" "potato /state compression"
assert_eq "$(demo_field potato STATE_SNAPSHOTS)" "1" "potato snapshots"
assert_eq "$(demo_field fast ALPENGLOW_SKU)" "fast" "fast sku"
assert_eq "$(demo_field fast SESSION)" "none" "fast session"
assert_eq "$(demo_field fast KERNEL_PROFILE)" "fast" "fast kernel"
assert_eq "$(demo_field fast FAST)" "1" "fast FAST compose"
assert_eq "$(demo_field fast WORLD_FILE)" "packages-fast.txt" "fast world"
assert_eq "$(demo_field fast STATE_COMPRESSION)" "none" "fast: no /state compression"
assert_eq "$(demo_field fast STATE_SNAPSHOTS)" "0" "fast: no snapshots"
assert_eq "$(demo_field fast KERNEL_POLICY)" "none" "fast: no kernel policy"
assert_eq "$(ALPENGLOW_STATE_SNAPSHOTS=1 demo_field fast STATE_SNAPSHOTS)" "1" "fast opt-in snapshots"
assert_eq "$(demo_field minimal ALPENGLOW_SKU)" "potato" "minimal→potato"
assert_eq "$(demo_field minimal SESSION)" "none" "minimal session"
assert_eq "$(demo_field minimal WORLD_FILE)" "packages-potato.txt" "minimal world"
assert_eq "$(demo_field desktop ALPENGLOW_SKU)" "desktop" "desktop sku"
assert_eq "$(demo_field desktop WORLD_FILE)" "packages-runtime.txt" "desktop world"
assert_eq "$(demo_field internet SESSION)" "sold" "internet session"
assert_eq "$(demo_field standard ALPENGLOW_SKU)" "potato" "standard→potato"
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

assert_file system/backends/appliance/packages-potato.txt
assert_file system/backends/appliance/packages-fast.txt
assert_not_contains system/backends/appliance/packages-fast.txt '^(dropbear|chrony|dnsmasq|earlyoom|alpenglowed)$'
assert_file system/backends/appliance/packages-internet.txt
assert_contains system/backends/appliance/packages-potato.txt '^dropbear$'
assert_contains system/backends/appliance/packages-potato.txt '^chrony$'
assert_contains system/backends/appliance/packages-potato.txt '^dnsmasq$'
assert_contains system/backends/appliance/packages-potato.txt '^earlyoom$'
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
    KERNEL_POLICY="${KERNEL_POLICY}" STATE_SNAPSHOTS="${STATE_SNAPSHOTS}" \
    system/backends/appliance/scripts/configure-rootfs.sh "${root}" >/dev/null
}

run_sku potato
assert_contains "${tmp}/potato/etc/alpenglow/edition" '^potato$'
assert_contains "${tmp}/potato/etc/alpenglow/system.json" '"sku": "potato"'
assert_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = dropbear'
assert_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = chronyd'
assert_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = dnsmasq'
assert_not_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = alpenglowed'
assert_not_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = sold'
assert_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = alpenglow-zram'
assert_contains "${tmp}/potato/etc/alpenglow/kernel-policy.json" '"profile": "potato"'
assert_file "${tmp}/potato/etc/alpenglow/state-snapshots"

run_sku fast
assert_contains "${tmp}/fast/etc/alpenglow/system.json" '"sku": "fast"'
assert_not_contains "${tmp}/fast/etc/dinit.d/boot" 'depends-on = alpenglow-(kernel-policy|zram)'
[ ! -e "${tmp}/fast/etc/alpenglow/kernel-policy.json" ] || fail "fast ships a kernel policy"
[ ! -e "${tmp}/fast/etc/alpenglow/state-snapshots" ] || fail "fast enables /state snapshots"
assert_not_contains "${tmp}/fast/etc/dinit.d/boot" 'depends-on = alpenglowed'

run_sku minimal
assert_contains "${tmp}/minimal/etc/alpenglow/system.json" '"sku": "potato"'
assert_contains "${tmp}/minimal/etc/dinit.d/boot" 'depends-on = dropbear'
assert_not_contains "${tmp}/minimal/etc/dinit.d/boot" 'depends-on = alpenglowed'

run_sku desktop
assert_contains "${tmp}/desktop/etc/alpenglow/role" '^desktop$'
assert_contains "${tmp}/desktop/etc/dinit.d/boot" 'depends-on = alpenglowed$'

run_sku internet
assert_contains "${tmp}/internet/etc/dinit.d/boot" 'depends-on = sold'
assert_contains "${tmp}/internet/etc/dinit.d/sold" '^depends-on = state-mount$'
assert_not_contains "${tmp}/internet/etc/alpenglow/world" '^alpenglowed$'

run_sku kiosk
assert_contains "${tmp}/kiosk/etc/dinit.d/boot" 'depends-on = cage'
assert_contains "${tmp}/kiosk/etc/dinit.d/cage" '^depends-on = state-mount$'
assert_file "${tmp}/kiosk/etc/alpenglow/session-lock.json"
assert_contains "${tmp}/kiosk/etc/alpenglow/role" '^internet$'

run_sku standard
assert_contains "${tmp}/standard/etc/alpenglow/edition" '^standard$'
assert_contains "${tmp}/standard/etc/alpenglow/system.json" '"sku": "potato"'
assert_contains "${tmp}/standard/etc/alpenglow/system.json" '"profile": "standard"'
assert_not_contains "${tmp}/standard/etc/dinit.d/boot" 'depends-on = alpenglowed'

sh scripts/export-container.sh "${tmp}/potato" "${tmp}/oci-out" >/dev/null
assert_file "${tmp}/oci-out/alpenglow-dev-potato-$(uname -m).tar"

printf 'ci-edition-roles: ok\n'
