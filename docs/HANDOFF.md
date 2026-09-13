# Handoff

*Written 2026-09-05, last updated 2026-09-11 on branch `rename/edraft`.
For whoever picks this up next — human or otherwise.*

Read this file first, then [MACOS-EXECUTION.md](MACOS-EXECUTION.md), which is
the live working document with the milestone checkboxes, and
[APPLE-PLATFORM-GUIDE.md](APPLE-PLATFORM-GUIDE.md) before touching a window,
a toolbar or a text view on any Apple platform. Everything below is
either state you need or a trap that has already cost someone hours.

---

## 1. What this is

**eDraft** — a screenwriting app. A TypeScript engine (the web app and the
source of truth for every screenplay rule), a Swift port of that engine, a
shipping iPhone app, and a macOS app that has just been born.

The owner is Ysr, a product owner with strong design judgement who tests every
change by hand and notices detail. Two things they ask for repeatedly, and mean:

- **"Professionalism."** Fix causes, not symptoms. No patching over a bug you
  do not understand. If you cannot verify something, say so plainly instead of
  implying you did.
- **"Clean, robust, production quality."** No spaghetti, no speculative
  abstraction, no indirection that only forwards a call. A refactor must earn
  itself — one was cancelled for exactly this reason (see M0.5 in the execution
  doc) and the cancellation was the right call, not a failure.

They respond very badly to confident claims that turn out to be untrue. Measure
first. Every non-obvious fix in this repo was found by instrumenting and
reading a number, not by reasoning about what ought to happen.

---

## 2. State of play

| | |
|---|---|
| Branch | `rename/edraft` |
| iOS app | Feature-complete for its own plan; ships |
| macOS app | An AppKit document window (`NSDocument`, `ScriptWindowController`) around the SwiftUI panels, one window at a time with a launch gallery behind it: page card, types, ghosts, finds, exports, prints, a format bar over a selection that toggles real style runs; the toolbar's glass turns light over the page, as Pages' does. Title page is a sheet; Cast opens the character thread and the page refits. Notes live in the margin. **Next: view modes, statistics; emphasis on the iPhone (runs are in the model and file, the phone does not draw them yet)** |
| Packages | `EDraftEngine`, `EDraftCore`, `EDraftUI`, `EDraftMacSurface`, `EDraftUIKitSurface`, `SplitWindowKit` |
| Xcode targets | `eDraft`, `eDraftTests`, `eDraft (macOS)` |

**The green baseline.** Run all of it before you start and after every step. If
a number drops, you broke something.

```bash
npm test                                              # 642 TypeScript (613 engine package + 29 web app)
npm run check:paste-corpus                            # 15 scripts hold (skips without the corpus)
swift test --package-path apple/eDraftEngine          # 150 engine
swift test --package-path apple/EDraftCore            # 294 core        (macOS)
swift test --package-path apple/EDraftUI              #  35 document    (macOS)
swift test --package-path apple/EDraftMacSurface      # 249 Mac surface (macOS)
npm run check:boundaries                              #  layer imports
xcodebuild test -project apple/eDraft.xcodeproj -scheme eDraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'    # 108 app
xcodebuild build -project apple/eDraft.xcodeproj -scheme 'eDraft (macOS)' \
  -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=""                                        # the Mac app
```

