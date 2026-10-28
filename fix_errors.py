import sys

def m(filepath, old, new):
    with open(filepath, 'r') as f:
        content = f.read()
    if old not in content:
        print(f"Warning: could not find in {filepath}:\n{old}")
    content = content.replace(old, new)
    with open(filepath, 'w') as f:
        f.write(content)

# mod.rs fixes
m('system/oil/src/system/registry/mod.rs', "provides_index.entry(prov.as_str()).or_insert(i);", "provides_index.entry(prov.as_ref()).or_insert(i);")
m('system/oil/src/system/registry/mod.rs', "name_index.entry(pkg.name.as_str()).or_insert(i);", "name_index.entry(pkg.name.as_ref()).or_insert(i);")
m('system/oil/src/system/registry/mod.rs', "if scheduled.contains(&pkg.name) {", "if scheduled.contains(pkg.name.as_ref()) {")
m('system/oil/src/system/registry/mod.rs', "if visiting.contains(&pkg.name) {", "if visiting.contains(pkg.name.as_ref()) {")
m('system/oil/src/system/registry/mod.rs', "visiting.insert(pkg.name.clone());", "visiting.insert(pkg.name.to_string());")
m('system/oil/src/system/registry/mod.rs', "visiting.remove(&pkg.name);", "visiting.remove(pkg.name.as_ref());")
m('system/oil/src/system/registry/mod.rs', "scheduled.insert(pkg.name.clone());", "scheduled.insert(pkg.name.to_string());")

# mod.rs lifetimes: PackageIndex<'a, 'p>
m('system/oil/src/system/registry/mod.rs', "pub struct PackageIndex<'a> {\n    pub packages: &'a [PackageMetadata<'a>],", "pub struct PackageIndex<'a, 'p> {\n    pub packages: &'a [PackageMetadata<'p>],")
m('system/oil/src/system/registry/mod.rs', "impl<'a> PackageIndex<'a> {\n    pub fn new(packages: &'a [PackageMetadata<'a>]) -> Self {", "impl<'a, 'p> PackageIndex<'a, 'p> {\n    pub fn new(packages: &'a [PackageMetadata<'p>]) -> Self {")
m('system/oil/src/system/registry/mod.rs', "pub fn find(&self, name: &str) -> Option<&'a PackageMetadata<'a>> {", "pub fn find(&self, name: &str) -> Option<&'a PackageMetadata<'p>> {")
m('system/oil/src/system/registry/mod.rs', "pub fn resolve_install_order<F: Fn(&str) -> bool + Copy>(\n        &self,\n        roots: &[String],\n        skip: F,\n    ) -> Result<Vec<&'a PackageMetadata<'a>>> {", "pub fn resolve_install_order<F: Fn(&str) -> bool + Copy>(\n        &self,\n        roots: &[String],\n        skip: F,\n    ) -> Result<Vec<&'a PackageMetadata<'p>>> {")
m('system/oil/src/system/registry/mod.rs', "let mut order: Vec<&'a PackageMetadata<'a>> = Vec::new();", "let mut order: Vec<&'a PackageMetadata<'p>> = Vec::new();")
m('system/oil/src/system/registry/mod.rs', "fn resolve_install_order_impl(\n        &self,\n        name: &str,\n        order: &mut Vec<&'a PackageMetadata<'a>>,", "fn resolve_install_order_impl(\n        &self,\n        name: &str,\n        order: &mut Vec<&'a PackageMetadata<'p>>,")

# apk.rs: parse_apkindex_archive map to Owned
m('system/oil/src/system/registry/apk.rs',
"""            if name == "APKINDEX" {
                packages.extend(parse_apkindex(
                    &data,
                    mirror,
                    branch,
                    repo,
                    arch,
                ));
            }""",
"""            if name == "APKINDEX" {
                packages.extend(parse_apkindex(
                    &data,
                    mirror,
                    branch,
                    repo,
                    arch,
                ).into_iter().map(|p| PackageMetadata {
                    name: Cow::Owned(p.name.into_owned()),
                    version: Cow::Owned(p.version.into_owned()),
                    description: Cow::Owned(p.description.into_owned()),
                    download_url: Cow::Owned(p.download_url.into_owned()),
                    sha256: p.sha256.map(|s| Cow::Owned(s.into_owned())),
                    installed_size: p.installed_size,
                    depends: p.depends.into_iter().map(|s| Cow::Owned(s.into_owned())).collect(),
                    provides: p.provides.into_iter().map(|s| Cow::Owned(s.into_owned())).collect(),
                }));
            }""")

# main.rs: change 'static to '_ in references
m('system/oil/src/main.rs', "fn install_package(pkg: &system::registry::PackageMetadata<'static>, dest: &Path) -> Result<()> {", "fn install_package(pkg: &system::registry::PackageMetadata<'_>, dest: &Path) -> Result<()> {")
m('system/oil/src/main.rs', "fn execute_install_plan<'a>(\n    state: &mut system::state::SystemState,\n    order: Vec<&'a system::registry::PackageMetadata<'static>>,\n    dest: &Path,\n) -> Result<()> {", "fn execute_install_plan<'a, 'p>(\n    state: &mut system::state::SystemState,\n    order: Vec<&'a system::registry::PackageMetadata<'p>>,\n    dest: &Path,\n) -> Result<()> {")
m('system/oil/src/main.rs', "    &'a system::registry::PackageMetadata<'static>,", "    &'a system::registry::PackageMetadata<'p>,")
m('system/oil/src/main.rs', "fn plan_upgrades<'a>(", "fn plan_upgrades<'a, 'p>(")
m('system/oil/src/main.rs', "registry: &'a system::registry::PackageIndex,", "registry: &'a system::registry::PackageIndex<'a, 'p>,")
m('system/oil/src/main.rs', "fn resolve_install_requirements<'a>(", "fn resolve_install_requirements<'a, 'p>(")
m('system/oil/src/main.rs', "fn list_available_packages(", "fn list_available_packages<'a, 'p>(")
m('system/oil/src/main.rs', "registry: &system::registry::PackageIndex,", "registry: &system::registry::PackageIndex<'a, 'p>,")
