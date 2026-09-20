# Multi-container pages — migrating off the spread fold

*Written 2026-09-16 on branch `rename/edraft`, HEAD `dba44af`, immediately
after the Stage 0 spike. It exists because Two-page mode has produced five
separate bugs that are one bug, and because four locks were spent patching
symptoms before the cause was named. Everything marked **measured** was run
on this machine and its output is quoted; everything else is named as
inference, as Apple's documented behaviour, or as still unproven. Read
[APPLE-PLATFORM-GUIDE.md](APPLE-PLATFORM-GUIDE.md) §0 first — its first
principle, "the platform does the work", is the whole argument here.*

---

## 0. The claim

Two-page mode draws the script correctly and answers every question about it
wrongly. Clicks, caret placement, selection, the format bar, the find bar,
the reveal highlight and the ghost overlay have each been reported as a
separate defect. They are one defect with seven faces, and no amount of
coordinate arithmetic fixes it, because the arithmetic is not where the lie
is.

The fix is the design TextKit was built for and the one Pages uses: **one
`NSTextStorage`, one `NSLayoutManager`, one `NSTextContainer` and one
`NSTextView` per sheet.** Layout, drawing and hit-testing then agree by
construction, because there is only one geometry and the platform owns it.

## 1. The original sin

`SpreadFold` is a drawing trick. `ArrangedTextView.draw(_:)` enumerates line
fragments and paints each one through `fold.spreadPoint(fromVertical:)`, so
the *pixels* land on facing pages. The layout manager is never told. It goes
on believing the script is one tall column, because it is.

Everything that asks "what is at this point?" therefore gets the column's
answer:

| symptom | what actually happens |
|---|---|
| click the right sheet, type | text lands on the left sheet at the same height |
| reveal a scene on page 3 | mark painted at the single-column position |
| select text in Two-page | format bar positioned off-viewport, so it hides |
| find a phrase | find rectangles drawn in column coordinates |
| prediction ghost | frame set in column coordinates |

Three overrides on `ArrangedTextView` try to compensate —
`characterIndexForInsertion(at:)` unfolds an incoming point, `firstRect(...)`
folds an outgoing one, `draw(_:)` folds the ink. Each is a patch over one
hole in a boundary that should not exist. `PageGapContainer` is a fourth: it
forces the single column to *look* paginated by making the type skip bands of
desk.

The measured cost of that pretence is written in `PageGapContainer`'s own doc
comment: exclusion paths for a feature's eight hundred gaps took **4.8 s a
layout** where the bare draft takes **0.3 s**, and merging the gaps into one
path was worse at **12.6 s**. The current binary-searched band list recovers
the time, but it exists only to sustain the illusion.

**The mutation evidence.** On 2026-09-16, in a fresh build at 125 %
magnification, clicking the right-hand sheet and typing inserted into the
left-hand sheet. The repro file `/tmp/caret-test.fountain` records it at
source level — `Marker 2 reads normal` became
`Marker 2 redfa**fadfaads** normal`. The right sheet is not interactive at
all; input falls through to the column beneath.

## 2. Stage 0 — the spike

A throwaway AppKit program, outside the product tree: one storage, one layout
manager, two containers, two views. Two questions, because both had to answer
yes or the design was dead.

### 2.1 Can a container be forced to end at a chosen character? **Yes — measured**

This was the real blocker. Today the *engine* decides page breaks
(`ScreenplayExporter.paginate`) and `PageGapContainer` forces the layout to
obey. With one container per page, TextKit would ordinarily decide breaks by
filling — and TextKit does not know screenplay rules: never orphan a
character cue from its dialogue, `(MORE)` and `(CONT'D)`, scene-heading
widows. Engine and TextKit would disagree exactly where it matters, and the
screen would show a different page number from the PDF.

Measured:

```
asked container 1 to stop at character 951  ("Line 31 …")
container 1 holds 0..<951      last line:  Line 30
container 2 holds 951..<3852   first line: Line 31
PASS — the break landed exactly where it was told to
```

