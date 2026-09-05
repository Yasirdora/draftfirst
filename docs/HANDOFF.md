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
| macOS app | Builds, launches, opens a screenplay, **types**. No ghost yet |
| Packages | `EDraftEngine`, `EDraftCore`, `EDraftUI`, `EDraftMacSurface` |
| Xcode targets | `eDraft`, `eDraftTests`, `eDraft (macOS)` |

**The green baseline.** Run all of it before you start and after every step. If
a number drops, you broke something.

```bash
npm test                                              # 413 TypeScript
swift test --package-path ios/eDraftEngine            #  95 engine
swift test --package-path ios/EDraftCore              #  58 core        (macOS)
swift test --package-path ios/EDraftUI                #  12 document    (macOS)
swift test --package-path ios/EDraftMacSurface        #  31 Mac surface (macOS)
npm run check:boundaries                              #  layer imports
xcodebuild test -project ios/eDraft.xcodeproj -scheme eDraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'    # 96 app
xcodebuild build -project ios/eDraft.xcodeproj -scheme 'eDraft (macOS)' \
  -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=""                                        # the Mac app
```

---

## 3. The architecture, and the rules that hold it up

```
EDraftEngine     the rules of the craft. Foundation only. Pinned byte-for-byte
                 to the TypeScript engine by a conformance corpus.
      ▲
EDraftCore       the app's mind. Foundation + Observation, never a UI framework.
                 EditorState, the edit planner, the models, casing memory,
                 PageScroll, ScriptTypography, RevealMark, ScreenplayFile,
                 ScreenplayExporter.
      ▲
EDraftUI         shared SwiftUI: Navigator (StoryList/StoryPanel), character
                 thread, title page, settings, EDraftDocument.
      ▲                                    ▲
eDraft (iOS)                        EDraftMacSurface → eDraft (macOS)
UITextView, nav-bar chrome,         NSTextView layout and page, then a
scanning, keyboard bar              thin app around it
```

**Four rules. Breaking any of them is the failure mode this structure exists to
prevent.**

1. **A screenplay rule lives in `EDraftEngine`, never in a view.** If a view
   decides what a Return key means, the two apps will disagree eventually.
   `Choreography.emptyLineEscape` is the template: the rule moved out of
   `ScriptTextView` into the engine, and the TypeScript engine got the same
   change in the same commit.
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

1. **Ghost prediction on the Mac.** `PredictionEngine` is in the engine already;
   Tab / ⇧Tab already cycle the kind. What is missing is drawing the suffix as
   inline secondary text, Space-to-accept, and ⌘→. The phone's ghost overlay
   in `ScriptTextView` is the reference — port the drawing, not the rule.
2. **Export and print on the Mac.** `ScreenplayExporter` (core) already gives
   Fountain, FDX and text. What is missing is the drawn half: copy
   `ios/eDraft/Document/ScreenplayPageRenderer.swift` to AppKit names. Its
   header comment says exactly this.
3. **Find (⌘F), Find Scene (⌘L).**
4. **The inspector** (third pane) — M3.
5. **M0.6**, optional: move to an `apple/` directory layout. The `ios/` name is
   now wrong for a tree with a Mac app in it.

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
| [MACOS-DESIGN.md](MACOS-DESIGN.md) | What the Mac app is: the reading of Finder/Messages/Find My, and the three-pane window it argues for |
| [SHARED-ARCHITECTURE.md](SHARED-ARCHITECTURE.md) | The layer boundary, the file-by-file inventory, and the migration |
| [MACOS-PLAN.md](MACOS-PLAN.md) | Why macOS, why now — the market position |
| [IOS-COMPLETENESS.md](IOS-COMPLETENESS.md) | Where the iPhone app stands |
| [VISION.md](VISION.md) | The product, from the beginning |
| `docs/artifacts/macos-design-direction.html` | A one-page summary of the design, also published as an artifact |
