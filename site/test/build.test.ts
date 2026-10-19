import { describe, expect, test, spyOn } from "bun:test";
import { buildSite } from "../src/build";
import { join } from "node:path";
import { tmpdir } from "node:os";

describe("buildSite", () => {
  test("builds the site successfully", async () => {
    const testOutDir = join(tmpdir(), `buildSite-test-${Math.random()}`);
    const resultDir = await buildSite(testOutDir);
    expect(resultDir).toBe(testOutDir);
    expect(await Bun.file(join(testOutDir, "index.html")).exists()).toBe(true);
    expect(await Bun.file(join(testOutDir, "shell.js")).exists()).toBe(true);
  });

  test("throws AggregateError when Bun.build fails", async () => {
    const buildSpy = spyOn(Bun, "build").mockResolvedValue({
      success: false,
      logs: ["mock error log"],
    } as any);

    const testOutDir = join(tmpdir(), `buildSite-test-${Math.random()}`);

    try {
      let error: any;
      try {
        await buildSite(testOutDir);
      } catch (e) {
        error = e;
      }
      expect(error).toBeInstanceOf(AggregateError);
      expect(error.message).toBe("shell bundle failed");
      expect(error.errors).toEqual(["mock error log"]);
    } finally {
      buildSpy.mockRestore();
    }
  });
});
