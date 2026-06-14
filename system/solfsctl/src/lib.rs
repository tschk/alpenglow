use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fmt;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

pub mod v2;

pub const MAGIC: &[u8; 8] = b"SOLFSV01";
pub const HEADER_LEN: usize = 56;
pub const ENTRY_LEN: usize = 92;
pub const KIND_DIR: u32 = 1;
pub const KIND_FILE: u32 = 2;
pub const KIND_SYMLINK: u32 = 3;
pub const FLAG_READONLY: u64 = 1;
pub const FLAG_MUTABLE: u64 = 2;
pub const FLAG_V2: u64 = 4;

#[derive(Debug)]
pub enum SolfsError {
    Io(io::Error),
    Invalid(String),
}

impl fmt::Display for SolfsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SolfsError::Io(error) => write!(f, "{error}"),
            SolfsError::Invalid(message) => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for SolfsError {}

impl From<io::Error> for SolfsError {
    fn from(error: io::Error) -> Self {
        SolfsError::Io(error)
    }
}

pub type Result<T> = std::result::Result<T, SolfsError>;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Header {
    pub entry_count: u32,
    pub entries_offset: u64,
    pub names_offset: u64,
    pub data_offset: u64,
    pub image_size: u64,
    pub flags: u64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Entry {
    pub inode: u64,
    pub parent: u64,
    pub name_offset: u64,
    pub name_len: u32,
    pub kind: u32,
    pub mode: u32,
    pub uid: u32,
    pub gid: u32,
    pub data_offset: u64,
    pub size: u64,
    pub digest: [u8; 32],
    pub path: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Image {
    pub header: Header,
    pub entries: Vec<Entry>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ImageMode {
    ReadOnly,
    Mutable,
}

impl Image {
    pub fn find_path(&self, path: &str) -> Option<&Entry> {
        let path = query_path(path);
        self.entries.iter().find(|entry| entry.path == path)
    }

    pub fn list_dir(&self, path: &str) -> Result<Vec<String>> {
        let path = query_path(path);
        let parent = self
            .find_path(&path)
            .ok_or_else(|| SolfsError::Invalid(format!("directory not found: {path}")))?;
        if parent.kind != KIND_DIR {
            return Err(SolfsError::Invalid(format!("not a directory: {path}")));
        }
        let mut names = self
            .entries
            .iter()
            .filter(|entry| entry.parent == parent.inode && entry.inode != parent.inode)
            .map(|entry| file_name(&entry.path).to_string())
            .collect::<Vec<_>>();
        names.sort();
        Ok(names)
    }
}

#[derive(Clone, Debug)]
struct BuildEntry {
    inode: u64,
    parent: u64,
    path: String,
    kind: u32,
    mode: u32,
    uid: u32,
    gid: u32,
    data: Vec<u8>,
    digest: [u8; 32],
}

pub fn build_image(source: impl AsRef<Path>, output: impl AsRef<Path>) -> Result<Image> {
    build_image_with_mode(source, output, ImageMode::ReadOnly)
}

pub fn build_image_with_mode(
    source: impl AsRef<Path>,
    output: impl AsRef<Path>,
    mode: ImageMode,
) -> Result<Image> {
    let source = source.as_ref();
    if !source.is_dir() {
        return Err(SolfsError::Invalid(format!(
            "source directory not found: {}",
            source.display()
        )));
    }

    let mut entries = collect_entries(source, mode)?;
    entries.sort_by(|left, right| left.path.cmp(&right.path));

    let mut inode_by_path = BTreeMap::new();
    inode_by_path.insert(String::new(), 1_u64);
    let mut next_inode = 2_u64;

    for entry in &mut entries {
        if entry.path.is_empty() {
            entry.inode = 1;
            entry.parent = 1;
        } else {
            entry.inode = next_inode;
            next_inode += 1;
            let parent_path = parent_path(&entry.path);
            let parent = inode_by_path
                .get(parent_path)
                .copied()
                .ok_or_else(|| SolfsError::Invalid(format!("missing parent for {}", entry.path)))?;
            entry.parent = parent;
        }
        inode_by_path.insert(entry.path.clone(), entry.inode);
    }

    let names_len = entries
        .iter()
        .filter(|entry| !entry.path.is_empty())
        .map(|entry| file_name(&entry.path).len())
        .sum::<usize>();
    let entries_offset = HEADER_LEN as u64;
    let names_offset = entries_offset + (entries.len() * ENTRY_LEN) as u64;
    let data_offset = align8(names_offset + names_len as u64);
    let mut cursor = data_offset;
    let mut names = Vec::with_capacity(names_len);
    let mut public_entries = Vec::with_capacity(entries.len());

    for entry in &entries {
        let name = file_name(&entry.path).as_bytes();
        let name_offset = names.len() as u64;
        names.extend_from_slice(name);
        let file_offset = if entry.kind != KIND_DIR {
            let offset = cursor;
            cursor += entry.data.len() as u64;
            cursor = align8(cursor);
            offset
        } else {
            0
        };
        public_entries.push(Entry {
            inode: entry.inode,
            parent: entry.parent,
            name_offset,
            name_len: name.len() as u32,
            kind: entry.kind,
            mode: entry.mode,
            uid: entry.uid,
            gid: entry.gid,
            data_offset: file_offset,
            size: entry.data.len() as u64,
            digest: entry.digest,
            path: entry.path.clone(),
        });
    }

    let header = Header {
        entry_count: public_entries.len() as u32,
        entries_offset,
        names_offset,
        data_offset,
        image_size: cursor,
        flags: match mode {
            ImageMode::ReadOnly => FLAG_READONLY,
            ImageMode::Mutable => FLAG_MUTABLE,
        },
    };

    let mut file = File::create(output)?;
    write_header(&mut file, &header)?;
    for entry in &public_entries {
        write_entry(&mut file, entry)?;
    }
    file.write_all(&names)?;
    write_zeroes_until(&mut file, data_offset)?;
    for (entry, public_entry) in entries.iter().zip(public_entries.iter()) {
        if entry.kind != KIND_DIR {
            file.seek(SeekFrom::Start(public_entry.data_offset))?;
            file.write_all(&entry.data)?;
            write_zeroes_until(
                &mut file,
                align8(public_entry.data_offset + public_entry.size),
            )?;
        }
    }
    file.flush()?;

    Ok(Image {
        header,
        entries: public_entries,
    })
}

pub fn inspect_image(path: impl AsRef<Path>) -> Result<Image> {
    let mut file = File::open(path)?;
    let mut header_bytes = [0_u8; HEADER_LEN];
    file.read_exact(&mut header_bytes)?;
    let header = parse_header(&header_bytes)?;
    let mut entries = Vec::with_capacity(header.entry_count as usize);

    file.seek(SeekFrom::Start(header.entries_offset))?;
    for _ in 0..header.entry_count {
        let mut entry_bytes = [0_u8; ENTRY_LEN];
        file.read_exact(&mut entry_bytes)?;
        entries.push(parse_entry(&entry_bytes)?);
    }

    let mut path_by_inode = BTreeMap::new();
    path_by_inode.insert(1_u64, String::new());

    for entry in &mut entries {
        if entry.name_len == 0 {
            entry.path.clear();
            path_by_inode.insert(entry.inode, String::new());
            continue;
        }
        file.seek(SeekFrom::Start(header.names_offset + entry.name_offset))?;
        let mut name = vec![0_u8; entry.name_len as usize];
        file.read_exact(&mut name)?;
        let name = String::from_utf8(name)
            .map_err(|_| SolfsError::Invalid("entry name is not valid utf-8".to_string()))?;
        let parent_path = path_by_inode
            .get(&entry.parent)
            .cloned()
            .ok_or_else(|| SolfsError::Invalid(format!("missing parent inode {}", entry.parent)))?;
        entry.path = if parent_path.is_empty() {
            name
        } else {
            format!("{parent_path}/{name}")
        };
        path_by_inode.insert(entry.inode, entry.path.clone());
    }

    validate_image(&header, &entries)?;
    Ok(Image { header, entries })
}

pub fn read_file(image: impl AsRef<Path>, path: &str) -> Result<Vec<u8>> {
    let image_path = image.as_ref();
    let image = inspect_image(image_path)?;
    let entry = image
        .find_path(path)
        .ok_or_else(|| SolfsError::Invalid(format!("file not found: {}", query_path(path))))?;
    if entry.kind != KIND_FILE {
        return Err(SolfsError::Invalid(format!(
            "not a file: {}",
            query_path(path)
        )));
    }
    let mut file = File::open(image_path)?;
    file.seek(SeekFrom::Start(entry.data_offset))?;
    let mut bytes = vec![0_u8; entry.size as usize];
    file.read_exact(&mut bytes)?;
    if image.header.flags & FLAG_MUTABLE == 0 && digest_bytes(&bytes) != entry.digest {
        return Err(SolfsError::Invalid(format!(
            "digest mismatch: {}",
            query_path(path)
        )));
    }
    Ok(bytes)
}

pub fn overwrite_file(image: impl AsRef<Path>, path: &str, data: &[u8]) -> Result<()> {
    let image_path = image.as_ref();
    let image = inspect_image(image_path)?;
    let path = query_path(path);
    if image.header.flags & FLAG_MUTABLE == 0 {
        return Err(SolfsError::Invalid(format!(
            "cannot write immutable SolFS image: {path}"
        )));
    }
    let (index, entry) = image
        .entries
        .iter()
        .enumerate()
        .find(|(_, entry)| entry.path == path)
        .ok_or_else(|| SolfsError::Invalid(format!("file not found: {path}")))?;
    if entry.kind != KIND_FILE {
        return Err(SolfsError::Invalid(format!("not a file: {path}")));
    }
    let mut updated = entry.clone();
    let old_size = entry.size;
    if data.len() as u64 > entry.size {
        updated.data_offset = align8(image.header.image_size);
    }
    updated.size = data.len() as u64;
    updated.digest = digest_bytes(data);
    let new_image_size = align8(updated.data_offset + updated.size);

    let mut file = OpenOptions::new().read(true).write(true).open(image_path)?;
    if new_image_size > image.header.image_size {
        let mut header = image.header.clone();
        header.image_size = new_image_size;
        file.seek(SeekFrom::Start(0))?;
        write_header(&mut file, &header)?;
    }
    file.seek(SeekFrom::Start(
        image.header.entries_offset + index as u64 * ENTRY_LEN as u64,
    ))?;
    write_entry(&mut file, &updated)?;
    file.seek(SeekFrom::Start(updated.data_offset))?;
    file.write_all(data)?;
    if old_size > updated.size && updated.data_offset == entry.data_offset {
        file.write_all(&vec![0_u8; (old_size - updated.size) as usize])?;
    }
    if new_image_size > updated.data_offset + updated.size {
        write_zeroes_until(&mut file, new_image_size)?;
    }
    file.flush()?;
    Ok(())
}

pub fn render_text(image: &Image) -> String {
    let mut lines = Vec::with_capacity(image.entries.len() + 1);
    lines.push(format!(
        "solfs entries={} size={} flags={}",
        image.header.entry_count, image.header.image_size, image.header.flags
    ));
    for entry in &image.entries {
        let kind = match entry.kind {
            KIND_DIR => "dir",
            KIND_FILE => "file",
            KIND_SYMLINK => "symlink",
            _ => "unknown",
        };
        let path = if entry.path.is_empty() {
            "/".to_string()
        } else {
            format!("/{}", entry.path)
        };
        lines.push(format!(
            "{} inode={} parent={} size={} digest={}",
            path,
            entry.inode,
            entry.parent,
            if entry.kind != KIND_DIR {
                entry.size
            } else {
                0
            },
            if entry.kind != KIND_DIR {
                hex_digest(&entry.digest)
            } else {
                "-".to_string()
            }
        ));
        lines.push(format!("type={kind} mode={:o}", entry.mode));
    }
    lines.join("\n")
}

#[cfg(test)]
mod behavior_tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn image_lists_directory_children_in_stable_order() {
        let root = temp_dir("list");
        fs::create_dir_all(root.join("usr/bin")).unwrap();
        fs::write(root.join("usr/bin/b"), b"b").unwrap();
        fs::write(root.join("usr/bin/a"), b"a").unwrap();
        let image_path = root.with_extension("solfs");
        build_image(&root, &image_path).unwrap();
        let image = inspect_image(&image_path).unwrap();

        let children = image.list_dir("usr/bin").unwrap();

        assert_eq!(children, vec!["a".to_string(), "b".to_string()]);
        fs::remove_dir_all(&root).unwrap();
        fs::remove_file(&image_path).unwrap();
    }

    #[test]
    fn image_reads_file_bytes_by_path() {
        let root = temp_dir("read");
        fs::create_dir_all(root.join("etc/soliloquy")).unwrap();
        fs::write(root.join("etc/soliloquy/system.json"), b"{\"ok\":true}\n").unwrap();
        let image_path = root.with_extension("solfs");
        build_image_with_mode(&root, &image_path, ImageMode::Mutable).unwrap();

        let bytes = read_file(&image_path, "etc/soliloquy/system.json").unwrap();

        assert_eq!(bytes, b"{\"ok\":true}\n");
        fs::remove_dir_all(&root).unwrap();
        fs::remove_file(&image_path).unwrap();
    }

    #[test]
    fn image_overwrites_existing_file_extent() {
        let root = temp_dir("write");
        fs::create_dir_all(root.join("var/lib/soliloquy")).unwrap();
        fs::write(root.join("var/lib/soliloquy/state.env"), b"renderer=old\n").unwrap();
        let image_path = root.with_extension("solfs");
        build_image_with_mode(&root, &image_path, ImageMode::Mutable).unwrap();

        overwrite_file(
            &image_path,
            "var/lib/soliloquy/state.env",
            b"renderer=new\n",
        )
        .unwrap();
        let bytes = read_file(&image_path, "var/lib/soliloquy/state.env").unwrap();

        assert_eq!(bytes, b"renderer=new\n");
        fs::remove_dir_all(&root).unwrap();
        fs::remove_file(&image_path).unwrap();
    }

    #[test]
    fn image_grows_mutable_file_by_allocating_new_extent() {
        let root = temp_dir("write-grow");
        fs::create_dir_all(root.join("var/lib/soliloquy")).unwrap();
        fs::write(root.join("var/lib/soliloquy/state.env"), b"small").unwrap();
        let image_path = root.with_extension("solfs");
        build_image_with_mode(&root, &image_path, ImageMode::Mutable).unwrap();

        overwrite_file(&image_path, "var/lib/soliloquy/state.env", b"larger-value").unwrap();
        let bytes = read_file(&image_path, "var/lib/soliloquy/state.env").unwrap();
        let image = inspect_image(&image_path).unwrap();

        assert_eq!(bytes, b"larger-value");
        assert_eq!(
            image.find_path("var/lib/soliloquy/state.env").unwrap().size,
            12
        );
        fs::remove_dir_all(&root).unwrap();
        fs::remove_file(&image_path).unwrap();
    }

    fn temp_dir(name: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "solfsctl-behavior-{name}-{}-{stamp}",
            std::process::id()
        ))
    }
}

