import re

def replace_in_file(filepath, rules):
    with open(filepath, 'r') as f:
        text = f.read()
    for o, n in rules:
        text = text.replace(o, n)
    with open(filepath, 'w') as f:
        f.write(text)

rules_main = [
    ("&'a system::registry::PackageMetadata,", "&'a system::registry::PackageMetadata<'static>,"),
]
replace_in_file("system/oil/src/main.rs", rules_main)

rules_recipe = [
    ("download_url: self.source.url.clone(),", "download_url: Cow::Owned(self.source.url.clone()),"),
    ("depends: self.depends.clone().unwrap_or_default().into_iter().map(Cow::Owned).collect(),", "depends: self.depends.clone().into_iter().map(Cow::Owned).collect(),"),
    ("provides: self.provides.clone().unwrap_or_default().into_iter().map(Cow::Owned).collect(),", "provides: self.provides.clone().into_iter().map(Cow::Owned).collect(),"),
]
replace_in_file("system/oil/src/recipe.rs", rules_recipe)

rules_apk = [
    ("let packages: Vec<PackageMetadata<'static>> = serde_json::from_slice(&body)", "let s = String::from_utf8(body).unwrap(); let leaked: &'static str = Box::leak(s.into_boxed_str()); let packages: Vec<PackageMetadata<'static>> = serde_json::from_str(leaked)"),
    ("Ok(serde_json::from_slice(&body)?)", "let s = String::from_utf8(body).unwrap(); let leaked: &'static str = Box::leak(s.into_boxed_str()); Ok(serde_json::from_str(leaked)?)"),
]
replace_in_file("system/oil/src/system/registry/apk.rs", rules_apk)

rules_tap = [
    ("use std::borrow::Cow;\n\n#[derive(Debug, Clone, Serialize, Deserialize)]", "#[derive(Debug, Clone, Serialize, Deserialize)]"),
]
replace_in_file("system/oil/src/tap.rs", rules_tap)
