#!/bin/sh
# CI: validate Zig code compiles and passes tests
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"

fail() { printf 'ci-zig: %s\n' "$1" >&2; exit 1; }

if ! command -v zig >/dev/null 2>&1; then
  echo "ci-zig: zig not installed, skipping"
  exit 0
fi

ZIG_VERSION="$(zig version 2>&1)"
echo "ci-zig: zig ${ZIG_VERSION}"
case "${ZIG_VERSION}" in
  0.1[5-9].*|0.[2-9][0-9].*) ;;
  *) fail "zig >= 0.15 required (got ${ZIG_VERSION})" ;;
esac

# standardOptimizeOption exposes -Drelease=true in Zig 0.14+.
RELEASE_FLAG="-Drelease=true"
echo "ci-zig: using ${RELEASE_FLAG}"

# Build alpenglow-ctl (multicall kernel/net/pressure/zram daemons)
echo "ci-zig: building alpenglow-ctl..."
(cd "${REPO_ROOT}/system/alpenglow-ctl" && zig build ${RELEASE_FLAG} -Dtarget=x86_64-linux-musl) 2>&1
echo "ci-zig: alpenglow-ctl built OK"

echo "ci-zig: running alpenglow-ctl tests..."
(cd "${REPO_ROOT}/system/alpenglow-ctl" && zig build test ${RELEASE_FLAG}) 2>&1
echo "ci-zig: alpenglow-ctl tests OK"

printf 'ci-zig: ok\n'
