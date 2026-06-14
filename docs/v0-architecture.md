# Soliloquy v0 architecture

## Goal

Deliver a minimal browser-only immutable OS experience on Alpine Linux:

- fullscreen Servo browser surface
- wlroots kiosk compositor
- command bar-first UX
- constrained Rust system bridge
- optional terminal mode through `os://term`

## Boot flow

1. Alpine/OpenRC boots.
2. OpenRC starts `seatd`, `sold`, and network.
3. OpenRC starts `sol-session` (no login manager).
4. `sol-session` runs `cage` and starts Servo fullscreen.
5. Servo loads the local `ui/desktop` bundle as the primary UI.

The host root filesystem is read-only at runtime; writable state is limited to browser profile, cache, downloads, logs, and terminal/session data.

## Security boundary

- UI cannot access host filesystem directly.
- UI talks only to `sold` over localhost APIs.
- `sold` requires bearer token (`SOL_TOKEN`).
- API allowlist:
  - `/v1/status/battery`
  - `/v1/status/network`
  - `/v1/power/*`
  - `/v1/notify`
  - `/v1/term/session*`

## Command model

The command bar is the main UX surface:

- URL input -> navigate
- free text -> search
- `os://status` -> system status panel
- `os://power/<action>` -> controlled power command
- `os://term` -> PTY session (`zellij` preferred, backed by `sold`)
