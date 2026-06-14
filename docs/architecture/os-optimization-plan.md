# Alpenglow OS Optimization Plan

Reasoning path: Soliloquy should borrow operating-system shapes that make a browser appliance faster, safer, and easier to recover, while using an explicit Linux appliance backend, keeping `../rv8` as the browser-engine boundary, and treating Vinix as reference-only because of GPL-2.0.

Confidence score: 8/10.

## Design Constraints

- Optimize for browser interactive time, renderer survival, tab residency, and recoverability.
- Prefer Linux primitives already available to Alpine: cgroup v2, PSI, seccomp, Landlock, pidfd, memfd, Unix socket FD passing, zram, EROFS, SquashFS, GlowFS, OpenRC.
- Keep the immutable root image small and boring.
- Keep browser, renderer, `sold`, network, terminal, and plugin work in separate failure domains.
- Measure before optimizing Rust code. Add telemetry first, then benchmarks or release-mode profiles before micro-optimizing.
- Use Rust policy types and explicit error paths for new services. Avoid ambient global state, unchecked `unwrap`, unbounded async queues, and blocking work inside async runtime tasks.
- Kernel-level modifications are in scope when they are carried as a small patch queue, guarded by bootable fallback kernels, and measured against browser-interactive, input latency, memory pressure, and frame pacing gates.

## Research Sources

- ChromeOS: verified boot, inactive-slot updates, rollback, and browser-first boot-good semantics.
  - https://www.chromium.org/chromium-os/chromiumos-design-docs/verified-boot/
  - https://www.chromium.org/chromium-os/chromiumos-design-docs/filesystem-autoupdate/
- Android: userspace low-memory daemon reacting to pressure before system-wide OOM.
  - https://source.android.com/docs/core/perf/lmkd
- Linux: PSI and cgroup v2 as control-plane signals and enforcement primitives.
  - https://kernel.org/doc/html/v6.0/accounting/psi.html
  - https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html
- Fuchsia/Zircon: handles, channels, jobs, VMOs, and capability-oriented process trees.
  - https://fuchsia.googlesource.com/fuchsia/+/17cd5efd427a/docs/concepts/kernel/concepts.md
- QNX: small service processes connected by disciplined message passing.
  - https://qnx.com/developers/docs/7.1/com.qnx.doc.neutrino.sys_arch/topic/intro_Message_passing_OS.html
- Genode and seL4: component isolation, resource budgets, capability distribution, and high-assurance boundaries.
  - https://genode.org/about/index
  - https://genode.org/documentation/genode-foundations/25.05/components/index.html
  - https://sel4.org/About/fact-sheet.html
- NixOS and Haiku: generations, rollback, packagefs-style read-only composition, and safe component disablement.
  - https://nixos.org/guides/how-nix-works/
  - https://wiki.nixos.org/wiki/NixOS/en
  - https://www.haiku-os.org/guides/daily-tasks/disable-package-entries/
- OpenBSD and FreeBSD: pledge/unveil and Capsicum-style least authority.
  - https://papers.freebsd.org/2010/rwatson-capsicum/
  - https://www.openbsd.org/papers/BeckPledgeUnveilBSDCan2018.pdf
- Windows: job-object process trees, resource accounting, app-container boundaries, and adaptive prefetch.
  - https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects
  - https://learn.microsoft.com/en-us/windows/security/book/application-security-application-isolation
- Apple platforms: low-power and thermal response policy for reducing optional work.
  - https://developer.apple.com/documentation/xcode/responding-to-power-notifications
- CachyOS and Arch-family systems: custom kernels, scheduler variants, optimized package repositories, kernel-manager style build matrices, and initramfs generation discipline.
  - https://wiki.cachyos.org/features/kernel/
  - https://wiki.cachyos.org/features/kernel_manager/
  - https://wiki.cachyos.org/features/optimized_repos/
  - https://wiki.archlinux.org/title/Mkinitcpio
- Puppy Linux: frugal installs, SquashFS layers, save files, and optional RAM-loaded system images.
  - https://www.wikka.puppylinux.com/FrugalOrFullInstallation
- Slackware: simple configuration, conservative patching, stability over novelty, and low abstraction.
  - https://docs.slackware.com/slackware:philosophy