fn collect_entries(source: &Path, mode: ImageMode) -> Result<Vec<BuildEntry>> {
    let dir_mode = match mode {
        ImageMode::ReadOnly => 0o755,
        ImageMode::Mutable => 0o755,
    };
    let file_mode = match mode {
        ImageMode::ReadOnly => 0o444,
        ImageMode::Mutable => 0o644,
    };
    let mut entries = vec![BuildEntry {
        inode: 1,
        parent: 1,
        path: String::new(),
        kind: KIND_DIR,
        mode: dir_mode,
        uid: 0,
        gid: 0,
        data: Vec::new(),
        digest: [0; 32],
    }];
    collect_dir(source, source, &mut entries, dir_mode, file_mode)?;
    Ok(entries)
}

fn collect_dir(
    root: &Path,
    dir: &Path,
    entries: &mut Vec<BuildEntry>,
    dir_mode: u32,
    file_mode: u32,
) -> Result<()> {
    let mut children = fs::read_dir(dir)?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<io::Result<Vec<PathBuf>>>()?;
    children.sort();

    for path in children {
        let metadata = fs::symlink_metadata(&path)?;
        let relative = path.strip_prefix(root).map_err(|_| {
            SolfsError::Invalid(format!("path escaped source root: {}", path.display()))
        })?;
        let relative = normalize_path(relative)?;
        if metadata.file_type().is_symlink() {
            let target = fs::read_link(&path)?;
            let target = target
                .to_str()
                .ok_or_else(|| {
                    SolfsError::Invalid(format!(
                        "symlink target is not valid utf-8: {}",
                        path.display()
                    ))
                })?
                .as_bytes()
                .to_vec();
            let digest = digest_bytes(&target);
            entries.push(BuildEntry {
                inode: 0,
                parent: 0,
                path: relative,
                kind: KIND_SYMLINK,
                mode: 0o777,
                uid: 0,
                gid: 0,
                data: target,
                digest,
            });
        } else if metadata.is_dir() {
            entries.push(BuildEntry {
                inode: 0,
                parent: 0,
                path: relative,
                kind: KIND_DIR,
                mode: dir_mode,
                uid: 0,
                gid: 0,
                data: Vec::new(),
                digest: [0; 32],
            });
            collect_dir(root, &path, entries, dir_mode, file_mode)?;
        } else if metadata.is_file() {
            let data = fs::read(&path)?;
            let digest = digest_bytes(&data);
            entries.push(BuildEntry {
                inode: 0,
                parent: 0,
                path: relative,
                kind: KIND_FILE,
                mode: entry_file_mode(&metadata, file_mode),
                uid: 0,
                gid: 0,
                data,
                digest,
            });
        }
    }
    Ok(())
}

