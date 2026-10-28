import re

def replace_in_file(filepath, rules):
    with open(filepath, 'r') as f:
        text = f.read()
    for o, n in rules:
        text = text.replace(o, n)
    with open(filepath, 'w') as f:
        f.write(text)

rules_mod = [
    ("#[derive(Debug, Clone, Serialize, Deserialize)]\npub struct PackageMetadata {\n    pub name: String,\n    pub version: String,\n    pub description: String,\n    pub download_url: String,\n    pub sha256: Option<String>,\n    pub installed_size: u64,\n    pub depends: Vec<String>,\n    pub provides: Vec<String>,\n}", "use std::borrow::Cow;\n\n#[derive(Debug, Clone, Serialize, Deserialize)]\npub struct PackageMetadata<'a> {\n    #[serde(borrow)]\n    pub name: Cow<'a, str>,\n    #[serde(borrow)]\n    pub version: Cow<'a, str>,\n    #[serde(borrow)]\n    pub description: Cow<'a, str>,\n    #[serde(borrow)]\n    pub download_url: Cow<'a, str>,\n    #[serde(borrow)]\n    pub sha256: Option<Cow<'a, str>>,\n    pub installed_size: u64,\n    #[serde(borrow)]\n    pub depends: Vec<Cow<'a, str>>,\n    #[serde(borrow)]\n    pub provides: Vec<Cow<'a, str>>,\n}"),
    ("pub struct PackageIndex<'a> {", "pub struct PackageIndex<'a, 'b> {"),
    ("pub packages: &'a [PackageMetadata],", "pub packages: &'a [PackageMetadata<'b>],"),
    ("impl<'a> PackageIndex<'a> {", "impl<'a, 'b> PackageIndex<'a, 'b> {"),
    ("pub fn new(packages: &'a [PackageMetadata]) -> Self {", "pub fn new(packages: &'a [PackageMetadata<'b>]) -> Self {"),
    ("provides_index.entry(prov.as_str()).or_insert(i);", "provides_index.entry(prov.as_ref()).or_insert(i);"),
    ("name_index.entry(pkg.name.as_str()).or_insert(i);", "name_index.entry(pkg.name.as_ref()).or_insert(i);"),
    ("pub fn find(&self, name: &str) -> Option<&'a PackageMetadata> {", "pub fn find(&self, name: &str) -> Option<&'a PackageMetadata<'b>> {"),
    (") -> Result<Vec<&'a PackageMetadata>> {", ") -> Result<Vec<&'a PackageMetadata<'b>>> {"),
    ("order: &mut Vec<&'a PackageMetadata>,", "order: &mut Vec<&'a PackageMetadata<'b>>,"),
    ("if scheduled.contains(&pkg.name) {", "if scheduled.contains(pkg.name.as_ref()) {"),
    ("if visiting.contains(&pkg.name) {", "if visiting.contains(pkg.name.as_ref()) {"),
    ("visiting.insert(pkg.name.clone());", "visiting.insert(pkg.name.clone().into_owned());"),
    ("visiting.remove(&pkg.name);", "visiting.remove(pkg.name.as_ref());"),
    ("scheduled.insert(pkg.name.clone());", "scheduled.insert(pkg.name.clone().into_owned());"),
    ("fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata {", "fn sample_pkg(name: &str, depends: Vec<String>) -> PackageMetadata<'static> {"),
    ("name: name.to_string(),", "name: Cow::Owned(name.to_string()),"),
    ("version: \"1.0.0\".to_string(),", "version: Cow::Owned(\"1.0.0\".to_string()),"),
    ("description: String::new(),", "description: Cow::Owned(String::new()),"),
    ("download_url: String::new(),", "download_url: Cow::Owned(String::new()),"),
    ("depends,", "depends: depends.into_iter().map(Cow::Owned).collect(),"),
    ("name: \"virtual\".to_string(),", "name: Cow::Owned(\"virtual\".to_string()),"),
    ("name: \"duplicate\".to_string(),", "name: Cow::Owned(\"duplicate\".to_string()),"),
    ("version: \"named\".to_string(),", "version: Cow::Owned(\"named\".to_string()),"),
    ("version: \"first\".to_string(),", "version: Cow::Owned(\"first\".to_string()),"),
    ("version: \"second\".to_string(),", "version: Cow::Owned(\"second\".to_string()),"),
    ("provides: vec![\"virtual\".to_string(), \"shared\".to_string()],", "provides: vec![Cow::Owned(\"virtual\".to_string()), Cow::Owned(\"shared\".to_string())],"),
    ("provides: vec![\"shared\".to_string()],", "provides: vec![Cow::Owned(\"shared\".to_string())],"),
    ("name: \"pkgA\".to_string(),", "name: Cow::Owned(\"pkgA\".to_string()),"),
    ("name: \"providerA\".to_string(),", "name: Cow::Owned(\"providerA\".to_string()),"),
    ("version: \"2.0.0\".to_string(),", "version: Cow::Owned(\"2.0.0\".to_string()),"),
    ("provides: vec![\"providerA\".to_string(), \"shared\".to_string()],", "provides: vec![Cow::Owned(\"providerA\".to_string()), Cow::Owned(\"shared\".to_string())],"),
    ("name: \"curl\".to_string(),", "name: Cow::Owned(\"curl\".to_string()),"),
    ("version: \"8.0.0\".to_string(),", "version: Cow::Owned(\"8.0.0\".to_string()),"),
    ("name: \"libssl3\".to_string(),", "name: Cow::Owned(\"libssl3\".to_string()),"),
    ("version: \"3.0.0\".to_string(),", "version: Cow::Owned(\"3.0.0\".to_string()),"),
    ("provides: vec![\"libssl\".to_string()],", "provides: vec![Cow::Owned(\"libssl\".to_string())],"),
    ("pkg.version.as_str()", "pkg.version.as_ref()"),
    ("p.name.as_str()", "p.name.as_ref()"),
]
replace_in_file("system/oil/src/system/registry/mod.rs", rules_mod)

