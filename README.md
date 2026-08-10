# Writing Desk

A privacy-first Markdown editor: write on a typeset page or in source, export clean HTML or print to PDF. **Nothing leaves your browser** — no accounts, no uploads, no tracking.

This is a production SvelteKit port of the original single-file `writing-desk.html`.

## Features

- **Dual surfaces** — Page (contenteditable), Markdown source, or split view
- **Custom Markdown engine** — CommonMark + GFM tables, task lists, strikethrough (no raw HTML)
- **Safe by design** — every string escaped; URLs filtered (`javascript:` blocked)
- **localStorage only** — documents never leave the device
- **Export** — `.md`, standalone `.html`, print / PDF
- **Focus mode**, outline, floating format toolbar, offline after first visit (service worker)

## Stack

- SvelteKit 2 + Svelte 5 (runes)
- TypeScript
- `@sveltejs/adapter-static` (deploy anywhere as static files)
- Vitest for pure markdown cores

## Develop

```sh
npm install
npm run dev
```

## Test

```sh
npm test
npm run check
```

## Build & deploy

```sh
npm run build
npm run preview
```

Output is in `build/`. Host on any static file server (Netlify, Cloudflare Pages, GitHub Pages, S3, nginx, etc.).

### GitHub Pages note

If the site is served under a subpath, set `kit.paths.base` in Vite / Kit config accordingly.

## Architecture

```
src/lib/markdown/     Pure cores (Node-testable)
  render.ts           MD → safe HTML
  serialise.ts        contenteditable DOM → Markdown
  format.ts           source-range format toggles
src/lib/components/
  WritingDesk.svelte  App shell, dual-surface sync, toolbar, export
src/lib/utils/        storage, download, export HTML
src/service-worker.ts Offline precache
```

The original single-file reference remains at `writing-desk.html`.

## Privacy

- No analytics
- No third-party scripts or fonts
- No network calls for document content
- Service worker only caches this app’s own assets

## License

Use freely for personal or commercial projects unless otherwise noted.
