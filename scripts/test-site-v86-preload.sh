#!/bin/sh
# Guard against preloading a URL that the runtime intentionally versions.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PAGE="$ROOT_DIR/site/src/document.ts"
SHELL="$ROOT_DIR/site/src/shell.js"

if grep -Fq 'href="/v86/v86.wasm"' "$PAGE" && grep -Fq 'asset("/v86/v86.wasm")' "$SHELL"; then
  printf '%s\n' 'index preloads an unversioned v86 Wasm URL while runtime requests a versioned URL' >&2
  exit 1
fi
