# eDraft on macOS — Execution

*Status: M0 all but complete · M1 answered · **M2 has a window that builds** · Last updated 2026-09-05*

This is the working document. New here? Read [HANDOFF.md](HANDOFF.md) first —
it carries the state, the rules and the traps in one page.
[MACOS-PLAN.md](MACOS-PLAN.md) says why we are
building it, [MACOS-DESIGN.md](MACOS-DESIGN.md) says what it is, and
[SHARED-ARCHITECTURE.md](SHARED-ARCHITECTURE.md) says how the two apps stay one
product. **Start here, then read those.**

---

## 0. Where we are today

No macOS *app* yet — by design. But the code it will be built from now exists
and compiles for macOS: `EDraftCore` and `EDraftUI` are packages, and 35 of the
app's tests run on the Mac under `swift test`.

**Green baseline** (re-run these before and after every step):

```bash
npm test                                    # 406 TypeScript engine tests
cd ios/eDraftEngine && swift test           #  89 Swift engine tests
cd ios/EDraftCore   && swift test           #  39 core tests — runs on macOS
cd ios/EDraftUI     && swift test           #   8 document tests — runs on macOS
cd ios/EDraftMacSurface && swift test       #  15 layout and page tests — macOS
xcodebuild build -project ios/eDraft.xcodeproj \
  -scheme 'eDraft (macOS)' -configuration Debug           # the Mac app
npm run check:boundaries                    #  the layers stay separate
xcodebuild test -project ios/eDraft.xcodeproj -scheme eDraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   #  82 app tests
```

The packages live at `ios/EDraftCore` and `ios/EDraftUI`, beside
`ios/eDraftEngine`, and are wired into `ios/eDraft.xcodeproj` as local package
references.

**State of the tree:** the directory rename `DraftFirst → eDraft` is complete
and verified (targets `eDraft`/`eDraftTests`, bundle ids `xyz.edraft.ios`,
module `EDraftEngine`, no stale references in source). The iOS app is feature-
complete for M1–M3 of its own plan; the most recent work was the Navigator
reveal mark (see §6).

**To resume cold:** read this file, then §1's next unchecked box. Every box
states its own proof; if the proof passes, the box is done.

---

## 1. Milestones

### M0 — Modularise (no behaviour change) · *the prerequisite*

The macOS app cannot link code that lives in an iOS app target. This milestone
moves it, and changes nothing else. Detail and file-by-file inventory in
[SHARED-ARCHITECTURE.md §4](SHARED-ARCHITECTURE.md).

- [x] **M0.1** `EDraftCore` package; move `EditorState`, `ScreenplayEditPlanner`,
      `ScreenplayModels`, `ElementCaseMemory`, `SceneHeadingSeparator`,
      `DocumentArrival` verbatim.
      *Done 2026-09-05 (`b96012c`).* iOS builds; all tests green.
- [x] **M0.2** Move core-only tests into `EDraftCoreTests`, run by `swift test`
      on iOS **and** macOS.
      *Done 2026-09-05 (`0e8485e`).* 89 app + 35 core = the same 124, and the
      35 now run on macOS.
- [x] **M0.3** Split `EDraftDocument`. *Done 2026-09-05 (`86eb324`).* The split
      as executed — and it was the fiddliest of the six, because one
      `enum ScreenplayExporter` interleaved pure and platform-bound code:

      | To `EDraftCore` | Stays on the surface |
      |---|---|
      | `extension UTType` (both declarations) | `pdfData` and its `UIFont`/`UIColor`/`UIGraphicsPDFRenderer` drawing |
      | `decode`/`encode`, typed and untyped | `rtfData` (uses the same font) |
      | `blankSource` | |
      | `fountainSource`, `fdxSource`, `plainText` | |
      | `sceneNumberIndex`, `sceneNumberMarks` | |
      | `paginate`, `leadingSpaces`, `renderedText` | |
      | `temporaryFile` | |

      `EDraftDocument` went to `EDraftUI` as a thin wrapper over
      `ScreenplayFile`; the drawn half is `ScreenplayPageRenderer` on the
      surface. The document's own tests went with it — `EDraftUI` has a test
      target now, so the round-trip, the UTF-8 refusal and the arrival rules
      run on macOS.