- Fedora Silverblue and bootc/image-mode systems: OSTree-style full-tree deployments, layered packages, and container-image OS composition.
  - https://docs.fedoraproject.org/pt_BR/fedora-silverblue/technical-information/
  - https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems
- Debian: stable/testing/unstable channel discipline, signed release metadata, and boring production defaults.
  - https://www.debian.org/releases/index.en.html
- Ubuntu Core: kernel/gadget/app components, transactional snap revisions, autonomous updates, and rollback for remote embedded systems.
  - https://documentation.ubuntu.com/core/explanation/core-elements/snaps-in-ubuntu-core/
- Linux kernel memory and latency features that fit appliance kernels without immediately carrying large source patches.
  - https://docs.kernel.org/admin-guide/mm/multigen_lru.html
  - https://docs.kernel.org/mm/damon/index.html
  - https://www.kernel.org/doc/html/latest/scheduler/sched-eevdf.html
  - https://www.kernel.org/doc/html/latest/scheduler/sched-ext.html
  - https://www.kernel.org/doc/html/latest/admin-guide/blockdev/zram.html
  - https://www.kernel.org/doc/html/next/core-api/real-time/theory.html
  - https://erofs.docs.kernel.org/
- Alpine kernel packaging: multiple kernel profiles already fit Alpine's model, so Soliloquy-specific kernel packages are compatible with the base OS direction.
  - https://wiki.alpinelinux.org/wiki/Kernels

## Fit Review

Soliloquy is not a general desktop distribution. It is a browser appliance on Alpine with an immutable root, OpenRC service startup, `sold` as the system bridge, Servo as the fullscreen surface, and `../rv8` as the browser-engine boundary. Keep ideas that improve boot-to-browser, active-tab latency, memory pressure behavior, rollback, and service recovery. Defer or reject ideas that mainly optimize distro-hopping convenience, gaming desktops, generic package availability, or broad desktop hardware coverage.

### Keep Now

- Runtime telemetry before policy:
  - browser-interactive timestamp
  - first frame
  - renderer restarts
  - cgroup placement
  - PSI memory/cpu/io
  - cache pressure
- cgroup v2 browser workload classes:
  - `system`
  - `network`
  - `browser`
  - `foreground-renderer`
  - `background-renderer`
  - `frozen-renderer`
  - `discardable-renderer`
  - `gpu-compositor`
- Kernel config work over source patches:
  - cgroup v2
  - PSI
  - MGLRU
  - zram
  - seccomp
  - Landlock
  - BBR/fq
  - EROFS/SquashFS fallback
  - DRM/KMS and input modules needed for first frame
- BORE-style source patch lane:
  - carry as a small explicit patch queue, not an ambient fork
  - measure only against browser-interactive, active-tab input, frame pacing, and memory pressure
  - require QEMU and target-board evidence before promotion
- Alpine-compatible kernel variants:
  - `sol-linux-baseline`
  - `sol-linux-appliance` as the default hybrid hardware-adapting kernel
  - `sol-linux-debug`
- One default hybrid hardware-adapting kernel:
  - adapt runtime policy to detected board, memory, thermal, input, GPU, and storage capabilities
  - keep generic baseline and broad fallback kernels bootable
  - keep experimental scheduler, memory, RT, and debug work as lanes behind the default
- Arch-style initramfs discipline:
  - one minimal first-frame image
  - one broad fallback image
  - hook/preset generation
  - kernel artifact provenance
- Fedora/Ubuntu Core-style atomic component thinking:
  - kernel component
  - board/boot component
  - root image component
  - browser shell component
  - plugin component
- Debian-style channel gates:
  - `stable` for release kernel
  - `testing` for soaked kernel
  - `unstable` for active experiments
  - `experimental` for risky patches
- Slackware-style plain files:
  - keep policy inspectable
  - keep service graph plain
  - keep patch series explicit
- Puppy-style layer recovery:
  - detachable plugin layers
  - RAM-root default on hardware that passes memory pressure and browser metrics
  - disk-backed fallback root for low-memory or failed RAM-root boot
  - easy layer disablement

### Keep Later

- Capability-oriented `sold` handles implementation lane:
  - high value, after runtime telemetry and cgroup placement.
- Shared-memory frame/resource transport implementation lane:
  - high value for copy reduction, after current frame path measurements.