fn entry_file_mode(metadata: &fs::Metadata, base_mode: u32) -> u32 {
    #[cfg(unix)]
    {
        if metadata.permissions().mode() & 0o111 != 0 {
            return base_mode | 0o111;
        }
    }
    base_mode
}

fn normalize_path(path: &Path) -> Result<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        let value = component.as_os_str().to_string_lossy();
        if value.is_empty() || value == "." || value == ".." {
            return Err(SolfsError::Invalid(format!(
                "invalid SolFS path component: {value}"
            )));
        }
        parts.push(value.to_string());
    }
    Ok(parts.join("/"))
}

fn validate_image(header: &Header, entries: &[Entry]) -> Result<()> {
    if header.entries_offset != HEADER_LEN as u64 {
        return Err(SolfsError::Invalid("bad entries offset".to_string()));
    }
    if header.names_offset < header.entries_offset + entries.len() as u64 * ENTRY_LEN as u64 {
        return Err(SolfsError::Invalid("bad names offset".to_string()));
    }
    if header.data_offset < header.names_offset {
        return Err(SolfsError::Invalid("bad data offset".to_string()));
    }
    if entries
        .first()
        .map(|entry| (entry.inode, entry.parent, entry.kind))
        != Some((1, 1, KIND_DIR))
    {
        return Err(SolfsError::Invalid("root entry is invalid".to_string()));
    }
    let mut inode_by_id = BTreeMap::new();
    for entry in entries {
        if inode_by_id.insert(entry.inode, true).is_some() {
            return Err(SolfsError::Invalid(format!(
                "duplicate inode {}",
                entry.inode
            )));
        }
        if entry.kind != KIND_DIR && entry.kind != KIND_FILE && entry.kind != KIND_SYMLINK {
            return Err(SolfsError::Invalid(format!(
                "bad entry kind {}",
                entry.kind
            )));
        }
        if entry.kind == KIND_DIR && (entry.size != 0 || entry.data_offset != 0) {
            return Err(SolfsError::Invalid(format!(
                "directory has file payload: {}",
                entry.inode
            )));
        }
    }
    Ok(())
}