*Recounted 2026-09-14 (fifth pass, at 5f3932c): TypeScript 642 (613 engine +
29 web), engine 150, core 294, document 35, Mac surface 249 (5 skipped) —
the layout lane (two-page book mode, grid overview, scene filter) committed
into the fourth-pass docs, so every suite was re-run at the merged tip in
the working tree, which was clean; the paste-corpus gate's 15 scripts hold
and the iOS app's 108 passed (xcresult bundle).
Fourth pass, at 738f91d: TypeScript 642 (613 engine +
29 web), engine 150, core 293, document 29 and Mac surface 238 (5 skipped)
were all run against the tip in a scratch worktree, so the other sessions'
uncommitted files (zoom, scene filter) are not in those numbers; the
paste-corpus gate's 15 scripts and the iOS app's 108 were verified in the
working tree (the corpus is never committed, and the iOS count comes from
the `.xcresult` bundle).
Third pass, at 23d0b78: TypeScript 627 (598 engine +
29 web), core 270, document 29 and Mac surface 238 were run against the tip
in a scratch worktree; the engine's 145 and the paste-corpus gate's
15 scripts were run in the working tree (nothing uncommitted touched them).
Second pass, at 1e0dc85: TypeScript 617 (588 engine +
29 web) and core 257 were run against the tip after cue confirmation landed;
the engine (145), document (29) and Mac surface (240, 5 skipped) numbers were
run in the same session with the zoom session's uncommitted files in the tree
(they touch PageZoomControl/ScriptSurface/ScriptMenus, not the paste route).
Earlier pass at 6b3bcec: 608 TypeScript (579 engine), 246 core. The iOS count
comes from the `.xcresult` bundle —
xcodebuild's stdout does not print it. Note: `apple/eDraftTests` holds two
files no target references — `HighlightPdfTests.swift` and
`HighlightRenderingTests.swift` (4 tests); they compile nowhere and run
nowhere. The iOS 108 is what the bundle actually contains.*

The `EDraftUIKitSurface` package has no suite of its own and is not in that
list. It imports UIKit, so it cannot be built by `swift test` on a Mac host at
all; its behaviour is covered by the 108 in the iOS app target, which runs under
the simulator where the document plumbing those tests drive already lives. A
test target there would be a path nobody could run.
**If a Mac build stops dead at `CodeSign`**, it is a keychain prompt: macOS is
asking for the signing key and `xcodebuild` waits for it indefinitely. The
ad-hoc flags in the command above avoid it; `CODE_SIGNING_ALLOWED=NO` verifies
compiling and linking alone. MACOS-EXECUTION §4a has the full note, including
what can and cannot be seen when the display is asleep — read it before
debugging a Mac build that appears to hang, which would have saved forty
minutes on 2026-09-06.

**Relaunching the Mac app for the owner** — build into the project-relative
derived-data path and open exactly that bundle, or you will hand them a stale
app without knowing it:

```bash
xcodebuild build -project apple/eDraft.xcodeproj -scheme 'eDraft (macOS)' \
  -derivedDataPath apple/build
pkill -f "Build/Products/Debug/eDraft"; sleep 1
open "apple/build/Build/Products/Debug/eDraft (macOS).app"
```

A bare `xcodebuild build` writes to `~/Library/Developer/Xcode/DerivedData`
instead, and `open` on the path above launches whatever bundle was already
there — on 2026-09-12 that cost the owner a test round against a build from
before the work being tested, and the bug report that followed was a ghost.
Check the bundle's mtime against the clock before you say "relaunched".

---

## 3. The architecture, and the rules that hold it up

```
EDraftEngine     the rules of the craft. Foundation only. Pinned byte-for-byte
                 to the TypeScript engine by a conformance corpus.
      ▲
EDraftCore       the app's mind. Foundation + Observation, never a UI framework.
                 EditorState, the edit planner, the models, casing memory,
                 PageScroll, ScriptTypography, RevealMark, ScreenplayFile,
                 ScreenplayExporter, ScreenplayPageLayout, PdfSignal,
                 CharacterRename.
      ▲                                    ▲
EDraftUIKitSurface                  EDraftUI         shared SwiftUI: Navigator
UITextView, reveal mark,                             (StoryList/StoryPanel),
printed page. Core + Engine                          character thread, title
only — the page, not the                             page, settings, document.
panels. Public face is one                ▲
view, ScriptSurfaceView.            EDraftMacSurface  NSTextView layout and page,
      ▲                                              and the window that
eDraft (iOS)                                         arranges the panels
nav-bar chrome, scanning,                 ▲
keyboard bar, the panels            eDraft (macOS)   NSDocument, the menu bar
```

