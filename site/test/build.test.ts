import { test, expect, spyOn } from "bun:test";
import { buildSite } from "../src/build";
import { resolve } from "node:path";
import { rm } from "node:fs/promises";

test("buildSite throws AggregateError on bundle failure", async () => {
  const mockBuild = spyOn(Bun, "build").mockResolvedValue({
    success: false,
    logs: ["mocked error 1", "mocked error 2"],
  } as any);

  const outDir = resolve(import.meta.dir, "..", "dist-test-fail");
  try {
    let error;
    try {
      await buildSite(outDir);
    } catch (e) {
      error = e;
    }

    expect(error).toBeInstanceOf(AggregateError);
    expect((error as Error).message).toBe("shell bundle failed");
    expect((error as AggregateError).errors).toEqual(["mocked error 1", "mocked error 2"]);
  } finally {
    mockBuild.mockRestore();
    await rm(outDir, { recursive: true, force: true });
  }
});
