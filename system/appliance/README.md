# Soliloquy Appliance Backend Contract

Soliloquy composes an immutable browser appliance from a small base system, staged browser artifacts, and a fixed runtime state contract. The base system is selected through a backend. The active direction is Oasis-style composition with a Void musl and runit backend.

The shared appliance contract owns:

- immutable rootfs and persistent state manifests,
- service identities and ordering,
- staged browser artifacts,
- package budget policy,
- installer bridge metadata,
- backend metadata validation.

Backends own:

- base package installation,
- libc and init selection,
- rootfs bootstrap,
- service-manager files,
- distro package manifests,
- distro-specific kernel packaging.

The installer bridge is `../oil`, currently via its `wax` binary. It is used for managed package additions into a composed rootfs with `WAX_SYSTEM_PREFIX`. Void base bootstrap still uses XBPS until Oil exposes a Void registry backend.

Current backend ranking:

1. `void-musl-runit`
2. `alpine-openrc`
3. `chimera-musl-dinit`
4. `oasis-static`

The `oasis-static` backend is the composition model. It is not the immediate runtime backend because Servo, V8, media, GPU, and Wayland dependencies still need the broader shared-library surface provided by Void or Alpine.
