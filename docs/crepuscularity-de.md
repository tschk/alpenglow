# Alpenglow Desktop — Crepuscularity/GPUI-based Desktop Environment

## Vision

Replace the traditional Wayland compositor + separate terminal + separate panels
with a single GPU-accelerated desktop shell built on Crepuscularity and GPUI
(Zed's GPU-accelerated UI framework). Write UI in `.crepus` templates — the same
DSL that targets desktop, terminal, web, mobile, and embedded.

## Why Crepuscularity/GPUI instead of wlroots/velox/foot

| Aspect | wlroots-based (traditional) | Crepuscularity/GPUI |
|--------|-----------------------------|---------------------|
| Rendering | Compositor (wlroots) + EGL clients | Single GPU-accelerated process (blade-graphics) |
| UI code | Separate: waybar + fuzzel + mako + kanshi | One codebase: `.crepus` templates → all UI |
| Hot reload | No (restart compositor) | Yes (live template updates) |
| Cross-target | Linux Wayland only | Desktop, TUI, web, mobile, embedded |
| Binary size | ~15MB for stack (compositor + terminal + bar + launcher + notif) | ~8-12MB single static binary |
| Language | C (wlroots) + Rust (velox) + C (foot) + C++ (waybar) | Rust + Crepuscularity templates |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│               Alpenglow Desktop Shell                │
│  (GPUI application, one static Rust binary ~10MB)    │
│                                                      │
│  ┌─────────┐ ┌──────────┐ ┌────────┐ ┌───────────┐ │
│  │ Launcher │ │ Status   │ │ Lock   │ │ Settings  │ │
│  │ (app     │ │ Bar      │ │ Screen │ │ Panel     │ │
│  │  grid)   │ │ (time,   │ │        │ │ (network, │ │
│  │          │ │  net,    │ │        │ │  display, │ │
│  │          │ │  battery)│ │        │ │  power)   │ │
│  └─────────┘ └──────────┘ └────────┘ └───────────┘ │
│                                                      │
│  ┌──────────────────────────────────────────────────┐│
│  │  Window Manager (GPUI window tree)               ││
│  │  - Tiling or stacking of launched apps           ││
│  │  - Each app is a GPUI child window or element    ││
│  └──────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────┘
                      │
                      ▼  (Wayland protocol)
┌──────────────────────────────────────────────┐
│  cage (wlroots kiosk compositor)             │
│  or smithay-based minimal compositor         │
│  Manages: DRM/KMS, input devices, EGL/Vulkan │
│  Exposes: wayland-1 socket                   │
└──────────────────────────────────────────────┘
                      │
                      ▼
              Linux Kernel (DRM/KMS)
```

## Implementation Plan

### Phase A: Bootstrap (1 week)

Create a minimal GPUI app that runs inside cage:

```
alpenglow-desktop/
├── Cargo.toml
│   depends: crepuscularity-gpui, gpui (from vendor/)
├── src/
│   ├── main.rs          — Application::new(), open fullscreen window
│   ├── desktop.rs       — Desktop element: wallpaper + status bar
│   ├── bar.rs           — Status bar: clock, layout switcher
│   └── launcher.rs      — Simple app grid (reads PATH)
└── templates/
    └── desktop.crepus   — Default desktop layout
```

**MVP features:**
- Fullscreen window that covers the display
- Status bar with clock
- "Terminal" button → launches foot
- "Exit" button → returns to greetd/login

**Build:**
```bash
cd alpenglow-desktop
cargo build --release --target x86_64-unknown-linux-musl
# ~10MB static binary
```

### Phase B: Desktop Shell (2 weeks)

- Replace cage with a custom minimal Wayland compositor (using `smithay` crate)
- This compositor runs the GPUI app directly, no separate display server
- Or: extend the GPUI app to speak wayland server protocol (add DRM/KMS via smithay)
- Status bar: network indicator (via iwd DBus), battery, volume
- App launcher: grid of `.desktop` entries from `/opt/alpenglow/apps/`
- Window management: simple stacking within the GPUI window tree
- Hot reload: edit `.crepus` templates, see changes live

### Phase C: Full Experience (2 weeks)

- Settings panel: WiFi management (iwd CLI integration), display config, power options
- Lock screen: GPUI-based, replaces greetd
- Notifications: simple FIFO-based notification daemon (no DBus dependency)
- Multi-monitor: detect outputs via wlr-randr/kanshi
- Session persistence: remember open apps, restore on reboot
- Keyboard shortcuts: launcher search (Super+Space), terminal toggle, lock, screenshot

### Phase D: Integration (1 week)

- Replace cage entirely: the GPUI app becomes the Wayland compositor
- Use `smithay` as the compositor backend within the same binary
- Direct DRM/KMS access for full GPU performance
- Remove foot dependency: embed a terminal widget in GPUI (using `cosmic-text` + `alacritty_terminal`)
- Static musl build: one binary, ~12MB, all deps embedded
- dinit service: `alpenglow-desktop` replaces `cage` + `foot` + `greetd`
- Boot from init to desktop in under 3 seconds

## Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Compositor backend | `smithay` (pure Rust) | No C/wlroots dependency, easier to static link |
| GPU backend | `blade-graphics` (Vulkan) | Same backend GPUI uses, proven in Zed |
| Text rendering | `cosmic-text` | GPUI uses this already, no HarfBuzz/pango needed |
| Theme | Crepuscularity Tailwind classes | Consistent with all `.crepus` templates |
| IPC for services | Unix sockets + FIFO | Simpler than DBus; iwd via ell's DBus proxy if needed |
| IPC for apps | None (single process) | Everything is in one binary; no app IPC needed |

## Build Requirements

- Rust nightly (GPUI requires nightly features)
- `vendor/gpui` (patched in `.cargo/config.toml`)
- Vulkan loader + validation layers (for dev)
- macOS: Xcode + Metal SDK (for dev on Mac)
- Linux: libxkbcommon, fontconfig (for text rendering)
- Static build: musl target for x86_64-unknown-linux-musl

## Comparison with Traditional Desktop

```
Traditional stack:
init → elogind → seatd → greetd → velox → foot + waybar + fuzzel + mako
                                                              (~25MB total, 6 daemons)

Crepuscularity stack:
init → seatd → cage → alpenglow-desktop
                                                              (~12MB total, 3 processes)

Ultimate (Phase D):
init → seatd → alpenglow-desktop (compositor + shell + terminal)
                                                              (~12MB total, 2 processes)
```

## Status

- [ ] Phase A: Bootstrap — MVP GPUI desktop inside cage
- [ ] Phase B: Desktop Shell — replace cage with smithay compositor
- [ ] Phase C: Full Experience — settings, lock screen, notifications
- [ ] Phase D: Integration — single binary, terminal widget, direct DRM

See also: [build-out.md](../plans/build-out.md), [Crepuscularity docs](../crepuscularity/docs/),
[GPUI docs](https://gpui.rs)
