#!/bin/sh
# CI: edition/role resolver + configure-rootfs contract
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

fail() { printf 'ci-edition-roles: %s\n' "$1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1' ($3)"; }
assert_contains() { grep -Eq "${2}" "$1" || fail "${1} missing pattern: ${2}"; }
assert_not_contains() { ! grep -Eq "${2}" "$1" || fail "${1} unexpectedly matches ${2}"; }
assert_file() { [ -f "$1" ] || fail "missing: $1"; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM
unset SESSION ALPENGLOW_SESSION ALPENGLOW_SKU ALPENGLOW_EDITION ALPENGLOW_ROLE ALPENGLOWED_ROLE ARTIFACT LOCK_SESSION SHELL_LOGIN FLEET_AGENT WORLD_FILE ALPENGLOW_FLEET ALPENGLOW_KIOSK ALPENGLOW_ARTIFACT

list="$(sh scripts/edition-resolve.sh --list)"
for sku in potato desktop internet; do
  printf '%s\n' "${list}" | grep -qx "${sku}" || fail "edition-resolve --list missing ${sku}"
done
for gone in fast minimal standard desktop-full embedded potatoes containers kiosk workstation; do
  printf '%s\n' "${list}" | grep -qx "${gone}" && fail "edition-resolve --list leaked alias ${gone}"
done

list_all="$(sh scripts/edition-resolve.sh --list-all)"
for sku in potato desktop internet fast minimal standard embedded potatoes desktop-lite containers desktop-full workstation kiosk; do
  printf '%s\n' "${list_all}" | grep -qx "${sku}" || fail "edition-resolve --list-all missing ${sku}"
done

demo_field() {
  sku="$1"
  field="$2"
  shift 2
  ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION="${sku}" "$@" sh scripts/edition-resolve.sh --demo \
    | tr ' ' '\n' | sed -n "s/^${field}=//p"
}

assert_eq "$(demo_field potato ALPENGLOW_SKU)" "potato" "potato sku"
assert_eq "$(demo_field potato ALPENGLOW_ROLE)" "potato" "potato role"
assert_eq "$(demo_field potato KERNEL_PROFILE)" "fast" "potato kernel"
assert_eq "$(demo_field potato SESSION)" "alpenglowed" "potato session"
assert_eq "$(demo_field potato ALPENGLOWED_ROLE)" "potato" "potato alpenglowed role"
assert_eq "$(demo_field potato WORLD_FILE)" "packages-potato.txt" "potato world"
assert_eq "$(demo_field desktop ALPENGLOW_SKU)" "desktop" "desktop sku"
assert_eq "$(demo_field desktop WORLD_FILE)" "packages-runtime.txt" "desktop world"
assert_eq "$(demo_field desktop ALPENGLOWED_ROLE)" "desktop" "desktop alpenglowed role"
assert_eq "$(demo_field desktop ALPENGLOW_DESKTOP_FULL)" "1" "desktop full"
assert_eq "$(demo_field internet SESSION)" "sold" "internet session"
assert_eq "$(demo_field internet WORLD_FILE)" "packages-internet.txt" "internet world"
assert_eq "$(demo_field internet ALPENGLOW_SKU)" "internet" "internet sku"

assert_eq "$(demo_field fast ALPENGLOW_SKU)" "potato" "fast→potato"
assert_eq "$(demo_field fast SESSION)" "none" "fast session"
assert_eq "$(demo_field fast WORLD_FILE)" "packages-minimal.txt" "fast world"
assert_eq "$(demo_field minimal ALPENGLOW_SKU)" "potato" "minimal→potato"
assert_eq "$(demo_field minimal KERNEL_PROFILE)" "minimal" "minimal kernel"
assert_eq "$(demo_field standard ALPENGLOW_SKU)" "potato" "standard→potato"
assert_eq "$(demo_field standard BUILD_PROFILE)" "standard" "standard profile"
assert_eq "$(demo_field standard WORLD_FILE)" "packages-standard.txt" "standard world"
assert_eq "$(demo_field potatoes ALPENGLOW_SKU)" "potato" "potatoes spelling"
assert_eq "$(demo_field potatoes ALPENGLOWED_ROLE)" "potato" "potatoes role"
assert_eq "$(demo_field embedded ALPENGLOW_SKU)" "potato" "embedded→potato"
assert_eq "$(demo_field embedded WORLD_FILE)" "packages-embedded.txt" "embedded world"
assert_eq "$(demo_field embedded SESSION)" "none" "embedded session"
assert_eq "$(demo_field containers ALPENGLOW_SKU)" "potato" "containers→potato"
assert_eq "$(demo_field containers ARTIFACT)" "userspace" "containers artifact"
assert_eq "$(demo_field desktop-full ALPENGLOW_SKU)" "desktop" "desktop-full→desktop"
assert_eq "$(demo_field workstation ALPENGLOW_SKU)" "desktop" "workstation→desktop"
assert_eq "$(demo_field workstation FLEET_AGENT)" "1" "workstation fleet"
assert_eq "$(demo_field workstation ALPENGLOWED_ROLE)" "desktop" "workstation alpenglowed role"
assert_eq "$(demo_field kiosk ALPENGLOW_SKU)" "internet" "kiosk→internet"
assert_eq "$(demo_field kiosk SESSION)" "cage" "kiosk session"
assert_eq "$(demo_field kiosk LOCK_SESSION)" "1" "kiosk lock"
assert_eq "$(demo_field kiosk SHELL_LOGIN)" "0" "kiosk shell"
assert_eq "$(demo_field kiosk ALPENGLOWED_ROLE)" "internet" "kiosk alpenglowed role"
assert_eq "$(demo_field kiosk ALPENGLOW_KIOSK)" "1" "kiosk flag"
assert_eq "$(
  unset SESSION ALPENGLOW_SESSION ALPENGLOW_SKU ALPENGLOW_EDITION ALPENGLOW_ROLE ALPENGLOW_FLEET ALPENGLOW_KIOSK ALPENGLOW_ARTIFACT
  ROOT_DIR="${REPO_ROOT}"
  export ROOT_DIR
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/scripts/edition-resolve.sh"
  printf '%s\n' "${ALPENGLOW_SKU} ${ALPENGLOW_EDITION} ${BUILD_PROFILE}"
)" "potato standard standard" "default request is standard→potato"