- [x] **M0.4** `EDraftUI` package; move `StoryPanel`, `CharacterThreadView`,
      `TitlePageSheet`, `SettingsPanel`; replace `navigationBarTitleDisplayMode`
      with a platform shim.
      *Done 2026-09-05 (`57534d0`).* Both packages build for macOS; iOS tests
      green. **Owed:** the screenshot comparison — the Mac's screen locked
      before it could be taken. Take it first thing: open a document, open the
      Navigator, compare against `docs/images` or a fresh baseline.
- [x] **M0.5** Share the reveal's *timing*, not its plumbing. *Done 2026-09-05.*
      The step as written would have added an indirection that only forwarded
      to `ScreenplayEditPlanner.ranges(for:)`, which is already core — hollow,
      and against the rule that a move must earn itself. What genuinely cannot
      be allowed to drift is when the mark appears and how long it is held: a
      mark that behaves differently on a desk than in a hand is one feature
      pretending to be two, and no compiler would notice. `RevealMark` in the
      core now holds the timing and the padding, with four tests; the iOS view
      reads them. It gained reduce-motion support in the process — the mark
      appears and goes without fading, because less motion must never mean no
      answer.
- [ ] **M0.6** *(optional, recommended)* adopt the `apple/` directory layout.
      *Proof:* clean checkout builds both schemes.

### M1 — The spike · *the unknown is answered*

The question was whether the Mac's text system can tell us where an element is,
since every scroll and every reveal is built on that. **It can — on both text
systems.** Measured, not assumed: `EDraftMacSurface` is a package rather than
app-target code precisely so the answer is a test rather than a demo, and
`swift test --package-path ios/EDraftMacSurface` runs it in a fraction of a
second with no window ever shown.

- [x] `ScriptLayout` sets the script for an `NSTextView` on either stack.
- [x] Element paragraph styles come from `ScriptTypography` in the core — the
      same fractions the iPhone uses, so the two platforms cannot disagree
      about the shape of a page. The iOS surface was changed to read them too;
      it had its own copy.
- [x] **TextKit 1 and TextKit 2 both place a late element.** TextKit 1's
      arithmetic is identical to the iPhone's, which is the deciding
      consideration: the reveal and scroll code ports rather than being
      rewritten. **Decision: TextKit 1 for the Mac surface**, with TextKit 2
      kept behind `ScriptLayout.TextStack` and under the same tests, so the
      choice can be revisited with evidence rather than argued.
- [ ] Ghost prediction drawn as inline secondary text — still to do.
- [ ] The text view inside an `NSViewRepresentable`, in a window.

**What the measurements found.** A line with nothing on it encloses no glyphs
and therefore measures **no width** — and `CGRect.isEmpty` is true when *either*
dimension is zero. Testing emptiness there silently discards a real line. The
blank line at the very end of a script is worse still: it has no line fragment
of its own at all and lives in the text system's *extra* fragment, which only
exists once the whole container has been laid out.

**This was a live bug on iOS**, found by writing the Mac's version as a
measurement: revealing a blank line drew no mark, and a reveal of the last line
of a script would have marked the wrong one. Both are fixed, in both surfaces,
and `NavigatorJumpTests.testABlankLineIsStillMarked` holds the line.

### M2 — The window · *begun*

- [x] A macOS app target, `eDraft (macOS)`, with its own scheme. It shares the
      project with the phone deliberately: one place to open, one set of
      packages, no second copy of anything.
