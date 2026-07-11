use std::time::Instant;

fn main() {
    let start = Instant::now();
    // Simulate what `load_registry` does
    let apk = system::registry::apk::ApkRegistry::alpine_default().load().unwrap();
    let mut all = apk.packages;

    // Create lots of taps for bench
    let mut threads = vec![];
    for i in 0..100 {
        // ...
    }
}
