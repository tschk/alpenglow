#!/bin/sh
# Write public/version.txt for the static site (release link + v86 cache busting).
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${ALP_VERSION:-$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 2>/dev/null || printf 'v0.1.%s' "$(git -C "${ROOT_DIR}" rev-list --count HEAD 2>/dev/null || echo 0)")}"
case "${VERSION}" in
  v*) ;;
  *) VERSION="v${VERSION}" ;;
esac

mkdir -p "${ROOT_DIR}/public"
printf '%s\n' "${VERSION}" > "${ROOT_DIR}/site/public/version.txt"
echo "site version: ${VERSION}"
