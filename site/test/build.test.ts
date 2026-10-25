import { describe, expect, spyOn, test } from "bun:test";
import { buildSite } from "../src/build";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

describe("buildSite", () => {
  test("throws AggregateError when shell bundle fails", async () => {
    const s = spyOn(Bun, "build").mockResolvedValue({
      success: false,
      logs: ["mock error"],
    } as any);

    const tempDir = await mkdtemp(join(tmpdir(), "buildSite-"));
    let error: unknown;
    try {
      await buildSite(tempDir);
    } catch (e: unknown) {
      error = e;
    } finally {
      s.mockRestore();
      await rm(tempDir, { recursive: true, force: true });
    }

    expect(error).toBeInstanceOf(AggregateError);
    expect((error as AggregateError).message).toBe("shell bundle failed");
    expect((error as AggregateError).errors).toEqual(["mock error"]);
  });

  test("returns outDir on successful build", async () => {
    const tempDir = await mkdtemp(join(tmpdir(), "buildSite-"));
    try {
      const outDir = await buildSite(tempDir);
      expect(outDir).toBe(tempDir);
      expect(await Bun.file(join(tempDir, "index.html")).exists()).toBe(true);
    } finally {
      await rm(tempDir, { recursive: true, force: true });
    }
  });
});
