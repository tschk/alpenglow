# Browser-Centric OS Optimization

Alpenglow should optimize for one primary workload: booting into an interactive browser surface quickly, keeping renderer work isolated, and recovering browser services without treating the machine like a general desktop distribution.

## Reference Systems

- ChromeOS defines useful browser-appliance goals: verified system state, rollback, and a boot-complete point tied to the browser login surface instead of generic init completion.
- Zircon is a useful model for handle-oriented process, channel, VMO, job, and futex boundaries. Alpenglow should mirror those boundaries in Rust and Linux primitives before considering kernel replacement work.
- Darwin/XNU is useful for service supervision, QoS, memory pressure, and driver-boundary organization. Alpenglow should copy the shape, not the code.
- Vinix is useful as a small-kernel module map and boot-sequencing reference. Vinix is GPL-2.0, so Alpenglow must not import or port Vinix code into this MPL-licensed repo.

## RV8 Boundary

[RV8](https://github.com/tschk/rv8) is the canonical browser-engine checkout. The Alpenglow root workspace should not build an in-repo RV8 crate as an active member.

Alpenglow owns:

- Alpine appliance image assembly.
- `sold` and authenticated local system APIs.
- Browser session startup, policy, service graph, and runtime telemetry.
- Servo launch policy and browser chrome ownership.

RV8 owns:

- Engine loop, renderer process model, tab/session model, and IPC protocol.
- Servo embed integration and V8 ownership.
- Shared frame and viewport protocol evolution.
- Browser storage and profile engine internals.

## Browser Boot Target

Boot is complete when the browser is interactive. The minimal runtime graph is:

1. `networking`
2. `sold`
3. `seatd`
4. `alpenglow-session`
5. `servo`
6. `rv8`
7. first frame
8. browser interactive

`sold` exposes the current graph through `/api/runtime`. Appliance launchers can populate these environment timestamps:

- `ALPENGLOW_SOLD_START_UNIX_MS`
- `ALPENGLOW_FIRST_FRAME_UNIX_MS`
- `ALPENGLOW_BROWSER_INTERACTIVE_UNIX_MS`
- `ALPENGLOW_RENDERER_RESTARTS`

## Kernel-Level Optimization Ideas

- Stage only browser-critical kernel modules into initramfs: framebuffer or DRM, input, storage root, network needed for first page, and board-specific essentials.
- Keep optional services out of the default OpenRC runlevel unless they directly support browser startup.
- Use cgroups or process affinity for renderer groups, GPU/compositor work, and `sold` instead of broad system-level tuning.
- Move frame transport toward shared-memory buffers with explicit ownership and lifecycle, using Zircon VMOs as the conceptual model.
- Treat browser sessions, renderer processes, terminal sessions, and privileged service calls as capability handles instead of ambient global APIs.
- Record service start, first frame, browser interactive, renderer restart, and memory pressure events before optimizing further.

## First Implementation Slice

- Keep Vinix reference-only in runtime status and docs.
- Externalize active RV8 build ownership to [RV8](https://github.com/tschk/rv8).
- Add browser-first runtime telemetry to `sold`.
- Keep the Alpine service graph minimal and browser-oriented.
- Validate with Cargo, Bun, and QEMU smoke checks before broad kernel or compositor changes.
