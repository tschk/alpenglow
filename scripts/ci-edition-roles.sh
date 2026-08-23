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
unset SESSION ALPENGLOW_SESSION ALPENGLOW_SKU ALPENGLOW_EDITION ALPENGLOW_ROLE ARTIFACT LOCK_SESSION SHELL_LOGIN FLEET_AGENT WORLD_FILE

list="$(sh scripts/edition-resolve.sh --list)"
for sku in fast minimal standard desktop desktop-full embedded potatoes containers internet kiosk workstation; do
  printf '%s\n' "${list}" | grep -qx "${sku}" || fail "edition-resolve --list missing ${sku}"
done

resolve() {
  sku="$1"
  ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION="${sku}"
  export ROOT_DIR ALPENGLOW_EDITION
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/scripts/edition-resolve.sh"
}

demo_field() {
  sku="$1"
  field="$2"
  ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION="${sku}" sh scripts/edition-resolve.sh --demo \
    | tr ' ' '\n' | sed -n "s/^${field}=//p"
}

assert_eq "$(demo_field embedded WORLD_FILE)" "packages-embedded.txt" "embedded world"
assert_eq "$(demo_field embedded SESSION)" "none" "embedded session"
assert_eq "$(demo_field embedded ALPENGLOW_ROLE)" "embedded" "embedded role"
assert_eq "$(demo_field internet SESSION)" "sold" "internet session"
assert_eq "$(demo_field internet WORLD_FILE)" "packages-internet.txt" "internet world"
assert_eq "$(demo_field kiosk SESSION)" "cage" "kiosk session"
assert_eq "$(demo_field kiosk LOCK_SESSION)" "1" "kiosk lock"
assert_eq "$(demo_field kiosk SHELL_LOGIN)" "0" "kiosk shell"
assert_eq "$(demo_field containers ARTIFACT)" "userspace" "containers artifact"
assert_eq "$(demo_field workstation FLEET_AGENT)" "1" "workstation fleet"
assert_eq "$(demo_field desktop WORLD_FILE)" "packages-desktop-lite.txt" "desktop world"
assert_eq "$(demo_field desktop-full WORLD_FILE)" "packages-runtime.txt" "desktop-full world"
assert_eq "$(demo_field potatoes KERNEL_PROFILE)" "fast" "potatoes kernel"

assert_eq "$(ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=embedded sh scripts/edition-resolve.sh --demo >/dev/null; ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=internet sh scripts/edition-resolve.sh --demo | tr ' ' '\n' | sed -n 's/^SESSION=//p')" \
  "sold" "later ALPENGLOW_EDITION wins over leftover SKU"
assert_eq "$(ROOT_DIR="${REPO_ROOT}" ALPENGLOW_ROLE=kiosk sh scripts/edition-resolve.sh --demo | tr ' ' '\n' | sed -n 's/^ALPENGLOW_EDITION=//p')" \
  "kiosk" "ALPENGLOW_ROLE selects SKU"
assert_eq "$(ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=minimal ALPENGLOW_SESSION=sold sh scripts/edition-resolve.sh --demo | tr ' ' '\n' | sed -n 's/^SESSION=//p')" \
  "sold" "session override"

if ROOT_DIR="${REPO_ROOT}" ALPENGLOW_EDITION=not-a-sku sh scripts/edition-resolve.sh --demo >/dev/null 2>"${tmp}/unknown.err"; then
  fail "unknown edition should fail"
fi
grep -q 'unknown edition or role' "${tmp}/unknown.err" || fail "unknown edition error text"

