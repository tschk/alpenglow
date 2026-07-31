import { reactRenderer } from "@tschk/moonshine-react";
import type { RenderContext, RouteArtifact } from "@tschk/moonshine-framework";
import { resolve } from "node:path";
import { description, title } from "./App";
import { globalCss } from "./styles";

export const clientEntry = "/shell.js";

export const route: RouteArtifact = {
  id: "home",
  path: "/",
  file: resolve(import.meta.dir, "App.tsx"),
  mode: "static",
  runtime: "bun",
  decision: "server",
  clientEntries: [clientEntry],
};

const headTags = [
  '<meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width, initial-scale=1">',
  `<meta name="description" content="${description}">`,
  `<title>${title}</title>`,
  '<link rel="icon" href="/favicon.png" type="image/png">',
  '<link rel="preload" href="/fonts/geist-mono-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>',
  `<link rel="modulepreload" href="${clientEntry}">`,
  `<style>${globalCss}</style>`,
].join("");

const bodyTags = `<script type="module" src="${clientEntry}"></script>`;

export async function renderDocument(request: Request): Promise<string> {
  const context: RenderContext = {
    request,
    route,
    params: {},
    data: null,
    signal: request.signal,
  };
  const html = await reactRenderer.prerender(context);
  return html
    .replace("<html>", '<html lang="en">')
    .replace("<head>", `<head>${headTags}`)
    .replace("</body>", `${bodyTags}</body>`);
}

export async function renderResponse(request: Request): Promise<Response> {
  return new Response(await renderDocument(request), {
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}
