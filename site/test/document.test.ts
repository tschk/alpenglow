import { describe, expect, test } from "bun:test";
import { renderDocument, renderResponse } from "../src/document";

describe("renderResponse", () => {
  test("returns Response with expected headers and HTML", async () => {
    const req = new Request("http://localhost/");
    const res = await renderResponse(req);
    expect(res).toBeInstanceOf(Response);
    expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
    const html = await res.text();
    expect(html).toContain("<!DOCTYPE html>");
  });
});

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

  test("injects expected head tags", async () => {
    const req = new Request("http://localhost/");
    const html = await renderDocument(req);
    expect(html).toContain('<link rel="icon" href="/favicon.png" type="image/png">');
    expect(html).toContain('<link rel="preload" href="/fonts/geist-mono-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>');
    expect(html).toContain('<link rel="modulepreload" href="/shell.js">');
    expect(html).toContain('<style>');
  });

  test("injects expected body script tag", async () => {
    const req = new Request("http://localhost/");
    const html = await renderDocument(req);
    expect(html).toContain('<script type="module" src="/shell.js"></script></body>');
  });

  test("respects AbortSignal", async () => {
    const controller = new AbortController();
    controller.abort();
    const req = new Request("http://localhost/", { signal: controller.signal });
    try {
      await renderDocument(req);
      expect.unreachable();
    } catch (e: any) {
      expect(e.name).toBe("AbortError");
    }
  });
});
