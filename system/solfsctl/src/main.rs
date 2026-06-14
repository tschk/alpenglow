use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("solfsctl: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> solfsctl::Result<()> {
    let mut args = env::args().skip(1);
    match args.next().as_deref() {
        Some("mkfs") => {
            let first = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing source directory".into()))?;
            let (mode, source) = if first == "--mutable" {
                (
                    solfsctl::ImageMode::Mutable,
                    args.next().ok_or_else(|| {
                        solfsctl::SolfsError::Invalid("missing source directory".into())
                    })?,
                )
            } else {
                (solfsctl::ImageMode::ReadOnly, first)
            };
            let output = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing output image".into()))?;
            let image = solfsctl::build_image_with_mode(source, output, mode)?;
            println!(
                "solfs image entries={} size={}",
                image.header.entry_count, image.header.image_size
            );
        }
        Some("inspect") => {
            let image = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing image path".into()))?;
            let image = solfsctl::inspect_image(image)?;
            println!("{}", solfsctl::render_text(&image));
        }
        Some("read") => {
            let image = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing image path".into()))?;
            let path = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing file path".into()))?;
            let bytes = solfsctl::read_file(image, &path)?;
            print!("{}", String::from_utf8_lossy(&bytes));
        }
        Some("write") => {
            let image = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing image path".into()))?;
            let path = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing file path".into()))?;
            let value = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing value".into()))?;
            solfsctl::overwrite_file(image, &path, value.as_bytes())?;
        }
        Some("plan-v2") => {
            let image = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing image path".into()))?;
            let target_size = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing target size".into()))?
                .parse::<u64>()
                .map_err(|_| solfsctl::SolfsError::Invalid("bad target size".into()))?;
            let image = solfsctl::inspect_image(image)?;
            let layout = solfsctl::v2::plan_v2_layout(&image.header, &image.entries, target_size)?;
            println!(
                "solfs-v2 block_size={} bitmap={}+{} extents={}+{} journal={}+{} data_start={} free_blocks={}",
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
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing image path".into()))?;
            let target_size = args
                .next()
                .ok_or_else(|| solfsctl::SolfsError::Invalid("missing target size".into()))?
                .parse::<u64>()
                .map_err(|_| solfsctl::SolfsError::Invalid("bad target size".into()))?;
            let layout = solfsctl::v2::upgrade_image_to_v2(image, target_size)?;
            println!(
                "solfs-v2 upgraded block_size={} superblock={} bitmap={}+{} extents={}+{} journal={}+{} data_start={} free_blocks={}",
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
            return Err(solfsctl::SolfsError::Invalid(format!(
                "unknown command: {command}"
            )));
        }
        None => {
            return Err(solfsctl::SolfsError::Invalid(
                "usage: solfsctl mkfs [--mutable] <source-dir> <image> | solfsctl inspect <image> | solfsctl read <image> <path> | solfsctl write <image> <path> <value> | solfsctl plan-v2 <image> <target-size> | solfsctl upgrade-v2 <image> <target-size>".into(),
            ));
        }
    }
    Ok(())
}
