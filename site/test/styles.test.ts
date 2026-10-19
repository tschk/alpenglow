import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("styles", () => {
  test("exports globalCss as a string", () => {
    expect(typeof globalCss).toBe("string");
  });

  test("globalCss contains expected font-face", () => {
    expect(globalCss).toContain('@font-face {');
    expect(globalCss).toContain('font-family: "Geist Mono";');
  });

  test("globalCss contains expected root styles", () => {
    expect(globalCss).toContain(':root {');
    expect(globalCss).toContain('color-scheme: dark;');
  });

  test("globalCss contains boot-top-bar styles", () => {
    expect(globalCss).toContain('.boot-top-bar {');
    expect(globalCss).toContain('pointer-events: auto;');
  });
});