- DAMON implementation lane:
  - useful for memory behavior, after PSI, MGLRU, zram, and cgroup event baselines.
- PREEMPT_RT implementation lane:
  - test as `sol-linux-rt-lab`, not default. Useful only if input/compositor latency data beats appliance kernel without hurting throughput or power.
- sched_ext implementation lane:
  - useful for scheduler experiments that can stay in BPF/userspace, after baseline EEVDF and cgroup data.
- Board-specific optimized builds implementation lane:
  - useful for `sold`, `sol-netd`, `glowfsctl`, Servo launcher helpers, and hot Rust services after correctness gates.

### Defer

- Multiple full kernel flavors for end users:
  - keep internal variants first; expose user-selectable kernels only after rollback and mark-good are solid.
- Full OSTree/rpm-ostree import:
  - keep full-tree deployment idea, but GlowFS/generation metadata already points in the local direction.
- Snap as package system:
  - keep kernel/gadget/base/app component model and transactional lessons, not snapd.
- Pacman, apt, dnf, or rpm package flow:
  - keep lessons, not package managers. Oil remains the package direction for Alpenglow.
- Broad codec and desktop convenience defaults:
  - keep browser-required media support explicit, not remix-style catch-all installs.

### Reject

- General desktop gaming kernel as default.
- Kernel patch that improves synthetic throughput but hurts active-tab input or first frame.
- Broad mutable root package layering.
- Importing Vinix code.
- Moving browser-engine ownership back into Soliloquy root.
- Adding telemetry that leaves the device by default.
- Supporting many distro families directly. Keep one active backend, one reference backend, and use the backend contract for experiments.

### Plan Corrections From Review

- Kernel work should start with config and in-tree kernel features while keeping the BORE-style source patch lane explicit, small, and reversible.
- `sol-linux-latency-lab` should be an experiment name, not a default release kernel.
- `sol-linux-rt-lab` should remain an explicit experimental lane.
- `sol-linux-appliance` should be the one default hybrid hardware-adapting kernel, with fallback kernels kept bootable.
- MGLRU should be added to the first kernel config target.
- DAMON should be listed as later-stage memory instrumentation, not first-stage policy.
- sched_ext and BORE-style source patches should both be lanes, with neither promoted without browser-appliance evidence.
- RAM-loaded root should become default only on hardware that still passes 150-tab pressure goals, with disk-backed fallback root preserved.
- Distro lessons should be reduced to mechanisms Soliloquy can own: generations, fallback boot, cgroup policy, immutable layers, kernel matrices, plain manifests.

## Linux Distribution Lessons

### CachyOS And Arch Family

- Carry multiple kernel flavors instead of one irreversible kernel bet:
  - `sol-linux-baseline`: conservative upstream kernel plus required board config.
  - `sol-linux-appliance`: first-frame modules, cgroups, PSI, MGLRU, zram, seccomp, Landlock, BBR/fq.
  - `sol-linux-latency-lab`: experimental scheduler/preemption lane.
  - `sol-linux-rt-lab`: optional PREEMPT_RT experiment for input and compositor tests.
  - `sol-linux-debug`: tracing, lockdep, and instrumentation.
- Borrow CachyOS kernel-manager shape:
  - build kernel variants from one declarative matrix
  - cache build artifacts
  - record config hash, patch hash, toolchain, and benchmark result
  - expose active kernel variant in `/api/runtime`
  - always keep previous known-good kernel bootable
- Borrow CachyOS scheduler experimentation, but constrain it:
  - test BORE-style burst responsiveness only against browser input and frame pacing
  - test sched_ext only if target kernel and appliance image can ship the userspace scheduler safely
  - keep EEVDF/default scheduler as fallback
  - no scheduler patch becomes default without QEMU and target-board browser metrics
- Borrow optimized repository idea for appliance-owned binaries:
  - build `sold`, `sol-netd`, `glowfsctl`, and hot Rust services for target CPU tiers where useful
  - for ARM64 board targets, prefer board-specific `-mcpu`/target-feature builds only after correctness gates pass
  - keep generic baseline artifact for recovery
- Borrow Arch `mkinitcpio` discipline:
  - initramfs generation should be explicit, hook-based, reproducible, and tied to installed kernel artifact
  - default image should include only first-frame critical modules
  - fallback image should include broad recovery modules

