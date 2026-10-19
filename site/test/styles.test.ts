import { describe, expect, test } from "bun:test";
import { globalCss } from "../src/styles";

describe("globalCss", () => {
  test("exports a string containing expected CSS rules", () => {
    expect(typeof globalCss).toBe("string");
    expect(globalCss).toContain("@font-face");
    expect(globalCss).toContain(":root");
    expect(globalCss).toContain("html");
    expect(globalCss).toContain(".boot-top-bar");
    expect(globalCss).toContain("#xterm_host");
  });
});