Mechanism: override
`NSTextContainer.lineFragmentRect(forProposedRect:at:writingDirection:remaining:)`
to return `.zero` past the chosen character, then call
`layoutManager.textContainerChangedGeometry(container)` to invalidate.

Two things worth keeping:

1. **This is the same override point `PageGapContainer` already uses.** The
   project has been steering TextKit this way all along — inside one
   container instead of across many.
2. **The invalidation is not optional and its absence is silent.** The
   spike's first run failed with container 1 holding all 3,852 characters and
   container 2 empty, purely because `breakAt` was assigned after layout had
   run. No error, no warning — a stale layout that looks like a design
   failure. `PageGapContainer`'s `gapBands` setter calls
   `textContainerChangedGeometry` for exactly this reason.

So the engine's page starts drive the containers, and TextKit never gets a
vote. **The blocker is gone.**

### 2.2 Does a selection span the container boundary? **Yes at the model level — measured**

```
set on view 1: 911..<991   (straddles the break at 951)
view 1 reports: 911..<991
view 2 reports: 911..<991
beginning-of-selection → view 1    end-of-selection → view 2
```

One selection; both views agree; AppKit places the two ends in different
views.

**API wrinkle.** `NSLayoutManager` offers `textViewForBeginningOfSelection`
but no matching accessor for the end. The end was resolved via
`textContainer(forGlyphAt:effectiveRange:)?.textView`. Stage 3's format-bar
work will need the same workaround.

### 2.3 By-product — `characterIndexForInsertion(at:)` takes view coordinates

Probing the same point in two spaces:

```
probe (20, 40) as VIEW coords   → character 1017  (Line 33)
probe (20, 40) as WINDOW coords → character 2262  (Line 71)
```

Container 2 begins at Line 31, so a probe 40 points down resolving to Line 33
is the correct answer; the window-space result is wrong (it merely happened
to stay inside container 2, which made the spike's own pass criterion too
lenient — the discriminating evidence is the line number, not container
membership).

**Inference, not proof:** this means the existing `ArrangedTextView` override
*is* being handed the space it expects, so the surviving explanation for the
live click bug is that AppKit's mouse path never calls that method at all.
That has not been proven — it would need instrumentation — and it becomes
moot under the new architecture, where nothing transforms anything.

### 2.4 What the spike did not prove

- **Drag-select as a gesture** across the view boundary. The model supports
  it; the mouse-tracking loop needs a live event stream and was not tested.
- **Which method AppKit's `mouseDown` uses** to resolve a click (§2.3).
- Anything about first responder, tab order, or IME across N views.

## 3. What it costs — measured

| | |
|---|---|
| `ScriptSurface.swift` | 3,535 lines, **121** `textView` references |
| public API | `public let textView: NSTextView` — a singular that must become plural |
| package consumers | `PageCanvasView` 13 · `FindBarClient` 10 · `SelectionFormatBar` 5 · `ScriptLayout` 1 |
| tests | **25 files, 264 references** |
| test floor | **251** macOS surface (5 skipped) + **317** core = **568**, 0 failures |
| deleted at the end | `PageGapContainer` 95 lines · `SpreadFold` + `ArrangedTextView` ≈ 140 |

Most of the 121 references are mechanical — `textView.string` wants the
storage, not a view. The position-related ones are not, and a compatibility
shim such as `var textView: NSTextView { sheets.first }` would keep them
compiling **while silently reintroducing this exact bug**: right answer for
page 1, wrong for every other. That shim must not be written.

## 4. What it buys

Clicks, caret, selection, selection painting and drag become native per view,
with no transform anywhere. Beyond that:

- The format bar positions against `textViewForBeginningOfSelection` instead
  of a hand-folded rectangle.
- The reveal highlight is added to the sheet's own view, in that view's own
  coordinates.
