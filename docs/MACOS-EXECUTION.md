# eDraft on macOS — Execution

*Status: M0 all but complete — five of six steps done · Last updated 2026-09-05*

This is the working document. [MACOS-PLAN.md](MACOS-PLAN.md) says why we are
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
npm run check:boundaries                    #  the layers stay separate
xcodebuild test -project ios/eDraft.xcodeproj -scheme eDraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   #  81 app tests
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

### M1 — The spike · *one day, throwaway allowed*

The only genuine unknown is the text surface. Prove it before committing.

- [ ] `NSTextView` in an `NSViewRepresentable`, one window, no document.
- [ ] Element paragraph styles at engine metrics (Courier Prime 12, real margins).
- [ ] `ScreenplayEditPlanner` driving edits through the same coordinator shape as iOS.
- [ ] Ghost prediction drawn as inline secondary text.
- [ ] Reveal + mark, using whichever text stack survives the next line.
- [ ] **Decide: TextKit 2 or TextKit 1.** iOS uses TextKit 1 deliberately; its
      scroll and reveal maths read `NSLayoutManager` rectangles. Either re-derive
      them via `NSTextLayoutManager` or match iOS exactly. Write the decision and
      the measurements into this file before proceeding.

*Proof:* type a scene, a cue and dialogue; Tab cycles by engine choreography;
prediction appears and accepts; a reveal marks the right line.

### M2 — The window

- [ ] `DocumentGroup`, open/save/iCloud, one document per window, tabs.
- [ ] Three-pane layout: Navigator · page canvas · inspector (hidden).
- [ ] Navigator from `EDraftUI` with the Scenes/Cast scope control.
- [ ] Page canvas: centred page, `underPageBackgroundColor`, zoom.
- [ ] Menu bar: File/Edit/Format/View per [MACOS-DESIGN.md §3.4](MACOS-DESIGN.md).
- [ ] ⌘1–9 element conversion; Tab/⇧Tab; ⌘F find; ⌘L find scene.
- [ ] Export PDF · FDX · Fountain · Text; native print.

*Proof:* a script written entirely on the Mac, exported to PDF, opens on iPhone
unchanged.

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

## 5a. Enforcement added

- **`npm run check:boundaries`** walks the three package sources and fails on a
  forbidden import: the engine may not reach for a UI framework or for the
  layers above it, the core may not draw, and a shared panel may not name UIKit
  or AppKit. It is plain Node, so it runs on the Linux box that runs CI, and it
  is wired into `npm run quality`. Verified by planting a violation and
  watching it fail.
- **A macOS CI job** now runs `swift test` over all three packages — 132 tests.
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
  view: `action → character`, `character → scene`, everything else `→ action`.
