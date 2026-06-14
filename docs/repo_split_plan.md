# Repo Split Plan

## Target repos

- `atechnology-company/soliloquy` — appliance runtime, Alpine packaging, `sold`, and product policy
- `atechnology-company/rv8` — canonical browser engine (multi-process IPC, Servo embed, V8, storage)

Archived (do not use for new work): `atechnology-company/rover`, `atechnology-company/rover-desktop`.

A different macOS launcher may also use the folder name `rover` (for example `semitechnological/rover`). That launcher is unrelated to RV8.

## Current incremental state

- `../rv8` is the canonical standalone local Git repository for browser-engine work.
- Soliloquy no longer carries an active in-repo RV8 crate as a workspace member.
- The sibling `../rv8` manifest points back to `../soliloquy/src` for the shared optimization crate while that library remains in Soliloquy.

## Next migration steps

1. Keep Soliloquy checks pointed at `../rv8` for browser-engine validation.
2. Keep local tooling free of stale in-repo RV8 source references.
3. Move RV8-only Servo/V8 bridge code behind the `rv8` API boundary.
4. Keep Soliloquy-specific appliance, `sold`, and Alpine UI code in this repo.