- **`NSTextFinderClient.contentView(at index:)` is already multi-view by
  design** — and `FindBarClient` currently returns the same view for every
  index. Stage 3 does not adapt the find bar to a new world; it stops lying
  to an API built for this one. The same reading applies to
  `textViewForBeginningOfSelection`: that accessor exists *because* AppKit
  expects several views per layout manager. The platform has been waiting.
- `PageGapContainer` disappears, and with it the per-line band search. This
  should be faster, not merely cleaner.

## 5. The stages

**Stage 1 — equivalence harness.** Tests only, zero production change. Over a
corpus of scripts, assert (a) every container's first character equals the
engine's page-start location, character for character, and (b) every
character's on-screen rect matches today's architecture within tolerance.
Assertion (a) is what stops screen and PDF diverging; (b) covers the caret,
the highlight, the format bar and the find rects in one place. A failure here
is information: it names the screenplay rule TextKit does not know, and the
plan gains a requirement instead of a surprise.

**Stage 2 — the sheet array, spread only, behind a flag.** `PageSheet`
(container + view) built from engine page starts; the old path stays live.
The large one.

**Stage 3 — migrate the consumers.** Clicks, caret, selection, format bar,
highlight, find, ghost. **The whole bug family dies here.**

**Stage 4 — the single-page decision.** Deferred. If Stage 1 shows geometry
identical and appearance untouched, migrating Single deletes the second
engine. Keeping Single on the old path means maintaining two layout
architectures and rebuilding on every mode switch.

**Stage 5 — delete the fold and `PageGapContainer`.** Net negative lines.

## 6. Risks still unproven

1. Drag-select across views as a gesture (§2.4).
2. First responder, tab order and `makeFirstResponder` across N views.
3. View churn: views created and destroyed as page count changes mid-edit.
   `PageCanvasView` already does this dance for the page *cards*; each now
   carries a live view, container and responder state.
4. `NSTextViewDelegate`, `shouldChangeTextIn`, typing attributes and the edit
   planner all assume one view.
5. Two architectures coexisting through Stages 2–4.

## 7. Superseded work

**IL-0022 as originally scoped is superseded by Stage 3.** It was queued to
fix three fold-blind consumers found while auditing IL-0020:

- `SelectionFormatBar.reposition` — converts an unfolded rectangle to canvas
  coordinates, so in a spread the bar lands off-viewport and hides itself.
- `FindBarClient.rects(forCharacterRange:)` — returns unfolded rectangles
  with `contentView` the single text view.
- `GhostTextOverlay.updateFrame` — sets a subview frame from `hostLineRect`,
  an unfolded rectangle.
- (also `screenOffsetForTesting`, fold-blind, test-only.)

Each would have been another coordinate patch on a boundary Stage 3 removes.
They are **not dropped** — they are the acceptance criteria for Stage 3, and
this section is the record of that decision.

`SpreadFold` itself is not at fault: its arithmetic round-trips, and there
are tests proving it. It is correct code answering a question that should not
be asked.

## 8. Open decisions

1. **Single-page mode** (Stage 4) — migrate, or maintain two engines.
2. **Whether the equivalence harness becomes CI-blocking** from Stage 1, or
   only from Stage 2.
3. **What to do if Stage 1 finds a divergence** the engine intends and TextKit
   cannot express — a forcing rule per container is the likely answer, but it
   is unwritten until a real script needs it.


## 9. Stage 2 implementation — 2026-09-19

This section records the Stage 2 state. Section 10 supersedes its read-only
preview restriction for the opt-in spread path.

`ScriptSurface` now owns one `NSTextStorage` and one `NSLayoutManager`.
With the flag enabled **and** the arrangement set to Two-page, its `sheets`
array holds one `PageSheet` (container and ordinary `NSTextView`) for each
engine page. The legacy `PageGapContainer` is detached from that manager
while the sheet containers are attached, so it cannot consume any text.
Single, Grid and Continuous still use the original container and view.
The existing public `textView` remains explicitly the **legacy** view; it
never returns the first sheet. Storage access no longer depends on that
view being attached.