assert_eq "$(ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=desktop ALPENGLOW_FLEET=1 sh scripts/edition-resolve.sh --demo | tr ' ' '\n' | sed -n 's/^FLEET_AGENT=//p')" \
  "1" "ALPENGLOW_FLEET on desktop"
assert_eq "$(ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=internet ALPENGLOW_KIOSK=1 sh scripts/edition-resolve.sh --demo | tr ' ' '\n' | sed -n 's/^SESSION=//p')" \
  "cage" "ALPENGLOW_KIOSK on internet"
assert_eq "$(ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=potato ALPENGLOW_ARTIFACT=tar sh scripts/edition-resolve.sh --demo | tr ' ' '\n' | sed -n 's/^ARTIFACT=//p')" \
  "userspace" "ALPENGLOW_ARTIFACT on potato"

assert_eq "$(
  unset SESSION ALPENGLOW_SESSION ALPENGLOW_SKU ALPENGLOW_EDITION ALPENGLOW_ROLE
  ROOT_DIR="${REPO_ROOT}"
  ALPENGLOW_EDITION=embedded
  export ROOT_DIR ALPENGLOW_EDITION
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/scripts/edition-resolve.sh"
  ALPENGLOW_EDITION=internet
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/scripts/edition-resolve.sh"
  printf '%s\n' "${SESSION}"
)" "sold" "later ALPENGLOW_EDITION wins over leftover SKU"
assert_eq "$(ROOT_DIR="${REPO_ROOT}" ALPENGLOW_ROLE=kiosk sh scripts/edition-resolve.sh --demo | tr ' ' '\n' | sed -n 's/^ALPENGLOW_SKU=//p')" \
  "internet" "ALPENGLOW_ROLE alias selects public SKU"
assert_eq "$(ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=minimal ALPENGLOW_SESSION=sold sh scripts/edition-resolve.sh --demo | tr ' ' '\n' | sed -n 's/^SESSION=//p')" \
  "sold" "session override"

if ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=not-a-sku sh scripts/edition-resolve.sh --demo >/dev/null 2>"${tmp}/unknown.err"; then
  fail "unknown edition should fail"
