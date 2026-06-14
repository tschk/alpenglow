# RV8 Linkage Roadmap

This document tracks the remaining work to move Soliloquy from the current hybrid `mozjs` / `v8-experimental` state to a real Servo + V8 runtime linkage.

## Current State

- Servo has an in-tree backend selection seam controlled by `SOLILOQUY_JS_ENGINE`.
- `v8-experimental` is real as a mode selection, but Servo script still boots through `mozjs`.
- `servoshell` is already patched in-tree and connected to Soliloquy optimization hooks.
- Phase 1 of the bridge extraction has started: live DOM snapshot storage and typed bridge operations now live in `third_party/servo/components/servo/soliloquy_bridge.rs`.
- `WebView::evaluate_javascript()` has a Soliloquy dispatcher for:
  - general ECMAScript evaluation through `rusty_v8` when `soliloquy_v8` is enabled
  - persistent V8 contexts keyed per WebView for embedder-driven evaluation state
  - structured command calls through `window.__soliloquyEval(...)`
  - live snapshot-backed reads for `document.title`, `location.href`, and `document.readyState`
  - snapshot-backed writes for `document.title` and absolute / relative `location.href`
  - stable command result envelopes for ok, error, and unsupported outcomes
- The `v8-experimental` dispatch backend now owns an explicit V8 isolate owner so the status surface can distinguish dispatch-only builds from real `rusty_v8` builds.
- Servo now publishes the bridge command schema from `soliloquy_bridge_schema.json`; the shell-side V8 mock includes the same file when reporting bridge capabilities.
- Servo now has an opt-in `soliloquy_v8` feature that wires the V8 owner to `rusty_v8` platform, thread-local isolate initialization, and per-WebView V8 contexts while leaving the default dispatch-only path unchanged.
- The shell-side V8 mock now understands the same typed bridge command surface and keeps a small DOM snapshot in sync with shell navigations.
- The local Servo `rv8` branch has been merged forward to upstream Servo `main` at `3949e2f46`, with the Soliloquy `rusty_v8`, bridge, `os://`, and QEMU boot patches retained.
- The local `surfman 0.11.0` patch remains pinned intentionally; upstream Servo currently points at `surfman 0.12.0`, but using that directly would bypass the Soliloquy QEMU/X11 boot fixes.
- QEMU now boots into the Servo browser appliance path. This is still Servo-first boot, not full RV8 page-script ownership.
- `os://terminal` is wired through Servo's `os:` protocol handler to the local sold terminal route.
- `ghostty-vt.wasm` now builds locally with Homebrew `zig@0.15` without replacing the user's default `zig 0.16`.
- RV8 now returns typed `ExecuteScript` results over renderer IPC instead of logging string-only callback placeholders.
- RV8's local V8 DOM handles now support basic mutation/event behavior: `appendChild`, `removeChild`, `setAttribute`, `getAttribute`, `textContent`, `querySelector`, and `addEventListener`.
- RV8's compositor now keeps a bounded present-pass queue alongside recent damage history.
- A standalone local `../rv8` repository is the canonical browser-engine checkout; Soliloquy no longer builds an in-repo RV8 crate as an active workspace member.
- The appliance session launches Servo with its built-in browser chrome disabled so the Svelte appliance shell provides the only browser UI surface.
- The Svelte appliance shell now has Zen-style vertical tabs, compact mode, split columns, split rows, and grid modes.
- The macOS desktop path launches Crepuscularity GPUI chrome from `../crepuscularity` and starts Servo with `--no-browser-chrome`; it can start or reuse `sold` for local runtime APIs but does not serve the Svelte appliance shell.
- Browser-global evaluation paths still fall back to Servo's existing `mozjs` path until DOM/Web IDL ownership moves to V8.

## What Has Been Done

