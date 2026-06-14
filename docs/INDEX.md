# Alpenglow Documentation Index

Alpenglow is currently documented around Cargo, the appliance backend flow, `sold`, kernel policy, SolFS, and Soliloquy desktop staging.

## Start Here

- [Project README](../readme.md)
- [Build Guide](./build.md)
- [Contributing](./contributing.md)
- [V0 Architecture](./v0-architecture.md)

## Runtime And Appliance

- [Appliance System Architecture](./architecture/appliance-system.md)
- [Soliloquy Alpine OS Optimization Plan](./architecture/os-optimization-plan.md)
- [API Contract](./api_contract.md)
- [RV8 Linkage Roadmap](./rv8_linkage_roadmap.md)
- [Browser Optimizations](./browser_optimizations.md)

## Guides

- [Developer Guide](./guides/dev_guide.md)
- [Tools Reference](./guides/tools_reference.md)

## Testing

- [Testing README](./testing/README.md)

## Current Commands

```bash
cargo test -p sold
./install.sh --check
./system/appliance/scripts/select-backend.sh
```