fi
grep -q 'unknown edition or role' "${tmp}/unknown.err" || fail "unknown edition error text"

assert_file system/backends/appliance/packages-embedded.txt
assert_file system/backends/appliance/packages-potato.txt
assert_file system/backends/appliance/packages-containers.txt
assert_file system/backends/appliance/packages-internet.txt
assert_file system/backends/appliance/packages-kiosk.txt
assert_not_contains system/backends/appliance/packages-embedded.txt '^dropbear$'
assert_not_contains system/backends/appliance/packages-embedded.txt '^linux-firmware$'
assert_not_contains system/backends/appliance/packages-containers.txt '^linux-hardened$'
assert_not_contains system/backends/appliance/packages-containers.txt '^eudev$'
assert_not_contains system/backends/appliance/packages-containers.txt '^alpenglow-initramfs$'
assert_contains system/backends/appliance/packages-desktop-lite.txt '^dropbear$'
assert_contains system/backends/appliance/packages-desktop-lite.txt '^chrony$'
assert_contains system/backends/appliance/packages-desktop-lite.txt '^dnsmasq$'
assert_contains system/backends/appliance/packages-desktop-lite.txt '^linux-firmware$'
assert_contains system/backends/appliance/packages-potato.txt '^dropbear$'
assert_not_contains system/backends/appliance/packages-kiosk.txt '^alpenglowed$'
assert_not_contains system/backends/appliance/packages-internet.txt '^alpenglowed$'
assert_not_contains system/backends/appliance/dinit/alpenglow-session 'depends-on = sold'
assert_file system/backends/appliance/dinit/sold
assert_file system/backends/appliance/dinit/cage
assert_file system/appliance/filesystems/update-policy.json
assert_contains system/appliance/filesystems/update-policy.json '"status": "scaffold"'

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
  BUILD_PROFILE="${BUILD_PROFILE}" \
    WORLD_FILE="${WORLD_FILE}" \
    SESSION="${SESSION}" \
    ALPENGLOW_ROLE="${ALPENGLOW_ROLE}" \
    ALPENGLOW_SKU="${ALPENGLOW_SKU}" \
    ARTIFACT="${ARTIFACT}" \
    LOCK_SESSION="${LOCK_SESSION}" \
    SHELL_LOGIN="${SHELL_LOGIN}" \
    FLEET_AGENT="${FLEET_AGENT}" \
    ALPENGLOW_FLEET="${ALPENGLOW_FLEET}" \
    ALPENGLOW_KIOSK="${ALPENGLOW_KIOSK}" \
    ALPENGLOWED_ROLE="${ALPENGLOWED_ROLE}" \
    ALPENGLOW_DESKTOP_FULL="${ALPENGLOW_DESKTOP_FULL}" \
    ALPENGLOW_EDITION="${ALPENGLOW_EDITION}" \
    system/backends/appliance/scripts/configure-rootfs.sh "${root}" >/dev/null
}

run_sku embedded
assert_contains "${tmp}/embedded/etc/alpenglow/world" '^eudev$'
assert_not_contains "${tmp}/embedded/etc/alpenglow/world" '^dropbear$'
assert_not_contains "${tmp}/embedded/etc/dinit.d/boot" 'depends-on = dropbear'
assert_contains "${tmp}/embedded/etc/alpenglow/role.json" '"sku": "potato"'
assert_contains "${tmp}/embedded/etc/alpenglow/sku" '^potato$'
assert_file "${tmp}/embedded/etc/alpenglow/update-policy.json"

run_sku internet
assert_contains "${tmp}/internet/etc/dinit.d/boot" 'depends-on = sold'
assert_contains "${tmp}/internet/etc/dinit.d/boot" 'depends-on = dropbear'
assert_contains "${tmp}/internet/etc/alpenglow/system.json" '"compositor":"sold"'
assert_not_contains "${tmp}/internet/etc/alpenglow/world" '^alpenglowed$'
assert_not_contains "${tmp}/internet/etc/dinit.d/boot" 'depends-on = alpenglowed'
assert_contains "${tmp}/internet/etc/alpenglow/role" '^internet$'
assert_contains "${tmp}/internet/etc/alpenglow/sku" '^internet$'
assert_file "${tmp}/internet/usr/local/bin/sold-session-start"
assert_file "${tmp}/internet/usr/share/defaults/soliloquy/README"

