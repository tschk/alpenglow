import re

def update_file(path, func):
    with open(path, 'r') as f:
        content = f.read()
    new_content = func(content)
    with open(path, 'w') as f:
        f.write(new_content)

def mod_rs(content):
    content = content.replace("use crate::error::{OilError, Result};", "use std::borrow::Cow;\n\nuse crate::error::{OilError, Result};")
    content = re.sub(
        r"pub struct PackageMetadata \{[^}]+\}",
        "pub struct PackageMetadata<'a> {\n    #[serde(borrow)]\n    pub name: Cow<'a, str>,\n    #[serde(borrow)]\n    pub version: Cow<'a, str>,\n    #[serde(borrow)]\n    pub description: Cow<'a, str>,\n    #[serde(borrow)]\n    pub download_url: Cow<'a, str>,\n    #[serde(borrow)]\n    pub sha256: Option<Cow<'a, str>>,\n    pub installed_size: u64,\n    #[serde(borrow)]\n    pub depends: Vec<Cow<'a, str>>,\n    #[serde(borrow)]\n    pub provides: Vec<Cow<'a, str>>,\n}",
        content
    )
    content = content.replace("pub packages: &'a [PackageMetadata],", "pub packages: &'a [PackageMetadata<'a>],")
    content = content.replace("pub fn new(packages: &'a [PackageMetadata]) -> Self {", "pub fn new(packages: &'a [PackageMetadata<'a>]) -> Self {")
    content = content.replace("pub fn find(&self, name: &str) -> Option<&'a PackageMetadata> {", "pub fn find(&self, name: &str) -> Option<&'a PackageMetadata<'a>> {")
    content = content.replace(") -> Result<Vec<&'a PackageMetadata>> {", ") -> Result<Vec<&'a PackageMetadata<'a>>> {")
    content = content.replace("order: &mut Vec<&'a PackageMetadata>,", "order: &mut Vec<&'a PackageMetadata<'a>>,")

    content = content.replace("visiting.insert(pkg.name.clone());", "visiting.insert(pkg.name.to_string());")
    content = content.replace("scheduled.insert(pkg.name.clone());", "scheduled.insert(pkg.name.to_string());")
    content = content.replace("scheduled.contains(&pkg.name)", "scheduled.contains(pkg.name.as_ref())")
    content = content.replace("visiting.contains(&pkg.name)", "visiting.contains(pkg.name.as_ref())")
    content = content.replace("visiting.remove(&pkg.name)", "visiting.remove(pkg.name.as_ref())")
    content = content.replace("provides_index.entry(prov.as_str())", "provides_index.entry(prov.as_ref())")
    content = content.replace("name_index.entry(pkg.name.as_str())", "name_index.entry(pkg.name.as_ref())")

    content = content.replace("fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata {", "fn sample_pkg<'a>(name: &str, depends: Vec<String>) -> PackageMetadata<'a> {")
    content = re.sub(r"name: \"(.*?)\"\.to_string\(\),", r'name: Cow::Borrowed("\1"),', content)
    content = re.sub(r"name: name\.to_string\(\),", r'name: Cow::Owned(name.to_string()),', content)
    content = re.sub(r"version: \"(.*?)\"\.to_string\(\),", r'version: Cow::Borrowed("\1"),', content)
    content = re.sub(r"description: \"(.*?)\"\.to_string\(\),", r'description: Cow::Borrowed("\1"),', content)
    content = re.sub(r"download_url: \"(.*?)\"\.to_string\(\),", r'download_url: Cow::Borrowed("\1"),', content)
    content = re.sub(r"provides: vec!\[\"(.*?)\"\.to_string\(\), \"(.*?)\"\.to_string\(\)\],", r'provides: vec![Cow::Borrowed("\1"), Cow::Borrowed("\2")],', content)
    content = re.sub(r"depends: depends,", r'depends: depends.into_iter().map(|s| Cow::Owned(s)).collect(),', content)
    content = re.sub(r"provides: vec!\[\],", r'provides: vec![],', content)

    content = content.replace("\"libssl\".to_string()", "std::borrow::Cow::Owned(\"libssl\".to_string())")
    content = content.replace("\"shared\".to_string()", "std::borrow::Cow::Owned(\"shared\".to_string())")
    content = content.replace("description: String::new()", "description: std::borrow::Cow::Borrowed(\"\")")
    content = content.replace("download_url: String::new()", "download_url: std::borrow::Cow::Borrowed(\"\")")
    content = content.replace("pkg.version.as_str()", "pkg.version.as_ref()")
    return content

