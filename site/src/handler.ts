import { tryServeStatic } from "@tschk/moonshine-server";
import { renderResponse } from "./document";

async function handleRoot(request: Request): Promise<Response> {
  return renderResponse(request);
}

async function handleStatic(
  request: Request,
  pathname: string,
  staticDir: string,
): Promise<Response> {
  if (request.method === "GET" || request.method === "HEAD") {
    const staticRes = await tryServeStatic(staticDir, pathname);
    if (staticRes) return staticRes;
  }
  return new Response("Not Found", { status: 404 });
}

export function createHandler(staticDir: string) {
  return async function handler(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const pathname = url.pathname.replace(/\/+$/, "") || "/";

    if (pathname === "/") {
      return handleRoot(request);
    }

    return handleStatic(request, pathname, staticDir);
  };
}
