import { describe, expect, test } from "bun:test";
import { renderDocument } from "../src/document";

describe("renderDocument", () => {
  test("renders HTML with expected tokens", async () => {
    const req = new Request("http://localhost/");
    const html = await renderDocument(req);
    expect(html).toContain("<!DOCTYPE html>");
    expect(html).toContain('<html lang="en">');
    expect(html).toContain("<head>");
    expect(html).toContain("</head>");
    expect(html).toContain("<body>");
    expect(html).toContain("</body>");
    expect(html).toContain('<meta charset="utf-8">');
    expect(html).toContain('<title>Alpenglow</title>');
  });
});