rules_main = [
    ("Vec<system::registry::PackageMetadata>", "Vec<system::registry::PackageMetadata<'static>>"),
    ("&system::registry::PackageMetadata,", "&system::registry::PackageMetadata<'static>,"),
    ("index: &'a PackageIndex<'a>,", "index: &'a PackageIndex<'a, 'static>,"),
    ("pkg.version.as_str()", "pkg.version.as_ref()"),
    ("latest.version.as_str()", "latest.version.as_ref()"),
]
replace_in_file("system/oil/src/main.rs", rules_main)

rules_recipe = [
    ("use crate::system::registry::PackageMetadata;", "use crate::system::registry::PackageMetadata;\nuse std::borrow::Cow;"),
    ("pub fn to_package_metadata(&self) -> PackageMetadata {", "pub fn to_package_metadata(&self) -> PackageMetadata<'static> {"),
    ("name: self.name.clone(),", "name: Cow::Owned(self.name.clone()),"),
    ("version: self.version.clone(),", "version: Cow::Owned(self.version.clone()),"),
    ("description: self.description.clone(),", "description: Cow::Owned(self.description.clone()),"),
    ("download_url: format!(\"{}\", cache_file.display()),", "download_url: Cow::Owned(format!(\"{}\", cache_file.display())),"),
    ("sha256: self.source.sha256.clone(),", "sha256: self.source.sha256.clone().map(Cow::Owned),"),
    ("depends: self.depends.clone(),", "depends: self.depends.clone().unwrap_or_default().into_iter().map(Cow::Owned).collect(),"),
    ("provides: self.provides.clone(),", "provides: self.provides.clone().unwrap_or_default().into_iter().map(Cow::Owned).collect(),"),
    ("assert_eq!(meta.sha256, recipe.source.sha256);", "assert_eq!(meta.sha256.as_ref().map(|s| s.as_ref()), recipe.source.sha256.as_deref());"),
]
replace_in_file("system/oil/src/recipe.rs", rules_recipe)

rules_tap = [
    ("use crate::system::registry::PackageMetadata;", "use crate::system::registry::PackageMetadata;\nuse std::borrow::Cow;"),
    ("Vec<PackageMetadata>", "Vec<PackageMetadata<'static>>"),
    ("let packages: Vec<PackageMetadata<'static>> = serde_json::from_slice(&body)", "let s = String::from_utf8(body.clone()).unwrap(); let leaked: &'static str = Box::leak(s.into_boxed_str()); let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(leaked)"),
    ("let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(&data)", "let leaked: &'static str = Box::leak(data.into_boxed_str()); let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(leaked)"),
    ("name: \"evil\".into(),", "name: Cow::Owned(\"evil\".into()),"),
    ("version: \"1\".into(),", "version: Cow::Owned(\"1\".into()),"),
    ("description: String::new(),", "description: Cow::Owned(String::new()),"),
    ("download_url: \"https://attacker.example/evil.apk\".into(),", "download_url: Cow::Owned(\"https://attacker.example/evil.apk\".into()),"),
]
replace_in_file("system/oil/src/tap.rs", rules_tap)