### Puppy Linux

- Borrow frugal/layered boot:
  - immutable base image
  - small writable save layer
  - optional read-only feature SFS layers
  - easy layer disablement for recovery
- Add RAM-root as the preferred boot mode where hardware allows it:
  - load GlowFS/EROFS root image into RAM on machines with enough memory
  - measure cold boot, first frame, and first remote page load against disk-backed boot
  - fall back to disk-backed boot for low-memory boards or failed RAM-root boots
- Treat plugin bundles as detachable read-only layers with separate writable state.

### Slackware

- Borrow simplicity as policy:
  - plain files for service graph and kernel policy
  - minimal patch stack
  - no opaque daemon if a static manifest works
  - no automatic magic that cannot be reproduced from a shell script
- Prefer upstream defaults unless Soliloquy has browser-appliance evidence.
- Make every local patch explain:
  - browser metric it affects
  - why upstream/default behavior is insufficient
  - how rollback works

### Fedora, Ultramarine, And Remixes

- Borrow Fedora Atomic/Silverblue image discipline:
  - full-tree deployment, not package mutation in place
  - reboot into known generation
  - layer exceptional components consciously
  - expose deployed generation status clearly
- Borrow bootc/image-mode thinking:
  - OS image can be composed from declarative layers
  - policy, services, and kernel artifacts are part of image provenance
  - build artifact should be deployable and testable as one unit
- Borrow Ultramarine/remix lesson:
  - users should not have to hand-tune obvious defaults
  - hardware enablement, codecs, input, networking, fonts, and browser policy should be ready from first boot
  - make defaults polished, but keep base immutable and inspectable

### Debian

- Borrow channel discipline:
  - `stable`: kernel/config known good for appliance releases
  - `testing`: next kernel/config after soak
  - `unstable`: active scheduler, memory, filesystem experiments
  - `experimental`: risky kernel patches or new filesystems
- Require signed generation metadata, even for local images.
- Keep release notes for each kernel/config generation:
  - changed config options
  - patch queue delta
  - known regressions
  - rollback instructions

### Ubuntu Core And Ubuntu Remixes

- Borrow component update model:
  - kernel component
  - bootloader/board component
  - base OS component
  - browser shell component
  - plugin/app component
- Borrow transactional remote update constraints:
  - interrupted updates must not brick device
  - network-free boot must work after failed update
  - critical fixes can be prioritized
  - rollback must be automatic if browser-interactive mark fails
- Borrow remix lesson:
  - produce opinionated variants from same base, not forks
  - possible variants: developer, appliance, debug, kiosk, board-lab

## Kernel Modification Track

Kernel work is allowed, but it must stay measurable, revertible, and browser-scoped.

### Patch Queue Rules

- Keep patches under `system/alpine/kernel/patches`.
- Maintain `series.toml` with:
  - patch id
  - upstream base
  - subsystem
  - reason
  - expected metric
  - risk level
  - fallback behavior
- Split config changes from source patches.
- Keep board-specific patches separate from generic browser-appliance patches.
- Rebase patches regularly; delete patches that no longer move a measured metric.

### First Kernel Targets

- Scheduler:
  - tune cgroup-aware foreground renderer and compositor behavior first
  - carry BORE-like burst heuristics as a source patch lane beside EEVDF and sched_ext experiments
  - evaluate sched_ext for browser workload classes beside reversible scheduler source patches
  - promote scheduler policy only when fallback boot, QEMU, and target-board browser metrics pass
- Memory:
  - enable PSI and cgroup memory events
  - enable and measure MGLRU
  - tune zram for tab snapshot pressure
  - test proactive reclaim for background renderers
  - evaluate DAMON only after PSI, cgroup events, MGLRU, and zram baselines are understood
  - expose low-memory notifications to `sol-pressure`
- IO:
  - prioritize profile writes, cache reads, and UI bundle reads
  - demote background HTTP cache churn
  - keep root image read-only and hot metadata compact
- Networking:
  - test BBR/fq only against page-load and QUIC behavior
  - keep deterministic fallback for bad links
  - expose network policy in `sol-netd`
