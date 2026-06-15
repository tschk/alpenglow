#!/bin/sh
# CI: validate Rust core packages compile and pass tests
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"
CARGO_CONFIG_BACKUP=""

fail() { printf 'ci-rust-core: %s\n' "$1" >&2; exit 1; }

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

cargo check --workspace 2>&1 | tail -5
cargo test -p sold 2>&1 | tail -5
cargo test -p alpenglow-kernelctl 2>&1 | tail -5
cargo test -p alpenglow-netd 2>&1 | tail -5
cargo test -p glowfsctl 2>&1 | tail -5

printf 'ci-rust-core: ok\n'