`EDraftMacSurface` stands on one more package, `SplitWindowKit`: the AppKit
window that hosts SwiftUI columns under a unified toolbar. It knows nothing
about screenplays — the boundary check forbids it importing any eDraft package
— because it is the piece the next app takes. Its comment carries the
measurement that made the Mac go AppKit for its window.

The two surfaces sit at different heights on purpose: the Mac's holds the
window, so it is above `EDraftUI`; the phone's holds only the page, because the
iPad's chrome will not be the iPhone's and inventing a shared one now would
produce a third that fits neither.

**Four rules. Breaking any of them is the failure mode this structure exists to
prevent.**

1. **A screenplay rule lives in `EDraftEngine`, never in a view.** If a view
   decides what a Return key means, the two apps will disagree eventually.
   `Choreography.emptyLineEscape` is the template: the rule moved out of
   `ScriptTextView` into the engine, and the TypeScript engine got the same
   change in the same commit.

   The rule has a second edge, and it drew blood: a *model* may not decide a
   rule on a view's behalf either. `EditorState.normalizedText` declined to
   capitalise ß, because SS is a different UTF-16 length and a text view
   repairing text in place could not survive that. Three tests wrote the
   decision down; one of them said outright that "the text storage
   intentionally leaves such text untouched, so the model must too". The bill
   came due when the Mac began capitalising at the input boundary and the same
   keystroke started producing two different files. If a rule's stated reason
   mentions a view, the rule is in the wrong place.
2. **TypeScript is the source of truth for engine behaviour.** Change
   `packages/edraft/src/*`, then `npm run package:build && npm run
   engine:conformance` to regenerate `apple/eDraftEngine/Fixtures/`, then make the
   Swift port match. Never the other way round.
3. **`EDraftCore` may not import SwiftUI, UIKit or AppKit.** Enforced —
   `npm run check:boundaries`, wired into `npm run quality`.
4. **One document format.** No macOS-only fields, ever. Both apps open the same
   `.draft`.

---

## 4. What to do next

The plan is [MACOS-EXECUTION.md](MACOS-EXECUTION.md). In order of value:

0. **WYSIWYG emphasis — Phase A shipped on the Mac (2026-09-10/11).** Bold,
   italic, underline and strikethrough are style runs in the model — both
   engines, corpus-pinned — never marker characters in the text; the
   Fountain and FDX boundaries synthesise and parse the markers
   (`Alignment="Center"` is the element's type, and Centre Line now flips
   that instead of wrapping a line in `> <`). On the Mac the format bar
   toggles them through the model, typed markers live-collapse on
   completion (D6), and the bar reads back what the selection wears. The
   design and its review are in this directory: [rfc-viewport-editing-model.md](rfc-viewport-editing-model.md)
   (the live one, v2.1 — code comments cite it as "RFC v2.1") over
   [rfc-emphasis-layout-model.md](rfc-emphasis-layout-model.md) (v1,
   superseded, kept for the audit trail). What remains: the iPhone carries
   runs losslessly but neither draws them nor offers the UI, and the Mac
   has no Format menu or keyboard shortcuts — the bar is the only way in.
   Later phases of the RFC (tags, revision marks, locks as run properties)
   are unpinned and unbuilt.

1. **The outline has no home.** `Outline 1/2/3` and `Summary` now read as
   sections and synopses instead of printing as stage directions, and
   `ScriptAsides` keeps them off the page — so a Final Draft file opens
   looking the way it does with the Outline Editor toggled off, and its page
   count is right at last. What is missing is the toggle's other position:
   nowhere in the app shows a writer their own act structure. The Navigator
   is the home (a third tab beside Scenes and Cast), not a mode of the page —
   Final Draft's Outline Editor is a panel for the same reason.
2. **Notes on iPhone.** The document half is done and shared — `ScriptAsides`
   splits them off the page, `EditorState` owns them, FDX and Fountain both
   carry them. What the phone has no UI for yet is seeing or leaving one:
   a mark in the margin is a Mac affordance, and the phone's answer is the
   selection context menu ("Add Note") plus somewhere to read them. Until
   that lands, a note opened on iPhone is invisible — preserved on save, but
   invisible.

   Both of these are the same shape, and it is worth naming: the document
   half of a feature is cheap to land and invisible when it is wrong. A
   writer cannot tell a note that saved from one that vanished.
