#!/bin/sh
set -eu

VERSION="${1:?release version required}"
SCOPE="${2:?asset scope required}"
ASSET_DIR="${3:?asset directory required}"
CHECKSUM_ROOT="${4:?checksum root required}"

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
sh "${SCRIPT_DIR}/verify-release-assets.sh" "${VERSION}" "${SCOPE}" "${ASSET_DIR}" "${CHECKSUM_ROOT}"
test "$(gh release view "${VERSION}" --json isDraft --jq .isDraft)" = true || {
  echo "release is not a draft: ${VERSION}" >&2
  exit 1
}

remote_names="$(gh release view "${VERSION}" --json assets --jq '.assets[].name')"
download_dir="$(mktemp -d)"
trap 'rm -rf "${download_dir}"' EXIT HUP INT TERM
for local_asset in "${ASSET_DIR}"/*; do
  name="${local_asset##*/}"
  if printf '%s\n' "${remote_names}" | grep -Fxq -- "${name}"; then
    gh release download "${VERSION}" --pattern "${name}" --dir "${download_dir}"
    cmp -s "${local_asset}" "${download_dir}/${name}" || {
      echo "existing release asset differs: ${name}" >&2
      exit 1
    }
    rm "${download_dir}/${name}"
  else
    gh release upload "${VERSION}" "${local_asset}"
  fi
done
