// gpui-ce links X11 as well as Wayland. A static (musl) link of the GUI does not follow
// libxkbcommon-x11 -> libxcb-xkb -> libxcb -> libXau/libXdmcp through shared-library NEEDED
// entries, so name the archives explicitly. No-op for other targets and non-GUI builds.
fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    let gui = std::env::var_os("CARGO_FEATURE_GUI").is_some();
    let linux_musl = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux")
        && std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("musl");
    if gui && linux_musl {
        for lib in ["xcb-xkb", "xcb", "Xau", "Xdmcp"] {
            println!("cargo:rustc-link-lib={lib}");
        }
    }
}