- [x] `DocumentGroup` over the same `EDraftDocument` the phone opens — so a
      script started on an iPhone opens here with no conversion and no second
      format. The Mac declares the same three document types in its own
      Info.plist (our own, plain text, Final Draft); they cannot be expressed as
      `INFOPLIST_KEY_*` settings, and a generated plist quietly leaves a
      document-based app unable to open a document.
- [x] Two of the three panes: `StoryList` in a sidebar at 240/260/360, the page
      beside it on `underPageBackgroundColor`. Sidebar visible by default.
- [x] The page itself — `ScriptSurface` — scrolls, reveals and marks, with 15
      tests. A Navigator row on the Mac does exactly what it does on the phone.
- [x] Format → Element with ⌘1–⌘9, through the model's own conversion channel,
      so casing memory and undo grouping come along rather than being
      re-implemented for a menu.
- [ ] Typing: the edit planner wired to the text view's delegate. **Next.**
- [ ] Tab / ⇧Tab choreography, and the ghost prediction.
- [ ] Find (⌘F), Find Scene (⌘L).
- [ ] Export PDF · FDX · Fountain · Text; native print.
- [ ] The rest of the menu bar: File, Edit, View per MACOS-DESIGN §3.4.

*Proof, when it closes:* a script written entirely on the Mac, exported to PDF,
opens on iPhone unchanged.

### M3 — The desk

- [ ] Inspector: title page · scene · character.
- [ ] Statistics in the window's status area.
- [ ] Writing-assistance settings, shared with iOS.
- [ ] Typewriter and Focus view modes.
- [ ] Full keyboard access and VoiceOver pass.

### M4 — The production layer

- [ ] Revision colours, marks, locked pages (engine already has `RevisionDiff`,
      `SceneNumbering`).
- [ ] Scene numbering UI in the inspector.
- [ ] Table read with `AVSpeechSynthesizer`, a voice per character.

### M5 — The platform

- [ ] Handoff between iPhone and Mac.
- [ ] Shortcuts actions, Spotlight indexing, Quick Look thumbnails, Services.

---

## 2. Definition of done, every milestone

1. All three suites green (§0).
2. No new rule outside `EDraftEngine`.
3. Dark mode, accent colour, reduce-motion, VoiceOver checked by hand.
4. Nothing added to the toolbar that the menu bar could carry.
5. The iOS app still builds and its tests still pass — the boundary held.

---

## 3. Risks, and what we do about them

| Risk | Response |
|---|---|
| TextKit 2 lacks the rectangle maths the reveal/scroll code relies on | M1 spike decides; TextKit 1 is an acceptable answer on both platforms |
| Modularisation drags | M0 is moves only; if a step needs a rewrite, the step is wrong |
| Menu conventions | Measured against Pages, not invented |
| Scope creep into M4 | Production layer is forbidden before M3 ships |
| Two codebases drift | `EDraftCoreTests` run on both platforms in CI (§5 of the architecture doc) |

---

## 4. Open questions for Ysr

None blocking. Two worth a decision when convenient:

1. **`apple/` layout (M0.6)** — do it now while the tree is churning, or later?
   Recommendation: now.
2. **Mac App Store vs direct + notarised** — affects sandbox entitlements for
   iCloud and scanning-adjacent features. Recommendation: sandboxed and
   Store-ready from M2, so it is never a retrofit.

---

## 5. Decisions already taken

| Date | Decision | Why |
|---|---|---|
| 2026-09-05 | Sidebar **visible** by default, reversing the earlier plan | The reference apps make the sidebar the organisation panel; a Mac window without one reads as a ported iPad app. Focus mode covers distraction-free writing. |
| 2026-09-05 | Three panes, not two | A screenplay needs a properties surface; Pages/Keynote/Xcode users look right for it. |
| 2026-09-05 | Modularise before writing Mac code | 2,155 lines are portable but trapped in an app target. |
| 2026-09-05 | No Catalyst, no Electron | Catalyst would ship iOS compromises to a desktop whose whole point is not having them. |
| 2026-09-05 | Packages sit at `ios/EDraftCore` and `ios/EDraftUI` for now | The `apple/` move (M0.6) is still worth doing, but not while three other steps were in flight. |
| 2026-09-05 | Core and UI packages are main-actor-by-default; their **test** targets are not | Matches the app targets exactly, and XCTestCase cannot inherit main-actor isolation. |