- Graphics/input:
  - keep DRM/KMS, input, and GPU modules first-frame critical
  - protect compositor/input latency with cgroup and scheduler policy
  - add frame pacing telemetry before source-level driver patches
- Filesystem:
  - keep GlowFS kernel path focused on verified read-only boot
  - make RAM-root the default where hardware passes 150-tab pressure goals
  - compare GlowFS, EROFS, SquashFS, RAM-root, and disk-backed fallback boot
  - avoid broad writable filesystem complexity in kernel

### Kernel Variant Matrix

- `baseline`: upstream kernel plus required board config.
- `appliance`: default hybrid hardware-adapting kernel with stripped modules, browser-first initramfs, cgroup/PSI/MGLRU/zram/seccomp/Landlock enabled.
- `latency-lab`: appliance plus scheduler/preemption experiments.
- `pressure-lab`: appliance plus memory reclaim, DAMON, and zram experiments.
- `rt-lab`: appliance plus PREEMPT_RT experiment.
- `debug`: tracing, symbols, lock debugging, and crash evidence.

Each variant must record:

- kernel version
- config hash
- patch series hash
- compiler
- target board
- root image generation
- boot-to-browser-interactive result
- input latency result
- frame pacing result
- memory pressure result

### Kernel Stop Rules

- If patch improves synthetic benchmark but hurts browser-interactive or active-tab latency, reject it.
- If patch cannot boot fallback generation cleanly, reject it.
- If patch requires ambient privileges in renderer or UI, reject it.
- If patch duplicates a cgroup/userspace policy that already solves the problem, keep userspace path.
- If patch cannot be tested in QEMU and on target board class, keep it experimental.

## Phase 1: Measurement Before Policy

- Extend `/api/runtime` with boot graph timestamps:
  - kernel start if available
  - OpenRC start
  - `sold` listening
  - network ready
  - `sol-session` launch
  - Servo process start
  - RV8 renderer process start
  - first frame
  - browser interactive
- Add renderer lifecycle counters:
  - spawn count
  - crash count
  - restart count
  - last exit status
  - time-to-first-script
  - time-to-first-navigation-commit
- Add pressure counters:
  - PSI cpu, memory, io `some` and `full`
  - cgroup memory events
  - zram usage
  - cache trim events
  - tab freeze, thaw, discard, restore events
- Add a browser-performance event ring in `sold`:
  - bounded capacity
  - monotonic timestamps
  - typed event enum
  - JSON export for UI and QEMU smoke checks
- Gate optimization work with repeatable checks:
  - cold boot to browser interactive
  - warm boot to browser interactive
  - first local `os://terminal` load
  - first remote page load
  - 25, 75, 150 tab residency simulations

## Phase 2: Browser Workload Classes

Borrow Windows job objects, Zircon jobs, and cgroup v2:

- Create stable process classes:
  - `system`: `sold`, service registry, watchdog
  - `network`: `sol-netd`, DNS, preconnect, QUIC
  - `browser`: shell, UI, session manager
  - `foreground-renderer`: active tab and immediate visible work
  - `background-renderer`: hidden but warm tabs
  - `frozen-renderer`: no CPU except lifecycle signals
  - `discardable-renderer`: safe to kill and restore from session state
  - `gpu-compositor`: frame scheduling and shared buffers
- Map classes to cgroup controls:
  - `cpu.weight`
  - `io.weight`
  - `memory.low`
  - `memory.high`
  - `memory.max`
  - `pids.max`
- Keep policy data declarative in `/etc/soliloquy/kernel-policy.json`.
- Make process placement observable in `/api/runtime`.
- Prefer pidfd-based tracking for renderer children when the target kernel supports it.

## Phase 3: Pressure Governor

Borrow Android LMKD, Darwin pressure response, and Chrome tab discard:

- Build `sol-pressure` as a small Rust service or `sold` module after telemetry proves the needed events.
- Inputs:
  - `/proc/pressure/{cpu,memory,io}`
  - cgroup memory events
  - renderer class
  - tab visibility
  - media/audio activity
  - form/input dirty state
  - navigation recency
  - cache pressure
- Actions by severity:
  - `normal`: allow speculation, keep warm tabs, allow texture/code caches.
  - `constrained`: pause optional speculation, trim low-value caches, lower background CPU weight.
  - `pressure`: freeze inactive renderers, compress tab snapshots, flush least-useful textures.
  - `critical`: discard lowest-rank renderers, stop prerender, shrink connection prewarm, preserve active tab.
