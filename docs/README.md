# Alpenglow Docs

Current docs cover the active Cargo, appliance backend, kernel, install, Servo staging, and `sold` paths.

Browser-engine work lives in `../rv8`; desktop-environment work lives in `../soliloquy`.

Alpenglow owns the Linux appliance, `sold` bridge, backend abstraction, kernel policy, and install path. The active backend direction is Oasis-style composition with Void musl and runit. Servo is launched with its browser chrome disabled so the Soliloquy desktop controls do not double up.

The macOS desktop path uses Crepuscularity GPUI chrome with Servo's built-in chrome disabled. Its smoke check is dry-run only; the real launcher can start or reuse `sold` for local runtime APIs, but it must not load the Svelte appliance chrome. See [Browser Chrome](./browser_chrome.md).

## Core

- [Index](./INDEX.md)
- [Build](./build.md)
- [Contributing](./contributing.md)
- [V0 Architecture](./v0-architecture.md)
- [Appliance System](./architecture/appliance-system.md)
- [Browser-Centric OS Optimization](./architecture/browser-centric-os.md)
- [Soliloquy Alpine OS Optimization Plan](./architecture/os-optimization-plan.md)
- [API Contract](./api_contract.md)
- [Browser Chrome](./browser_chrome.md)
- [RV8 Linkage Roadmap](./rv8_linkage_roadmap.md)
- [Testing](./testing/README.md)
