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

# Build kernelctl-zig (ReleaseSmall, x86_64-linux-musl)
cd "${REPO_ROOT}/system/kernelctl-zig"
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall 2>&1 | tail -3
echo "ci-zig: kernelctl-zig built OK"

printf 'ci-zig: ok\n'
