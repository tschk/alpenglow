import { describe, expect, test, mock, spyOn, afterEach } from "bun:test";
import * as serverModule from "../src/server";
import * as moonshineServer from "@tschk/moonshine-server";

describe("server.ts handler", () => {
  let tryServeStaticSpy: ReturnType<typeof spyOn>;

  afterEach(() => {
    if (tryServeStaticSpy) tryServeStaticSpy.mockRestore();
  });

  test("server is not started on import (import.meta.main is false)", () => {
    expect(serverModule.server).toBeUndefined();
  });

  test("GET / returns 200 and renders response", async () => {
    const req = new Request("http://localhost:3000/");
    const res = await serverModule.handler(req);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
  });

  test("Trailing slashes are removed from pathname", async () => {
    const req = new Request("http://localhost:3000////");
    const res = await serverModule.handler(req);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
  });

  test("GET /static.txt serves static file using mocked tryServeStatic", async () => {
    tryServeStaticSpy = spyOn(moonshineServer, "tryServeStatic").mockImplementation(async (dir, pathname) => {
      if (pathname === "/static.txt") {
        return new Response("mocked static", { status: 200, headers: { "content-type": "text/plain" } });
      }
      return null;
    });

    const req = new Request("http://localhost:3000/static.txt");
    const res = await serverModule.handler(req);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/plain");
    expect(await res.text()).toBe("mocked static");
    expect(tryServeStaticSpy).toHaveBeenCalled();
  });

  test("HEAD request serves static file", async () => {
    tryServeStaticSpy = spyOn(moonshineServer, "tryServeStatic").mockImplementation(async () => {
      return new Response("", { status: 200 });
    });
    const req = new Request("http://localhost:3000/static.txt", { method: "HEAD" });
    const res = await serverModule.handler(req);
    expect(res.status).toBe(200);
  });

  test("GET /not-found returns 404", async () => {
    tryServeStaticSpy = spyOn(moonshineServer, "tryServeStatic").mockImplementation(async () => null);
    const req = new Request("http://localhost:3000/not-found");
    const res = await serverModule.handler(req);
    expect(res.status).toBe(404);
    expect(await res.text()).toBe("Not Found");
  });

  test("POST / returns 404 for non-root paths since only GET/HEAD are allowed for static", async () => {
    const req = new Request("http://localhost:3000/static.txt", { method: "POST" });
    const res = await serverModule.handler(req);
    expect(res.status).toBe(404);
  });
});