3. **View modes** (Page · Typewriter · Focus) and statistics in the
   status area — remaining M3. The inspector was retired: a properties
   pane has nothing continuous to hold. Format → Element, Scene Numbers,
   File → Title Page, and the Cast thread are done.
4. **Writing-assistance settings**, shared with iOS.

Do **not** copy `ScreenplayPageRenderer.swift` to AppKit names. Placement is
`EDraftCore.ScreenplayPageLayout`; each surface draws the runs. A second
233-line renderer is two answers to where a line sits.

---

## 5. Traps, each one already paid for

**Environment**

- **Simulator bundle id is `xyz.edraft.ios`.** Not `com.edraft.*`. Launching
  the wrong one fails with `FBSOpenApplicationServiceErrorDomain code=4`, which
  looks like a crash and is not.
- **Headless `codesign` with the Developer identity hangs forever** waiting for
  a keychain prompt nobody can answer. Pass `CODE_SIGN_IDENTITY="-"
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""`.
- **`swift test` failing every package with `missing required module 'SwiftShims'`**
  is a stale `.build` from when this repo lived at another path, not a broken
  floor. `rm -rf apple/*/.build` and run again.
- **When the Mac's screen is locked**, `screencapture` returns black and the
  accessibility API reports zero windows. Neither means the app is broken. Use
  `CGWindowListCopyWindowInfo` to see what really exists — there is a working
  snippet in the session history and it is three lines.
- **`xcodebuild` output does not contain assertion messages.** To see why a
  test failed: `xcrun xcresulttool get test-results tests --path <.xcresult>`
  and walk the JSON for `nodeType == "Failure Message"`. Without this you will
  be guessing.
- **The Mac's keyboard layout here is ABC-QWERTZ.** AppleScript `keystroke`
  swaps Y and Z. Typing "DAY" into the simulator produces "DAZ". This was once
  reported as a text-corruption bug in the app; it was the harness.
- **Xcode is not being driven interactively.** New files must be added to
  `apple/eDraft.xcodeproj/project.pbxproj` by hand: a `PBXBuildFile`, a
  `PBXFileReference`, a group child, and a Sources entry. There are several
  worked examples in the git history — copy one.

- **`pgrep -f` and `pkill -f` take a regex.** `eDraft (macOS)` matches nothing
  until the parentheses are escaped; a capture script that "finds no process"
  is usually this. Launch the built app with `open -n -a`, then find it by pid.

**Code**

- **A SwiftUI window never lets the toolbar's glass adapt to the page.** Measured
  on macOS 26.5 with real scroll events: `NavigationSplitView` in every style,
  with or without its sidebar toggle, and with an `NSToolbar` installed on the
  SwiftUI window — the chips stay dark over white paper. An `NSSplitViewController`
  hosted *inside* a SwiftUI window loses the full-height sidebar and the toggle.
  Only a window AppKit created, with the split view controller as its content,
  does it all — which is what `SplitWindowController` is, and why the Mac app
  is `NSDocument`-based. Do not put `NavigationSplitView` back.
- **Setting `contentViewController` resizes the window** to the controller's
  view — a fresh `NSSplitViewController` gave 1093×500 for a window created
  at 1280×860. State the size again after assigning it.
- **`ScriptLayout.boundingRect` is already in view coordinates.** It adds
  `textContainerOrigin`, which is the inset. Adding `textContainerInset` again
  moved the reveal mark, the find bar's highlight and the format bar one line
  low — the inset is exactly one line of glyph headroom — and nothing in 147
  tests noticed until a screenshot did. `RevealMarkPlacementTests` now looks.

