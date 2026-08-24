#!/bin/sh
# Source after setting ALPENGLOW_EDITION or ALPENGLOW_ROLE (optional). Exports
# BUILD_PROFILE, KERNEL_PROFILE, FAST, GRAPHICAL, BUILD_SERVICES,
# ALPENGLOW_AUTOLOGIN, ALPENGLOW_DESKTOP_FULL, WORLD_FILE, SESSION,
# ALPENGLOW_SKU, ALPENGLOW_ROLE, ALPENGLOWED_ROLE, ARTIFACT, LOCK_SESSION,
# SHELL_LOGIN, FLEET_AGENT, ALPENGLOW_FLEET, ALPENGLOW_KIOSK, ALPENGLOW_ARTIFACT.
# ALPENGLOW_SESSION=none|alpenglowed|sold|cage overrides the SKU session.
# Public SKUs: potato, desktop, internet. Other names are internal aliases.
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

_PUBLIC_SKUS="potato
desktop
internet"

_ALIAS_SKUS="fast
minimal
standard
embedded
potatoes
desktop-lite
containers
desktop-full
workstation
kiosk"

if [ "${_want_list}" = "1" ]; then
  printf '%s\n' "${_PUBLIC_SKUS}"
  case "$0" in
    */edition-resolve.sh|edition-resolve.sh) exit 0 ;;
  esac
fi

if [ "${_want_list_all}" = "1" ]; then
  printf '%s\n' "${_PUBLIC_SKUS}"
  printf '%s\n' "${_ALIAS_SKUS}"
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
  EDITION="standard"
fi

_REQUESTED="${EDITION}"

_public_sku_for() {
  case "$1" in
    potato|potatoes|desktop-lite|fast|minimal|standard|embedded|containers) printf '%s\n' potato ;;
    desktop|desktop-full|workstation) printf '%s\n' desktop ;;
    internet|kiosk) printf '%s\n' internet ;;
    *) printf '%s\n' "" ;;
  esac
}

_PUBLIC_SKU="$(_public_sku_for "${_REQUESTED}")"
if [ -z "${_PUBLIC_SKU}" ]; then
  echo "unknown edition or role: ${_REQUESTED}." >&2
  echo "public SKUs: potato desktop internet (scripts/edition-resolve.sh --list)" >&2
  echo "internal aliases: scripts/edition-resolve.sh --list-all" >&2
  exit 1
fi

_edition_kv() {
  awk -v want="${_PUBLIC_SKU}" '
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
  echo "unknown edition or role: ${_REQUESTED}." >&2
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
[ -n "${ROLE}" ] || ROLE="${_PUBLIC_SKU}"
[ -n "${ARTIFACT}" ] || ARTIFACT="image"
[ -n "${LOCK_SESSION}" ] || LOCK_SESSION="0"
[ -n "${SHELL_LOGIN}" ] || SHELL_LOGIN="1"
[ -n "${FLEET_AGENT}" ] || FLEET_AGENT="0"
[ -n "${ALPENGLOWED_ROLE}" ] || ALPENGLOWED_ROLE="none"

case "${_REQUESTED}" in
  fast)
    SESSION="none"
    ALPENGLOW_AUTOLOGIN="0"
    WORLD_FILE="packages-minimal.txt"
    ALPENGLOWED_ROLE="none"
    ;;
  minimal)
    SESSION="none"
    ALPENGLOW_AUTOLOGIN="0"
    WORLD_FILE="packages-minimal.txt"
    KERNEL_PROFILE="minimal"
    FAST="0"
    ALPENGLOWED_ROLE="none"
    ;;
  standard)
    BUILD_PROFILE="standard"
    SESSION="none"
    ALPENGLOW_AUTOLOGIN="0"
    WORLD_FILE="packages-standard.txt"
    KERNEL_PROFILE="minimal"
    FAST="0"
    ALPENGLOWED_ROLE="none"
    ;;
  embedded)
    SESSION="none"
    ALPENGLOW_AUTOLOGIN="0"
    WORLD_FILE="packages-embedded.txt"
    ALPENGLOWED_ROLE="none"
    ;;
  containers)
    SESSION="none"
    ALPENGLOW_AUTOLOGIN="0"
    WORLD_FILE="packages-containers.txt"
    ARTIFACT="userspace"
    ALPENGLOWED_ROLE="none"
    ;;
  workstation)
    FLEET_AGENT="1"
    ;;
  kiosk)
    SESSION="cage"
    LOCK_SESSION="1"
    SHELL_LOGIN="0"
    WORLD_FILE="packages-kiosk.txt"
    ALPENGLOWED_ROLE="internet"
    _kiosk_override="1"
    ;;
esac

ROLE="${_PUBLIC_SKU}"

case "${_session_override}" in
  none|alpenglowed|sold|cage) SESSION="${_session_override}" ;;
esac

if [ "${_fleet_override}" = "1" ]; then
  FLEET_AGENT="1"
fi

if [ "${_kiosk_override}" = "1" ]; then
  LOCK_SESSION="1"
  SHELL_LOGIN="0"
  case "${_session_override}" in
    none|alpenglowed|sold|cage) ;;
    *) SESSION="cage" ;;
  esac
  case "${WORLD_FILE##*/}" in
    packages-internet.txt) WORLD_FILE="packages-kiosk.txt" ;;
  esac
  if [ "${_PUBLIC_SKU}" = "internet" ]; then
    ALPENGLOWED_ROLE="internet"
  fi
fi

case "${_artifact_override}" in
  oci|tar|userspace)
    ARTIFACT="userspace"
    case "${WORLD_FILE##*/}" in
      packages-potato.txt) WORLD_FILE="packages-containers.txt" ;;
    esac
    ;;
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
  printf 'ALPENGLOW_EDITION=%s ALPENGLOW_SKU=%s ALPENGLOW_ROLE=%s BUILD_PROFILE=%s KERNEL_PROFILE=%s FAST=%s GRAPHICAL=%s BUILD_SERVICES=%s ALPENGLOW_AUTOLOGIN=%s ALPENGLOW_DESKTOP_FULL=%s WORLD_FILE=%s SESSION=%s ALPENGLOWED_ROLE=%s ARTIFACT=%s LOCK_SESSION=%s SHELL_LOGIN=%s FLEET_AGENT=%s ALPENGLOW_FLEET=%s ALPENGLOW_KIOSK=%s ALPENGLOW_ARTIFACT=%s\n' \
    "${ALPENGLOW_EDITION}" "${ALPENGLOW_SKU}" "${ALPENGLOW_ROLE}" "${BUILD_PROFILE}" "${KERNEL_PROFILE}" "${FAST}" "${GRAPHICAL}" \
    "${BUILD_SERVICES}" "${ALPENGLOW_AUTOLOGIN}" "${ALPENGLOW_DESKTOP_FULL}" "${WORLD_FILE}" \
    "${SESSION}" "${ALPENGLOWED_ROLE}" "${ARTIFACT}" "${LOCK_SESSION}" "${SHELL_LOGIN}" "${FLEET_AGENT}" \
    "${ALPENGLOW_FLEET}" "${ALPENGLOW_KIOSK}" "${ALPENGLOW_ARTIFACT}"
fi
