import { describe, expect, test, spyOn } from "bun:test";
import { buildSite } from "../src/build";
import { resolve } from "node:path";
import { rm } from "node:fs/promises";

describe("buildSite", () => {
  const testOutDir = resolve(import.meta.dir, "..", "dist-test");

  test("throws AggregateError when bundling fails", async () => {
    const mockBuild = spyOn(Bun, "build").mockResolvedValueOnce({
      success: false,
      logs: ["error1", "error2"]
    } as any);

    try {
      await expect(buildSite(testOutDir)).rejects.toThrow(AggregateError);
    } finally {
      mockBuild.mockRestore();
      await rm(testOutDir, { recursive: true, force: true });
    }
  });

  test("builds successfully when bundling passes", async () => {
    const mockBuild = spyOn(Bun, "build").mockResolvedValueOnce({
      success: true,
      logs: []
    } as any);

    try {
      const result = await buildSite(testOutDir);
      expect(result).toBe(testOutDir);
    } finally {
      mockBuild.mockRestore();
      await rm(testOutDir, { recursive: true, force: true });
    }
  });
});
