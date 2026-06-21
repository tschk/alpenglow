# Alpenglow Appliance Backend Contract

Alpenglow composes an immutable appliance from its native musl+dinit system, staged desktop artifacts, and a fixed runtime state contract.

The shared appliance contract owns:

- immutable rootfs and persistent state manifests,
- service identities and ordering,
- staged browser artifacts,
- package budget policy,
- installer bridge metadata,
- backend metadata validation.

The native backend owns:

- base package installation through Oil,
- libc and init selection,
- rootfs bootstrap,
- service-manager files,
- package manifests,
- kernel packaging.

The package-manager identity is `oil`, sourced from [Oil](https://github.com/tschk/oil). The current sibling checkout still builds a binary named `wax`, so scripts call that binary through the Oil bridge.

Current backend ranking:

1. `alpenglow-native`
