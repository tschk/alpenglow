#!/bin/sh
# Source after setting ALPENGLOW_EDITION or ALPENGLOW_ROLE (optional). Exports
# BUILD_PROFILE, KERNEL_PROFILE, FAST, GRAPHICAL, BUILD_SERVICES,
# ALPENGLOW_AUTOLOGIN, ALPENGLOW_DESKTOP_FULL, WORLD_FILE, SESSION,
# ALPENGLOW_ROLE, ALPENGLOWED_ROLE, ARTIFACT, LOCK_SESSION, SHELL_LOGIN,
# FLEET_AGENT.
# ALPENGLOW_SESSION=none|alpenglowed|sold|cage overrides the SKU session.
set -eu

if [ -z "${ROOT_DIR:-}" ]; then
  case "$0" in
    */edition-resolve.sh|edition-resolve.sh)
      ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
      ;;
    *)
      echo "edition-resolve.sh: set ROOT_DIR before sourcing" >&2
      exit 1
      ;;
  esac
fi
_EDITION_TOML="${ROOT_DIR}/editions.toml"

_want_demo=0
_want_list=0
for _arg in "$@"; do
  case "${_arg}" in
    --demo) _want_demo=1 ;;
    --list) _want_list=1 ;;
  esac
done

if [ "${_want_list}" = "1" ]; then
  awk '/^\[editions\./ {
    line = $0
    sub(/^\[editions\./, "", line)
    sub(/\]$/, "", line)
    print line
  }' "${_EDITION_TOML}"
  case "$0" in
    */edition-resolve.sh|edition-resolve.sh) exit 0 ;;
  esac
fi

_session_override="${ALPENGLOW_SESSION:-}"

if [ -n "${ALPENGLOW_EDITION:-}" ]; then
  EDITION="${ALPENGLOW_EDITION}"
elif [ -n "${ALPENGLOW_SKU:-}" ]; then
  EDITION="${ALPENGLOW_SKU}"
elif [ -n "${ALPENGLOW_ROLE:-}" ]; then
  EDITION="${ALPENGLOW_ROLE}"
else
  EDITION="standard"
fi

_edition_kv() {
  awk -v want="${EDITION}" '
    BEGIN { n = 0 }
    /^\[editions\./ {
      line = $0
      sub(/^\[editions\./, "", line)
      sub(/\]$/, "", line)
      active = (line == want)
      next
    }
    active && /^[a-z_]+ = / {
      key = $1
      sub(/=$/, "", key)
      val = $3
      gsub(/^"/, "", val)
      gsub(/"$/, "", val)
      print key "=" val
      n++
    }
    END { if (n == 0) exit 1 }
  ' "${_EDITION_TOML}"
}

_lines="$(_edition_kv)" || {
  echo "unknown edition or role: ${EDITION}." >&2
  echo "see ${_EDITION_TOML} (scripts/edition-resolve.sh --list)" >&2
  exit 1
}

BUILD_PROFILE=""
KERNEL_PROFILE=""
FAST=""
GRAPHICAL=""
BUILD_SERVICES=""
ALPENGLOW_AUTOLOGIN=""
ALPENGLOW_DESKTOP_FULL=""
WORLD_FILE=""
SESSION=""
ROLE=""
ARTIFACT=""
LOCK_SESSION=""
SHELL_LOGIN=""
FLEET_AGENT=""
ALPENGLOWED_ROLE=""

IFS='
'
# shellcheck disable=SC2086
set -- ${_lines}
IFS=' '

while [ "$#" -gt 0 ]; do
  line="$1"
  shift
  key="${line%%=*}"
  val="${line#*=}"
  case "${key}" in
    build_profile) BUILD_PROFILE="${val}" ;;
    kernel_profile) KERNEL_PROFILE="${val}" ;;
    fast) FAST="${val}" ;;
    graphical) GRAPHICAL="${val}" ;;
    build_services) BUILD_SERVICES="${val}" ;;
    alpenglow_autologin) ALPENGLOW_AUTOLOGIN="${val}" ;;
    alpenglow_desktop_full) ALPENGLOW_DESKTOP_FULL="${val}" ;;
    world_file) WORLD_FILE="${val}" ;;
    session) SESSION="${val}" ;;
    role) ROLE="${val}" ;;
    artifact) ARTIFACT="${val}" ;;
    lock_session) LOCK_SESSION="${val}" ;;
    shell_login) SHELL_LOGIN="${val}" ;;
    fleet_agent) FLEET_AGENT="${val}" ;;
    alpenglowed_role) ALPENGLOWED_ROLE="${val}" ;;
  esac
done

[ -n "${SESSION}" ] || SESSION="none"
[ -n "${ROLE}" ] || ROLE="appliance"
[ -n "${ARTIFACT}" ] || ARTIFACT="image"
[ -n "${LOCK_SESSION}" ] || LOCK_SESSION="0"
[ -n "${SHELL_LOGIN}" ] || SHELL_LOGIN="1"
[ -n "${FLEET_AGENT}" ] || FLEET_AGENT="0"
[ -n "${ALPENGLOWED_ROLE}" ] || ALPENGLOWED_ROLE="none"

case "${_session_override}" in
  none|alpenglowed|sold|cage) SESSION="${_session_override}" ;;
esac

export ALPENGLOW_EDITION="${EDITION}"
export ALPENGLOW_SKU="${EDITION}"
export ALPENGLOW_ROLE="${ROLE}"
export BUILD_PROFILE KERNEL_PROFILE FAST GRAPHICAL BUILD_SERVICES
export ALPENGLOW_AUTOLOGIN ALPENGLOW_DESKTOP_FULL WORLD_FILE
export SESSION ALPENGLOWED_ROLE
export ARTIFACT LOCK_SESSION SHELL_LOGIN FLEET_AGENT

if [ "${_want_demo}" = "1" ]; then
  printf 'ALPENGLOW_EDITION=%s ALPENGLOW_ROLE=%s BUILD_PROFILE=%s KERNEL_PROFILE=%s FAST=%s GRAPHICAL=%s BUILD_SERVICES=%s ALPENGLOW_AUTOLOGIN=%s ALPENGLOW_DESKTOP_FULL=%s WORLD_FILE=%s SESSION=%s ALPENGLOWED_ROLE=%s ARTIFACT=%s LOCK_SESSION=%s SHELL_LOGIN=%s FLEET_AGENT=%s\n' \
    "${ALPENGLOW_EDITION}" "${ALPENGLOW_ROLE}" "${BUILD_PROFILE}" "${KERNEL_PROFILE}" "${FAST}" "${GRAPHICAL}" \
    "${BUILD_SERVICES}" "${ALPENGLOW_AUTOLOGIN}" "${ALPENGLOW_DESKTOP_FULL}" "${WORLD_FILE}" \
    "${SESSION}" "${ALPENGLOWED_ROLE}" "${ARTIFACT}" "${LOCK_SESSION}" "${SHELL_LOGIN}" "${FLEET_AGENT}"
fi
