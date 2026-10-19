import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("styles", () => {
  test("globalCss exports correct string", () => {
    expect(typeof globalCss).toBe("string");
    expect(globalCss).toContain("@font-face");
    expect(globalCss).toContain("Geist Mono");
    expect(globalCss).toContain(".boot-top-bar");
    expect(globalCss).toContain(".page-shell");
  });
});