- Added a typed Servo-side bridge module for the current snapshot-backed operations.
- Replaced direct snapshot ownership in the evaluator with bridge helpers and typed read/write targets.
- Added a stable command result envelope carrying `ok`, `status`, `value`, and `detail`.
- Replaced the structured command dispatcher internals with typed command variants before execution.
- Moved the Servo-side bridge command enum and command-target parsing into the bridge boundary.
- Added a narrow `location.href` write path that updates the live snapshot and marks `document.readyState` as `loading`.
- Resolved relative `location.href` writes against the live document URL before mutation routing.
- Routed validated `location.href` writes through Servo's `LoadUrl` constellation message.
- Taught the shell-side V8 mock to execute typed bridge reads, writes, command envelopes, and navigation snapshot updates.
- Added the initial Servo-side script backend trait with `mozjs` fallback and `v8-experimental` dispatch implementations.
- Added a dispatch-only V8 isolate owner stub behind the `v8-experimental` backend and exposed it through `engine.status`.
- Added a shared bridge schema JSON and exposed it through `dom.capabilities` on both the Servo bridge and shell V8 mock.
- Added an opt-in `soliloquy_v8` feature that initializes a real `rusty_v8` platform, thread-local isolate, and persistent per-WebView contexts for embedder-driven JavaScript evaluation.
- Fixed the Servo bridge test compile path against Servo's composite `WebViewId`, Rust 2024 environment mutation rules, and the `HistoryChanged` WebView ownership path.
- Kept the `rv8` dispatcher local-first, with fallback to Servo's existing `mozjs` path for unsupported operations.
- Kept the shell-side JS engine status plumbing aligned with `SOLILOQUY_JS_ENGINE`.
- Upgraded the desktop UI dependency stack and cleared the open `ui/desktop` Dependabot alerts locally.
- Verified the current shell and UI paths with passing tests/builds.
- Verified Servo-side bridge tests with explicit macOS SDK sysroot:
  - `cargo test -p servo soliloquy_javascript --lib`
  - `cargo test -p servo javascript_evaluator --lib`
  - `cargo test -p servo soliloquy_bridge --lib`
  - `cargo test -p servo soliloquy_javascript --lib --features soliloquy_v8`
- Added `tools/rv8_servo_test.sh` so the targeted Servo bridge checks can run with the required macOS SDK sysroot env without hand-typing it.
- Added schema-driven parser tests for `soliloquy_bridge_schema.json` so declared commands and DOM targets must parse through the typed Servo bridge boundary.
- Added `start.sh` at the repo root as a small launcher for the QEMU appliance path and the existing dev script.
- Added Servo's `os:` protocol handler so `os://terminal` routes to the local terminal surface.
- Merged the local Servo branch forward over the latest upstream Servo mainline and updated the root Soliloquy gitlink.
- Removed the obsolete local `sea-query-rusqlite` patch from the active Servo dependency graph after the upstream merge; Servo now uses the pinned upstream crate release.
- Aligned the local `surfman` patch to Servo's current `glow 0.17` dependency so targeted `soliloquy_v8` checks pass again.
- Updated `scripts/build-ghostty-wasm.sh` to prefer `GHOSTTY_ZIG` or Homebrew's unlinked `zig@0.15` binary, then built `bundle/terminal/ghostty-vt.wasm`.
- Added typed RV8 script-result IPC, DOM mutation/event tests, and a bounded compositor present-queue test.

## What Is Still Missing

- A typed host bridge between Servo script operations and the Soliloquy V8 runtime.
- Browser-global bindings for `window`, `document`, navigation, storage, timers, events, and fetch in the V8-owned path.
- Full DOM object identity, handle lifetime, and cross-runtime serialization rules beyond the local RV8 handle prototype.
- Mutation routing from V8-owned calls into the actual Servo script / DOM thread beyond the local RV8 mutation log.
- Event delivery from Servo into the V8 side for navigation, load, timers, and DOM changes beyond the local RV8 listener prototype.
- A plan to remove or sharply reduce `mozjs` ownership without breaking Web IDL bindings.

## Compositor Reference Notes

Hyprland is a useful reference for the RV8 compositor shape, not a code source to copy. Its optimized path centers on per-output frame scheduling, a damage ring retained across the swap chain depth, explicit damage entry points, a pass queue that is built before GPU execution, and visibility / occlusion checks before expensive rendering. See:

- Hyprland rendering pipeline notes: <https://deepwiki.com/hyprwm/Hyprland/6.1-rendering-pipeline>
- Hyprland repository: <https://github.com/hyprwm/Hyprland>

RV8 should mirror those architecture choices in Rust / WGPU terms:

- Frame production must be damage-driven; avoid a permanent 16 ms render loop when no visible content changed.
- Track damage per output / surface and retain recent damage across the buffer queue so partial redraw is safe after swaps.
- Build an explicit render pass list from tabs, layers, popups, cursor, overlays, and browser UI before submitting GPU commands.
- Cull invisible or fully occluded layers before pass construction.
- Keep presentation timing and frame statistics in the compositor boundary so QEMU and hardware tests can assert real frame flow.
- Add snapshot textures for closing / animating tabs or surfaces so animations do not depend on a live renderer buffer.

## Recommended Phases

### Phase 1: Harden The Host Bridge

