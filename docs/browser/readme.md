# Alpenglow browser demo

Serial console in Alpenglow Linux 7.0.12 (i686). Not the full Alpenglowed desktop.

If you're reading this in vro, welcome! This is vro, my version of a terminal text editor. You can press Ctrl-E to access the command bar and Ctrl-Q to exit. In oksh, type `vro --help` to view more.

## Product

- Immutable RAM root + bcachefs `/state`
- dinit, toybox, oksh, Oil, kernelctl, netd-zig
- Desktop: `BUILD_PROFILE=desktop` + [Alpenglowed](https://github.com/tschk/alpenglowed)

## Shell

oksh (same shell as the production appliance). The browser initramfs does not ship bash.

## Boot banner colors

| Style | Meaning |
|-------|---------|
| **cyan bold** | `Alpenglow` title and version |
| dim gray | One-line product summary |
| **green** | Measured boot time (kernel uptime) and RAM footprint at login |
| dim rule | ASCII `--------` divider under the stats line |
| **yellow** | `docs:` and `try:` hints |

Production hardware targets (~2s boot, &lt;64 MiB idle) are in [benchmarks.md](benchmarks.md), not on the live banner.

## Try

```sh
fastfetch
wax info fastfetch
oil update
vro readme.md
cat ideology.md
ls --color=auto
```

Case-sensitive. Docs also under `/usr/share/alpenglow/browser/`.
