import { test, expect, describe, spyOn } from "bun:test";
import { buildSite } from "../src/build";
import { resolve } from "node:path";
import { rm } from "node:fs/promises";

describe("buildSite", () => {
  test("throws AggregateError when bundling fails", async () => {
    const buildMock = spyOn(Bun, "build").mockResolvedValue({
      success: false,
      logs: ["error 1", "error 2"],
    } as any);

    try {
      const outDir = resolve(import.meta.dir, "..", "dist-test");

      let error: Error | undefined;
      try {
        await buildSite(outDir);
      } catch (err: any) {
        error = err;
      }

      expect(error).toBeInstanceOf(AggregateError);
      expect(error?.message).toBe("shell bundle failed");
      expect((error as AggregateError).errors).toEqual(["error 1", "error 2"]);

      // Cleanup
      await rm(outDir, { recursive: true, force: true });
    } finally {
      buildMock.mockRestore();
    }
  });
});
