# Alpenglow site

The Alpenglow site is built with [moonshine](https://github.com/tschk/moonshine) — a Bun-first web framework. It runs on Bun with React 19 server-rendered through `@tschk/moonshine-react` and served by `@tschk/moonshine-deploy-bun`.

## Stack

- **Runtime:** Bun
- **Framework:** moonshine (`@tschk/moonshine-framework`, `@tschk/moonshine-server`, `@tschk/moonshine-deploy-bun`)
- **Renderer:** `@tschk/moonshine-react` — React 19 server rendering
- **Client:** `src/shell.js`, bundled to `dist/shell.js` (ghostty-web terminal + v86 emulator)

## Layout

```
src/App.tsx       page markup
src/styles.ts     global CSS
src/document.ts   route artifact + document assembly
src/shell.js      browser entry (bundled)
src/build.ts      static build → dist/
src/server.ts     Bun dev/preview server
public/           static assets (fonts, favicon, v86 kernel + initrd)
```

## Develop

```sh
bun install
bun run dev      # http://localhost:3000
```

## Build / preview

```sh
bun run build    # writes dist/ (index.html + bundled shell.js + public assets)
bun run start    # respects PORT env
```

## Test

```sh
bun test
bun run typecheck
```

## Deploy

The site is hosted on Cloudflare Pages (project `alpenglow`, domain `alpenglow.tsc.hk`). There is no CI deploy workflow; deploys are manual from the repository root:

```sh
bun run deploy   # build + wrangler pages deploy site/dist --project-name alpenglow
```

## Benchmarks

Local dev-server benchmarks, measured on the same host. "Before" is the previous Astro site (`astro dev`); "After" is this moonshine site (`bun run start`). Each average is the mean of 10 sequential `curl` requests after a warm-up request.

| Metric              | Before (Astro, local) | After (moonshine, local) |
|---------------------|-----------------------|--------------------------|
| Avg response time   | 8.5ms                 | 6.0ms                    |
| TTFB                | 8.4ms                 | 3.6ms                    |
| HTML size           | 7.9KB                 | 25.1KB                   |
| Stack               | Astro                 | Bun + React SSR          |
