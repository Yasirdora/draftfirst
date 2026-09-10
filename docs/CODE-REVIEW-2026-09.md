# Code Review — September 2026

*Written 2026-09-10, on branch `rename/edraft`, HEAD `5f0f803` plus an
uncommitted page-gap refactor in `EDraftMacSurface`/`EDraftCore`.*

## Scope, method, and honesty about coverage

The original plan was a full line-by-line pass over all ~56k lines via parallel
review agents. Token-budget limits killed the agents twice, so the review was
executed directly and prioritised by risk instead. **Read line-by-line:** the
TypeScript engine's parse, classify, paginate, serialise, choreography,
smarttype, rename, continuity, validation, zip, docx, pdfsignal, and platform
modules; the conformance exporter; the boundary checker; the web service
worker; CI workflows; and the Swift engine's file inventory plus targeted
spot-checks. **Reviewed by sweep, not line-by-line:** `fdx.ts` (1,322 lines,
covered by 44 tests + an adversarial conformance fixture), `predict.ts` (85
tests + fixture), `EDraftCore`, `EDraftUIKitSurface`, the iOS app target, and
`ScriptEditor.svelte` (2,811 lines — targeted greps only). Those remain owed a
deep pass and are listed under "Remaining debt" below.

### Baseline (run before review)

| Suite | Result |
|---|---|
| `npm test` | 428 passed |
| `swift test apple/eDraftEngine` | 112 passed |
| `swift test apple/EDraftCore` | 149 passed |
| `swift test apple/EDraftUI` | 24 passed |
| `npm run check:boundaries` | holds (73 files scanned) |
| `swift test apple/EDraftMacSurface` | **fails to compile — see C1** |

---

## Critical

### C1 — The working tree does not compile

`swift build --package-path apple/EDraftMacSurface` fails:

- `PageGapContainer.swift:18` — main-actor-isolated `init(size:)` /
  `init(coder:)` override nonisolated superclass initialisers.
- `PageGapContainer.swift:51` — `ScreenplayPageLayout` not in scope.
- `PageGapContainer.swift:50` — main-actor-isolated `bandMeeting` called from
  a nonisolated context.

The tree carries an uncommitted, half-landed refactor: untracked
`PageGapContainer.swift`, `PageGapContainerTests.swift`,
`LayoutBenchmarkTests.swift`, and modifications to
`EDraftCore/ScreenplayPageLayout.swift`, `PageCanvasView.swift`,
`ScriptLayout.swift`, `ScriptSurface.swift`. Pushed as-is, this breaks the CI
`swift-packages` job. If this refactor is being driven by another session,
this is informational; otherwise the fix is to give `PageGapContainer` the
same actor isolation as its `NSView` superclass expects and import/qualify
`ScreenplayPageLayout`.

### C2 — `inflateRaw` accumulates unboundedly before checking the declared size

`packages/edraft/src/platform.ts:71-86` reads the entire inflation stream into
`chunks` and only afterwards compares `out.length !== expectedSize` (line 86).
`zip.ts:104` validates the *declared* `rawSize` against `maxEntryBytes` before
inflating — but a hostile archive can declare 1 KB and deflate to gigabytes;
the declared-size guard never sees the real output, and the length check in
`inflateRaw` fires only after the memory is already gone. A 32 MB `.docx`
(the `importDocx` cap) at DEFLATE's worst-case ratio is a device-killing
allocation. **Direction:** abort the read loop as soon as the running `length`
exceeds `expectedSize` — one comparison per chunk — so the bomb dies at the
64 MB entry cap instead of at the OOM killer.

---

## Bugs

### B1 — The conformance corpus can go silently stale; nothing checks freshness

`scripts/engine-conformance-export.mjs` regenerates the golden masters that
pin Swift to TypeScript, but no automated step verifies freshness: `npm run
quality` (package.json:25) does not include it, and `.github/workflows/ci.yml`
runs the Swift tests against whatever fixtures happen to be committed. A TS
engine change whose author forgets `npm run engine:conformance` leaves the
Swift port pinned to yesterday's behaviour — the exact drift the corpus exists
to prevent, and invisible in CI. Compounding it: the exporter imports from
`packages/edraft/dist/` (lines 17–33) without building first, so a stale `dist/`
produces "fresh-looking" fixtures from old code. **Direction:** a CI step that
builds the package, regenerates into a temp dir, and `diff -r` against
`apple/eDraftEngine/Fixtures/`.

