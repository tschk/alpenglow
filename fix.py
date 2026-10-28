import sys

def m(filepath, old, new):
    with open(filepath, 'r') as f:
        content = f.read()
    if old not in content:
        print(f"Warning: could not find in {filepath}:\n{old}")
    content = content.replace(old, new)
    with open(filepath, 'w') as f:
        f.write(content)

# mod.rs
m('system/oil/src/system/registry/mod.rs',
"""#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackageMetadata {
    pub name: String,
    pub version: String,
    pub description: String,
    pub download_url: String,
    pub sha256: Option<String>,
    pub installed_size: u64,
    pub depends: Vec<String>,
    pub provides: Vec<String>,
}""",
"""use std::borrow::Cow;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PackageMetadata<'a> {
    pub name: Cow<'a, str>,
    pub version: Cow<'a, str>,
    pub description: Cow<'a, str>,
    pub download_url: Cow<'a, str>,
    pub sha256: Option<Cow<'a, str>>,
    pub installed_size: u64,
    pub depends: Vec<Cow<'a, str>>,
    pub provides: Vec<Cow<'a, str>>,
}""")

m('system/oil/src/system/registry/mod.rs', "pub struct PackageIndex<'a> {\n    pub packages: &'a [PackageMetadata],", "pub struct PackageIndex<'a> {\n    pub packages: &'a [PackageMetadata<'a>],")
m('system/oil/src/system/registry/mod.rs', "pub fn new(packages: &'a [PackageMetadata]) -> Self {", "pub fn new(packages: &'a [PackageMetadata<'a>]) -> Self {")
m('system/oil/src/system/registry/mod.rs', "pub fn find(&self, name: &str) -> Option<&'a PackageMetadata> {", "pub fn find(&self, name: &str) -> Option<&'a PackageMetadata<'a>> {")

m('system/oil/src/system/registry/mod.rs',
"""    pub fn resolve_install_order<F: Fn(&str) -> bool + Copy>(
        &self,
        roots: &[String],
        skip: F,
    ) -> Result<Vec<&'a PackageMetadata>> {
        let mut order = Vec::new();""",
"""    pub fn resolve_install_order<F: Fn(&str) -> bool + Copy>(
        &self,
        roots: &[String],
        skip: F,
    ) -> Result<Vec<&'a PackageMetadata<'a>>> {
        let mut order = Vec::new();""")

m('system/oil/src/system/registry/mod.rs', "fn resolve_install_order_impl(\n        &self,\n        name: &str,\n        order: &mut Vec<&'a PackageMetadata>,", "fn resolve_install_order_impl(\n        &self,\n        name: &str,\n        order: &mut Vec<&'a PackageMetadata<'a>>,")

# apk.rs
m('system/oil/src/system/registry/apk.rs', "pub fn refresh(&self) -> Result<Vec<PackageMetadata>> {", "pub fn refresh(&self) -> Result<Vec<PackageMetadata<'static>>> {")
m('system/oil/src/system/registry/apk.rs', "pub fn load(&self) -> Result<Vec<PackageMetadata>> {", "pub fn load(&self) -> Result<Vec<PackageMetadata<'static>>> {")
m('system/oil/src/system/registry/apk.rs', "move || -> Result<Vec<PackageMetadata>> {", "move || -> Result<Vec<PackageMetadata<'static>>> {")
m('system/oil/src/system/registry/apk.rs', "let mut all_packages: Vec<PackageMetadata> = Vec::new();", "let mut all_packages: Vec<PackageMetadata<'static>> = Vec::new();")

