import sys

def m(filepath, old, new):
    with open(filepath, 'r') as f:
        content = f.read()
    if old not in content:
        print(f"Warning: could not find in {filepath}:\n{old}")
    content = content.replace(old, new)
    with open(filepath, 'w') as f:
        f.write(content)

m('system/oil/src/main.rs', "    index: &'a PackageIndex<'a>,", "    index: &'a PackageIndex<'a, 'p>,")
m('system/oil/src/main.rs', "fn get_installed_packages<'a>(", "fn get_installed_packages<'a, 'p>(")

m('system/oil/src/system/registry/mod.rs', "order: &mut Vec<&'a PackageMetadata>,", "order: &mut Vec<&'a PackageMetadata<'p>>,")

# apk.rs: parse_apkindex_archive map to Owned
m('system/oil/src/system/registry/apk.rs',
"""        if let Ok(content) = std::str::from_utf8(&tar[data_start..data_end])
            .map_err(|e| OilError::Install(format!("APKINDEX is not UTF-8: {e}")))
        {
            return Ok(parse_apkindex(content, mirror, branch, repo, arch));
        }""",
"""        if let Ok(content) = std::str::from_utf8(&tar[data_start..data_end])
            .map_err(|e| OilError::Install(format!("APKINDEX is not UTF-8: {e}")))
        {
            let pkgs = parse_apkindex(content, mirror, branch, repo, arch);
            return Ok(pkgs.into_iter().map(|p| PackageMetadata {
                name: std::borrow::Cow::Owned(p.name.into_owned()),
                version: std::borrow::Cow::Owned(p.version.into_owned()),
                description: std::borrow::Cow::Owned(p.description.into_owned()),
                download_url: std::borrow::Cow::Owned(p.download_url.into_owned()),
                sha256: p.sha256.map(|s| std::borrow::Cow::Owned(s.into_owned())),
                installed_size: p.installed_size,
                depends: p.depends.into_iter().map(|s| std::borrow::Cow::Owned(s.into_owned())).collect(),
                provides: p.provides.into_iter().map(|s| std::borrow::Cow::Owned(s.into_owned())).collect(),
            }).collect());
        }""")

m('system/oil/src/main.rs', "fn execute_install_plan<'a>(", "fn execute_install_plan<'a, 'p>(")
m('system/oil/src/main.rs', "order: Vec<&'a system::registry::PackageMetadata>,", "order: Vec<&'a system::registry::PackageMetadata<'p>>,")
m('system/oil/src/main.rs', "registry: &'a system::registry::PackageIndex,", "registry: &'a system::registry::PackageIndex<'a, 'p>,")
m('system/oil/src/main.rs', "fn resolve_install_requirements<'a>(", "fn resolve_install_requirements<'a, 'p>(")
m('system/oil/src/main.rs', "fn list_available_packages(", "fn list_available_packages<'a, 'p>(")
m('system/oil/src/main.rs', "registry: &system::registry::PackageIndex,", "registry: &system::registry::PackageIndex<'a, 'p>,")
