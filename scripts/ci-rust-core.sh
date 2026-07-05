#!/bin/sh
# CI: validate Rust core packages compile and pass tests
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"
CARGO_CONFIG_BACKUP=""

fail() { printf 'ci-rust-core: %s\n' "$1" >&2; exit 1; }

run_cargo() {
  output="$(mktemp)"
  if "$@" >"${output}" 2>&1; then
    tail -5 "${output}"
    rm -f "${output}"
    return 0
  fi
  tail -20 "${output}" >&2
  rm -f "${output}"
  fail "$* failed"
}

restore_cargo_config() {
  if [ -n "${CARGO_CONFIG_BACKUP}" ] && [ -f "${CARGO_CONFIG_BACKUP}" ]; then
    mv "${CARGO_CONFIG_BACKUP}" .cargo/config.toml
  fi
}

trap restore_cargo_config EXIT INT TERM

if [ -f .cargo/config.toml ]; then
  CARGO_CONFIG_BACKUP=".cargo/config.toml.ci-disabled"
  mv .cargo/config.toml "${CARGO_CONFIG_BACKUP}"
fi

run_cargo cargo check --workspace
run_cargo cargo test -p alpenglow-netd
run_cargo cargo test -p oil
run_cargo cargo test -p oil --no-default-features --features system-apk

printf 'ci-rust-core: ok\n'
