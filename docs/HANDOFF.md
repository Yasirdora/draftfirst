# Handoff

*Written 2026-09-05, last updated on branch `rename/edraft`.
For whoever picks this up next — human or otherwise.*

Read this file first, then [MACOS-EXECUTION.md](MACOS-EXECUTION.md), which is
the live working document with the milestone checkboxes. Everything below is
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
| macOS app | Greets on launch, page card, types, ghosts, finds, exports, prints. Title page is a sheet; Cast opens the character thread. View modes and statistics still M3 |
| Packages | `EDraftEngine`, `EDraftCore`, `EDraftUI`, `EDraftMacSurface`, `EDraftUIKitSurface` |
| Xcode targets | `eDraft`, `eDraftTests`, `eDraft (macOS)` |

**The green baseline.** Run all of it before you start and after every step. If
a number drops, you broke something.

```bash
npm test                                              # 414 TypeScript
swift test --package-path ios/eDraftEngine            #  95 engine
swift test --package-path ios/EDraftCore              #  88 core        (macOS)
swift test --package-path ios/EDraftUI                #  18 document    (macOS)
swift test --package-path ios/EDraftMacSurface        #  77 Mac surface (macOS)
npm run check:boundaries                              #  layer imports
xcodebuild test -project ios/eDraft.xcodeproj -scheme eDraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'    # 102 app
xcodebuild build -project ios/eDraft.xcodeproj -scheme 'eDraft (macOS)' \
  -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=""                                        # the Mac app
```

The `EDraftUIKitSurface` package has no suite of its own and is not in that
list. It imports UIKit, so it cannot be built by `swift test` on a Mac host at
all; its behaviour is covered by the 102 in the iOS app target, which runs under
the simulator where the document plumbing those tests drive already lives. A
test target there would be a path nobody could run.

**If a Mac build stops dead at `CodeSign`**, look for a keychain prompt: macOS
is asking for the signing key and `xcodebuild` will wait for it indefinitely.
`CODE_SIGNING_ALLOWED=NO` verifies that the target compiles and links without
touching the key, which is what a build check actually needs.

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
keyboard bar, the panels            eDraft (macOS)   menus, document plumbing
```

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
   engine:conformance` to regenerate `ios/eDraftEngine/Fixtures/`, then make the
   Swift port match. Never the other way round.
3. **`EDraftCore` may not import SwiftUI, UIKit or AppKit.** Enforced —
   `npm run check:boundaries`, wired into `npm run quality`.
4. **One document format.** No macOS-only fields, ever. Both apps open the same
   `.draft`.

---

## 4. What to do next

The plan is [MACOS-EXECUTION.md](MACOS-EXECUTION.md). In order of value:

1. **View modes** (Page · Typewriter · Focus) and statistics in the
   status area — remaining M3. The inspector was retired: a properties
   pane has nothing continuous to hold. Format → Element, Scene Numbers,
   File → Title Page, and the Cast thread are done.
2. **Writing-assistance settings**, shared with iOS.
3. **M0.6**, optional: move to an `apple/` directory layout. The `ios/` name is
   now wrong for a tree with a Mac app in it.

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
  floor. `rm -rf ios/*/.build` and run again.
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
  `ios/eDraft.xcodeproj/project.pbxproj` by hand: a `PBXBuildFile`, a
  `PBXFileReference`, a group child, and a Sources entry. There are several
  worked examples in the git history — copy one.

**Code**

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
  xcodebuild build -project ios/eDraft.xcodeproj -scheme eDraft \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG EDITOR_PREVIEW'
  # then install and launch with one of:
  #   -qa-scroll-stability  -qa-action-lowercase
  #   -qa-character-uppercase  -qa-quicktype-scene
  # the app staying alive for ~10s is the pass
  ```
  Run it after touching anything about scrolling, typing or layout.

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

## 7. The documents

| File | What it is |
|---|---|
| [MACOS-EXECUTION.md](MACOS-EXECUTION.md) | **The working document.** Milestones, proofs, decisions taken, known issues |
| [MACOS-DESIGN.md](MACOS-DESIGN.md) | What the Mac app is: the reading of Finder/Messages/Find My, and the two-pane window it argues for |
| [SHARED-ARCHITECTURE.md](SHARED-ARCHITECTURE.md) | The layer boundary, the file-by-file inventory, and the migration |
| [MACOS-PLAN.md](MACOS-PLAN.md) | Why macOS, why now — the market position |
| [IOS-COMPLETENESS.md](IOS-COMPLETENESS.md) | Where the iPhone app stands |
| [VISION.md](VISION.md) | The product — the writer never formats |
| `docs/artifacts/macos-design-direction.html` | A one-page summary of the design, also published as an artifact |