fn parse_header(bytes: &[u8; HEADER_LEN]) -> Result<Header> {
    if &bytes[0..8] != MAGIC {
        return Err(SolfsError::Invalid("bad SolFS magic".to_string()));
    }
    let version = u32_at(bytes, 8);
    if version != 1 {
        return Err(SolfsError::Invalid(format!("bad SolFS version {version}")));
    }
    Ok(Header {
        entry_count: u32_at(bytes, 12),
        entries_offset: u64_at(bytes, 16),
        names_offset: u64_at(bytes, 24),
        data_offset: u64_at(bytes, 32),
        image_size: u64_at(bytes, 40),
        flags: u64_at(bytes, 48),
    })
}

fn parse_entry(bytes: &[u8; ENTRY_LEN]) -> Result<Entry> {
    let mut digest = [0_u8; 32];
    digest.copy_from_slice(&bytes[60..92]);
    Ok(Entry {
        inode: u64_at(bytes, 0),
        parent: u64_at(bytes, 8),
        name_offset: u64_at(bytes, 16),
        name_len: u32_at(bytes, 24),
        kind: u32_at(bytes, 28),
        mode: u32_at(bytes, 32),
        uid: u32_at(bytes, 36),
        gid: u32_at(bytes, 40),
        data_offset: u64_at(bytes, 44),
        size: u64_at(bytes, 52),
        digest,
        path: String::new(),
    })
}

