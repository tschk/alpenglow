#!/bin/sh
set -eu

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${REPO_ROOT}"
CARGO_CONFIG_BACKUP=""

fail() {
  printf 'ci-rust-core: %s\n' "$1" >&2
  exit 1
}

restore_cargo_config() {
  if [ -n "${CARGO_CONFIG_BACKUP}" ] && [ -f "${CARGO_CONFIG_BACKUP}" ]; then
    mv "${CARGO_CONFIG_BACKUP}" .cargo/config.toml
  fi
}

cargo_ci() {
  cargo "$@"
}

trap restore_cargo_config EXIT INT TERM

if [ -f .cargo/config.toml ]; then
  CARGO_CONFIG_BACKUP=".cargo/config.toml.ci-disabled"
  mv .cargo/config.toml "${CARGO_CONFIG_BACKUP}"
fi

metadata="$(cargo_ci metadata --no-deps --format-version 1)"

cargo_ci fmt --package sold -- --check
cargo_ci fmt --package alpenglow-netd -- --check
cargo_ci fmt --package glowfsctl -- --check
cargo_ci test -p sold
cargo_ci test -p alpenglow-kernelctl
cargo_ci test -p alpenglow-netd
cargo_ci test -p glowfsctl
cargo_ci test -p alpenglow-drivers

printf 'ci-rust-core: ok\n'
