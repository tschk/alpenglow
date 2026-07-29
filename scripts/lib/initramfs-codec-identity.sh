#!/bin/sh

initramfs_detect_codec() {
  path="$1"
  [ -f "${path}" ] || return 1
  magic="$(od -An -tx1 -N4 "${path}" 2>/dev/null | tr -d ' \n')"
  case "${magic}" in
    1f8b*) printf '%s\n' gzip ;;
    28b52ffd) printf '%s\n' zstd ;;
    04224d18) printf '%s\n' lz4 ;;
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

initramfs_resolve_release_artifact() {
  native_dir="$1"
  out_dir="$2"
  for name in initramfs.cpio.zst initramfs.cpio.lz4 initramfs.cpio.gz; do
    src="${native_dir}/${name}"
    if [ -f "${src}" ]; then
      dest="${out_dir}/${name}"
      cp "${src}" "${dest}"
      initramfs_assert_codec_identity "${dest}" || return 1
      printf '%s\n' "${dest}"
      return 0
    fi
  done
  return 1
}