run_sku kiosk
assert_contains "${tmp}/kiosk/etc/dinit.d/boot" 'depends-on = cage'
assert_contains "${tmp}/kiosk/etc/alpenglow/system.json" '"compositor":"cage"'
assert_file "${tmp}/kiosk/etc/alpenglow/session-lock.json"
assert_file "${tmp}/kiosk/etc/alpenglow/kiosk-command"
assert_not_contains "${tmp}/kiosk/etc/alpenglow/world" '^alpenglowed$'
assert_not_contains "${tmp}/kiosk/etc/dinit.d/boot" 'depends-on = alpenglowed'
assert_contains "${tmp}/kiosk/etc/alpenglow/role" '^internet$'
assert_contains "${tmp}/kiosk/etc/alpenglow/sku" '^internet$'
assert_contains "${tmp}/kiosk/etc/alpenglow/role.json" '"kiosk": 1'
assert_contains "${tmp}/kiosk/etc/alpenglow/world" '^dropbear$'

run_sku potato
assert_contains "${tmp}/potato/etc/alpenglow/world" '^cage$'
assert_contains "${tmp}/potato/etc/alpenglow/world" '^alpenglowed$'
assert_not_contains "${tmp}/potato/etc/alpenglow/world" '^pipewire$'
assert_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = alpenglowed-lite'
assert_not_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = pipewire'
assert_not_contains "${tmp}/potato/etc/dinit.d/boot" 'depends-on = alpenglowed$'
assert_contains "${tmp}/potato/etc/alpenglow/role" '^potato$'
assert_contains "${tmp}/potato/etc/alpenglow/sku" '^potato$'
assert_contains "${tmp}/potato/etc/alpenglow/world" '^dropbear$'

run_sku containers
assert_not_contains "${tmp}/containers/etc/alpenglow/world" '^linux-hardened$'
assert_not_contains "${tmp}/containers/etc/dinit.d/boot" 'depends-on = state-mount'
assert_contains "${tmp}/containers/etc/alpenglow/role.json" '"artifact": "userspace"'
assert_contains "${tmp}/containers/etc/alpenglow/sku" '^potato$'

run_sku workstation
assert_contains "${tmp}/workstation/etc/dinit.d/boot" 'depends-on = alpenglow-fleet-agent'
assert_contains "${tmp}/workstation/etc/dinit.d/boot" 'depends-on = alpenglowed$'
assert_contains "${tmp}/workstation/etc/alpenglow/world" '^alpenglowed$'
assert_contains "${tmp}/workstation/etc/alpenglow/role" '^desktop$'
assert_contains "${tmp}/workstation/etc/alpenglow/sku" '^desktop$'
assert_file "${tmp}/workstation/etc/alpenglow/fleet-agent.json"

run_sku desktop
assert_contains "${tmp}/desktop/etc/alpenglow/world" '^dropbear$'
assert_contains "${tmp}/desktop/etc/dinit.d/boot" 'depends-on = dropbear'
assert_contains "${tmp}/desktop/etc/dinit.d/boot" 'depends-on = alpenglowed$'
assert_contains "${tmp}/desktop/etc/dinit.d/boot" 'depends-on = pipewire'
assert_contains "${tmp}/desktop/etc/alpenglow/world" '^alpenglowed$'
assert_contains "${tmp}/desktop/etc/alpenglow/role" '^desktop$'
assert_contains "${tmp}/desktop/etc/alpenglow/sku" '^desktop$'
assert_file "${tmp}/desktop/usr/local/bin/alpenglow-session-start"
assert_file "${tmp}/desktop/usr/local/bin/alpenglow-role-publish"

sh scripts/export-container.sh "${tmp}/containers" "${tmp}/oci-out" >/dev/null
assert_file "${tmp}/oci-out/alpenglow-dev-potato-$(uname -m).tar"
assert_file "${tmp}/oci-out/oci/index.json"
assert_file "${tmp}/oci-out/oci/oci-layout"
assert_contains "${tmp}/oci-out/oci/index.json" 'application/vnd.oci.image.manifest.v1[+ ]json'

printf 'ci-edition-roles: ok\n'