`PageSheetContainer` refuses line fragments at the next engine page start.
Its boundary setter calls `textContainerChangedGeometry` when the break
changes, including after layout has already run. Container height is
unbounded so TextKit cannot move a break earlier to make the text fit the
paper. A resize or a moved break reuses the existing views. Page-count
changes add/remove only the tail of the array. Returning to a legacy mode
reattaches the original container, invalidates its cached page bands, and
restores the saved selection, clamped to the current storage.

The canvas uses the existing paper frames and AppKit's frame/bounds scaling
to position the sheet views. The new path has no `SpreadFold`; the fold and
`ArrangedTextView` implementation remain compiled and unchanged for the
legacy path.

### Enabling the preview

The flag defaults **OFF**. In a Debug launch, set the environment variable
`EDRAFT_MULTI_CONTAINER_SPREAD=1` and choose Two-page using the existing
arrangement control. Unset the variable and relaunch to disable it. Release
builds ignore this environment switch. Tests use
`ScriptSurface(multiContainerSpreadEnabled: true)` or `false` explicitly.
There is no new settings UI or persisted preference.

This is a **read-only layout preview** until Stage 3: the new views reject
editing and selection, and the legacy find/format/ghost overlays are not
rehosted onto them. That gate prevents unobserved edits from reaching shared
storage before the planner, delegate routing and geometry consumers have
been migrated. It does not claim to fix the right-sheet insertion bug.

### Evidence and limits

The Stage 1 harness keeps its independent forced-container candidate and
legacy per-page geometry assertions, and runs those checks against the
production `PageSheet` array too. A separate full-rectangle comparison maps
every UTF-16 character in the corpus to canvas coordinates through each
architecture, within 0.5 points, including fitted spreads and resizes.
Lifecycle tests cover shared ownership, break invalidation after layout,
changed text, page growth/shrinkage, empty/trailing-empty elements, mode
round trips, view reuse and restoration of legacy geometry.

**Unchecked:** drag-select as a gesture across views; first responder, tab
order and IME across sheet views; Stage 3 caret, selection, format bar,
find, reveal and ghost behavior; manual appearance and accessibility with
real input; performance on production-length documents. The geometry
tests prove rectangle placement, not those interactions.


The initial full-suite run on the unchanged checkout exposed a lifetime
bug in `TextFinderMeasurementTests`: an ARC-owned window was also released
on close. A zombie run identified `-[NSWindow release]` on a deallocated
instance. The one-line `isReleasedWhenClosed = false` correction arrived
independently in the working tree; Stage 2 did not edit that file.

On 2026-09-20 the full Mac surface suite passed: **278 tests, zero failures,
five existing opt-in benchmarks skipped**, including all **17** Stage 2
equivalence/lifecycle tests. The engine suite passed **222** tests and the
requested macOS Debug build succeeded on 2026-09-19 (IL-0053 run
`20260919-210042` ran that exact build after the final source changes).
A fresh 2026-09-20 build passed with `CODE_SIGNING_ALLOWED=NO` after
developer-certificate signing stalled and the platform guide's ad-hoc
options encountered a provisioning-profile requirement. The unsigned build
checks compilation and linking; it does not prove signing. No signing
settings in the project were changed. Full acceptance is still blocked by
seven `PasteCorpusGateTests` that cannot read their external `scripts-corpus`
directory (`Operation not permitted`). The core and engine were not edited
by this stage, and the corpus tests were not skipped or pointed at an empty
directory to make the verification command pass. An accessible copy can be
supplied through the tests' existing `EDRAFT_SCRIPT_CORPUS` setting.


## 10. Stage 3 implementation — 2026-09-20

