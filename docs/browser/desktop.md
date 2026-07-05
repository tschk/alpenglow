# Desktop: Alpenglowed

## Not a traditional DE

Alpenglow desktop profile ships **Alpenglowed** -- a single fullscreen **GPUI** bar (Crepuscularity) over Wayland:

- Launcher + fuzzy app search from PATH
- Calculator, `> shell` commands, plugins (Rust / Crepus / web)
- Pills: clock, date, battery, CPU, Wi-Fi, weather
- Notifications daemon, clipboard history, file search (`/query`), emoji picker
- **Compositor**: `alpenglowed --compositor` with embedded **Smithay** (Wayland socket under `$XDG_RUNTIME_DIR/alpenglowed/`)

Read `../alpenglowed/README.md` for phases and architecture.

## Stack on the image

| Piece | Role |
|-------|------|
| greetd | Session |
| seatd | Seat permissions |
| foot | Terminal emulator |
| PipeWire + ALSA | Audio |
| iwd | Wi-Fi |
| Alpenglowed | Shell UI + compositor path |

All of that lives in the **immutable root image**. Sessions, dotfiles, and Oil state live on **`/state`**.

## Browser demo

No Wayland in v86 -- serial bash only. Desktop is documented so you know what production `BUILD_PROFILE=desktop` targets.