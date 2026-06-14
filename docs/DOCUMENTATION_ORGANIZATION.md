# Documentation Organization Summary

This document summarizes the current documentation structure for Soliloquy OS.

## Current Structure

```
docs/
├── README.md
├── INDEX.md
├── build.md
├── contributing.md
├── v0-architecture.md
├── rv8_linkage_roadmap.md
├── api_contract.md
├── architecture/
│   ├── README.md
│   ├── architecture.md
│   ├── appliance-system.md
│   ├── component_manifest.md
│   └── quick_reference_manifest.md
├── guides/
│   ├── README.md
│   ├── dev_guide.md
│   ├── getting_started_with_testing.md
│   ├── driver_porting.md
│   ├── servo_integration.md
│   └── tools_reference.md
├── testing/
│   ├── README.md
│   ├── testing.md
│   └── test_coverage_broadening.md
├── tutorials/
│   ├── README.md
│   └── getting_started.md
└── ui/
    ├── flatland_bindings.md
    └── flatland_integration.md
```

## Active Tool References

```
tools/
├── rv8_servo_test.sh
└── soliloquy/
    ├── build_ui.sh
    ├── debug.sh
    ├── dev_ui.sh
    └── start.sh
```

## Navigation

| Task | Documentation |
|------|---------------|
| Start with the project | `docs/README.md` |
| Find all docs | `docs/INDEX.md` |
| Build active surfaces | `docs/build.md` |
| Understand the appliance | `docs/v0-architecture.md` |
| Work on runtime linkage | `docs/rv8_linkage_roadmap.md` |
| Use tools | `docs/guides/tools_reference.md` |

## Validation

Documentation should avoid references to removed translation tooling and removed helper scripts. Active runtime checks should use:

```bash
./tools/rv8_servo_test.sh bridge
```
