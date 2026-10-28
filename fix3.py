import sys

def m(filepath, old, new):
    with open(filepath, 'r') as f:
        content = f.read()
    if old not in content:
        print(f"Warning: could not find in {filepath}:\n{old}")
    content = content.replace(old, new)
    with open(filepath, 'w') as f:
        f.write(content)

m('system/oil/src/recipe.rs', "assert_eq!(meta.sha256, recipe.source.sha256);", "assert_eq!(meta.sha256, recipe.source.sha256.clone().map(std::borrow::Cow::Owned));")

m('system/oil/src/system/registry/mod.rs', "p.name.as_str()", "p.name.as_ref()")
m('system/oil/src/system/registry/mod.rs', "pkg.version.as_str()", "pkg.version.as_ref()")

m('system/oil/src/system/registry/mod.rs',
"""fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata<'static> {
    PackageMetadata {
        name: name.to_string(),
        version: "1.0.0".to_string(),
        description: String::new(),
        download_url: String::new(),
        sha256: None,
        installed_size: 0,
        depends,""",
"""fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata<'static> {
    PackageMetadata {
        name: std::borrow::Cow::Owned(name.to_string()),
        version: std::borrow::Cow::Owned("1.0.0".to_string()),
        description: std::borrow::Cow::Owned(String::new()),
        download_url: std::borrow::Cow::Owned(String::new()),
        sha256: None,
        installed_size: 0,
        depends: depends.into_iter().map(std::borrow::Cow::Owned).collect(),""")
