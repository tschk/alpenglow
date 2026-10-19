import { describe, expect, test, spyOn, afterAll } from "bun:test";
import { buildSite } from "../src/build";
import { resolve } from "node:path";
import { rm } from "node:fs/promises";

describe("buildSite", () => {
  afterAll(async () => {
    await rm(resolve(import.meta.dir, "..", "dist-test-build"), { recursive: true, force: true });
  });

  test("throws AggregateError when bundling fails", async () => {
    const mockBuild = spyOn(Bun, "build").mockResolvedValue({
      success: false,
      logs: ["mock error log"],
    } as any);

    const outDir = resolve(import.meta.dir, "..", "dist-test-build");

    try {
      await expect(buildSite(outDir)).rejects.toThrow(AggregateError);
      await expect(buildSite(outDir)).rejects.toThrow("shell bundle failed");
    } finally {
      mockBuild.mockRestore();
    }
  });
});
