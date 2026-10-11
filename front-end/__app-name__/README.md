# <{{ app_name }}> Frontend

React + TypeScript + Ionic 8 PWA, built with Vite and pnpm.

## Local dev

```bash
pnpm install
pnpm dev          # dev server at http://localhost:<{{ dev_fe_port }}>
```

`VITE_API_BASE` (the backend origin for `dataApi`) comes from the committed `.env.development`, which Vite loads for `pnpm dev` only. Deployed builds set it from CI / `manual-deploy-frontend.sh`; there is no fallback, so a missing value throws at startup.

## Auth: two origins

Auth uses the Token-Mediating Backend (TMB) pattern, so the app talks to two RTK Query APIs:

- **`authApi`** (`src/rtk/auth-api.ts`) — same-origin, `baseUrl: '/auth'`, `credentials: 'include'`. Carries the opaque `HttpOnly` session cookie. In dev, Vite proxies `/auth/*` to the backend (`server.proxy` in `vite.config.ts`); in prod, CloudFront routes `/auth/*` to the auth Lambda. The refresh token never touches the browser.
- **`dataApi`** (`src/rtk/data-api.ts`) — cross-origin, `baseUrl: VITE_API_BASE`, `credentials: 'omit'`, sends `Authorization: Bearer <accessToken>`. Used for todos and other data endpoints.

Because `/auth/*` is proxied, keep `VITE_API_BASE` pointed at the backend for data calls; the proxy handles auth automatically.

## Scripts

| Script | What it does |
|---|---|
| `pnpm dev` | Start dev server with HMR |
| `pnpm build` | Production build |
| `pnpm lint` | Run ESLint |
| `pnpm test` | Run Vitest unit tests |
| `pnpm test:watch` | Vitest in watch mode |
| `pnpm storybook` | Launch Storybook component explorer |
| `pnpm build-storybook` | Build static Storybook |
| `pnpm e2e` | Run Playwright end-to-end tests (starts dev server automatically) |