fn write_header(mut writer: impl Write, header: &Header) -> io::Result<()> {
    writer.write_all(MAGIC)?;
    writer.write_all(&1_u32.to_le_bytes())?;
    writer.write_all(&header.entry_count.to_le_bytes())?;
    writer.write_all(&header.entries_offset.to_le_bytes())?;
    writer.write_all(&header.names_offset.to_le_bytes())?;
    writer.write_all(&header.data_offset.to_le_bytes())?;
    writer.write_all(&header.image_size.to_le_bytes())?;
    writer.write_all(&header.flags.to_le_bytes())?;
    Ok(())
}

fn write_entry(mut writer: impl Write, entry: &Entry) -> io::Result<()> {
    writer.write_all(&entry.inode.to_le_bytes())?;
    writer.write_all(&entry.parent.to_le_bytes())?;
    writer.write_all(&entry.name_offset.to_le_bytes())?;
    writer.write_all(&entry.name_len.to_le_bytes())?;
    writer.write_all(&entry.kind.to_le_bytes())?;
    writer.write_all(&entry.mode.to_le_bytes())?;
    writer.write_all(&entry.uid.to_le_bytes())?;
    writer.write_all(&entry.gid.to_le_bytes())?;
    writer.write_all(&entry.data_offset.to_le_bytes())?;
    writer.write_all(&entry.size.to_le_bytes())?;
    writer.write_all(&entry.digest)?;
    Ok(())
}

