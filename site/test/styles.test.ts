import { test, expect, describe } from "bun:test";
import { globalCss } from "../src/styles.ts";

describe("styles", () => {
  test("globalCss is a string", () => {
    expect(typeof globalCss).toBe("string");
  });

  test("globalCss contains necessary styles", () => {
    expect(globalCss).toContain("@font-face");
    expect(globalCss).toContain("font-family: \"Geist Mono\"");
    expect(globalCss).toContain(":root");
    expect(globalCss).toContain("html,");
    expect(globalCss).toContain("body");
    expect(globalCss).toContain(".boot-top-bar");
    expect(globalCss).toContain(".page-shell");
    expect(globalCss).toContain(".hidden");
    expect(globalCss).toContain(".boot-status");
    expect(globalCss).toContain(".site-credit");
    expect(globalCss).toContain("#xterm_host");
  });
});