rules_apk = [
    ("Result<Vec<PackageMetadata>>", "Result<Vec<PackageMetadata<'static>>>"),
    ("let mut all_packages: Vec<PackageMetadata> = Vec::new();", "let mut all_packages: Vec<PackageMetadata<'static>> = Vec::new();"),
    ("fn write_cache(path: &std::path::Path, packages: &[PackageMetadata])", "fn write_cache(path: &std::path::Path, packages: &[PackageMetadata<'_>])"),
    ("let packages: Vec<PackageMetadata<'static>> = serde_json::from_reader(decoder)", "let mut buf = String::new(); std::io::Read::read_to_string(&mut decoder, &mut buf).unwrap(); let leaked: &'static str = Box::leak(buf.into_boxed_str()); let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(leaked)"),
    ("fn parse_apkindex(\n    content: &str,\n    mirror: &str,\n    branch: &str,\n    repo: &str,\n    arch: &str,\n) -> Vec<PackageMetadata> {", "fn parse_apkindex<'a>(\n    content: &'a str,\n    mirror: &str,\n    branch: &str,\n    repo: &str,\n    arch: &str,\n) -> Vec<PackageMetadata<'a>> {"),
    ("fn parse_apk_stanza(\n    stanza: &str,\n    mirror: &str,\n    branch: &str,\n    repo: &str,\n    arch: &str,\n) -> Option<PackageMetadata> {\n    let mut name = String::new();\n    let mut version = String::new();\n    let mut description = String::new();\n    let mut installed_size: u64 = 0;\n    let mut depends: Vec<String> = Vec::new();\n    let mut provides: Vec<String> = Vec::new();", "use std::borrow::Cow;\nfn parse_apk_stanza<'a>(\n    stanza: &'a str,\n    mirror: &str,\n    branch: &str,\n    repo: &str,\n    arch: &str,\n) -> Option<PackageMetadata<'a>> {\n    let mut name = Cow::Borrowed(\"\");\n    let mut version = Cow::Borrowed(\"\");\n    let mut description = Cow::Borrowed(\"\");\n    let mut installed_size: u64 = 0;\n    let mut depends: Vec<Cow<'a, str>> = Vec::new();\n    let mut provides: Vec<Cow<'a, str>> = Vec::new();"),
    ("\"P\" => name = val.to_string(),", "\"P\" => name = Cow::Borrowed(val),"),
    ("\"V\" => version = val.to_string(),", "\"V\" => version = Cow::Borrowed(val),"),
    ("\"T\" => description = val.to_string(),", "\"T\" => description = Cow::Borrowed(val),"),
    ("depends.push(dname.to_string());", "depends.push(Cow::Borrowed(dname));"),
    ("provides.push(pname.to_string());", "provides.push(Cow::Borrowed(pname));"),
    ("        name,\n        version,\n        description,\n        download_url: url,\n        sha256: None,\n        installed_size,\n        depends,\n        provides,", "        name,\n        version,\n        description,\n        download_url: Cow::Owned(url),\n        sha256: None,\n        installed_size,\n        depends,\n        provides,"),
    ("let content = std::str::from_utf8(&tar[data_start..data_end])\n                .map_err(|e| OilError::Install(format!(\"APKINDEX is not UTF-8: {e}\")))?;\n            return Ok(parse_apkindex(content, mirror, branch, repo, arch));", "let content = std::str::from_utf8(&tar[data_start..data_end])\n                .map_err(|e| OilError::Install(format!(\"APKINDEX is not UTF-8: {e}\")))?;\n            let leaked: &'static str = Box::leak(content.to_string().into_boxed_str());\n            return Ok(parse_apkindex(leaked, mirror, branch, repo, arch));"),
    ("name: \"testpkg\".into(),", "name: Cow::Owned(\"testpkg\".into()),"),
    ("version: \"1.0\".into(),", "version: Cow::Owned(\"1.0\".into()),"),
    ("description: \"test\".into(),", "description: Cow::Owned(\"test\".into()),"),
    ("download_url: \"https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/testpkg-1.0.apk\".into(),", "download_url: Cow::Owned(\"https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/testpkg-1.0.apk\".into()),"),
    ("name: \"evil\".into(),", "name: Cow::Owned(\"evil\".into()),"),
    ("version: \"1\".into(),", "version: Cow::Owned(\"1\".into()),"),
    ("description: String::new(),", "description: Cow::Owned(String::new()),"),
    ("download_url: \"https://attacker.example/evil.apk\".into(),", "download_url: Cow::Owned(\"https://attacker.example/evil.apk\".into()),"),
]
replace_in_file("system/oil/src/system/registry/apk.rs", rules_apk)

with open("system/oil/src/tap.rs", 'r') as f:
    text = f.read()
if "use std::borrow::Cow;" in text:
    pass
with open("system/oil/src/tap.rs", 'w') as f:
    f.write(text.replace("use super::PackageMetadata;", "use super::PackageMetadata;\nuse std::borrow::Cow;"))
