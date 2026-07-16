#!/bin/sh
# Source after setting ALPENGLOW_EDITION (optional). Exports BUILD_PROFILE, KERNEL_PROFILE,
# FAST, GRAPHICAL, BUILD_SERVICES, ALPENGLOW_AUTOLOGIN, ALPENGLOW_DESKTOP_FULL, WORLD_FILE.
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
EDITION="${ALPENGLOW_EDITION:-standard}"

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
  echo "unknown edition: ${EDITION}. Use fast, minimal, standard, desktop, or desktop-full." >&2
  echo "see ${_EDITION_TOML}" >&2
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
  esac
done

export ALPENGLOW_EDITION="${EDITION}"
export BUILD_PROFILE KERNEL_PROFILE FAST GRAPHICAL BUILD_SERVICES
export ALPENGLOW_AUTOLOGIN ALPENGLOW_DESKTOP_FULL WORLD_FILE

if [ "${1:-}" = "--demo" ]; then
  printf 'ALPENGLOW_EDITION=%s BUILD_PROFILE=%s KERNEL_PROFILE=%s FAST=%s GRAPHICAL=%s BUILD_SERVICES=%s ALPENGLOW_AUTOLOGIN=%s ALPENGLOW_DESKTOP_FULL=%s WORLD_FILE=%s\n' \
    "${ALPENGLOW_EDITION}" "${BUILD_PROFILE}" "${KERNEL_PROFILE}" "${FAST}" "${GRAPHICAL}" \
    "${BUILD_SERVICES}" "${ALPENGLOW_AUTOLOGIN}" "${ALPENGLOW_DESKTOP_FULL}" "${WORLD_FILE}"
fi