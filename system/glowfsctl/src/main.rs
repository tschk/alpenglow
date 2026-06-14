use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("glowfsctl: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> glowfsctl::Result<()> {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("mkfs") => {
            let first = args.next().ok_or_else(|| {
                glowfsctl::GlowfsError::Invalid("missing source directory".into())
            })?;
            let (mode, source) = if first == "--mutable" {
                (
                    glowfsctl::ImageMode::Mutable,
                    args.next().ok_or_else(|| {
                        glowfsctl::GlowfsError::Invalid("missing source directory".into())
                    })?,
                )
            } else {
                (glowfsctl::ImageMode::ReadOnly, first)
            };
            let output = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing output image".into()))?;
            let image = glowfsctl::build_image_with_mode(source, output, mode)?;
            println!(
                "glowfs image entries={} size={}",
                image.header.entry_count, image.header.image_size
            );
        }
        Some("inspect") => {
            let image = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing image path".into()))?;
            let image = glowfsctl::inspect_image(image)?;
            println!("{}", glowfsctl::render_text(&image));
        }
        Some("read") => {
            let image = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing image path".into()))?;
            let path = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing file path".into()))?;
            let bytes = glowfsctl::read_file(image, &path)?;
            print!("{}", String::from_utf8_lossy(&bytes));
        }
        Some("write") => {
            let image = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing image path".into()))?;
            let path = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing file path".into()))?;
            let value = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing value".into()))?;
            glowfsctl::overwrite_file(image, &path, value.as_bytes())?;
        }
        Some("plan-v2") => {
            let image = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing image path".into()))?;
            let target_size = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing target size".into()))?
                .parse::<u64>()
                .map_err(|_| glowfsctl::GlowfsError::Invalid("bad target size".into()))?;
            let image = glowfsctl::inspect_image(image)?;
            let layout = glowfsctl::v2::plan_v2_layout(&image.header, &image.entries, target_size)?;
            println!(
                "glowfs-v2 block_size={} bitmap={}+{} extents={}+{} journal={}+{} data_start={} free_blocks={}",
                layout.block_size,
                layout.bitmap_offset,
                layout.bitmap_len,
                layout.extent_table_offset,
                layout.extent_table_len,
                layout.journal_offset,
                layout.journal_len,
                layout.data_start,
                layout.free_blocks
            );
        }
        Some("upgrade-v2") => {
            let image = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing image path".into()))?;
            let target_size = args
                .next()
                .ok_or_else(|| glowfsctl::GlowfsError::Invalid("missing target size".into()))?
                .parse::<u64>()
                .map_err(|_| glowfsctl::GlowfsError::Invalid("bad target size".into()))?;
            let layout = glowfsctl::v2::upgrade_image_to_v2(image, target_size)?;
            println!(
                "glowfs-v2 upgraded block_size={} superblock={} bitmap={}+{} extents={}+{} journal={}+{} data_start={} free_blocks={}",
                layout.block_size,
                layout.superblock_offset,
                layout.bitmap_offset,
                layout.bitmap_len,
                layout.extent_table_offset,
                layout.extent_table_len,
                layout.journal_offset,
                layout.journal_len,
                layout.data_start,
                layout.free_blocks
            );
        }
        Some(command) => {
            return Err(glowfsctl::GlowfsError::Invalid(format!(
                "unknown command: {command}"
            )));
        }
        None => {
            return Err(glowfsctl::GlowfsError::Invalid(
                "usage: glowfsctl mkfs [--mutable] <source-dir> <image> | glowfsctl inspect <image> | glowfsctl read <image> <path> | glowfsctl write <image> <path> <value> | glowfsctl plan-v2 <image> <target-size> | glowfsctl upgrade-v2 <image> <target-size>".into(),
            ));
        }
    }
    Ok(())
}
