# Editions and roles

One OS. Three public SKUs. Source: [`editions.toml`](../editions.toml), [`scripts/edition-resolve.sh`](../scripts/edition-resolve.sh).

| SKU | Userspace | Kernel | Session | World |
|-----|-----------|--------|---------|-------|
| `potato` | minimal | fast | alpenglowed (`alpenglowed-lite`) | `packages-potato.txt` |
| `desktop` | desktop | desktop | alpenglowed | `packages-runtime.txt` |
| `internet` | minimal | minimal | sold | `packages-internet.txt` |

```sh
ALPENGLOW_EDITION=potato
ALPENGLOW_EDITION=desktop ALPENGLOW_FLEET=1
ALPENGLOW_EDITION=internet ALPENGLOW_KIOSK=1
ALPENGLOW_ARTIFACT=tar sh scripts/export-container.sh
sh scripts/edition-resolve.sh --list
```

`ALPENGLOW_SKU` is always `potato|desktop|internet`. Board (RK3566) is a kernel fragment, not a SKU. Container is a potato artifact. Kiosk is internet + `ALPENGLOW_KIOSK=1` / `ALPENGLOW_SESSION=cage`. Fleet is `ALPENGLOW_FLEET=1` on desktop (no agent in tree).

Internal aliases (`fast`, `minimal`, `standard`, `embedded`, `potatoes`, `containers`, `desktop-full`, `workstation`, `kiosk`) resolve for CI. `standard` is potato + toolchain. Default SKU is `potato`.

Alpenglowed is a Cage Wayland client. potato: `cargo build --release --no-default-features`. desktop: `cargo build --release`. `--features compositor` is experimental and is not in the image. Contract: [alpenglowed#2](https://github.com/tschk/alpenglowed/pull/2).

Release names: `alpenglow-v0.1.<count>-{potato|desktop|internet}-<arch>.{iso,img.zst}` and `alpenglow-v0.1.<count>-potato-<arch>.tar`.
