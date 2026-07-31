# Alpenglow site

The Alpenglow marketing/site is built with [moonshine](https://github.com/tschk/moonshine) — a Bun-first web framework with a Crepus IR renderer. It runs on Bun with React components compiled to a Crepus intermediate representation served by `@tschk/moonshine-deploy-bun`.

## Stack

- **Runtime:** Bun
- **Framework:** moonshine (`@tschk/moonshine-framework`, `@tschk/moonshine-server`, `@tschk/moonshine-deploy-bun`)
- **Renderer:** Crepus (`@tschk/crepus-moonshine`) — renders a Crepus IR artifact to HTML
- **UI:** React 19 (compiled to Crepus IR at build time)

## Develop

```sh
bun install
bun run dev      # http://localhost:3000
```

## Build / preview

```sh
bun run build
bun run start    # respects PORT env
```

## Test

```sh
bun test
bun run typecheck
```

## Benchmarks

Local dev-server benchmarks, measured on the same host. "Before" is the previous Astro site (`astro dev`); "After" is this moonshine site (`bun run start`). Each average is the mean of 10 sequential `curl` requests after a warm-up request.

| Metric              | Before (Astro, local) | After (moonshine, local) |
|---------------------|-----------------------|--------------------------|
| Avg response time   | 8.5ms                 | 6.0ms                    |
| TTFB                | 8.4ms                 | 3.6ms                    |
| HTML size           | 7.9KB                 | 25.1KB                   |
| Stack               | Astro                 | Bun + React + Crepus IR  |
