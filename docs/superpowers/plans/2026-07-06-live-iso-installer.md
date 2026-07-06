# Live ISO Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a live ISO release path with a Crepuscularity TUI installer, a Crepuscularity desktop installer entrypoint, and GitHub release assets.

**Architecture:** One Rust installer core validates targets and writes a prepared Alpenglow disk image. TUI, GUI, and host executable entrypoints call the same core. Release automation builds the existing disk image, compresses it, writes checksums, and packages a live ISO when host tools are available.

**Tech Stack:** Rust, Cargo, shell, GitHub Actions, Crepuscularity TUI, optional Crepuscularity GPUI.

---

### Task 1: Installer Core

**Files:**
- Create: `system/installer/Cargo.toml`
- Create: `system/installer/src/lib.rs`
- Create: `system/installer/tests/install.rs`
- Modify: `Cargo.toml`

- [ ] **Step 1: Write failing tests**

```rust
use alpenglow_installer::{install_image, validate_target};
use std::fs;

#[test]
fn rejects_non_device_targets_by_default() {
    let dir = tempfile::tempdir().unwrap();
    let target = dir.path().join("disk.img");
    fs::write(&target, []).unwrap();
    let err = validate_target(&target, false).unwrap_err();
    assert!(err.to_string().contains("refusing"));
}

#[test]
fn copies_image_when_allowed() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source.img");
    let target = dir.path().join("target.img");
    fs::write(&source, b"alpenglow").unwrap();
    install_image(&source, &target, true).unwrap();
    assert_eq!(fs::read(&target).unwrap(), b"alpenglow");
}
```

- [ ] **Step 2: Run failing test**

Run: `cargo test -p alpenglow-installer`
Expected: FAIL because the package does not exist.

- [ ] **Step 3: Implement minimal core**

Create a library with `validate_target` and `install_image`.

- [ ] **Step 4: Run passing test**

Run: `cargo test -p alpenglow-installer`
Expected: PASS.

### Task 2: Crepuscularity TUI

**Files:**
- Create: `system/installer/src/bin/alpenglow-install-tui.rs`
- Create: `system/installer/ui/tui.crepus`

- [ ] **Step 1: Add render smoke test or cargo check**

Run: `cargo check -p alpenglow-installer --bin alpenglow-install-tui`
Expected: PASS.

### Task 3: GUI Entry

**Files:**
- Create: `system/installer/src/bin/alpenglow-install-gui.rs`

- [ ] **Step 1: Add feature-gated binary**

Run: `cargo check -p alpenglow-installer --features gui --bin alpenglow-install-gui`
Expected: PASS on a host with the selected GPUI platform feature.

### Task 4: Release Assets

**Files:**
- Create: `scripts/release-assets.sh`
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Shell syntax check**

Run: `sh -n scripts/release-assets.sh`
Expected: PASS.

- [ ] **Step 2: Workflow publishes assets**

Run: `git diff --check .github/workflows/release.yml scripts/release-assets.sh`
Expected: PASS.
