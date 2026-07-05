# Alpenglow browser demo

Serial console in Alpenglow Linux 7.0.12 (i686). Not the full Alpenglowed desktop.

## Product

- Immutable RAM root + bcachefs `/state`
- dinit, toybox, oksh, Oil, kernelctl, netd-zig
- Desktop: `BUILD_PROFILE=desktop` + [Alpenglowed](https://github.com/tschk/alpenglowed)

## Shell

bash with colors. Production uses oksh.

## Try

```sh
fastfetch
wax info fastfetch
oil update
vro README.md
cat ideology.md
ls --color=auto
```

Case-sensitive. Docs also under `/usr/share/alpenglow/browser/`.
