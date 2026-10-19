import { describe, expect, test, spyOn, afterAll } from "bun:test";
import { resolve } from "node:path";
import { rm } from "node:fs/promises";
import { buildSite } from "../src/build";

describe("buildSite", () => {
  const testDist = resolve(import.meta.dir, "..", "test-dist");

  test("builds the site successfully", async () => {
    const result = await buildSite(testDist);
    expect(result).toBe(testDist);
    expect(await Bun.file(resolve(testDist, "index.html")).exists()).toBe(true);
    expect(await Bun.file(resolve(testDist, "shell.js")).exists()).toBe(true);
  });

  test("throws AggregateError when bundling fails", async () => {
    const originalBuild = Bun.build;
    spyOn(Bun, "build").mockResolvedValueOnce({
      success: false,
      logs: ["mock error log"],
    } as any);

    try {
      await buildSite(testDist);
      expect(true).toBe(false);
    } catch (e) {
      expect(e).toBeInstanceOf(AggregateError);
      expect((e as AggregateError).message).toBe("shell bundle failed");
      expect((e as AggregateError).errors).toEqual(["mock error log"]);
    } finally {
      spyOn(Bun, "build").mockImplementation(originalBuild);
    }
  });

  afterAll(async () => {
    await rm(testDist, { recursive: true, force: true });
  });
});
