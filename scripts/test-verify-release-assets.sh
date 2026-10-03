#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "${FIXTURE}"' EXIT HUP INT TERM
cd "${FIXTURE}"
mkdir -p build/release/assets

make_asset() {
  asset="alpenglow-v0.1.700-${1}-${2}.${3}"
  printf 'fixture for %s\n' "${asset}" > "build/release/assets/${asset}"
  sha256sum "build/release/assets/${asset}" > "build/release/assets/${asset}.sha256"
}

for arch in x86_64 aarch64; do
  for edition in potato desktop internet; do
    make_asset "${edition}" "${arch}" img.zst
    make_asset "${edition}" "${arch}" iso
  done
done
make_asset potato riscv64 tar.zst

verify() {
  sh "${ROOT_DIR}/scripts/verify-release-assets.sh" v0.1.700 "$1" build/release/assets .
}

verify complete >/dev/null
mkdir -p scope/build/release/assets
cp build/release/assets/alpenglow-v0.1.700-potato-x86_64.* scope/build/release/assets/
(cd scope && verify potato-x86_64 >/dev/null)
mkdir -p riscv64-src/build/release/assets
cp build/release/assets/alpenglow-v0.1.700-potato-riscv64.* riscv64-src/build/release/assets/
(cd riscv64-src && verify potato-riscv64 >/dev/null)

payload=build/release/assets/alpenglow-v0.1.700-potato-x86_64.iso
printf 'tampered\n' >> "${payload}"
if verify complete >/dev/null 2>&1; then
  echo 'corrupt payload passed verification' >&2
  exit 1
fi
sha256sum "${payload}" > "${payload}.sha256"

mv "${payload}.sha256" "${payload}.missing"
if verify complete >/dev/null 2>&1; then
  echo 'missing checksum passed verification' >&2
  exit 1
fi
mv "${payload}.missing" "${payload}.sha256"

printf 'unexpected\n' > build/release/assets/extra
if verify complete >/dev/null 2>&1; then
  echo 'unexpected asset passed verification' >&2
  exit 1
fi
rm build/release/assets/extra

printf '%s  %s\n' "$(sha256sum "${payload}" | cut -d ' ' -f 1)" /tmp/wrong-path > "${payload}.sha256"
if verify complete >/dev/null 2>&1; then
  echo 'redirected checksum passed verification' >&2
  exit 1
fi
sha256sum "${payload}" > "${payload}.sha256"

mkdir -p fake-bin remote-assets
cat > fake-bin/gh <<'EOF'
#!/bin/sh
set -eu
case "$1 $2" in
  'release view')
    case "$5" in
      isDraft) echo true ;;
      databaseId) echo 42 ;;
      *) exit 1 ;;
    esac
    ;;
  'release upload')
    cp "$4" "${FAKE_RELEASE_DIR}/"
    printf 'upload %s\n' "${4##*/}" >> "${FAKE_GH_LOG}"
    ;;
  'release download')
    test -f "${FAKE_RELEASE_DIR}/$5"
    cp "${FAKE_RELEASE_DIR}/$5" "$7/"
    ;;
  'api --paginate')
    asset_id=0
    for asset in "${FAKE_RELEASE_DIR}"/*; do
      test -f "${asset}" || continue
      asset_id=$((asset_id + 1))
      name="${asset##*/}"
      state=uploaded
      test ! -f "${FAKE_RELEASE_DIR}/.starter-${name}" || state=starter
      printf '%s\t%s\t%s\n' "${asset_id}" "${name}" "${state}"
    done
    ;;
  'api -X')
    test "$3" = DELETE
    asset_id=0
    for asset in "${FAKE_RELEASE_DIR}"/*; do
      test -f "${asset}" || continue
      asset_id=$((asset_id + 1))
      if test "${asset_id}" = "${4##*/}"; then
        rm "${asset}" "${FAKE_RELEASE_DIR}/.starter-${asset##*/}"
        printf 'delete %s\n' "${asset##*/}" >> "${FAKE_GH_LOG}"
        exit 0
      fi
    done
    exit 1
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x fake-bin/gh
export FAKE_RELEASE_DIR="${FIXTURE}/remote-assets"
export FAKE_GH_LOG="${FIXTURE}/gh.log"
export GITHUB_REPOSITORY=tschk/alpenglow
PATH="${FIXTURE}/fake-bin:${PATH}"
export PATH

upload() {
  sh "${ROOT_DIR}/scripts/upload-release-assets.sh" v0.1.700 potato-x86_64 \
    scope/build/release/assets scope
}
upload >/dev/null
test "$(wc -l < "${FAKE_GH_LOG}" | tr -d ' ')" -eq 4
upload >/dev/null
test "$(wc -l < "${FAKE_GH_LOG}" | tr -d ' ')" -eq 4
rm remote-assets/alpenglow-v0.1.700-potato-x86_64.iso
upload >/dev/null
test "$(wc -l < "${FAKE_GH_LOG}" | tr -d ' ')" -eq 5
printf 'remote changed\n' >> remote-assets/alpenglow-v0.1.700-potato-x86_64.iso
if upload >/dev/null 2>&1; then
  echo 'different existing release asset passed verification' >&2
  exit 1
fi
touch remote-assets/.starter-alpenglow-v0.1.700-potato-x86_64.iso
upload >/dev/null
test ! -e remote-assets/.starter-alpenglow-v0.1.700-potato-x86_64.iso
test "$(grep -c '^delete ' "${FAKE_GH_LOG}")" -eq 1
test "$(grep -c '^upload ' "${FAKE_GH_LOG}")" -eq 6

echo 'Release asset fixture checks passed.'
