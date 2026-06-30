# <{{ app_name }}> Frontend

React + TypeScript + Ionic 8 PWA, built with Vite and pnpm.

## Local dev

```bash
pnpm install
pnpm dev          # dev server at http://localhost:5173
```

Create a `.env.local` file (not committed) with:

```
VITE_API_BASE=http://localhost:8000
```

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
