# Editions and roles

One OS. Five public SKUs. Source: [`editions.toml`](../editions.toml), [`scripts/edition-resolve.sh`](../scripts/edition-resolve.sh).

| SKU | Userspace | Kernel | Session | World |
|-----|-----------|--------|---------|-------|
| `fast` | minimal | fast | none | `packages-minimal.txt` |
| `minimal` | minimal | minimal | none | `packages-minimal.txt` |
| `potato` | minimal | fast | alpenglowed (`alpenglowed-lite`) | `packages-potato.txt` |
| `desktop` | desktop | desktop | alpenglowed | `packages-runtime.txt` |
| `internet` | minimal | minimal | sold | `packages-internet.txt` |

```sh
ALPENGLOW_EDITION=fast
ALPENGLOW_EDITION=minimal
ALPENGLOW_EDITION=potato
ALPENGLOW_EDITION=desktop ALPENGLOW_FLEET=1
ALPENGLOW_EDITION=internet ALPENGLOW_KIOSK=1
ALPENGLOW_ARTIFACT=tar sh scripts/export-container.sh
sh scripts/edition-resolve.sh --list
```

`ALPENGLOW_SKU` is always `fast|minimal|potato|desktop|internet`. Board (RK3566) is a kernel fragment, not a SKU.

Aliases and flags (not public SKUs):

- `standard` — `minimal` plus the toolchain world (`BUILD_PROFILE=standard`, `packages-standard.txt`)
- `kiosk` — `internet` plus lock (`ALPENGLOW_KIOSK=1` / `ALPENGLOW_SESSION=cage`)
- `fleet` — `ALPENGLOW_FLEET=1` on desktop (no agent in tree)
- `container` — potato artifact (`scripts/export-container.sh` / `ALPENGLOW_ARTIFACT=oci|tar`)
- `potatoes`, `desktop-lite`, `embedded`, `containers` — resolve to `potato`
- `desktop-full`, `workstation` — resolve to `desktop`

Default SKU is `potato`. `--list` prints all five public names.

Alpenglowed is a Cage Wayland client. potato: `cargo build --release --no-default-features`. desktop: `cargo build --release`. `--features compositor` is experimental and is not in the image. Contract: [alpenglowed#2](https://github.com/tschk/alpenglowed/pull/2).

Release names: `alpenglow-v0.1.n-{fast|minimal|potato|desktop|internet}-arch.{iso,img.zst}` and `alpenglow-v0.1.n-potato-arch.tar`. RISC-V boot bundle: `alpenglow-v0.1.n-fast-riscv64.tar.zst`.