- Rust shape:
  - `PressureSample`
  - `RendererImportance`
  - `PressureLevel`
  - `GovernorAction`
  - `PolicyDecision`
- Error shape:
  - typed errors for missing PSI, cgroup write denial, stale pid, invalid policy, and unsupported kernel feature.
- Async shape:
  - bounded `tokio::sync::mpsc` channel for samples
  - `watch` channel for current pressure level
  - no blocking filesystem polling on core runtime worker threads

## Phase 4: Immutable Generations And Rollback

Borrow ChromeOS A/B, NixOS generations, Haiku packagefs, and Solaris boot environments:

- Treat a Soliloquy release as a generation:
  - kernel or boot artifact
  - initramfs
  - root image
  - OpenRC service graph
  - UI bundle
  - `sold`
  - policy files
  - Servo launcher
- Mark a generation good only after:
  - root image verified
  - `sold` listening
  - Servo started
  - first frame observed
  - browser interactive event observed
- Keep inactive generation writable only to update tooling.
- Keep mutable state outside generation ownership:
  - browser profile
  - downloads
  - logs
  - caches
  - terminal/session state
- Add recovery behavior:
  - if browser-interactive mark fails after N attempts, roll back
  - if service graph fails, boot safe generation
  - if plugin disables boot, boot with plugin packagefs disabled
- Make GlowFS generation metadata first-class:
  - generation id
  - content digests
  - build provenance
  - required kernel features
  - rollback parent
  - browser-interactive mark

## Phase 5: Capability-Oriented `sold`

Borrow Zircon handles, Capsicum, OpenBSD pledge/unveil, Genode components, and seL4 capability discipline:

- Replace broad ambient system APIs with explicit capabilities:
  - terminal session handle
  - browser profile handle
  - download directory handle
  - power control handle
  - network status handle
  - plugin install handle
  - frame buffer handle
- Mint capabilities from `sold` after authentication and policy checks.
- Scope every capability by:
  - operation set
  - resource id
  - expiry
  - owner process
  - revocation path
- Expose narrow APIs:
  - create handle
  - inspect handle metadata
  - use handle
  - revoke handle
- Keep filesystem visibility explicit:
  - no UI direct host filesystem access
  - no renderer direct system write path
  - no plugin access outside granted state roots
- Use Rust newtypes for handle ids and resource ids.

## Phase 6: Shared-Memory Frame And Asset Transport

Borrow Zircon VMOs, Chrome shared-image style thinking, Linux `memfd`, and QNX message separation:

- Move large frame/resource payloads off JSON and websocket body paths.
- Use `memfd_create` for shared buffers where supported.
- Pass file descriptors over Unix domain sockets.
- Seal immutable buffers after write.
- Track explicit ownership:
  - producer owns write phase
  - compositor owns present phase
  - renderer gets read-only phase
  - buffer returns to pool or closes
- Add lifecycle telemetry:
  - buffer allocation count
  - bytes in flight
  - frame drops
  - missed present deadlines
  - copy count estimate
- Keep fallback path:
  - normal byte transport for unsupported kernels and local dev
  - feature detection reported through runtime API

## Phase 7: Scheduler And QoS Policy

Borrow Darwin QoS, Windows priority classes, FreeBSD scheduler lessons, and Linux cgroups:

- Define Soliloquy QoS labels:
  - `interactive`: active tab input, compositor, command bar
  - `visible`: current page render and media
  - `utility`: downloads, cache writes, profile sync
  - `background`: hidden tabs, prefetch, indexing
  - `maintenance`: update checks, cleanup, log rotation
- Map QoS to:
  - cgroup cpu/io weight
  - nice level where useful
  - async task queues inside Rust services
  - speculation budgets
- Do not custom-patch kernel scheduler until telemetry proves Linux policy knobs are insufficient.
- Give compositor and input work a protected budget before renderer background work.

## Phase 8: Security And Sandboxing

Borrow OpenBSD, FreeBSD Capsicum, Windows AppContainer, Android app sandbox, and Chrome renderer isolation:

- Keep renderers least-privilege:
  - seccomp filter
  - Landlock rules if target kernel supports it
  - no ambient profile filesystem writes
  - no direct system APIs
  - cgroup placement by class
