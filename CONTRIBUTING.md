# Contributing to Draft First

Thank you for helping writers keep control of their work.

## Development

Draft First requires Node.js 22 for repository development. Install the exact
dependency graph and run the full quality gate before opening a pull request:

```sh
npm ci
npm run quality
```

The public engine lives in `packages/draftfirst`. The Svelte editor is a package
consumer and must not be imported by the engine.

## Changes to file formats

- Add a minimal fixture that demonstrates the behavior.
- Test malformed and maximum-size input as well as the happy path.
- Preserve writer text whenever recovery is possible.
- Return a stable diagnostic for unavoidable loss or unsupported semantics.
- Never describe a partial Fountain or FDX implementation as lossless.

## Pull requests

Keep changes focused, document public API changes in the package changelog, and
include tests for every bug fix. Public API removals wait for a major release;
the package is pre-1.0, but compatibility remains an explicit design concern.

Maintainers should follow [RELEASING.md](./RELEASING.md) for versioning,
publication, and provenance requirements.
