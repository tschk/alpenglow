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

        Some(command) => {
            return Err(glowfsctl::GlowfsError::Invalid(format!(
                "unknown command: {command}"
            )));
        }
        None => {
            return Err(glowfsctl::GlowfsError::Invalid(
                "usage: glowfsctl mkfs [--mutable] <source-dir> <image> | glowfsctl inspect <image> | glowfsctl read <image> <path> | glowfsctl write <image> <path> <value>".into(),
            ));
        }
    }
    Ok(())
}
