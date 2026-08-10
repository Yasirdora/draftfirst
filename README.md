# Draft First Screenwriting

[![npm version](https://img.shields.io/npm/v/%40draftfirst%2Fcore?label=%40draftfirst%2Fcore&color=cb3837)](https://www.npmjs.com/package/@draftfirst/core)
[![npm downloads](https://img.shields.io/npm/dm/%40draftfirst%2Fcore?color=cb3837)](https://www.npmjs.com/package/@draftfirst/core)
[![CI](https://github.com/Yasirdora/draftfirst/actions/workflows/ci.yml/badge.svg)](https://github.com/Yasirdora/draftfirst/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-2ea44f.svg)](./LICENSE)

Draft First is a privacy-first screenwriting workspace backed by a reusable,
framework-independent TypeScript engine. It supports Fountain and a deliberately
bounded subset of FDX, deterministic screenplay pagination, story-aware writing
assistance, and continuity analysis without sending a writer's work to a server.

Development began in November 2025. The first public engine release was prepared
in August 2026 after the document model, interoperability layer, pagination, and
editor policies were separated into a tested package.

- Website: [draftfirst.xyz](https://draftfirst.xyz)
- npm package: [`@draftfirst/core`](https://www.npmjs.com/package/@draftfirst/core)
- Package source: [`packages/draftfirst`](./packages/draftfirst)
- License: [MIT](./LICENSE)

## Why this project exists

Screenwriting software should be predictable, portable, and honest about file
compatibility. Draft First separates document logic from interface code so the
same tested engine can power a browser editor, command-line tool, desktop app,
or integration without bringing along a UI framework.

The engine provides:

- a typed screenplay document model with runtime validation;
- Fountain parsing, serialization, and normalization;
- bounded FDX import and export with explicit compatibility diagnostics;
- deterministic pagination and runtime estimates;
- document-derived character, location, and continuity intelligence;
- framework-free prediction and keyboard-choreography policies;
- zero runtime dependencies, network requests, telemetry, or file-system access.

## Install the engine

```sh
npm install @draftfirst/core
```

```ts
import { parseFountain, validateScreenplay } from '@draftfirst/core';
import { paginate } from '@draftfirst/core/layout';

const screenplay = parseFountain(`INT. KITCHEN - NIGHT

MARA
We begin.`);

const validation = validateScreenplay(screenplay);
if (!validation.ok) {
	console.error(validation.diagnostics);
}

const pages = paginate(screenplay);
```

The package API, supported formats, limitations, and security model are
documented in the [`@draftfirst/core` README](./packages/draftfirst/README.md).
The Svelte editor is intentionally not shipped in the npm package.

## Repository structure

```text
packages/draftfirst/          Public @draftfirst/core package
  src/                        Document, format, layout, and analysis modules
  README.md                   Package API and compatibility contract
src/lib/components/
  ScriptEditor.svelte         Draft First web editor
src/lib/screenplay/
  pdf.ts                      App-only PDF export
  sample.ts                   App-only sample screenplay
src/routes/                     The editor at `/` (legacy `/screenplay` redirects)
scripts/                      Package-boundary and release verification
.github/workflows/            Continuous integration and npm publishing
```

PDF export remains app-only until its Unicode font embedding and text extraction
are suitable for a stable public API. Keeping it outside the package avoids
promising fidelity the first release cannot yet guarantee.

## Development

The public engine supports Node.js 20 or newer. Repository development and the
web application use Node.js 22, as recorded in `.nvmrc`.

```sh
npm install
npm run dev
```

Useful verification commands:

```sh
npm run check             # Svelte and TypeScript checks
npm test                  # application and package tests
npm run package:verify    # API, types, tests, build, and package linting
npm run package:smoke     # install the packed tarball in a clean consumer
npm run quality           # complete release gate
```

Production builds are emitted to `build/` and can be served by any static host.
The included Cloudflare Pages configuration uses the same build output.

## Compatibility and security

Draft First treats imported documents as untrusted input. Parsers enforce
resource limits, FDX processing does not resolve external entities, and lossy or
unsupported conversions return diagnostics. Applications should retain original
production files and review those diagnostics before replacing them.

Please report security issues through
[GitHub private vulnerability reporting](https://github.com/Yasirdora/draftfirst/security)
instead of a public issue. See [SECURITY.md](./SECURITY.md) for the policy.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](./CONTRIBUTING.md) and
run `npm run quality` before opening a pull request.

## License

MIT © 2026 Yasir Dora.
