import { describe, expect, test, spyOn } from "bun:test";
import { buildSite } from "../src/build";
import { resolve } from "node:path";

describe("buildSite", () => {
  test("throws AggregateError when Bun.build fails", async () => {
    const mockBuild = spyOn(Bun, "build").mockImplementation(async () => {
      return { success: false, logs: ["mocked build error"] } as any;
    });

    try {
      const outDir = resolve(import.meta.dir, "..", "dist-test-fail");
      await expect(buildSite(outDir)).rejects.toThrow(AggregateError);
    } finally {
      mockBuild.mockRestore();
    }
  });
});
