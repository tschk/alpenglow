#!/bin/sh
set -eu

VERSION="${1:?release version required}"
SCOPE="${2:?asset scope required}"
ASSET_DIR="${3:?asset directory required}"
CHECKSUM_ROOT="${4:?checksum root required}"

case "${VERSION}" in
  v[0-9]*) ;;
  *) echo "invalid release version: ${VERSION}" >&2; exit 1 ;;
esac
case "${VERSION}" in
  *[!a-zA-Z0-9._-]*) echo "invalid release version: ${VERSION}" >&2; exit 1 ;;
esac

set --
add_image_assets() {
  base="alpenglow-${VERSION}-${1}-${2}"
  set -- "${base}.img.zst" "${base}.img.zst.sha256" \
    "${base}.iso" "${base}.iso.sha256"
  for asset do
    printf '%s\n' "${asset}"
  done
}

case "${SCOPE}" in
  complete)
    expected="$(for arch in x86_64 aarch64; do
      for edition in potato desktop internet; do
        add_image_assets "${edition}" "${arch}"
      done
    done
    printf '%s\n' "alpenglow-${VERSION}-potato-riscv64.tar.zst" \
      "alpenglow-${VERSION}-potato-riscv64.tar.zst.sha256")"
    ;;
  potato-x86_64|desktop-x86_64|internet-x86_64|potato-aarch64|desktop-aarch64|internet-aarch64)
    edition="${SCOPE%-*}"
    arch="${SCOPE#*-}"
    expected="$(add_image_assets "${edition}" "${arch}")"
    ;;
  potato-riscv64)
    expected="$(printf '%s\n' "alpenglow-${VERSION}-potato-riscv64.tar.zst" \
      "alpenglow-${VERSION}-potato-riscv64.tar.zst.sha256")"
    ;;
  *) echo "invalid asset scope: ${SCOPE}" >&2; exit 1 ;;
esac

test -d "${ASSET_DIR}" || { echo "missing asset directory: ${ASSET_DIR}" >&2; exit 1; }
expected_count=0
old_ifs="${IFS}"
IFS='
'
for asset in ${expected}; do
  test -f "${ASSET_DIR}/${asset}" && test ! -L "${ASSET_DIR}/${asset}" && test -s "${ASSET_DIR}/${asset}" || {
    echo "missing or empty asset: ${asset}" >&2
    exit 1
  }
  expected_count=$((expected_count + 1))
  case "${asset}" in
    *.sha256)
      payload="${asset%.sha256}"
      test "$(wc -l < "${ASSET_DIR}/${asset}" | tr -d ' ')" -eq 1 || {
        echo "invalid checksum lines: ${asset}" >&2
        exit 1
      }
      IFS=' ' read -r digest checksum_path < "${ASSET_DIR}/${asset}"
      test "${#digest}" -eq 64 && test "${checksum_path}" = "build/release/assets/${payload}" || {
        echo "invalid checksum entry: ${asset}" >&2
        exit 1
      }
      case "${digest}" in
        *[!0-9a-f]*) echo "invalid checksum digest: ${asset}" >&2; exit 1 ;;
      esac
      (cd "${CHECKSUM_ROOT}" && sha256sum -c "build/release/assets/${asset}")
      ;;
  esac
done
IFS="${old_ifs}"

actual_count="$(find "${ASSET_DIR}" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
test "${actual_count}" -eq "${expected_count}" || {
  echo "unexpected asset count: expected ${expected_count}, found ${actual_count}" >&2
  exit 1
}
echo "Verified ${expected_count} release files for ${SCOPE}."
