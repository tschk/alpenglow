use criterion::{black_box, criterion_group, criterion_main, Criterion};

#[path = "../src/system/registry/mod.rs"]
mod registry;
use registry::{PackageIndex, PackageMetadata};

// Dummy errors module to satisfy registry/mod.rs dependencies
#[path = "../src/error.rs"]
pub mod error;

fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata {
    PackageMetadata {
        name: name.to_string(),
        version: "1.0.0".to_string(),
        description: String::new(),
        download_url: String::new(),
        sha256: None,
        installed_size: 0,
        depends,
        provides: vec![],
    }
}

fn generate_packages(count: usize) -> Vec<PackageMetadata> {
    let mut pkgs = Vec::with_capacity(count);
    for i in 0..count {
        let depends = if i > 0 {
            vec![format!("pkg{}", i - 1)]
        } else {
            vec![]
        };
        pkgs.push(sample_pkg(&format!("pkg{}", i), depends));
    }
    pkgs
}

fn criterion_benchmark(c: &mut Criterion) {
    let pkgs = generate_packages(1000);
    let index = PackageIndex::new(&pkgs);
    let roots = vec!["pkg999".to_string()];

    c.bench_function("resolve_install_order", |b| {
        b.iter(|| {
            let order = index.resolve_install_order(black_box(&roots), |_| false).unwrap();
            black_box(order);
        })
    });
}

criterion_group!(benches, criterion_benchmark);
criterion_main!(benches);
