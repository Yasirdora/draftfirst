# Changelog

All notable changes to the Draft First Screenwriting Engine will be documented here. The project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Universal import behind `@draftfirst/core/import`: a shared classifier that gives every imported line a type, a confidence, and a plain-language reason, with low-confidence lines flagged in an `ImportReport` for writer review.
- Dependency-free `.docx` import: hand-rolled ZIP reader (stored + deflated via the platform's native `DecompressionStream`, CRC-32 integrity, size caps) and OOXML reading for styles, indents, alignment, page breaks, tracked changes, tables, and images.
- Plain-text and paste import covering typewriter layout and reflowed prose, with pagination artifacts (`(MORE)`, `CONTINUED`, page numbers) stripped and counted.
- `.docx` export (`writeDocx`) closing the round trip: production-office OOXML with Courier New 12pt, screenplay margins and indents, `keepNext` speech protection, and title-page emission — verified by reading exports back through the importer.

## [0.1.0] - 2026-08-10

### Added

- Typed screenplay document model and runtime validation.
- Fountain parsing and serialization.
- Best-effort FDX import and deterministic export with diagnostics.
- Deterministic screenplay pagination and runtime estimation.
- Story-aware prediction, continuity, SmartType, and editor choreography cores.
- ESM exports and TypeScript declarations with zero runtime dependencies.

[Unreleased]: https://github.com/Yasirdora/draftfirst/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Yasirdora/draftfirst/releases/tag/v0.1.0
