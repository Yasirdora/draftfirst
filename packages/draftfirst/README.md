# Draft First Screenwriting Engine

The Draft First Screenwriting Engine is a framework-free TypeScript library for
screenplay documents. It parses and serializes Fountain, imports and exports a
deliberately bounded FDX subset, paginates screenplay elements deterministically,
and derives useful story context without sending a writer's work anywhere.

Draft First has been under development since November 2025. Version `0.1.0` is
the first public package release.

```sh
npm install @draftfirst/core
```

```ts
import { parseFountain, serializeFountain, validateScreenplay } from '@draftfirst/core';
import { paginate } from '@draftfirst/core/layout';

const script = parseFountain(`INT. KITCHEN - NIGHT

MARA
We begin.`);

const validation = validateScreenplay(script);
if (!validation.ok) {
	console.error(validation.diagnostics);
}

const pages = paginate(script);
const fountain = serializeFountain(script);
```

## Public modules

- `@draftfirst/core` — document types, validation, and the stable Fountain API
- `@draftfirst/core/fountain` — Fountain parsing, serialization, and normalization
- `@draftfirst/core/fdx` — bounded, best-effort FDX interoperability
- `@draftfirst/core/layout` — deterministic pagination and runtime estimates
- `@draftfirst/core/analysis` — SmartType and continuity analysis
- `@draftfirst/core/editor` — framework-free prediction and keyboard choreography

The Svelte editor used at [draftfirst.xyz](https://draftfirst.xyz) is not part of
this package. The package contains no UI framework, network, storage, analytics,
or runtime dependencies.

## Compatibility contract

Draft First preserves screenplay text and reports unsupported or malformed input
instead of silently claiming perfect compatibility. Fountain and FDX are richer
than a single initial release can safely promise:

- Fountain title pages, scenes, action, cues, dialogue, parentheticals,
  transitions, shots, centered text, lyrics, notes, sections, synopses, dual
  dialogue, scene numbers, and page breaks are supported.
- FDX support focuses on paragraph content, common paragraph types, scene
  numbers, dual-dialogue markers, and title-page text. Formatting runs,
  production revisions, locked pages, macros, and arbitrary Final Draft metadata
  are not yet fidelity-preserving.
- PDF generation is intentionally not exported in `0.1.0`; correct Unicode font
  embedding and extraction must land before it becomes a public contract.

Keep the original file when importing an irreplaceable production document and
review returned FDX diagnostics before replacing it.

## Security and resource limits

The engine does not execute scripts, load external entities, access the network,
or read files. Public parsers and validators enforce bounded input and return
diagnostics for malformed data. Applications should still enforce their own file
size limits before reading a user-selected file into memory.

Security reports should use GitHub's private vulnerability reporting for the
[Draft First repository](https://github.com/Yasirdora/draftfirst/security).

## Support

Draft First is ESM-only and supports Node.js 20 or newer and modern browsers.
TypeScript declarations are included. The public API is pre-1.0 and may evolve
through documented minor releases.

Draft First is not affiliated with or endorsed by Final Draft, Inc.

## License

[MIT](./LICENSE) © 2026 Yasir Dora.