---

## 4a. Building and running the Mac app

```bash
xcodebuild build -project ios/eDraft.xcodeproj -scheme 'eDraft (macOS)' -configuration Debug
```

**One environmental note.** Signing with the Developer identity asks the
keychain for permission, which a headless build cannot answer — the build then
hangs at `codesign` indefinitely. From Xcode this is a prompt you click once.
From a script, pass `CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual
DEVELOPMENT_TEAM=""` to sign ad hoc, which is enough to run locally.

Verified on 2026-09-05: the app builds, launches, presents its menu bar (File,
Edit, View, Window) and opens a `.fountain` script into a document window —
confirmed through `CGWindowListCopyWindowInfo`, since the screen was locked and
neither a screenshot nor the accessibility API can see a window in that state.

## 5a. Enforcement added

- **`npm run check:boundaries`** walks the three package sources and fails on a
  forbidden import: the engine may not reach for a UI framework or for the
  layers above it, the core may not draw, and a shared panel may not name UIKit
  or AppKit. It is plain Node, so it runs on the Linux box that runs CI, and it
  is wired into `npm run quality`. Verified by planting a violation and
  watching it fail.
- **A macOS CI job** now runs `swift test` over all four packages — 143 tests.
  It has not run on a GitHub runner yet: the packages require macOS 26, so the
  first run needs watching in case `macos-latest` is still older than that.

## 6. Known issues, carried forward

- **`Screenplay` names two different types** — the engine's and the app's. Nine
  call sites now say `EDraftCore.Screenplay` explicitly. Qualifying is a label,
  not a fix; renaming one of them (the app's, most likely, to
  `ScreenplayDocumentModel`) is worth a focused pass.
- ~~The iOS Navigator screenshot comparison for M0.4 is owed.~~ **Done** —
  captured after the extraction and identical to the pre-extraction shot: same
  rows, same numbers, same two-line footnote.
- **The FDX rename-compatibility contract was lost and restored** during the
  rename: `LEGACY_ATTRIBUTE_PREFIXES` had been emptied in both engines and the
  TypeScript suite guarding it deleted, which would have silently dropped
  `draftfirst:` extension data — lyrics types, keyed title pages — from every
  file exported under the old name. Both engines now carry the prefix and both
  have tests. If any other back-compat was swept up in that rename, this is the
  shape it would take.

## 7. Recent iOS work this plan assumes

- **Navigator reveal + mark.** A Navigator row now reveals its element *and
  marks it*, because a page stops scrolling when its last page reaches the
  bottom — targets near the end never reach the top, and targets already on
  screen never move at all. Both looked like dead rows, on scenes and worse on
  cast lines. `ScriptTextView.reveal(_:)` refreshes its range table from the
  model before looking up (so a stale cache cannot miss silently) and marks the
  landing with `RevealHighlightView`. Covered by `NavigatorJumpTests` (7).
- **Reading-mode chrome.** `[(<)(Edit) … (Navigator)(…)]`; the slot beside the
  menu morphs into Undo when writing begins.
- **Empty-line escape** lives in `Choreography.emptyLineEscape` — engine, not
  view — and is a **two-stop ring**: `action ⇄ character`, everything else
  `→ action`. A scene heading is deliberately not in it: Fountain defines a line
  beginning INT./EXT./EST./I/E. as a slug, and `ScenePromotion` now promotes it
  as it is typed. Three stops cost a third tap for the two kinds a writer cannot
  type their way into, and landed the oldest reflex in the craft — Return twice
  after a speech — on a heading instead of action.
