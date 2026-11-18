#!/bin/sh

initramfs_detect_codec() {
  path="$1"
  [ -f "${path}" ] || return 1
  magic="$(od -An -tx1 -N4 "${path}" 2>/dev/null | tr -d ' \n')"
  case "${magic}" in
    1f8b*) printf '%s\n' gzip ;;
    28b52ffd) printf '%s\n' zstd ;;
    04224d18 | 02214c18) printf '%s\n' lz4 ;;
    *) printf '%s\n' unknown ;;
  esac
}

initramfs_expected_basename() {
  codec="$1"
  case "${codec}" in
    gzip) printf '%s\n' initramfs.cpio.gz ;;
    zstd) printf '%s\n' initramfs.cpio.zst ;;
    lz4) printf '%s\n' initramfs.cpio.lz4 ;;
    *) return 1 ;;
  esac
}

initramfs_assert_codec_identity() {
  path="$1"
  codec="$(initramfs_detect_codec "${path}")" || return 1
  expected="$(initramfs_expected_basename "${codec}")" || {
    printf 'initramfs-codec-identity: unknown codec for %s\n' "${path}" >&2
    return 1
  }
  base="$(basename -- "${path}")"
  [ "${base}" = "${expected}" ] || {
    printf 'initramfs-codec-identity: %s is %s but named %s (want %s)\n' \
      "${path}" "${codec}" "${base}" "${expected}" >&2
    return 1
  }
}

initramfs_pack() (
  root="$1"
  destination="$2"
  destination="$(CDPATH='' cd -- "$(dirname -- "${destination}")" && pwd)/$(basename -- "${destination}")" || exit 1
  work="$(mktemp -d "$(dirname -- "${destination}")/.initramfs.XXXXXX")" || exit 1
  trap 'rm -rf "${work}"' EXIT INT TERM
  cd "${root}" || exit 1
  find . -print > "${work}/files" || exit 1
  cpio -o -H newc < "${work}/files" > "${work}/archive" || exit 1
  case "${destination}" in
    *.zst) zstd -6 -T0 < "${work}/archive" > "${work}/compressed" || exit 1 ;;
    *.lz4) lz4 -l -9 -c < "${work}/archive" > "${work}/compressed" || exit 1 ;;
    *) printf 'unsupported initramfs destination: %s\n' "${destination}" >&2; exit 1 ;;
  esac
  mv "${work}/compressed" "${destination}"
)