### B2 — The boundary checker is evadable with submodule imports

`scripts/check-swift-boundaries.mjs:69` matches `^\s*(?:@\w+\s+)?import\s+([A-Za-z_]…)`.
Legal Swift `import struct UIKit.NSView` / `import class AppKit.NSWindow`
captures `struct`/`class` as the module name and sails through every ban list.
The layer rule this script enforces (rule 3 in HANDOFF) is one `import struct`
away from silently breaking. **Direction:** capture the module after an
optional `(struct|class|func|var|let|typealias|enum|protocol)\s+` token.

### B3 — Legacy PDF marker list contains the current marker, not the legacy one

`packages/edraft/src/pdfsignal.ts:32-34`:

```ts
export const LEGACY_PDF_MARKER_PREFIXES: readonly string[] = Object.freeze([
	'EDRAFT_FOUNTAIN'
]);
```

The comment says this is "the prefix written before the eDraft rename… we read
it forever and never write it again" — but `PDF_MARKER_PREFIX` (line 23) *is*
`'EDRAFT_FOUNTAIN'`. The legacy list duplicates the current prefix, so the
actual pre-rename marker (whatever the app was called before) is recognised by
nobody: every PDF exported under the old name has silently lost its
source-recovery signal, exactly the writer-backup scenario the comment
promises to protect. **Direction:** find the old marker string in git history
and put *it* in the list.

### B4 — `renameCharacter` and `normalizeCueName` disagree on what a base name is

`rename.ts:50` matches cues with `stripCueExtensions` (smarttype.ts:62), which
strips only a fixed extension list (V.O., O.S., O.C., CONT'D, SUBTITLE,
PRE-LAP, FILTERED, INTO PHONE/RADIO/COMMS). `normalizeCueName` (rename.ts:16)
strips from the *first `(` anywhere*. Consequences, both demonstrated by
reading the two functions against each other:

- `renameCharacter(script, 'MARA', 'MARY')` skips every `MARA (WHISPERING)`
  cue — the target normalises to `MARA`, the cue's base stays
  `MARA (WHISPERING)`.
- `renameCharacter(script, 'MARA (WHISPERING)', 'MARY')` also changes nothing:
  the *target* collapses to `MARA`, which matches neither base form.

The doc comment ("extensions stripped, case ignored") describes neither
behaviour for non-list parentheticals. **Direction:** one shared definition of
"base name" — either extend the extension list, or make both sides strip from
the first `(`.

### B5 — Web autosave fails silently and permanently on quota exhaustion

`ScriptEditor.svelte:1437-1447`: both the debounced autosave and the
pagehide flush wrap `localStorage.setItem` in `try { } catch { /* keep typing
*/ }`. localStorage quotas (~5 MB) are reachable by a feature-length script
with notes, and once full, *every subsequent save throws* — the writer types
on, believes the work is safe, and loses it on close. A local-first app's
save path must never fail silently. **Direction:** on catch, surface a
persistent, blocking-level warning and stop treating the document as saved.

### B6 — Service worker updates stall behind open tabs

`src/service-worker.ts` never calls `skipWaiting()` on install or
`clients.claim()` on activate. Browsers therefore hold the new worker in
"waiting" until every tab of the app closes — for a writing tool whose tabs
live for weeks, security and bug fixes ship never. The per-build cache name
(`edraft-${version}`, line 11) means the stall also pins stale assets. The
trade-off (an open editor mid-session suddenly running new code) is real, so
this wants a deliberate decision — e.g. activate on next navigation, or a
visible "update ready" affordance — not the accidental default.

---

## Inefficiencies

- **I1 — `docx.ts:49-51`**: `attribute()` compiles a new `RegExp` per call,
  several calls per paragraph, on the import hot path. Hoist the patterns or
  write a two-line scanner.
- **I2 — `pdfsignal.ts:74-79`**: `readKeywordsHex` runs a regex per character
  and string-concatenates hex digits; measured-real payloads reach 500k chars.
  Slice to the closer, then validate once.