- **Geometry read from a text view is a *result* of laying out.** `contentSize`
  on iOS, and the text view's own height on macOS, are not recomputed when the
  storage is replaced — they wait for the next layout pass. Measure in between
  and the page appears one screen tall, the scroll arithmetic decides there is
  nowhere to go, and a reveal silently does nothing. This is what made a
  Navigator row work on the second tap and not the first: the tap arrived in the
  same turn as a render. Both surfaces now ask for the layout before measuring
  (`scrollableRange` on iOS, `layOut()` on the Mac) and both have a test for a
  reveal landing in that gap.
- **`CGRect.isEmpty` is true when *either* dimension is zero.** A blank line
  encloses no glyphs and so has no width, but it has a height and a place. This
  silently broke the reveal mark on iOS for exactly the lines a writer is about
  to type into. Test `height > 0`, not `!isEmpty`.
- **A blank line at the very end of a document has no line fragment.** It lives
  in `extraLineFragmentUsedRect`, which only exists after
  `ensureLayout(for: container)` — laying out just the range's glyphs is not
  enough and fails silently.
- **The iOS surface uses TextKit 1 deliberately** (`usingTextLayoutManager:
  false`), and the Mac followed it after measuring both. Its rectangles are
  what `PageScroll` and the reveal were written against. `ScriptLayout.TextStack`
  keeps TextKit 2 under the same tests if the decision ever needs revisiting.
- **A coordinator captured `[weak self]` must be retained by the test.**
  Binding it to `_` deallocates it immediately and every callback silently does
  nothing — this produced an hour of chasing a bug in the app that was really a
  bug in the test. `withExtendedLifetime(coordinator) {}`.
- **`NSTextView.undoManager` is nil without a window.** The tests drive the
  surface windowless. `ScriptSurface` owns an `UndoManager` and vends it
  through `undoManager(for:)`. Do not read `textView.undoManager` in a test
  and conclude undo is broken.
- **Tab on the Mac is `textView(_:doCommandBy:)`, not an `NSTextView` subclass.**
  Return stays in `shouldChangeTextIn` only — one path per key. Tests of Tab
  and ⌘1–9 must set the selection directly; `reveal` also jumps the model and
  will hide a missing `textViewDidChangeSelection`.
- **Predictions are async.** `refreshPredictions` sleeps 65ms then runs off
  the main actor. Tests that assert a ghost immediately flake. Wait for the
  suffix, then call `updateGhost()`. `RunLoop.run(mode:before:)` returns
  immediately when idle; `run(until:)` actually waits.
- **`osascript` is not allowed assistive access** in this environment.
  System Events cannot read the menu bar or type. `CGWindowListCopyWindowInfo`
  still sees windows. Do not report a UI confirmation you could not drive.

  It does not fail cleanly, which is what makes it expensive. `keystroke`
  partly lands: measured on 2026-09-09, typing into a note's popover put the
  characters into the *script* instead and left `ACEINT. LAB - DAY` in the
  document, and reading the window list with System Events pressed a note
  marker's accessibility action and opened its card. Both were then chased as
  app bugs. If a UI needs driving, synthesise `CGEvent` clicks at coordinates
  read from `CGWindowListCopyWindowInfo`, and read the result from a
  screenshot — never from AppleScript.
- **`NSTextView.replaceCharacters(in:with:)` does not go through
  `shouldChangeTextIn`.** Find's Replace would desync the model. The Mac
  find bar is the system one with Replace disabled (`FindBarClient.isEditable
  == false`). Do not turn Replace on without a new measurement.
- **`CommandGroupPlacement.textFinding` is not in this SDK.** Find commands
  go in Edit after Paste. The system find bar itself does not appear from
  `performFindPanelAction(nil)` in a windowed XCTest — hand-pass ⌘F.
- **`NSTextView.init(frame:textContainer:)` copies the frame into `maxSize`.**
  Height 0 means `sizeToFit` cannot grow the view. The layout manager still
  has the glyphs; the view displays one point of them. `NSScrollView` hid
  this by sizing its document view. A page card does not. Set `minSize` /
  `maxSize` before asking the view how tall it is. See M1 in the execution
  doc — the third time a text view's height was not what layout produced.
- **A flipped canvas with an unflipped page card puts the script at the
  foot of the sheet.** The window shows the top. Blank. `pageView` must
  be flipped too. `testTheFirstLineSitsAtTheTopOfTheCard`.
