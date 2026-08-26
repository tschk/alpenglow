#!/bin/sh
# Source after ALPENGLOW_EDITION or ALPENGLOW_ROLE.
# Public SKUs: potato, desktop, internet.
# ALPENGLOW_SESSION=none|alpenglowed|sold|cage overrides session only.
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
_want_list_all=0
for _arg in "$@"; do
  case "${_arg}" in
    --demo) _want_demo=1 ;;
    --list) _want_list=1 ;;
    --list-all) _want_list_all=1 ;;
  esac
done

if [ "${_want_list}" = "1" ]; then
  printf '%s\n' potato desktop internet
  case "$0" in
    */edition-resolve.sh|edition-resolve.sh) exit 0 ;;
  esac
fi
if [ "${_want_list_all}" = "1" ]; then
  printf '%s\n' potato desktop internet fast minimal standard embedded potatoes desktop-lite containers desktop-full workstation kiosk
  case "$0" in
    */edition-resolve.sh|edition-resolve.sh) exit 0 ;;
  esac
fi

_session_override="${ALPENGLOW_SESSION:-}"
_fleet_override="${ALPENGLOW_FLEET:-}"
_kiosk_override="${ALPENGLOW_KIOSK:-}"
_artifact_override="${ALPENGLOW_ARTIFACT:-}"

if [ -n "${ALPENGLOW_EDITION:-}" ]; then
  EDITION="${ALPENGLOW_EDITION}"
elif [ -n "${ALPENGLOW_SKU:-}" ]; then
  EDITION="${ALPENGLOW_SKU}"
elif [ -n "${ALPENGLOW_ROLE:-}" ]; then
  EDITION="${ALPENGLOW_ROLE}"
else
  EDITION="potato"
fi
_REQUESTED="${EDITION}"

case "${_REQUESTED}" in
  potato|potatoes|desktop-lite|fast|minimal|standard|embedded|containers) _PUBLIC_SKU=potato ;;
  desktop|desktop-full|workstation) _PUBLIC_SKU=desktop ;;
  internet|kiosk) _PUBLIC_SKU=internet ;;
  *)
    echo "unknown edition or role: ${_REQUESTED}." >&2
    echo "public SKUs: potato desktop internet" >&2
    exit 1
    ;;
esac

_lines="$(awk -v want="${_PUBLIC_SKU}" '
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
' "${_EDITION_TOML}")" || {
  echo "unknown edition or role: ${_REQUESTED}." >&2
  exit 1
}

BUILD_PROFILE="" KERNEL_PROFILE="" FAST="" GRAPHICAL="" BUILD_SERVICES=""
ALPENGLOW_AUTOLOGIN="" ALPENGLOW_DESKTOP_FULL="" WORLD_FILE="" SESSION=""
ROLE="" ARTIFACT="" LOCK_SESSION="" SHELL_LOGIN="" FLEET_AGENT="" ALPENGLOWED_ROLE=""

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

SESSION="${SESSION:-none}"
ARTIFACT="${ARTIFACT:-image}"
LOCK_SESSION="${LOCK_SESSION:-0}"
SHELL_LOGIN="${SHELL_LOGIN:-1}"
FLEET_AGENT="${FLEET_AGENT:-0}"
ALPENGLOWED_ROLE="${ALPENGLOWED_ROLE:-none}"
ROLE="${_PUBLIC_SKU}"

case "${_REQUESTED}" in
  standard)
    BUILD_PROFILE="standard"
    SESSION="none"
    ALPENGLOW_AUTOLOGIN="0"
    WORLD_FILE="packages-standard.txt"
    KERNEL_PROFILE="minimal"
    FAST="0"
    ALPENGLOWED_ROLE="none"
    ;;
  containers)
    ARTIFACT="userspace"
    SESSION="none"
    ALPENGLOW_AUTOLOGIN="0"
    ALPENGLOWED_ROLE="none"
    ;;
  embedded)
    SESSION="none"
    ALPENGLOW_AUTOLOGIN="0"
    ALPENGLOWED_ROLE="none"
    ;;
  workstation)
    FLEET_AGENT="1"
    ;;
  kiosk)
    SESSION="cage"
    LOCK_SESSION="1"
    SHELL_LOGIN="0"
    _kiosk_override="1"
    ;;
esac

case "${_session_override}" in
  none|alpenglowed|sold|cage) SESSION="${_session_override}" ;;
esac
[ "${_fleet_override}" = "1" ] && FLEET_AGENT="1"
if [ "${_kiosk_override}" = "1" ]; then
  LOCK_SESSION="1"
  SHELL_LOGIN="0"
  case "${_session_override}" in
    none|alpenglowed|sold|cage) ;;
    *) SESSION="cage" ;;
  esac
fi
case "${_artifact_override}" in
  oci|tar|userspace) ARTIFACT="userspace" ;;
esac

ALPENGLOW_FLEET="${FLEET_AGENT}"
if [ "${LOCK_SESSION}" = "1" ] || [ "${_kiosk_override}" = "1" ]; then
  ALPENGLOW_KIOSK="1"
else
  ALPENGLOW_KIOSK="0"
fi
case "${_artifact_override}" in
  oci|tar|userspace) ALPENGLOW_ARTIFACT="${_artifact_override}" ;;
  *)
    if [ "${ARTIFACT}" = "userspace" ]; then
      ALPENGLOW_ARTIFACT="userspace"
    else
      ALPENGLOW_ARTIFACT="image"
    fi
    ;;
esac

export ALPENGLOW_EDITION="${_REQUESTED}"
export ALPENGLOW_SKU="${_PUBLIC_SKU}"
export ALPENGLOW_ROLE="${ROLE}"
export BUILD_PROFILE KERNEL_PROFILE FAST GRAPHICAL BUILD_SERVICES
export ALPENGLOW_AUTOLOGIN ALPENGLOW_DESKTOP_FULL WORLD_FILE
export SESSION ALPENGLOWED_ROLE
export ARTIFACT LOCK_SESSION SHELL_LOGIN FLEET_AGENT
export ALPENGLOW_FLEET ALPENGLOW_KIOSK ALPENGLOW_ARTIFACT

if [ "${_want_demo}" = "1" ]; then
  printf 'ALPENGLOW_EDITION=%s ALPENGLOW_SKU=%s ALPENGLOW_ROLE=%s BUILD_PROFILE=%s KERNEL_PROFILE=%s SESSION=%s ALPENGLOWED_ROLE=%s WORLD_FILE=%s ARTIFACT=%s LOCK_SESSION=%s ALPENGLOW_KIOSK=%s ALPENGLOW_FLEET=%s\n' \
    "${ALPENGLOW_EDITION}" "${ALPENGLOW_SKU}" "${ALPENGLOW_ROLE}" "${BUILD_PROFILE}" "${KERNEL_PROFILE}" \
    "${SESSION}" "${ALPENGLOWED_ROLE}" "${WORLD_FILE}" "${ARTIFACT}" "${LOCK_SESSION}" \
    "${ALPENGLOW_KIOSK}" "${ALPENGLOW_FLEET}"
fi
