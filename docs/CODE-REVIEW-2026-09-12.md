# Code Review — 2026-09-12

*Written on branch `rename/edraft`, HEAD after the highlighter's Phase 2.
Reviewer: Kimi, directly — no parallel agents.*

## Scope and method

Two inputs frame this pass. First, the September 10 review
(`CODE-REVIEW-2026-09.md`) whose every finding is now verified fixed: C1
(compile), C2 (zip-bomb early abort), B1 (conformance freshness in CI), B2
(boundary-checker submodule imports), B3 (legacy PDF marker), B4 (rename base
names), B5 (autosave quota), B6 (service-worker activation), I1 (hot-path
regex). Each was re-read against the current tree, not taken on trust.

Second, everything built since: the paste machinery, incremental pagination,
the run-aware FDX boundary, and the highlighter. Plus systematic scans of the
whole tree for leftover markers, debug prints, empty catches, and
style-run constructions that drop a property.

**Read line by line this pass:** `ScriptSurface.swift` (3,227 lines — the
app's largest file, every section), `EditorState.swift` (1,413),
`PasteReassembly.swift`, `ScreenplayEditPlanner.swift`, the Swift engine's
`Paginate.swift` fold and `BlockSource`, the changed sections of `fdx.ts`,
`SelectionFormatBar.swift`, `GhostTextOverlay.swift`, `PageScrollView.swift`.
**Reviewed by sweep with targeted reads:** the rest of `EDraftCore`,
`PageCanvasView`, `ScriptWindowController`, `EDraftUIKitSurface`, the iOS app
target, and the web app — each is named under "Remaining debt" rather than
claimed.

### Baseline (run before and after)

| Suite | Result |
|---|---|
| `npm test` | 547 passed |
| `swift test apple/eDraftEngine` | 141 passed |
| `swift test apple/EDraftCore` | 196 passed |
| `swift test apple/EDraftMacSurface` | 232 passed |
| `npm run check:boundaries` | holds |
| iOS app target (simulator) | 108 passed |
| Mac app build | clean |

---

## Fixed in this pass

### 1. The planner's donor dropped the mark — runs, *every* property or none

`ScreenplayEditPlanner.runsForPart` built the donor's replacement run with
`styles`, `revisionID` and `tagNumbers` — and not `highlight`. The donor rule
(§4) gives inserted text the donor's *whole* property set; typing or splicing
into a highlighted span silently lost the mark on the new text. This is the
class of bug that only a property added after the function was written can
create, and the fix is one line plus the discipline it implies: every
construction that copies a donor now carries every property the donor has.

Regression test: `PasteFormattingTests.testInsertionIntoAMarkedSpanKeepsTheMark`
— inserting at the end of a highlighted word leaves the mark covering both.

### 2. A character rename silently destroyed runs

`EditorState.renameCharacter` rewrote cue and prose text and never re-seated
runs: any style or mark on a renamed line misaligned by the name-length delta,
and a mention replacement consumed the mention's own run entirely (measured:
the highlight vanished; "the mark stood on nothing"). The typing-donor rule
couldn't answer this — replacing text is not typing into it — so the rename
gains its own rule: **a name is atomic**. A run that overlaps the replaced
mention at all covers the new name whole; runs before or after shift by the
delta; mentions replace latest-first so earlier offsets stay true.

Regression tests: `EditorPanelCacheTests` —
`testARenameCarriesRunsThroughTheLengthChange` (cue and prose, mark stretches
with the name) and `testARenameAcrossSeveralMentionsReSeatsRunsOnceEach`
(multi-mention paragraphs re-seat once each, never twice).

### 3. A comment described a JavaScript bridge that does not exist

`EditorState.quickStats` was documented as "never touching the JavaScript
bridge" — a relic from before the Swift engine existed. The comment now says
what the function is: a line-count estimate, replaced by the measured pass the
moment it lands.

### 4. PasteReassembly's mode-2 limits are now written where they live

The unindented hard-wrap reader had two honest edges undocumented in the code:
consecutive marker-less action paragraphs join, and a scene heading long
enough to wrap loses its continuation line to action. Both are the
irreducible ambiguity of a structure-less paste — margins are the only thing
that tells a heading's second line from a new paragraph, and this paste has
none. Named in the doc comment rather than discovered by a writer.

---

## Verified clean this pass

- **The text-edit delegate core** (`shouldChangeTextIn`): every path —
  marked text, prediction accept, scene separator, live collapse, structural
  replacement, incremental typing — re-read line by line. The single-path-per-
  key discipline holds; nothing sneaks past the planner.
- **The zoom machinery**: the preference/borrow/lend state machine is
  consistent and every mutator funnels through one apply point, with the
  gesture-ownership guards documented at the places they'd break.
- **Notes, ghost, undo timelines, external-sync merge** (`EditorState`
  `applyExternalSource`, notes plumbing, dual undo stacks): all read; the
  invariants they claim are the invariants they keep.
- **The incremental pagination fold** (TS `runFold`/`BlockSource` and the
  Swift port): re-read after the lazy-block conversion; the two engines match
  call for call, and the fuzz in both holds it.

## Watch items (not fixed — deliberately, and here's why)

### W1 — `ScriptSurface.swift` is 3,227 lines

Fifteen concerns in one file: zoom, drift, notes, ghost, find, typing,
paste, styling, reveal, undo, viewport, separator, predictions. The MARK
sections and the test net hold it together today, and every concern is
individually documented — but the file is past the size where a change in one
concern can be read without the others. The honest seam, if it splits: the
zoom machinery (`applyZoom`…`tick`) is the most self-contained cluster and
would lift cleanly. Not split now because a split that isn't driven by a
concrete need is churn, and the page's behavior is the most heavily
regression-tested surface in the app — moving it without a reason risks the
net's precision for tidiness. Revisit when the next zoom feature lands.

### W2 — The iPhone's renderer still draws no emphasis styles

`EDraftUIKitSurface`'s `draw(_:)` puts runs on paper as plain text: no bold,
italic or underline in the phone's PDF (the Mac's draws them; the web's PDF
has its own treatment). The highlight landed there because one document is
one document; full emphasis on iPhone is the queued project, and this gap is
recorded so it isn't discovered twice.

## What is exemplary (the standard this pass met, not set)

- The donor/property discipline: every run construction now carries every
  property, and the two places that didn't were found by construction-site
  audit, not by test failure — the tests then pinned them.
- The fixpoint discipline in `applyPageBreaks` and the incremental pagination
  splice: performance work that is *provably* output-identical, fuzz-pinned in
  both languages, rather than "faster, probably".
- The paste machinery's named limits: what the heuristics cannot read is
  written in the doc comments, in the tests, and here — never silent.

## Remaining debt (the deep passes still owed)

- `PageCanvasView.swift` and `ScriptWindowController.swift` — swept, not read.
- `EDraftUIKitSurface` beyond the render path — swept, not read.
- The web app's `ScriptEditor.svelte` and routes — not read this pass (the
  prior review's B5/B6 fixes are verified, and the file is due its own pass).
- `predict.ts`, `classify.ts`, `continuity.ts` — covered by heavy suites and
  fixtures; not re-read since September 10.

## Order of attack for the next pass

1. W2 (iPhone emphasis) — it's already the planned project.
2. W1's zoom extraction — when the next zoom feature makes it earn itself.
3. The web app's editor pass — the desktop's sibling surface deserves the
   same treatment.