- **`kCGPDFContextKeywords` writes `/Keywords (hex)` as a PDF literal.**
  The extractor reads both `(hex)` and `<hex>`. Do not append after `%%EOF`:
  Preview's re-save drops trailing junk. Measured: 500_000 hex characters
  survive a `PDFDocument` rewrite.
- **`NSTextView.textContainerInset` width is applied on both sides.** The
  108pt left / 72pt right print margins are a text view framed inside the
  page card, not an inset.
- **Layer `cgColor`s do not track appearance.** Snapshot them inside
  `effectiveAppearance.performAsCurrentDrawingAppearance` or the page card
  loses its edge in one of the two looks.
- **`Screenplay` names two different types** — `EDraftEngine.Screenplay` and
  `EDraftCore.Screenplay`. Nine call sites qualify it explicitly. Qualifying is
  a label, not a fix; renaming one of them is worth a focused pass and should
  happen before the Mac doubles the number of call sites.

**Verification**

- **The QA fixture programme is the only net that has ever caught a scroll or
  typing regression.** It compiles under `EDITOR_PREVIEW` and asserts with
  `precondition()`, so a violation crashes the app:
  ```bash
  xcodebuild build -project apple/eDraft.xcodeproj -scheme eDraft \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG EDITOR_PREVIEW'
  # then install and launch with one of:
  #   -qa-scroll-stability  -qa-action-lowercase
  #   -qa-character-uppercase  -qa-quicktype-scene  -qa-sharp-s
  # the app staying alive for ~10s is the pass
  ```
  Run it after touching anything about scrolling, typing or layout.

  It is also the net most likely to break silently, because nothing else
  compiles it. Moving the surface into a package broke it while 102 tests
  stayed green; it was found by running the fixtures, not by the suite. If
  you touch `ScriptTextView` or `EDraftApp`, build this configuration too —
  a green `xcodebuild test` says nothing about it.

  Each fixture should be watched failing once. `-qa-sharp-s` was: putting the
  UTF-16 length guard back into `EditorState.normalizedText` kills the app on
  launch, which is what a working net looks like.

---

## 6. Working conventions

- **Commit messages are prose**, not bullet lists: what changed, and why it was
  worth changing. Look at `git log` — match that voice. Trailer:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Comments explain why, never what.** The codebase's comments are unusually
  dense and unusually specific — they name the bug the code prevents. Keep that
  standard; it is most of what makes this code maintainable.
- **Commit at every green point.** Several sessions have ended abruptly.
- **Update [MACOS-EXECUTION.md](MACOS-EXECUTION.md) as you go** — tick the box,
  record the commit, and write down anything you had to measure. That file is
  what makes the next handoff cheap.

### Parallel sessions

Several agents work this tree at once. It holds up when — and only when —
each one keeps to its lane:

- **Own a lane, and say which one is yours.** The lanes as of 2026-09-12:
  the paste route and corpus gate (`packages/edraft`, `apple/eDraftEngine`,
  `PasteReassembly.swift`, `ScreenplayEditPlanner.swift`,
  `EditorState.kindForInsertedElement`, `scripts/`); the zoom cluster
  (`PageZoom.swift`, `PageZoomControl.swift`, the zoom parts of
  `ScriptSurface.swift`); the Scenes-tab filter (`EDraftUI`'s
  `StoryPanel.swift` / `NavigatorOutline.swift` and the outline derivations
  in `EDraftCore`). A lane is a promise that nobody else needs to read your
  diffs to keep their own work true.
- **`EditorState.swift` is the one file every lane crosses.** When your hunk
  shares a file with another session's uncommitted work, stage with
  `git add -p` and answer per hunk — never stage a hunk you did not write.
  One concern per commit, so the next session's `git log` reads as a ledger,
  not a braid.
- **Leave nothing uncommitted that another lane is about to touch.**
  Uncommitted hunks in a shared file turn the next session's routine staging
  into surgery — and the sessions that follow you cannot tell your leftovers
  from their own bugs.
