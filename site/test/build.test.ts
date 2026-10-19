import { describe, expect, test, mock, spyOn, afterEach } from "bun:test";
import { buildSite } from "../src/build";
import { resolve } from "node:path";
import { rm } from "node:fs/promises";

describe("buildSite", () => {
  afterEach(() => {
    mock.restore();
  });

  test("throws AggregateError when bundle fails", async () => {
    const buildSpy = spyOn(Bun, "build").mockResolvedValue({
      success: false,
      logs: ["mock error log 1", "mock error log 2"],
    } as any);

    const outDir = resolve(import.meta.dir, "..", "dist_test");

    try {
      await buildSite(outDir);
      expect(true).toBe(false); // should not reach here
    } catch (e) {
      expect(e).toBeInstanceOf(AggregateError);
      expect((e as AggregateError).message).toBe("shell bundle failed");
      expect((e as AggregateError).errors).toEqual(["mock error log 1", "mock error log 2"]);
    } finally {
      await rm(outDir, { recursive: true, force: true });
    }
  });
});
