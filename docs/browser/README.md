# Alpenglow browser demo

You are in a **serial console** inside **Alpenglow Linux 7.0.12 (i686)** in the browser. This is a taste of the userspace (Oil/wax, bash, docs) -- not the full **Alpenglowed** desktop (see `desktop.md`).

## The real product (from this repo + alpenglowed)

- **Immutable RAM root** (erofs/squashfs) + **bcachefs `/state`** for home and package metadata
- **dinit**, toybox, oksh, Oil, kernelctl, netd-zig -- see repo `AGENTS.md`
- **Desktop**: `BUILD_PROFILE=desktop` + **[Alpenglowed](https://github.com/tschk/alpenglowed)** -- Raycast-style GPUI bar, Smithay compositor feature, foot, PipeWire, iwd

## Shell here

Login shell is **bash** (colors: `TERM=xterm-256color`, `LS_COLORS`). Production minimal images use **oksh**.

## Try

```sh
fastfetch
wax info fastfetch
cat ideology.md
cat desktop.md
ls --color=auto
```

Paths are **case-sensitive** (`README.md` not `readme.md` -- `readme.md` is a symlink).

Docs also under `/usr/share/alpenglow/browser/`.