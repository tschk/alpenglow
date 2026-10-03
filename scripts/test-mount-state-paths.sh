#!/bin/sh
# Exercise state setup without a block device or real mounts.
set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
helper="${repo_root}/system/backends/appliance/scripts/mount-state-paths.sh"
tmp="$(mktemp -d)"
stage="setup"
test_status=0
trap 'test_status=$?; if [ "${test_status}" -ne 0 ]; then echo "test-mount-state-paths: failed at ${stage}" >&2; fi; rm -rf "${tmp}"' EXIT INT TERM
mkdir -p "${tmp}/bin" "${tmp}/state" "${tmp}/target/home" \
  "${tmp}/target/var/lib/alpenglow" "${tmp}/target/var/cache/alpenglow" \
  "${tmp}/target/var/log/alpenglow"

cat >"${tmp}/bin/chown" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${STATE_TEST_CHOWN_LOG}"
EOF
cat >"${tmp}/bin/mount" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${STATE_TEST_MOUNT_LOG}"
[ "${STATE_TEST_FAIL_BIND:-}" != "$3" ]
EOF
chmod +x "${tmp}/bin/chown" "${tmp}/bin/mount"
export PATH="${tmp}/bin:${PATH}"
export STATE_TEST_CHOWN_LOG="${tmp}/chown.log"
export STATE_TEST_MOUNT_LOG="${tmp}/mount.log"

# shellcheck source=../system/backends/appliance/scripts/mount-state-paths.sh
. "${helper}"
stage="fresh paths"
setup_state_paths "${tmp}/state" "${tmp}/target"
[ "$(wc -l <"${STATE_TEST_MOUNT_LOG}" | tr -d ' ')" -eq 4 ]
grep -Fq "770:770 ${tmp}/state/var/lib/alpenglow/browser/profiles" "${STATE_TEST_CHOWN_LOG}"
[ "$(stat -c %a "${tmp}/state/var/lib/alpenglow/browser/profiles" 2>/dev/null || stat -f %Lp "${tmp}/state/var/lib/alpenglow/browser/profiles")" = 700 ]

# Existing directories and their permissions must not be reset on a later boot.
stage="existing paths"
chmod 755 "${tmp}/state/var/lib/alpenglow/browser/profiles"
: >"${STATE_TEST_CHOWN_LOG}"
setup_state_paths "${tmp}/state" "${tmp}/target"
[ ! -s "${STATE_TEST_CHOWN_LOG}" ]
[ "$(stat -c %a "${tmp}/state/var/lib/alpenglow/browser/profiles" 2>/dev/null || stat -f %Lp "${tmp}/state/var/lib/alpenglow/browser/profiles")" = 755 ]

stage="failed bind"
STATE_TEST_FAIL_BIND="${tmp}/target/var/cache/alpenglow"
export STATE_TEST_FAIL_BIND
if setup_state_paths "${tmp}/state" "${tmp}/target" 2>"${tmp}/error"; then
  echo "failed bind was accepted" >&2
  exit 1
fi
grep -Fq 'state bind mount failed:' "${tmp}/error"
unset STATE_TEST_FAIL_BIND

stage="failed directory creation"
mkdir -p "${tmp}/blocked"
: >"${tmp}/blocked/home"
if setup_state_paths "${tmp}/blocked" "${tmp}/target" 2>"${tmp}/error"; then
  echo "failed directory creation was accepted" >&2
  exit 1
fi
grep -Fq 'state directory creation failed:' "${tmp}/error"

stage="symlinked directory"
mkdir -p "${tmp}/linked"
ln -s "${tmp}/state/home" "${tmp}/linked/home"
if setup_state_paths "${tmp}/linked" "${tmp}/target" 2>"${tmp}/error"; then
  echo "symlinked state directory was accepted" >&2
  exit 1
fi
grep -Fq 'state directory is a symlink:' "${tmp}/error"

echo 'test-mount-state-paths: ok'