fn u32_at(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap_or([0; 4]))
}

fn u64_at(bytes: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(bytes[offset..offset + 8].try_into().unwrap_or([0; 8]))
}

fn digest_bytes(data: &[u8]) -> [u8; 32] {
    let digest = Sha256::digest(data);
    let mut out = [0_u8; 32];
    out.copy_from_slice(&digest);
    out
}

fn hex_digest(bytes: &[u8; 32]) -> String {
    let mut out = String::with_capacity(64);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

fn align8(value: u64) -> u64 {
    (value + 7) & !7
}

fn write_zeroes_until(file: &mut File, target: u64) -> io::Result<()> {
    let current = file.stream_position()?;
    if current < target {
        file.write_all(&vec![0_u8; (target - current) as usize])?;
    }
    Ok(())
}

fn parent_path(path: &str) -> &str {
    path.rsplit_once('/')
        .map(|(parent, _)| parent)
        .unwrap_or("")
}

fn file_name(path: &str) -> &str {
    path.rsplit_once('/').map(|(_, name)| name).unwrap_or(path)
}

fn query_path(path: &str) -> String {
    path.trim_matches('/').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn build_and_inspect_round_trip() {
        let root = temp_dir("round-trip");
        fs::create_dir_all(root.join("etc/soliloquy")).unwrap();
        fs::write(root.join("etc/soliloquy/system.json"), b"{\"ok\":true}\n").unwrap();
        let image = root.with_extension("solfs");

        let built = build_image(&root, &image).unwrap();
        let inspected = inspect_image(&image).unwrap();

        assert_eq!(built.header.entry_count, inspected.header.entry_count);
        assert!(inspected.entries.iter().any(|entry| entry.path == "etc"));
        assert!(inspected
            .entries
            .iter()
            .any(|entry| entry.path == "etc/soliloquy/system.json" && entry.kind == KIND_FILE));
        fs::remove_dir_all(&root).unwrap();
        fs::remove_file(&image).unwrap();
    }

    #[test]
    fn builds_symlink_entries() {
        let root = temp_dir("symlink");
        fs::create_dir_all(&root).unwrap();
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink("target", root.join("link")).unwrap();
            let image = root.with_extension("solfs");
            build_image(&root, &image).unwrap();
            let inspected = inspect_image(&image).unwrap();
            let link = inspected.find_path("link").unwrap();
            assert_eq!(link.kind, KIND_SYMLINK);
            assert_eq!(
                read_file(&image, "link").unwrap_err().to_string(),
                "not a file: link"
            );
            fs::remove_file(&image).unwrap();
        }
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn readonly_images_preserve_file_execute_bits() {
        let root = temp_dir("exec");
        fs::create_dir_all(root.join("sbin")).unwrap();
        let init = root.join("sbin/init");
        fs::write(&init, b"#!/bin/sh\n").unwrap();
        #[cfg(unix)]
        fs::set_permissions(&init, fs::Permissions::from_mode(0o755)).unwrap();
        let image = root.with_extension("solfs");

        build_image(&root, &image).unwrap();
        let inspected = inspect_image(&image).unwrap();
        let entry = inspected.find_path("sbin/init").unwrap();

        assert_eq!(entry.mode & 0o111, 0o111);
        assert_eq!(entry.mode & 0o222, 0);
        fs::remove_dir_all(&root).unwrap();
        fs::remove_file(&image).unwrap();
    }

    fn temp_dir(name: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("solfsctl-{name}-{}-{stamp}", std::process::id()))
    }
}
