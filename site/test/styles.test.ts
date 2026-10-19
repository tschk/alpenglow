import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("globalCss", () => {
  test("exports a string", () => {
    expect(typeof globalCss).toBe("string");
  });

  test("contains @font-face definition", () => {
    expect(globalCss).toContain("@font-face");
    expect(globalCss).toContain('font-family: "Geist Mono"');
  });

  test("contains :root variables", () => {
    expect(globalCss).toContain(":root");
    expect(globalCss).toContain("color-scheme: dark");
  });

  test("contains key class selectors", () => {
    const classes = [
      ".boot-top-bar",
      ".boot-top-sep",
      ".page-shell",
      ".hidden",
      ".boot-status",
      ".site-credit",
    ];
    for (const cls of classes) {
      expect(globalCss).toContain(cls);
    }
  });
});