- **I3 — `paginate.ts:85-109`**: `wrapText` measures in UTF-16 code units. The
  torture fixture pins this deliberately for NEL/combining-mark parity with the
  Swift port, but double-width scripts (CJK) will overflow their column — an
  accepted limitation worth one documenting comment so nobody "fixes" the
  fixtures again.

## Clarity & architecture

- **A1 — `ScriptEditor.svelte` is 2,811 lines.** Autosave, theme, predictions,
  toasts, title-page modal, import/export, and the editor surface all live in
  one component. This is the web app's `ScriptTextView`-shaped risk: every
  future change lands in the same file. Not urgent; worth an extraction pass
  when the web app next gets feature work.
- **A2 — `Paginate.swift:283`** crashes (`preconditionFailure`) where the TS
  source of truth throws a catchable `Error` (paginate.ts:172). The path is
  provably unreachable today, but the failure-mode asymmetry means a future
  reachable path kills the app instead of surfacing an error. Align on throw.
- **A3 — Conformance coverage gaps.** The corpus pins parse, serialise,
  paginate, predict, choreography, normalize, ghostSuffix, crc32, and FDX.
  Nothing pins: Swift `SmartType.swift` vocabulary extraction (198 lines),
  `Revisions.swift`, `SceneNumbering.swift`, `TitleCredits.swift`,
  `ScreenplayTranscription.swift` (394 lines — Apple-only by nature, fine, but
  unpinned); or TS-side `classify.ts` (the docx/plaintext classifier — the
  code most exposed to foreign documents), `continuity.ts`, `rename.ts`
  (a data-mutation feature; see B4), and `validation.ts`. Prioritise
  `classify` and `rename`.
- **A4 — No CSP in `static/_headers`.** The app loads no third-party scripts,
  so `default-src 'self'` is nearly free hardening for the "private,
  local-first" promise. `nosniff`, frame denial, and referrer policy are
  already there.

## Unverified suspicions (recorded, not claimed)

- `serialise.ts:110` — a note whose text contains `]]` would break its own
  round-trip; no escaping is visible. Edge case; needs a test to confirm.
- `serialise.ts:70` — a scene whose text begins with `#`/`=` gets a `.`
  prefix that parse.ts:409 only re-accepts when a letter/digit follows; such a
  scene may degrade to action on round-trip.
- `parse.ts:298` — notes attached to title-page lines are dropped by the
  `ll.slice(consumed)` offset; likely intentional, unconfirmed.

## What is exemplary (the standard to hold)

- The conformance corpus is genuinely adversarial — NFD marks, NEL, ZWJ emoji,
  unclosed boneyards, lone-CR, `&#x110000;` entities — with comments naming
  the exact historical bug each hazard caused. This is how golden masters
  should be written.
- `zip.ts`'s doctrine ("refuse loudly what we do not understand") with caps on
  entries, entry bytes, and total bytes, CRC verification, and central-directory
  trust — a model untrusted-input reader.
- `validation.ts` — thorough, non-mutating, diagnostic-path-carrying
  untrusted-value validation.
- The `choreography.ts` comments explain *why* (the two-stop ring, the
  one-way-door bug) — the codebase's own standard, met.
- CI pins GitHub actions by SHA and runs the four Swift suites on macOS.

## Remaining debt (the deep passes still owed)

1. `EDraftCore` line-by-line (EditorState, edit planner, ScreenplayFile
   round-trip) — deferred by the quota interruption.
2. `EDraftUIKitSurface` + iOS app target — same.
3. `fdx.ts` and `predict.ts` full reads (both well-tested; lower urgency).
4. `ScriptEditor.svelte` full read (see A1).
5. The in-flight page-gap refactor (C1) once it lands — review it as a diff.

## Recommended order of attack

1. **C1** — get the tree compiling again (or commit the WIP to a branch).
2. **C2** — one-line early-abort in `inflateRaw`, plus a bomb test.
3. **B1** — CI freshness check for the corpus; this guards everything else.
4. **B3** — restore the real legacy PDF marker (data-recovery promise).
5. **B2** — close the `import struct` hole.
6. **B5/B6** — save-path honesty and the SW update decision.
7. **B4, A3** — shared base-name definition, then corpus fixtures for
   `classify` and `rename`.
