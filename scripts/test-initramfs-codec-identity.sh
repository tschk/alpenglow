#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"
fail() { printf 'test-initramfs-codec-identity: %s\n' "$1" >&2; exit 1; }

. "${REPO_ROOT}/scripts/lib/initramfs-codec-identity.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM
native="${tmp}/native"
release="${tmp}/release"
boot="${tmp}/boot"
mkdir -p "${native}" "${release}" "${boot}"

printf '\037\213\010\000' > "${native}/initramfs.cpio.gz.fixture"
printf '\050\265\057\375' > "${native}/initramfs.cpio.zst.fixture"
printf '\004\042\115\030' > "${native}/initramfs.cpio.lz4.fixture"
printf '\002\041\114\030' > "${native}/initramfs.cpio.lz4.legacy"

[ "$(initramfs_detect_codec "${native}/initramfs.cpio.gz.fixture")" = gzip ] || fail "gzip magic"
[ "$(initramfs_detect_codec "${native}/initramfs.cpio.zst.fixture")" = zstd ] || fail "zstd magic"
[ "$(initramfs_detect_codec "${native}/initramfs.cpio.lz4.fixture")" = lz4 ] || fail "lz4 magic"
[ "$(initramfs_detect_codec "${native}/initramfs.cpio.lz4.legacy")" = lz4 ] || fail "legacy lz4 magic (lz4 -l)"

cp "${native}/initramfs.cpio.zst.fixture" "${tmp}/initramfs.cpio.gz"
if initramfs_assert_codec_identity "${tmp}/initramfs.cpio.gz" 2>/dev/null; then
  fail "expected identity failure for zstd bytes under .gz name"
fi

cp "${native}/initramfs.cpio.zst.fixture" "${native}/initramfs.cpio.zst"
resolved="$(initramfs_resolve_release_artifact "${native}" "${release}")"
[ "${resolved}" = "${release}/initramfs.cpio.zst" ] || fail "resolve path: ${resolved}"
initramfs_assert_codec_identity "${resolved}" || fail "resolved zst identity"

legacy_native="${tmp}/legacy-native"
legacy_release="${tmp}/legacy-release"
mkdir -p "${legacy_native}" "${legacy_release}"
cp "${native}/initramfs.cpio.lz4.legacy" "${legacy_native}/initramfs.cpio.lz4"
legacy_resolved="$(initramfs_resolve_release_artifact "${legacy_native}" "${legacy_release}")"
[ "${legacy_resolved}" = "${legacy_release}/initramfs.cpio.lz4" ] || fail "legacy lz4 resolve path: ${legacy_resolved}"
initramfs_assert_codec_identity "${legacy_resolved}" || fail "legacy lz4 identity"
base="$(basename -- "${resolved}")"
cp "${resolved}" "${boot}/${base}"
initramfs_assert_codec_identity "${boot}/${base}" || fail "installed boot identity"
module_path="boot():/boot/${base}"
case "${module_path}" in
  *initramfs.cpio.zst) ;;
  *) fail "module_path must use final basename: ${module_path}" ;;
esac

br="${REPO_ROOT}/scripts/build-release.sh"
[ -f "${br}" ] || fail "missing build-release.sh"

if grep -Eq 'INITRAMFS="\$\{OUT_DIR\}/initramfs\.cpio\.gz"' "${br}" \
  && grep -Eq 'cp "\$\{native_initramfs\}" "\$\{INITRAMFS\}"' "${br}"; then
  fail "build-release copies native zst/lz4 onto fixed initramfs.cpio.gz path"
fi

if grep -Eq 'cp "\$\{INITRAMFS\}" "\$\{MNT_ROOT\}/boot/initramfs\.cpio\.gz"' "${br}"; then
  fail "build-release installs initramfs under hard-coded .gz name"
fi

if grep -Eq 'module_path: boot\(\):/boot/initramfs\.cpio\.gz' "${br}"; then
  fail "build-release hard-codes Limine module_path to initramfs.cpio.gz"
fi

grep -Eq 'initramfs_resolve_release_artifact|initramfs_assert_codec_identity' "${br}" \
  || fail "build-release must use initramfs codec identity helpers"

printf 'test-initramfs-codec-identity: ok\n'
