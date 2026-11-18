#!/bin/sh
set -eu

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "${root}/scripts/lib/toybox-safety.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT INT TERM

cat > "${tmp}/toybox" <<'EOF'
#!/bin/sh
case "${TEST_APPLETS:-safe}" in
  safe) printf 'cat echo passwd-helper sh\n' ;;
  passwd|chsh|useradd|userdel|groupadd|groupdel) printf 'cat echo\n%s sh\n' "${TEST_APPLETS}" ;;
  broken) exit 1 ;;
esac
EOF
chmod +x "${tmp}/toybox"
TEST_APPLETS=safe check_toybox_safety "${tmp}/toybox"
for scenario in passwd chsh useradd userdel groupadd groupdel broken; do
  if TEST_APPLETS="${scenario}" check_toybox_safety "${tmp}/toybox" >"${tmp}/output" 2>&1; then
    echo "unsafe or uninspectable toybox accepted: ${scenario}" >&2
    exit 1
  fi
done
echo 'toybox account applets and uninspectable binaries are rejected'