def apk_rs(content):
    content = content.replace("pub fn refresh(&self) -> Result<Vec<PackageMetadata>>", "pub fn refresh(&self) -> Result<Vec<PackageMetadata<'static>>>")
    content = content.replace("pub fn load(&self) -> Result<Vec<PackageMetadata>>", "pub fn load(&self) -> Result<Vec<PackageMetadata<'static>>>")
    content = content.replace("move || -> Result<Vec<PackageMetadata>> {", "move || -> Result<Vec<PackageMetadata<'static>>> {")
    content = content.replace("let mut all_packages: Vec<PackageMetadata> = Vec::new();", "let mut all_packages: Vec<PackageMetadata<'static>> = Vec::new();")
    content = content.replace("fn write_cache(path: &std::path::Path, packages: &[PackageMetadata])", "fn write_cache(path: &std::path::Path, packages: &[PackageMetadata<'_>])")

    content = re.sub(
        r"fn read_cache\(path: &std::path::Path\) -> Result<Vec<PackageMetadata>> \{\n.*?Ok\(serde_json::from_slice\(&body\)\?\)\n\}",
        "fn read_cache(path: &std::path::Path) -> Result<Vec<PackageMetadata<'static>>> {\n    let decoder = MultiGzDecoder::new(std::fs::File::open(path)?);\n    let body = read_limited(decoder, MAX_DECOMPRESSED_INDEX_SIZE, \"APK index cache\")?;\n    let body = Box::leak(body.into_boxed_slice());\n    Ok(serde_json::from_slice(body)?)\n}",
        content, flags=re.DOTALL
    )

    content = content.replace(") -> Result<Vec<PackageMetadata>> {", ") -> Result<Vec<PackageMetadata<'static>>> {")
    content = re.sub(
        r"    let tar = read_limited\(decoder, MAX_DECOMPRESSED_INDEX_SIZE, \"APKINDEX archive\"\)\?;",
        "    let tar = read_limited(decoder, MAX_DECOMPRESSED_INDEX_SIZE, \"APKINDEX archive\")?;\n    let tar = Box::leak(tar.into_boxed_slice());",
        content
    )
    content = content.replace("fn parse_apk_stanza(\n    stanza: &str,", "fn parse_apk_stanza(\n    stanza: &'static str,")
    content = content.replace("fn parse_apkindex(\n    content: &str,", "fn parse_apkindex(\n    content: &'static str,")

    content = content.replace(") -> Option<PackageMetadata> {", ") -> Option<PackageMetadata<'static>> {")
    content = content.replace(") -> Vec<PackageMetadata> {", ") -> Vec<PackageMetadata<'static>> {")

    content = content.replace("depends.push(dname.to_string());", "depends.push(std::borrow::Cow::Borrowed(dname));")
    content = content.replace("provides.push(pname.to_string());", "provides.push(std::borrow::Cow::Borrowed(pname));")
    content = content.replace("let mut depends: Vec<String> = Vec::new();", "let mut depends: Vec<std::borrow::Cow<'static, str>> = Vec::new();")
    content = content.replace("let mut provides: Vec<String> = Vec::new();", "let mut provides: Vec<std::borrow::Cow<'static, str>> = Vec::new();")

    content = content.replace("name = val.to_string()", "name = val")
    content = content.replace("version = val.to_string()", "version = val")
    content = content.replace("description = val.to_string()", "description = val")

    content = content.replace("let mut name = String::new();", "let mut name = \"\";")
    content = content.replace("let mut version = String::new();", "let mut version = \"\";")
    content = content.replace("let mut description = String::new();", "let mut description = \"\";")

    pkg_create_old = """    Some(PackageMetadata {
        name,
        version,
        description,
        download_url: url,
        sha256: None,
        installed_size,
        depends,
        provides,
    })"""
    pkg_create_new = """    Some(PackageMetadata {
        name: std::borrow::Cow::Borrowed(name),
        version: std::borrow::Cow::Borrowed(version),
        description: std::borrow::Cow::Borrowed(description),
        download_url: std::borrow::Cow::Owned(url),
        sha256: None,
        installed_size,
        depends,
        provides,
    })"""
    content = content.replace(pkg_create_old, pkg_create_new)

    content = content.replace("let mut packages = Vec::new();", "let mut packages = Vec::new();")

    content = content.replace("name: \"testpkg\".into(),", "name: std::borrow::Cow::Borrowed(\"testpkg\"),")
    content = content.replace("version: \"1.0\".into(),", "version: std::borrow::Cow::Borrowed(\"1.0\"),")
    content = content.replace("description: String::new(),", "description: std::borrow::Cow::Borrowed(\"\"),")
    content = content.replace("download_url: \"https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/testpkg-1.0.apk\".into(),", "download_url: std::borrow::Cow::Borrowed(\"https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/testpkg-1.0.apk\"),")
    content = content.replace("description: \"test\".into(),", "description: std::borrow::Cow::Borrowed(\"test\"),")
    content = content.replace("name: \"evil\".into(),", "name: std::borrow::Cow::Borrowed(\"evil\"),")
    content = content.replace("version: \"1\".into(),", "version: std::borrow::Cow::Borrowed(\"1\"),")
    content = content.replace("download_url: \"https://attacker.example/evil.apk\".into(),", "download_url: std::borrow::Cow::Borrowed(\"https://attacker.example/evil.apk\"),")

    return content

