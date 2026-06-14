# Appliance System Architecture

## Goals

- Keep the base system immutable.
- Restrict user writes to home directories only.
- Keep browser profiles system-managed.
- Keep cross-device sync optional and separate from the immutable base image.
- Stay minimal in the base image while remaining feature rich through optional services and plugins.

## Filesystem Layout

- `/` is an immutable system image.
- `/home/<user>` is the only user-writable persistent area.
- `/var/lib/alpenglow/browser/profiles` stores system-managed browser profiles.
- `/var/lib/alpenglow/system` stores system-owned plugin and policy state.
- `/var/cache/alpenglow` stores system-owned cache data.
- `/var/log/alpenglow` stores system-owned logs.
- `/tmp` is a system scratch area, not a user workspace.

## Browser Data Model

- Browser profile data is not stored as user-managed dotfiles.
- The browser reads and writes explicit system-owned directories.
- User files remain in `/home/<user>`, but history, tabs, cookies, sync metadata, and caches stay under system control.

## Plugin Model

- Plugins are optional downloads rather than part of the immutable base.
- Plugin policy defaults live in `/etc/alpenglow/system.json`.
- Plugin package manifests live in `/etc/alpenglow/plugins/*.json`.
- Writable plugin state lives in `/var/lib/alpenglow/system/plugin-state.json`.
- Writable plugin install state lives in `/var/lib/alpenglow/system/plugin-installs.json`.
- The first plugin is `remote-sync`, with separate feature flags for:
  - file sync
  - photo sync
  - clipboard sync

Package staging now requires a manifest-declared version and checksum match before
the install state is marked verified.

## Service Architecture

The target service architecture borrows from several operating system designs:

- Solaris: declarative service graph, restart behavior, maintenance states, boot environments.
- GNU Hurd: path-backed service views and translator-style namespace composition.
- Capability-oriented systems: service boundaries, driver isolation, structured diagnostics.
- BSD: simple service supervision, `rc` discipline, `devfs`-style device handling, log rotation.
- Redox and Plan 9: treat devices and services as named resources instead of hard-coded global subsystems.
- MINIX 3: restartable critical services.
- Haiku: strong separation between immutable system state and user state.
- ToaruOS and Vinix: lean startup path, explicit boot sequencing, minimal runtime assumptions. Vinix is reference-only because it is GPL-2.0.

The current appliance now carries a small declarative service registry in
`/etc/alpenglow/services.json`. It is intentionally small, but it is the first
step toward a more declarative service graph instead of purely
implicit shell-script ordering.

## Immediate System Changes

These changes are already reflected or scaffolded in the current appliance path:

- Immutable-root assumptions are encoded in the system policy file.
- Browser storage defaults point at system-owned directories.
- The local system service exposes policy and plugin state over authenticated API endpoints.
- The local system service exposes the service registry over authenticated API endpoints.
- Boot scripts create and lock down system runtime directories.
- Plugin state is separated into immutable defaults and writable runtime state.
- System service accounts partition runtime ownership between browser and local system services.

## Near-Term Follow-Up

- Reduce the remaining root-only session path once the display stack can run under a dedicated account.
- Implement plugin download/install state and signature verification.
- Add a generic encrypted sync service and trust model if cross-device sync is enabled.
- Replace ad hoc OpenRC service behavior with a more declarative service registry over time.

## Updates And Rollback

- Update policy lives in `/etc/alpenglow/update-policy.json`.
- Writable update state lives in `/var/lib/alpenglow/system/update-state.json`.
- The current strategy is `atomic-generations` with rollback enabled.
- This mirrors the direction borrowed from Solaris boot environments and modern image-based Linux systems.

## Package Management

- Oil is the declared package manager for Alpenglow system packages.
- Alpenglow should track Oil's `system-packages` direction rather than the simpler Homebrew-style user package workflow.
- Oil is expected to manage generations, manifests, and system/userland package state under `/var/lib/alpenglow/oil`.
- The browser profile vault remains outside package-manager ownership.

## Why These Changes

The operating system research pushed the design in a consistent direction:

- keep the base image boring and immutable,
- move mutable complexity into narrow, auditable services,
- keep device and service policy explicit,
- design for rollback, observability, and recovery from the start.
