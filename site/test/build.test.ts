import { describe, expect, spyOn, test } from "bun:test";
import { buildSite } from "../src/build";
import { resolve } from "node:path";
import { rm } from "node:fs/promises";

const tempDir = resolve(import.meta.dir, "..", "dist-test-build");

describe("buildSite", () => {
  test("throws AggregateError when Bun.build fails", async () => {
    const buildSpy = spyOn(Bun, "build").mockResolvedValue({
      success: false,
      logs: ["Mock bundling error"]
    } as any);

    try {
      await expect(buildSite(tempDir)).rejects.toThrow(AggregateError);
      await expect(buildSite(tempDir)).rejects.toThrow("shell bundle failed");
    } finally {
      buildSpy.mockRestore();
      await rm(tempDir, { recursive: true, force: true });
    }
  });

  test("builds site successfully", async () => {
    const outDir = await buildSite(tempDir);
    expect(outDir).toBe(tempDir);
    expect(await Bun.file(resolve(outDir, "index.html")).exists()).toBe(true);
    await rm(tempDir, { recursive: true, force: true });
  });
});