- Completed in part:
  - moved the current snapshot store behind a dedicated bridge module
  - introduced typed read targets for `document.title`, `location.href`, and `document.readyState`
  - introduced typed write targets for `document.title` and `location.href`
  - defined the initial stable command result envelope for ok, error, and unsupported operations
  - moved structured command dispatch through typed command variants
  - moved Servo-side bridge command definitions into the bridge boundary
  - connected absolute `location.href` writes to Servo's real navigation request path
  - resolved relative `location.href` writes against the live document URL
  - mirrored the typed bridge surface in the shell-side V8 mock
  - published the bridge command schema from Servo and included it from the shell-side V8 mock
  - added schema-driven parser tests for declared commands, read targets, and write targets
- Still to do:
  - add more result-envelope coverage for arrays and objects as bridge commands expand

### Phase 2: Introduce A Real V8 Execution Core

- Completed in part:
  - added a Servo-side trait for script execution backends
  - added a `mozjs` fallback implementation that declines local execution
  - moved the current Soliloquy V8 dispatch path behind a `v8-experimental` backend implementation
  - added a V8 isolate owner so backend status can report `isolateOwner` and `realIsolate`
  - added an opt-in `soliloquy_v8` feature that bootstraps `rusty_v8` platform / thread-local isolate ownership
  - added persistent per-WebView V8 contexts for general embedder-driven ECMAScript evaluation
- Still to do:
  - define isolate lifetime, value transport, and error propagation contracts
  - install typed browser globals into V8 contexts
  - keep direct DOM execution scoped until value transport, error propagation, and isolate lifetime are stable

### Phase 3: Add DOM Handle Semantics

- Completed in part:
  - added local RV8 `NodeId`-backed JS objects with basic DOM methods and `textContent` accessors
  - added mutation logging for append, remove, attribute, and text writes
  - added local event listener registration and dispatch for host-routed events
- Still to do:
  - introduce opaque Servo node / window / document handles instead of local-only `NodeId` objects
  - define lookup, invalidation, and stale-handle behavior across Servo and V8
- Add explicit thread-affinity rules for script thread access.

### Phase 4: Expand Mutation Coverage

- Add write operations beyond title:
  - location navigation
  - selected attribute / property mutation
  - limited element creation and text updates
- Each added operation needs:
  - bridge command
  - serializer contract
  - unit tests
  - fallback behavior

### Phase 5: Move Evaluation Ownership

- Route a bounded subset of Servo `evaluate_javascript()` entirely through the V8 backend.
- Add feature-gated telemetry for:
  - backend chosen
  - fallback rate
  - unsupported operation rate
  - serialization failures
- Only after fallback rates are low should wider JS execution migrate away from `mozjs`.

### Phase 6: Rework Script Bindings

- Audit the current `js::...` coupling in Servo script and bindings.
- Identify the smallest binding surface that can be abstracted first.
- Expect this to be the longest and highest-risk phase; Web IDL integration is where a full engine swap becomes real work instead of dispatcher plumbing.

## Acceptance Criteria For Full Linkage

- Servo can boot with V8 selected and execute real page script through V8, not only host-dispatched probes.
- DOM reads and writes go through a typed bridge or native binding layer rather than snapshot-only helpers.
- Fallback to `mozjs` is either removed or confined to explicitly unsupported legacy paths.
- Integration tests cover:
  - evaluation
  - DOM mutation
  - navigation
  - event delivery
  - isolate teardown
  - multi-webview separation
- QEMU boot tests confirm visible browser rendering and successful script execution under the selected V8 mode.

## Current Blockers

- Plain local Servo Rust validation now works for the targeted Soliloquy path with the local SDK/toolchain shim.
  - Full locked Cargo metadata passes for `third_party/servo/Cargo.toml`.
  - Targeted `cargo check -p servo --no-default-features --features soliloquy_v8` passes after cleaning `mozjs_sys` and aligning the local `surfman` patch to `glow 0.17`.
  - Running without `/usr/bin/python3` first in `PATH` also trips over Homebrew Python 3.14 `sitecustomize`; use Xcode's Python 3.9.6 for Servo checks.
  - The Xcode SDK / `libclang` env shim is still needed for local macOS checks.
- The current bridge is intentionally narrow and does not yet own general DOM execution.
- Browser boot currently lands in the Servo appliance surface. Full RV8 page-script ownership is still future work.

## Immediate Next Steps

1. Broaden the navigation bridge test into an integration path that crosses `WebView::evaluate_javascript()` and observes the emitted `LoadUrl` request.
2. Connect the local RV8 typed script-result path to Servo's `v8-experimental` dispatcher.
3. Extend schema coverage to mutation definitions once the next Servo mutation command is added.
4. Add stale-handle and multi-document tests for the local RV8 DOM handle prototype.
5. Continue replacing the RV8 compositor stub with a Hyprland-style per-surface scheduler and occlusion-aware pass builder.