- Split privileged service functions:
  - `sold`: authenticated system bridge
  - `sol-netd`: network policy and probes
  - `sol-updated`: generation install and rollback
  - `sol-pressure`: pressure governor if separated from `sold`
  - `sol-plugin`: plugin install and packagefs policy
- Add policy audit endpoint:
  - current sandbox mode
  - missing kernel features
  - degraded protections
  - last policy error

## Phase 9: Cache And Prefetch Economy

Borrow Windows SysMain, browser prefetchers, Haiku packagefs read-only caching, and Soliloquy existing V8/cache work:

- Treat free memory as useful cache only while pressure is low.
- Classify caches:
  - V8 bytecode cache
  - texture atlas
  - HTTP cache
  - DNS and TLS session cache
  - profile hot metadata
  - UI bundle assets
- Rank cache entries by restore value:
  - active origin
  - predicted next origin
  - pinned app
  - recent tab
  - cold background tab
- Add prefetch budget:
  - disabled under pressure
  - reduced on battery/thermal constraint
  - local-first for `os://` and UI assets
  - remote only after network ready and active tab stable
- Keep cache eviction deterministic enough for tests.

## Phase 10: Recovery, Watchdogs, And Service Graph

Borrow Solaris SMF, MINIX restartable services, QNX supervision, and ChromeOS recovery:

- Replace shell-order assumptions with a declarative service graph:
  - dependency
  - readiness probe
  - restart policy
  - timeout
  - cgroup class
  - degraded-mode behavior
- Mark services as:
  - `starting`
  - `ready`
  - `degraded`
  - `maintenance`
  - `failed`
- Browser-first stop rule:
  - system not healthy until browser is interactive
  - service graph can be green only after browser interactive mark
- Add watchdog actions:
  - restart renderer
  - restart Servo shell
  - restart `sold` only if session handoff safe
  - boot safe generation
  - disable last plugin generation

## Creative Bets

- Browser budget market: every optional subsystem spends from a frame, memory, IO, and power budget. When budget tightens, optional work stops before user-visible work suffers.
- Tab hibernation receipt: every frozen/discarded tab writes a small receipt with URL, scroll, form dirty bit, session storage summary, and restore cost estimate.
- Service capability ledger: UI can show exactly which service owns which capability and why.
- Cache heat map: runtime endpoint exposes cache value, not just cache size.
- Boot provenance bar: developer mode can show which generation, policy, service graph, and renderer path produced the current frame.
- Failure replay bundle: failed boot or renderer crash emits a small bundle containing service graph, pressure samples, policy, and last lifecycle events.

## Implementation Order

1. Extend runtime telemetry in `sold` and appliance launch scripts.
2. Add QEMU/browser-interactive measurement gate.
3. Create kernel variant matrix and fallback boot contract.
4. Normalize cgroup classes and expose process placement.
5. Implement pressure governor in observe-only mode.
6. Turn pressure governor actions on behind policy flags.
7. Test kernel scheduler, memory, IO, networking, and filesystem patches behind variant flags.
8. Add generation mark-good and rollback semantics.
9. Move broad `sold` APIs toward capability handles.
10. Add shared-memory transport for large frame/resource paths.
11. Split service graph into declarative registry with readiness probes.
12. Harden renderer and plugin sandbox policy.

## Validation Gates

- `cargo fmt --all -- --check`
- `cargo clippy --all-targets --all-features --locked -- -D warnings`
- `cargo test --workspace`
- `bun run check` in `ui/desktop`
- `bun run build` in `ui/desktop`
- `./tools/soliloquy/smoke_macos.sh`
- headless QEMU boot to browser-interactive
- pressure simulation showing active tab preserved while background tabs freeze or discard
- generation rollback simulation

## Non-Goals

- Do not replace the active Linux appliance backend to chase theoretical kernel wins.
- Do not import Vinix code.
- Do not move browser-engine ownership back into Soliloquy root.
- Do not add broad package managers beside Oil for system packages.
- Do not optimize Rust internals without release-mode measurement.
- Do not add telemetry that leaves the device by default.
- Do not ship a custom kernel patch as default until fallback boot, QEMU boot, and target-board browser metrics pass.