def tap_rs(content):
    content = content.replace("pub fn update(&self) -> Result<Vec<PackageMetadata>> {", "pub fn update(&self) -> Result<Vec<PackageMetadata<'static>>> {")
    content = content.replace("pub fn load(&self) -> Result<Vec<PackageMetadata>> {", "pub fn load(&self) -> Result<Vec<PackageMetadata<'static>>> {")

    update_old = """        let packages: Vec<PackageMetadata> = serde_json::from_slice(&body)
            .map_err(|e| OilError::Install(format!("Failed to parse tap index: {e}")))?;

        std::fs::write(&cache_path, &body)?;
        Ok(packages)"""
    update_new = """        let body = Box::leak(body.into_boxed_slice());
        let packages: Vec<PackageMetadata<'static>> = serde_json::from_slice(&*body)
            .map_err(|e| OilError::Install(format!("Failed to parse tap index: {e}")))?;

        std::fs::write(&cache_path, &*body)?;
        Ok(packages)"""
    content = content.replace(update_old, update_new)

    load_old = """        if is_cache_fresh(&cache_path) {
            let data = std::fs::read_to_string(&cache_path)?;
            let packages: Vec<PackageMetadata> = serde_json::from_str(&data)
                .map_err(|e| OilError::Install(format!("Failed to parse tap index: {e}")))?;"""
    load_new = """        if is_cache_fresh(&cache_path) {
            let data = std::fs::read_to_string(&cache_path)?;
            let data = Box::leak(data.into_boxed_str());
            let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(data)
                .map_err(|e| OilError::Install(format!("Failed to parse tap index: {e}")))?;"""
    content = content.replace(load_old, load_new)
    return content

def main_rs(content):
    content = content.replace("mut all: Vec<system::registry::PackageMetadata>,", "mut all: Vec<system::registry::PackageMetadata<'static>>,")
    content = content.replace(") -> Vec<system::registry::PackageMetadata> {", ") -> Vec<system::registry::PackageMetadata<'static>> {")
    content = content.replace("fn load_registry() -> Result<Vec<system::registry::PackageMetadata>> {", "fn load_registry() -> Result<Vec<system::registry::PackageMetadata<'static>>> {")
    content = content.replace("fn refresh_registry() -> Result<Vec<system::registry::PackageMetadata>> {", "fn refresh_registry() -> Result<Vec<system::registry::PackageMetadata<'static>>> {")
    content = content.replace("&'a system::registry::PackageMetadata,", "&'a system::registry::PackageMetadata<'a>,")
    content = content.replace("fn install_package(pkg: &system::registry::PackageMetadata, dest: &Path) -> Result<()> {", "fn install_package(pkg: &system::registry::PackageMetadata<'_>, dest: &Path) -> Result<()> {")
    content = content.replace("pkg.version.as_str()", "pkg.version.as_ref()")
    content = content.replace("latest.version.as_str()", "latest.version.as_ref()")
    return content

def recipe_rs(content):
    content = content.replace("pub fn to_package_metadata(&self) -> PackageMetadata {", "pub fn to_package_metadata<'a>(&self) -> PackageMetadata<'a> {")
    pkg_create = """        PackageMetadata {
            name: self.name.clone(),
            version: self.version.clone(),
            description: self.description.clone(),
            download_url: self.source.url.clone(),
            sha256: self.source.sha256.clone(),
            installed_size: 0,
            depends: self.depends.clone(),
            provides: self.provides.clone(),
        }"""
    pkg_create_new = """        PackageMetadata {
            name: std::borrow::Cow::Owned(self.name.clone()),
            version: std::borrow::Cow::Owned(self.version.clone()),
            description: std::borrow::Cow::Owned(self.description.clone()),
            download_url: std::borrow::Cow::Owned(self.source.url.clone()),
            sha256: self.source.sha256.clone().map(std::borrow::Cow::Owned),
            installed_size: 0,
            depends: self.depends.iter().map(|s| std::borrow::Cow::Owned(s.clone())).collect(),
            provides: self.provides.iter().map(|s| std::borrow::Cow::Owned(s.clone())).collect(),
        }"""
    content = content.replace(pkg_create, pkg_create_new)
    return content

update_file("system/oil/src/system/registry/mod.rs", mod_rs)
update_file("system/oil/src/system/registry/apk.rs", apk_rs)
update_file("system/oil/src/tap.rs", tap_rs)
update_file("system/oil/src/main.rs", main_rs)
update_file("system/oil/src/recipe.rs", recipe_rs)