m('system/oil/src/system/registry/apk.rs',
"""            if let Ok(pkgs) = handle.join().unwrap() {
                all_packages.extend(pkgs);
            }""",
"""            if let Ok(pkgs) = handle.join().unwrap() {
                all_packages.extend(pkgs.into_iter().map(|p| PackageMetadata {
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

m('system/oil/src/system/registry/apk.rs', "fn read_cache(path: &std::path::Path) -> Result<Vec<PackageMetadata>> {", "fn read_cache(path: &std::path::Path) -> Result<Vec<PackageMetadata<'static>>> {")
m('system/oil/src/system/registry/apk.rs', "fn write_cache(path: &std::path::Path, packages: &[PackageMetadata]) -> Result<()> {", "fn write_cache(path: &std::path::Path, packages: &[PackageMetadata<'_>]) -> Result<()> {")

m('system/oil/src/system/registry/apk.rs',
"""fn parse_apkindex_archive(
    bytes: &[u8],
    mirror: &str,
    branch: &str,
    repo: &str,
    arch: &str,
) -> Result<Vec<PackageMetadata>> {""",
"""use std::borrow::Cow;

fn parse_apkindex_archive<'a>(
    bytes: &'a [u8],
    mirror: &str,
    branch: &str,
    repo: &str,
    arch: &str,
) -> Result<Vec<PackageMetadata<'static>>> {""")

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

m('system/oil/src/system/registry/apk.rs',
"""fn parse_apk_stanza(
    stanza: &str,
    mirror: &str,
    branch: &str,
    repo: &str,
    arch: &str,
) -> Option<PackageMetadata> {
    let mut name = String::new();
    let mut version = String::new();
    let mut description = String::new();
    let mut installed_size: u64 = 0;
    let mut depends: Vec<String> = Vec::new();
    let mut provides: Vec<String> = Vec::new();

    for line in stanza.lines() {
        if line.len() < 2 || line.as_bytes()[1] != b':' {
            continue;
        }
        let key = &line[..1];
        let val = line[2..].trim();

        match key {
            "P" => name = val.to_string(),
            "V" => version = val.to_string(),
            "T" => description = val.to_string(),
            "I" => installed_size = val.parse().unwrap_or(0),
            "D" => {
                for dep in val.split_whitespace() {
                    let dname = super::parse_dep_name(dep);
                    if !dname.is_empty() && !dname.starts_with('!') {
                        depends.push(dname.to_string());
                    }
                }
            }
            "p" => {
                for prov in val.split_whitespace() {
                    let pname = super::parse_dep_name(prov);
                    if !pname.is_empty() {
                        provides.push(pname.to_string());
                    }
                }
            }
            _ => {}
        }
    }

    if name.is_empty() || version.is_empty() {
        return None;
    }

    let url = format!("{mirror}/{branch}/{repo}/{arch}/{name}-{version}.apk");
    Some(PackageMetadata {
        name,
        version,
        description,
        download_url: url,
        sha256: None,
        installed_size,
        depends,
        provides,
    })
}""",
"""fn parse_apk_stanza<'a>(
    stanza: &'a str,
    mirror: &str,
    branch: &str,
    repo: &str,
    arch: &str,
) -> Option<PackageMetadata<'a>> {
    let mut name = Cow::Borrowed("");
    let mut version = Cow::Borrowed("");
    let mut description = Cow::Borrowed("");
    let mut installed_size: u64 = 0;
    let mut depends: Vec<Cow<'a, str>> = Vec::new();
    let mut provides: Vec<Cow<'a, str>> = Vec::new();

    for line in stanza.lines() {
        if line.len() < 2 || line.as_bytes()[1] != b':' {
            continue;
        }
        let key = &line[..1];
        let val = line[2..].trim();

        match key {
            "P" => name = Cow::Borrowed(val),
            "V" => version = Cow::Borrowed(val),
            "T" => description = Cow::Borrowed(val),
            "I" => installed_size = val.parse().unwrap_or(0),
            "D" => {
                for dep in val.split_whitespace() {
                    let dname = super::parse_dep_name(dep);
                    if !dname.is_empty() && !dname.starts_with('!') {
                        depends.push(Cow::Borrowed(dname));
                    }
                }
            }
            "p" => {
                for prov in val.split_whitespace() {
                    let pname = super::parse_dep_name(prov);
                    if !pname.is_empty() {
                        provides.push(Cow::Borrowed(pname));
                    }
                }
            }
            _ => {}
        }
    }

    if name.is_empty() || version.is_empty() {
        return None;
    }

    let url = format!("{mirror}/{branch}/{repo}/{arch}/{}-{}.apk", name, version);
    Some(PackageMetadata {
        name,
        version,
        description,
        download_url: Cow::Owned(url),
        sha256: None,
        installed_size,
        depends,
        provides,
    })
}""")

m('system/oil/src/system/registry/apk.rs',
"""fn parse_apkindex(
    content: &str,
    mirror: &str,
    branch: &str,
    repo: &str,
    arch: &str,
) -> Vec<PackageMetadata> {""",
"""fn parse_apkindex<'a>(
    content: &'a str,
    mirror: &str,
    branch: &str,
    repo: &str,
    arch: &str,
) -> Vec<PackageMetadata<'a>> {""")

# tests in mod.rs
import re

with open('system/oil/src/system/registry/mod.rs', 'r') as f:
    content = f.read()

content = re.sub(
    r'PackageMetadata \{\s*name:\s*(.*?),\s*version:\s*(.*?),\s*description:\s*(.*?),\s*download_url:\s*(.*?),\s*sha256:\s*(.*?),\s*installed_size:\s*(.*?),\s*depends:\s*(.*?),\s*provides:\s*(.*?),\s*\}',
    lambda m: f"PackageMetadata {{\n            name: std::borrow::Cow::Owned({m.group(1)}),\n            version: std::borrow::Cow::Owned({m.group(2)}),\n            description: std::borrow::Cow::Owned({m.group(3)}),\n            download_url: std::borrow::Cow::Owned({m.group(4)}),\n            sha256: {m.group(5)}.map(std::borrow::Cow::Owned),\n            installed_size: {m.group(6)},\n            depends: {m.group(7)}.into_iter().map(std::borrow::Cow::Owned).collect(),\n            provides: {m.group(8)}.into_iter().map(std::borrow::Cow::Owned).collect(),\n        }}",
    content
)
content = content.replace("fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata {", "fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata<'static> {")
with open('system/oil/src/system/registry/mod.rs', 'w') as f:
    f.write(content)

# tests in apk.rs
with open('system/oil/src/system/registry/apk.rs', 'r') as f:
    content = f.read()

content = re.sub(
    r'PackageMetadata \{\s*name:\s*(.*?),\s*version:\s*(.*?),\s*description:\s*(.*?),\s*download_url:\s*(.*?),\s*sha256:\s*(.*?),\s*installed_size:\s*(.*?),\s*depends:\s*(.*?),\s*provides:\s*(.*?),\s*\}',
    lambda m: f"PackageMetadata {{\n            name: std::borrow::Cow::Owned({m.group(1)}),\n            version: std::borrow::Cow::Owned({m.group(2)}),\n            description: std::borrow::Cow::Owned({m.group(3)}),\n            download_url: std::borrow::Cow::Owned({m.group(4)}),\n            sha256: {m.group(5)}.map(std::borrow::Cow::Owned),\n            installed_size: {m.group(6)},\n            depends: {m.group(7)}.into_iter().map(std::borrow::Cow::Owned).collect(),\n            provides: {m.group(8)}.into_iter().map(std::borrow::Cow::Owned).collect(),\n        }}",
    content
)
with open('system/oil/src/system/registry/apk.rs', 'w') as f:
    f.write(content)

# tap.rs
m('system/oil/src/tap.rs', "pub fn update(&self) -> Result<Vec<PackageMetadata>> {", "pub fn update(&self) -> Result<Vec<PackageMetadata<'static>>> {")
m('system/oil/src/tap.rs', "let packages: Vec<PackageMetadata> = serde_json::from_slice(&body)", "let packages: Vec<PackageMetadata<'static>> = serde_json::from_slice(&body)")
m('system/oil/src/tap.rs', "pub fn load(&self) -> Result<Vec<PackageMetadata>> {", "pub fn load(&self) -> Result<Vec<PackageMetadata<'static>>> {")
m('system/oil/src/tap.rs', "let packages: Vec<PackageMetadata> = serde_json::from_str(&data)", "let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(&data)")

with open('system/oil/src/tap.rs', 'r') as f:
    content = f.read()
content = re.sub(
    r'PackageMetadata \{\s*name:\s*(.*?),\s*version:\s*(.*?),\s*description:\s*(.*?),\s*download_url:\s*(.*?),\s*sha256:\s*(.*?),\s*installed_size:\s*(.*?),\s*depends:\s*(.*?),\s*provides:\s*(.*?),\s*\}',
    lambda m: f"PackageMetadata {{\n            name: std::borrow::Cow::Owned({m.group(1)}),\n            version: std::borrow::Cow::Owned({m.group(2)}),\n            description: std::borrow::Cow::Owned({m.group(3)}),\n            download_url: std::borrow::Cow::Owned({m.group(4)}),\n            sha256: {m.group(5)}.map(std::borrow::Cow::Owned),\n            installed_size: {m.group(6)},\n            depends: {m.group(7)}.into_iter().map(std::borrow::Cow::Owned).collect(),\n            provides: {m.group(8)}.into_iter().map(std::borrow::Cow::Owned).collect(),\n        }}",
    content
)
with open('system/oil/src/tap.rs', 'w') as f:
    f.write(content)


# recipe.rs
m('system/oil/src/recipe.rs',
"""    pub fn to_package_metadata(&self) -> PackageMetadata {
        PackageMetadata {
            name: self.name.clone(),
            version: self.version.clone(),
            description: self.description.clone(),
            download_url: self.source.url.clone(),
            sha256: self.source.sha256.clone(),
            installed_size: 0,
            depends: self.depends.clone(),
            provides: self.provides.clone(),
        }
    }""",
"""    pub fn to_package_metadata(&self) -> PackageMetadata<'static> {
        PackageMetadata {
            name: std::borrow::Cow::Owned(self.name.clone()),
            version: std::borrow::Cow::Owned(self.version.clone()),
            description: std::borrow::Cow::Owned(self.description.clone()),
            download_url: std::borrow::Cow::Owned(self.source.url.clone()),
            sha256: self.source.sha256.clone().map(std::borrow::Cow::Owned),
            installed_size: 0,
            depends: self.depends.iter().map(|s| std::borrow::Cow::Owned(s.clone())).collect(),
            provides: self.provides.iter().map(|s| std::borrow::Cow::Owned(s.clone())).collect(),
        }
    }""")


# main.rs
m('system/oil/src/main.rs', "mut all: Vec<system::registry::PackageMetadata>,", "mut all: Vec<system::registry::PackageMetadata<'static>>,")
m('system/oil/src/main.rs', ") -> Vec<system::registry::PackageMetadata> {", ") -> Vec<system::registry::PackageMetadata<'static>> {")
m('system/oil/src/main.rs', "fn load_registry() -> Result<Vec<system::registry::PackageMetadata>> {", "fn load_registry() -> Result<Vec<system::registry::PackageMetadata<'static>>> {")
m('system/oil/src/main.rs', "fn refresh_registry() -> Result<Vec<system::registry::PackageMetadata>> {", "fn refresh_registry() -> Result<Vec<system::registry::PackageMetadata<'static>>> {")
m('system/oil/src/main.rs', "    &'a system::registry::PackageMetadata,", "    &'a system::registry::PackageMetadata<'static>,")
m('system/oil/src/main.rs', "fn execute_install_plan<'a>(\n    state: &mut system::state::SystemState,\n    order: Vec<&'a system::registry::PackageMetadata>,\n    dest: &Path,\n) -> Result<()> {", "fn execute_install_plan<'a>(\n    state: &mut system::state::SystemState,\n    order: Vec<&'a system::registry::PackageMetadata<'static>>,\n    dest: &Path,\n) -> Result<()> {")
m('system/oil/src/main.rs', "fn install_package(pkg: &system::registry::PackageMetadata, dest: &Path) -> Result<()> {", "fn install_package(pkg: &system::registry::PackageMetadata<'static>, dest: &Path) -> Result<()> {")

# in main.rs, fix clone / as_str usages:
with open('system/oil/src/main.rs', 'r') as f:
    content = f.read()
content = content.replace("state.mark_installed(&pkg.name, Some(pkg.version.as_str()));", "state.mark_installed(&pkg.name, Some(&pkg.version));")
content = content.replace("state.mark_installed(name, Some(latest.version.as_str()));", "state.mark_installed(name, Some(&latest.version));")
with open('system/oil/src/main.rs', 'w') as f:
    f.write(content)
