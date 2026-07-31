import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { renderDocument } from "./document";

const root = resolve(import.meta.dir, "..");
const publicDir = resolve(root, "public");
const distDir = resolve(root, "dist");

export async function buildSite(outDir: string = distDir): Promise<string> {
  await rm(outDir, { recursive: true, force: true });
  await mkdir(outDir, { recursive: true });
  await cp(publicDir, outDir, { recursive: true });

  const bundle = await Bun.build({
    entrypoints: [resolve(import.meta.dir, "shell.js")],
    outdir: outDir,
    target: "browser",
    format: "esm",
    minify: true,
    naming: "[name].[ext]",
  });
  if (!bundle.success) {
    throw new AggregateError(bundle.logs, "shell bundle failed");
  }

  const html = await renderDocument(new Request("http://localhost/"));
  await writeFile(resolve(outDir, "index.html"), html, "utf8");
  return outDir;
}

if (import.meta.main) {
  const outDir = await buildSite();
  console.log(`alpenglow site built → ${outDir}`);
}