- **Recount the baseline when you move it.** The numbers in §2 were run
  against the tree they name; if your commit changes one, change the line,
  and put the suite counts you actually ran in your commit message — not the
  ones you remember.

## 7. The documents

| File | What it is |
|---|---|
| [MACOS-EXECUTION.md](MACOS-EXECUTION.md) | **The working document.** Milestones, proofs, decisions taken, known issues |
| [MACOS-DESIGN.md](MACOS-DESIGN.md) | What the Mac app is: the reading of Finder/Messages/Find My, and the two-pane window it argues for |
| [SHARED-ARCHITECTURE.md](SHARED-ARCHITECTURE.md) | The layer boundary, the file-by-file inventory, and the migration |
| [MACOS-PLAN.md](MACOS-PLAN.md) | Why macOS, why now — the market position |
| [IOS-COMPLETENESS.md](IOS-COMPLETENESS.md) | Where the iPhone app stands |
| [VISION.md](VISION.md) | The product — the writer never formats |
| [rfc-viewport-editing-model.md](rfc-viewport-editing-model.md) | **RFC v2.1, the live editing-model design** — runs in the model, markers at the boundary; cited by code comments and commit messages as "RFC v2.1" (§3.3, D6, §5.x) |
| [RFC-HIGHLIGHTER.md](RFC-HIGHLIGHTER.md) | The highlighter: single yellow attention mark on the run, FDX namespace round-trip, PDF prints it, note-wash stacking rule |
| [RFC-ACT-BREAK.md](RFC-ACT-BREAK.md) | **Phases 1–3 landed** (model + boundaries: b3d1fc5, de1406a, 442d720; derivation, selector, renumber, navigator — Mac first: 1f90e5c, e6babe6, e58b3d9, 0558928, d3da099; paste route + corpus gate: 9b16b74, b7c9189, b3bfd95, 34ad3c1; the production draft's furniture + the raw route's attachment channel: 1fe01c3, b0913af; the OMIT dash-heading, the marked title card, and the edge tell: ca95d69, 3d4dd47, 6b3bcec; cue confirmation — a pasted cue keeps `character` only when speech follows, on both engines, with the cast pinned by name in both gates: 1e0dc85; the camera's grammar types as shots on both engines, speech position answers before the cue shape, and the cue shape itself reached parity — colon labels, terminal punctuation, paren extensions — with godfather-2 the fifteenth witness: 23d0b78) — the act break: printing element, break-before, derived act ends, generated FDX `End of Act` mirroring the act's own card, canonical renumber, paste route |
| [RFC-SECONDARY-SLUG.md](RFC-SECONDARY-SLUG.md) | **Landed** (738f91d) — secondary slugs typed `.scene` (numbering honours `isSecondary`), the pasted title-page block (credit-anchored), `THE END` as a closing card, the typed OMITTED card — the third paste-routing pass |
| [rfc-emphasis-layout-model.md](rfc-emphasis-layout-model.md) | RFC v1, superseded by v2 — kept for the audit trail; its §3 consumer list was Phase 0's checklist |
| [bold-italic-underline-review.md](bold-italic-underline-review.md) | The peer review the RFCs stand on — claim-by-claim verdicts, the Beat architecture read, the landscape survey |
| [evaluation-draft-format-plan.md](evaluation-draft-format-plan.md) | The `.draft` format evaluation — the tier rule (anything pointing at text positions must be modelled) that flipped D1 |
| [CODE-REVIEW-2026-09-12.md](CODE-REVIEW-2026-09-12.md) | The September 12 code review — the September 10 findings verified fixed, two bugs found and pinned (the donor's mark, the rename's runs), watch items named |
| [work-package-1.txt](work-package-1.txt) | The paginator-parity work package RFC v2.1 §5.4 gates locked pages on |
| [Goal support bold i.txt](<Goal support bold i.txt>) | The original recommendation the peer review examined — kept so the review's subject is readable |
| `docs/artifacts/macos-design-direction.html` | A one-page summary of the design, also published as an artifact |