assert_file system/backends/appliance/packages-embedded.txt
assert_file system/backends/appliance/packages-potatoes.txt
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
  unset SESSION ALPENGLOW_SESSION ALPENGLOW_ROLE ALPENGLOW_SKU ARTIFACT LOCK_SESSION SHELL_LOGIN FLEET_AGENT WORLD_FILE
  ROOT_DIR="${REPO_ROOT}"
  ALPENGLOW_EDITION="${sku}"
  export ROOT_DIR ALPENGLOW_EDITION
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/scripts/edition-resolve.sh"
  BUILD_PROFILE="${BUILD_PROFILE}" \
    WORLD_FILE="${WORLD_FILE}" \
    SESSION="${SESSION}" \
    ALPENGLOW_ROLE="${ALPENGLOW_ROLE}" \
    ARTIFACT="${ARTIFACT}" \
    LOCK_SESSION="${LOCK_SESSION}" \
    SHELL_LOGIN="${SHELL_LOGIN}" \
    FLEET_AGENT="${FLEET_AGENT}" \
    ALPENGLOW_DESKTOP_FULL="${ALPENGLOW_DESKTOP_FULL}" \
    ALPENGLOW_EDITION="${ALPENGLOW_EDITION}" \
    system/backends/appliance/scripts/configure-rootfs.sh "${root}" >/dev/null
}

run_sku embedded
assert_contains "${tmp}/embedded/etc/alpenglow/world" '^eudev$'
assert_not_contains "${tmp}/embedded/etc/alpenglow/world" '^dropbear$'
assert_not_contains "${tmp}/embedded/etc/dinit.d/boot" 'depends-on = dropbear'
assert_contains "${tmp}/embedded/etc/alpenglow/role.json" '"role": "embedded"'
assert_file "${tmp}/embedded/etc/alpenglow/update-policy.json"

run_sku internet
assert_contains "${tmp}/internet/etc/dinit.d/boot" 'depends-on = sold'
assert_contains "${tmp}/internet/etc/dinit.d/boot" 'depends-on = dropbear'
assert_contains "${tmp}/internet/etc/alpenglow/system.json" '"compositor":"sold"'
assert_not_contains "${tmp}/internet/etc/alpenglow/world" '^alpenglowed$'
assert_file "${tmp}/internet/usr/local/bin/sold-session-start"
assert_file "${tmp}/internet/usr/share/defaults/soliloquy/README"

run_sku kiosk
assert_contains "${tmp}/kiosk/etc/dinit.d/boot" 'depends-on = cage'
assert_contains "${tmp}/kiosk/etc/alpenglow/system.json" '"compositor":"cage"'
assert_file "${tmp}/kiosk/etc/alpenglow/session-lock.json"
assert_file "${tmp}/kiosk/etc/alpenglow/kiosk-command"
assert_not_contains "${tmp}/kiosk/etc/alpenglow/world" '^alpenglowed$'
assert_contains "${tmp}/kiosk/etc/alpenglow/world" '^dropbear$'

run_sku potatoes
assert_contains "${tmp}/potatoes/etc/alpenglow/world" '^cage$'
assert_not_contains "${tmp}/potatoes/etc/dinit.d/boot" 'depends-on = cage'
assert_contains "${tmp}/potatoes/etc/alpenglow/world" '^dropbear$'

run_sku containers
assert_not_contains "${tmp}/containers/etc/alpenglow/world" '^linux-hardened$'
assert_not_contains "${tmp}/containers/etc/dinit.d/boot" 'depends-on = state-mount'
assert_contains "${tmp}/containers/etc/alpenglow/role.json" '"artifact": "userspace"'

run_sku workstation
assert_contains "${tmp}/workstation/etc/dinit.d/boot" 'depends-on = alpenglow-fleet-agent'
assert_contains "${tmp}/workstation/etc/alpenglow/world" '^alpenglowed$'
assert_file "${tmp}/workstation/etc/alpenglow/fleet-agent.json"

run_sku desktop
assert_contains "${tmp}/desktop/etc/alpenglow/world" '^dropbear$'
assert_contains "${tmp}/desktop/etc/dinit.d/boot" 'depends-on = dropbear'
assert_contains "${tmp}/desktop/etc/alpenglow/world" '^alpenglowed$'

sh scripts/export-container.sh "${tmp}/containers" "${tmp}/oci-out" >/dev/null
assert_file "${tmp}/oci-out/alpenglow-dev-containers-$(uname -m).tar"
assert_file "${tmp}/oci-out/oci/index.json"
assert_file "${tmp}/oci-out/oci/oci-layout"
assert_contains "${tmp}/oci-out/oci/index.json" 'application/vnd.oci.image.manifest.v1[+ ]json'

printf 'ci-edition-roles: ok\n'