The opt-in spread path now accepts editing and selection. The flag still
defaults **OFF**; the Debug environment switch in §9 is unchanged. There
is no new settings UI, no single-page migration and no removal of the
legacy fold. The legacy finder implementation is retained verbatim, with
a separate `PageSheetFindBarClient` installed only while sheets are active.

Each sheet is connected to the surface's existing edit delegate before it
becomes editable. The delegate's event view handles native input; model
edits, formatting and undo read the shared layout manager's selection.
`selectionTextView` resolves the beginning-of-selection view, and character
lookups resolve the owning engine page, including an empty trailing page.
The stored `textView` remains the detached legacy column, not a page-one
compatibility alias. Container break invalidation remains unchanged.

Geometry consumers now use each sheet's native view coordinates. Finder
reports both the actual content view and its effective character range.
The format bar resolves the selection's end through its glyph container,
measures each intersected view, and positions against the visible portions.
Reveal highlights and predictions are hosted by the owning sheet. Viewport
anchors, caret visibility, screen offsets and note margins use native view
conversion, without fold/unfold arithmetic on the sheet path. Notes at the
same height on different pages remain separate.

Repagination reuses existing sheets, restores the shared selection, and
moves the first responder when the caret's owning page changes. Replacing
the document preserves and clamps the selection before relayout. Selection
repainting invalidates affected sheets rather than the whole document.

### Measured evidence

`PageSheetInteractionTests` adds 13 tests covering:

- A native mouse click on the right sheet followed by insertion at that
  location, with exact storage and bound-model agreement; a double-click
  selecting the word under that pointer. A permanent generated fixture of
  numbered “Marker … reads normal.” paragraphs replaces the unavailable
  `/tmp/caret-test.fountain` reproduction file.
- One shared cross-page selection with endpoints in different views, and
  native arrow movement across a page boundary.
- Format-bar placement on the right sheet and for a selection whose
  beginning is above the viewport; right-sheet formatting and undo.
- Finder content-view identity, effective range, local match rectangles
  and shared selection, with Replace still disabled.
- Reveal highlight and screen-offset geometry on the right sheet;
  prediction placement on a later sheet without modifying document text.
- Return through the planner and undo; growth and shrinkage of the sheet
  array during native edits, with selection, model and responder checks.
- Separate note markers for left/right pages at the same vertical position.

The mouse tests hit-test the actual canvas and deliver native mouse events
to the hit text view. They explicitly focus that view: the package test
host could not become a key application in this session. They do not set
a character selection to simulate the click, and they do not prove
foreground-window activation by a physical click.

On this checkout, the full Mac surface suite passed **291 tests**, with
**zero failures** and **five existing opt-in benchmark skips**. This
includes the unmodified four-test equivalence harness exercising both
architectures, exact engine page starts, complete character coverage, and
every character's canvas rectangle within 0.5 points across resizes.
The engine passed **10 XCTest tests plus 222 Swift Testing tests**. The
exact requested macOS Debug build succeeded, including signing, without
changing signing settings or adding command-line signing overrides.

**Acceptance blocker:** the full Core suite ran 350 tests; seven
`PasteCorpusGateTests` failed with `NSCocoaErrorDomain Code=257` / POSIX
`Operation not permitted` reading the external `scripts-corpus` directory.
An elevated direct read in this Codex process failed too. The other 343
Core tests passed. Core and engine sources were not changed, and no corpus
test was skipped or weakened. Full acceptance requires rerunning with
access to the same complete corpus, using the existing
`EDRAFT_SCRIPT_CORPUS` override if it is supplied at another readable path.

### Unchecked

Cross-view drag-selection as a physical gesture and its feel; complete
first-responder/tab traversal across all views; physical foreground-window
activation; IME composition spanning or repaginating sheets; accessibility
and visual inspection with real input; feature-length editing performance.
The responder and churn tests above establish their specific native-edit
cases, not all combinations of those interactions. The default flag must
remain off pending the separate human decision after on-screen testing.
