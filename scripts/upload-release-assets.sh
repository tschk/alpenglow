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
: "${GITHUB_REPOSITORY:?GitHub repository required}"
release_id="$(gh release view "${VERSION}" --json databaseId --jq .databaseId)"
case "${release_id}" in
  ''|*[!0-9]*) echo "invalid release ID: ${release_id}" >&2; exit 1 ;;
esac

remote_assets="$(gh api --paginate \
  "repos/${GITHUB_REPOSITORY}/releases/${release_id}/assets?per_page=100" \
  --jq '.[] | [.id,.name,.state] | @tsv')"
download_dir="$(mktemp -d)"
trap 'rm -rf "${download_dir}"' EXIT HUP INT TERM
for local_asset in "${ASSET_DIR}"/*; do
  name="${local_asset##*/}"
  match_id=""
  match_state=""
  old_ifs="${IFS}"
  IFS='
'
  for record in ${remote_assets}; do
    IFS="$(printf '\t')" read -r asset_id remote_name state <<EOF
${record}
EOF
    if [ "${remote_name}" = "${name}" ]; then
      test -z "${match_id}" || { echo "duplicate release asset: ${name}" >&2; exit 1; }
      match_id="${asset_id}"
      match_state="${state}"
    fi
  done
  IFS="${old_ifs}"
  case "${match_state}" in
    uploaded)
      gh release download "${VERSION}" --pattern "${name}" --dir "${download_dir}"
      cmp -s "${local_asset}" "${download_dir}/${name}" || {
        echo "existing release asset differs: ${name}" >&2
        exit 1
      }
      rm "${download_dir}/${name}"
      ;;
    starter)
      case "${match_id}" in
        ''|*[!0-9]*) echo "invalid release asset ID: ${match_id}" >&2; exit 1 ;;
      esac
      gh api -X DELETE "repos/${GITHUB_REPOSITORY}/releases/assets/${match_id}"
      gh release upload "${VERSION}" "${local_asset}"
      ;;
    '') gh release upload "${VERSION}" "${local_asset}" ;;
    *) echo "unexpected release asset state for ${name}: ${match_state}" >&2; exit 1 ;;
  esac
done
