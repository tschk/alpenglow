// gpui-ce links X11 as well as Wayland. A static (musl) link of the GUI does not follow
// libxkbcommon-x11 -> libxcb-xkb -> libxcb -> libXau/libXdmcp through shared-library NEEDED
// entries, so name the archives explicitly. No-op for other targets and non-GUI builds.
//
// The GUI also needs a dynamically linked musl binary at runtime: wayland-client and wgpu
// dlopen libwayland-client/libvulkan, which a static musl executable cannot do (it panics
// with NoWaylandLib). Build with `-C target-feature=-crt-static`. Raw rust-lld, unlike a cc
// driver, neither records the program interpreter nor adds musl's start file, so do both
// here; without `_start` the binary has entry point 0 and crashes before main.
use std::path::PathBuf;

fn native_search_dirs() -> Vec<PathBuf> {
    let flags = std::env::var("CARGO_ENCODED_RUSTFLAGS").unwrap_or_default();
    flags
        .split('\x1f')
        .filter_map(|flag| flag.strip_prefix("native="))
        .map(PathBuf::from)
        .collect()
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=CARGO_ENCODED_RUSTFLAGS");
    let gui = std::env::var_os("CARGO_FEATURE_GUI").is_some();
    let linux_musl = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux")
        && std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("musl");
    if gui && linux_musl {
        for lib in ["xcb-xkb", "xcb", "Xau", "Xdmcp"] {
            println!("cargo:rustc-link-lib={lib}");
        }
        let crt_static = std::env::var("CARGO_CFG_TARGET_FEATURE")
            .map(|features| features.split(',').any(|feature| feature == "crt-static"))
            .unwrap_or(false);
        if !crt_static {
            let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
            println!("cargo:rustc-link-arg-bins=--dynamic-linker=/lib/ld-musl-{arch}.so.1");
            // `-L native=<sysroot>/usr/lib` comes from RUSTFLAGS; musl-dev ships Scrt1.o there.
            // Absent when a cc driver links (it supplies the start file itself).
            for dir in native_search_dirs() {
                let start_file = dir.join("Scrt1.o");
                if start_file.is_file() {
                    println!("cargo:rustc-link-arg-bins={}", start_file.display());
                    break;
                }
            }
        }
    }
}
