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
[ "${STATE_TEST_FAIL_CHOWN:-}" != "$2" ]
EOF
cat >"${tmp}/bin/chmod" <<'EOF'
#!/bin/sh
[ "${STATE_TEST_FAIL_CHMOD:-}" != "$2" ] || exit 1
exec /bin/chmod "$@"
EOF
cat >"${tmp}/bin/mount" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${STATE_TEST_MOUNT_LOG}"
[ "${STATE_TEST_FAIL_BIND:-}" != "$3" ]
EOF
cat >"${tmp}/bin/find" <<'EOF'
#!/bin/sh
case "$1" in
  */.alpenglow-state-migrations)
    marker_mode="$(stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1")"
    [ "${marker_mode}" = 700 ] && printf '%s\n' "$1"
    exit 0 ;;
esac
if [ "${STATE_TEST_LEGACY_DIR:-}" = "$1" ]; then
  printf '%s\n' "$1"
else
  exec /usr/bin/find "$@"
fi
EOF
chmod +x "${tmp}/bin/chown" "${tmp}/bin/chmod" "${tmp}/bin/mount" "${tmp}/bin/find"
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

# Custom existing directories and their permissions must not be reset.
stage="existing paths"
chmod 755 "${tmp}/state/var/lib/alpenglow/browser/profiles"
chmod 755 "${tmp}/state/var/lib/alpenglow/browser/cache" \
  "${tmp}/state/var/lib/alpenglow/browser/downloads"
mkdir "${tmp}/state/var/lib/alpenglow/browser/profiles/.alpenglow-state-migration-incomplete"
: >"${tmp}/state/var/lib/alpenglow/browser/cache/.alpenglow-state-migration-incomplete"
ln -s "${tmp}/state/home" "${tmp}/state/var/lib/alpenglow/browser/downloads/.alpenglow-state-migration-incomplete"
: >"${STATE_TEST_CHOWN_LOG}"
setup_state_paths "${tmp}/state" "${tmp}/target"
[ ! -s "${STATE_TEST_CHOWN_LOG}" ]
[ "$(stat -c %a "${tmp}/state/var/lib/alpenglow/browser/profiles" 2>/dev/null || stat -f %Lp "${tmp}/state/var/lib/alpenglow/browser/profiles")" = 755 ]
[ "$(stat -c %a "${tmp}/state/var/lib/alpenglow/browser/cache" 2>/dev/null || stat -f %Lp "${tmp}/state/var/lib/alpenglow/browser/cache")" = 755 ]
[ "$(stat -c %a "${tmp}/state/var/lib/alpenglow/browser/downloads" 2>/dev/null || stat -f %Lp "${tmp}/state/var/lib/alpenglow/browser/downloads")" = 755 ]

# Only the old root-owned default layout is migrated; contents are retained.
stage="legacy state upgrade"
legacy="${tmp}/state/var/lib/alpenglow/browser/profiles"
echo preserved >"${legacy}/user-data"
export STATE_TEST_LEGACY_DIR="${legacy}"
setup_state_paths "${tmp}/state" "${tmp}/target"
grep -Fq "770:770 ${legacy}" "${STATE_TEST_CHOWN_LOG}"
[ "$(stat -c %a "${legacy}" 2>/dev/null || stat -f %Lp "${legacy}")" = 700 ]
grep -Fq preserved "${legacy}/user-data"
unset STATE_TEST_LEGACY_DIR

# A failed ownership update must leave the path private and resume on retry.
stage="interrupted legacy upgrade"
chmod 755 "${legacy}"
export STATE_TEST_LEGACY_DIR="${legacy}"
export STATE_TEST_FAIL_CHOWN="${legacy}"
if setup_state_paths "${tmp}/state" "${tmp}/target" 2>"${tmp}/error"; then
  echo "failed legacy migration was accepted" >&2
  exit 1
fi
grep -Fq 'state directory permissions failed:' "${tmp}/error"
[ "$(stat -c %a "${legacy}" 2>/dev/null || stat -f %Lp "${legacy}")" = 700 ]
[ -d "${tmp}/state/.alpenglow-state-migrations/browser_profiles" ]
unset STATE_TEST_LEGACY_DIR STATE_TEST_FAIL_CHOWN
setup_state_paths "${tmp}/state" "${tmp}/target"
[ ! -e "${tmp}/state/.alpenglow-state-migrations/browser_profiles" ]
grep -Fq preserved "${legacy}/user-data"

stage="interrupted fresh path"
fresh="${tmp}/fresh-state"
mkdir "${fresh}"
export STATE_TEST_FAIL_CHMOD="${fresh}/var/lib/alpenglow/browser/profiles"
if setup_state_paths "${fresh}" "${tmp}/target" 2>"${tmp}/error"; then
  echo "failed fresh permissions were accepted" >&2
  exit 1
fi
grep -Fq 'state directory permissions failed:' "${tmp}/error"
[ "$(stat -c %a "${fresh}/var/lib/alpenglow/browser/profiles" 2>/dev/null || stat -f %Lp "${fresh}/var/lib/alpenglow/browser/profiles")" = 700 ]
[ -d "${fresh}/.alpenglow-state-migrations/browser_profiles" ]
unset STATE_TEST_FAIL_CHMOD
setup_state_paths "${fresh}" "${tmp}/target"
[ ! -e "${fresh}/.alpenglow-state-migrations/browser_profiles" ]

stage="untrusted migration markers"
chmod 755 "${fresh}/.alpenglow-state-migrations"
if setup_state_paths "${fresh}" "${tmp}/target" 2>"${tmp}/error"; then
  echo "public migration marker directory was accepted" >&2
  exit 1
fi
grep -Fq 'state migration marker directory is not root-owned and private:' "${tmp}/error"
chmod 700 "${fresh}/.alpenglow-state-migrations"
ln -s "${fresh}/home" "${fresh}/.alpenglow-state-migrations/browser_profiles"
if setup_state_paths "${fresh}" "${tmp}/target" 2>"${tmp}/error"; then
  echo "symlinked migration marker was accepted" >&2
  exit 1
fi
grep -Fq 'invalid state migration marker:' "${tmp}/error"
rm "${fresh}/.alpenglow-state-migrations/browser_profiles"

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
grep -Fq 'state directory is not a directory:' "${tmp}/error"

stage="symlinked directory"
mkdir -p "${tmp}/linked"
ln -s "${tmp}/state/home" "${tmp}/linked/home"
if setup_state_paths "${tmp}/linked" "${tmp}/target" 2>"${tmp}/error"; then
  echo "symlinked state directory was accepted" >&2
  exit 1
fi
grep -Fq 'state directory is a symlink:' "${tmp}/error"

echo 'test-mount-state-paths: ok'
