# eDraft on macOS — Execution

*Status: M0 all but complete · M1 answered · M2 closed · **M3** · Last updated 2026-09-06*

This is the working document. New here? Read [HANDOFF.md](HANDOFF.md) first —
it carries the state, the rules and the traps in one page.
[MACOS-PLAN.md](MACOS-PLAN.md) says why we are
building it, [MACOS-DESIGN.md](MACOS-DESIGN.md) says what it is, and
[SHARED-ARCHITECTURE.md](SHARED-ARCHITECTURE.md) says how the two apps stay one
product. **Start here, then read those.**

---

## 0. Where we are today

The Mac app builds, opens a `.draft` / Fountain file, scrolls, reveals,
types, ghosts, finds, exports, prints. Title page is a sheet; the
character thread is the Cast tab. View modes and statistics are still
ahead.

**Green baseline** (re-run these before and after every step):

```bash
npm test                                              # 414 TypeScript
swift test --package-path apple/eDraftEngine            #  95 engine
swift test --package-path apple/EDraftCore              #  88 core        (macOS)
swift test --package-path apple/EDraftUI                #  18 document/filter (macOS)
swift test --package-path apple/EDraftMacSurface        #  76 Mac surface (macOS)
npm run check:boundaries                              #  layer imports
xcodebuild test -project apple/eDraft.xcodeproj -scheme eDraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'    # 96 app
xcodebuild build -project apple/eDraft.xcodeproj -scheme 'eDraft (macOS)' \
  -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=""                                        # the Mac app
```

If `swift test` fails in every package with `missing required module 'SwiftShims'`,
the `.build` directories were compiled at an older path of this repo. That is
not a broken floor: `rm -rf apple/*/.build` and run again.

The packages live at `apple/EDraftCore` and `apple/EDraftUI`, beside
`apple/eDraftEngine`, and are wired into `apple/eDraft.xcodeproj` as local package
references.

**State of the tree:** the directory rename `DraftFirst → eDraft` is complete
and verified (targets `eDraft`/`eDraftTests`, bundle ids `xyz.edraft.ios`,
module `EDraftEngine`, no stale references in source). The iOS app is feature-
complete for M1–M3 of its own plan. The Mac page now takes a keystroke (see M2).

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
- [x] **M0.7** `EDraftUIKitSurface` package; move `ScriptTextView`,
      `RevealHighlight`, `ScreenplayPageRenderer` out of the iOS app target.
      *Done 2026-09-06.* The last of the modularisation, and iPadOS is what
      made it due rather than tidy. Three files moved unchanged — git records
      all three as renames — and the whole delta is twenty-one lines of access
      control. The app turned out to touch the package in two files and two
      symbols, fewer than the estimate; the three other files given imports on
      the way did not need them, which the compiler was asked rather than
      trusted. 96 iOS tests passed before and after, unchanged in name.
- [x] **M0.6** adopt the `apple/` directory layout.
      *Proof:* clean checkout builds both schemes. Now the more adjacent of the
      two — five packages live under `apple/`, and the folder's name has been
      wrong since the Mac app existed.
      *Done 2026-09-08.* `git mv ios apple`; every path in the docs, the scripts,
      CI and `.gitignore` followed, `.build` caches were dropped, and the boundary
      check and both package builds were green afterwards.

### M1 — The spike · *the unknown is answered*

The question was whether the Mac's text system can tell us where an element is,
since every scroll and every reveal is built on that. **It can — on both text
systems.** Measured, not assumed: `EDraftMacSurface` is a package rather than
app-target code precisely so the answer is a test rather than a demo, and
`swift test --package-path apple/EDraftMacSurface` runs it in a fraction of a
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
- [x] Ghost prediction drawn as inline secondary text — tracked under M2.
- [x] The text view inside an `NSViewRepresentable`, in a window.
      *Done with the M2 window (`ScriptPageView`).*

**What the measurements found.** A line with nothing on it encloses no glyphs
and therefore measures **no width** — and `CGRect.isEmpty` is true when *either*
dimension is zero. Testing emptiness there silently discards a real line. The
blank line at the very end of a script is worse still: it has no line fragment
of its own at all and lives in the text system's *extra* fragment, which only
exists once the whole container has been laid out.

**The height is a result of layout, and of `maxSize`.** M1: a text view's
height is not recomputed until it is asked (`sizeToFit` / `ensureLayout`).
M2's page card, two stacked causes, both required:

1. `NSTextView.init(frame:textContainer:)` copies the frame into min/max
   size. We passed height 0; `sizeToFit` will not grow past `maxSize`.
   `layoutPage` then set the view to `max(0, 1)` — one point tall, glyphs
   still in the layout manager. `NSScrollView` had been sizing its
   document view and hiding this. Measured after init: `frame=(432, 0)
   min=(432, 0) max=(432, 0)`. After render, before the fix:
   `frame=(432, 1) max=(432, 1)`.
2. The page card itself was not flipped. The canvas and the text view
   are. An unflipped card inside a flipped canvas puts `y = 72` at the
   *bottom* of the sheet. A 450pt window shows the top of an 11″ card
   — empty paper — with the script sitting at the foot. Measured:
   first line at canvas y=450, expected 108. `testTheFirstLineSitsAtTheTopOfTheCard`.

The third occurrence should be recognised on sight: if the script is
not on the page, print `minSize` / `maxSize` / `frame.height` **and**
convert the first line into the canvas and see whether it is at the
top of the card. `testTheLastElementLandsOnTheCard` is the assertion
that would have stopped a 1pt-tall view shipping green — last
element's bounding rect inside the text view and inside the card,
not a height greater than zero. It would not have caught the flip;
that needed a coordinate in the canvas.

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
- [x] Two panes: `StoryList` in a sidebar at 240/260/360, the page
      beside it on `underPageBackgroundColor`. Sidebar visible by default.
- [x] The page itself — `ScriptSurface` — scrolls, reveals and marks. A
      Navigator row on the Mac does exactly what it does on the phone.
- [x] Format → Element with ⌘1–⌘9, through the model's own conversion channel,
      so casing memory and undo grouping come along rather than being
      re-implemented for a menu. The callback was unwired until typing bound
      it; the menu is live now.
- [x] Typing: the edit planner wired to the text view's delegate.
      *Done 2026-09-05.* `ScriptSurface` is the `NSTextViewDelegate`. Ordinary
      letters stay with AppKit; Return, a boundary delete, a scene-heading
      dash, empty-line escape and scene promotion go through the planner and
      the engine, never through a view-local rule. 15 typing tests, no window.
      **Measured, not assumed:**
      - `NSTextView.undoManager` is nil without a window (the tests never have
        one). The surface owns an `UndoManager` and vends it through
        `undoManager(for:)`.
      - Tab is `textView(_:doCommandBy:)` — `insertTab` / `insertBacktab` —
        not an `NSTextView` subclass. Return stays in `shouldChangeTextIn`
        only, so it has one path.
      - `textViewDidChangeSelection` writes `editor.selectionChanged`. Tab and
        ⌘1–9 read `activeElementID`; without this they convert whichever
        element was last rendered or jumped to. The tests set the selection
        directly, not via `reveal`.
      - `typingAttributes` come from `ScriptLayout.attributes` on every
        selection change. There is no software-keyboard trait on the Mac.
      - `isRichText = false` did **not** steal a cue's indent when a letter
        was typed into the action below it
        (`testTypingDoesNotRestyleADifferentElement`).
      - `Choreography.emptyLineEscape` is the primitive; the surface still
        wraps it with the whitespace-only guard and the no-op-when-same-kind
        guard, same as the phone.
      - A SwiftUI refresh after a keystroke (`renderIfNeeded`, which is what
        `updateNSView` calls) must not replace the storage. Live typing
        records `renderedRevision` so the subtitle reading `stats` cannot
        send the caret to the top.
- [x] Tab / ⇧Tab choreography. *Shipped with typing.* Ghost prediction is
      still open — that is drawing, not the key.
- [x] Ghost prediction drawn as inline secondary text.
      *Done 2026-09-05.* `GhostTextOverlay` is its own TextKit stack, never
      inserted into the document. Space accepts; a suffix that begins with a
      space inserts literally (so EVENING is still typeable); ⌘→ is Edit →
      Accept Suggestion, routed through `editor.acceptPrediction()`. 12 tests,
      the first real net the ghost has had on either platform.
      **Measured, not assumed:**
      - Predictions are async (65ms + detached engine). Tests that asserted
        immediately flaked. Wait for the suffix, then call `updateGhost()`.
      - `RunLoop.run(mode:before:)` returns immediately when idle and starves
        the MainActor `Task.sleep`. `run(until:)` actually waits.
      - `firstRect(forCharacterRange:)` is screen-space and junk without a
        window. The caret-alignment hide is skipped when there is no window;
        the layout-manager checks still run.
      - A surface with no window is allowed to draw (the test harness); a
        real window without focus is not.
      - Overlay `isFlipped` matches the text view. A test asserts a non-zero
        frame sitting on the host line, not just a stored suffix string.
      - Hint colour is `NSColor.tertiaryLabelColor`, live colour is
        `secondaryLabelColor` — read back off the overlay, not a bool.
      - `NSTextView.insertText("int. kitchen")` promotes to a scene heading
        without throwing. That is the AppKit path the phone's UIKit
        `textDidChange` → `render` was suspected of breaking.
- [x] Find (⌘F), Find Scene (⌘L).
      *Done 2026-09-05.* System find bar, not a custom one. Find Scene is
      the Navigator filter (⌘L), not a Spotlight overlay.
      **Measured, not assumed:**
      - `insertText` *does* call `shouldChangeTextIn` (harness check).
      - `NSTextView.replaceCharacters(in:with:)` does **not** call
        `shouldChangeTextIn` and does not fire `textDidChange`. Replace
        would write the storage behind the planner. **Find ships without
        Replace:** the find client reports `isEditable = false` so the
        bar does not offer it; the text view itself stays editable for
        typing. `replaceDisabled()` is also set on the page.
      - `performFindPanelAction(nil)` in a windowed XCTest did **not**
        show a find bar. The bar needs a hand pass. A full storage
        replace did not crash.
      - Incremental search: we do not set `NSTextView.usesFindBar` (that
        client is editable and would offer Replace). The `NSTextFinder`
        we own uses the system bar; content is not dimmed
        (`incrementalSearchingShouldDimContentView = false`) because
        dimming the page hides the match.
      - `CommandGroupPlacement.textFinding` does not exist in this SDK.
        Find commands sit in Edit after Paste.
- [x] Export PDF · FDX · Fountain · Text; native print.
      *Done 2026-09-05.* The page on screen is the page that prints:
      Courier 12, 612pt card, 108pt left margin, paginator indents,
      centred on `underPageBackgroundColor`. File → Export offers the
      four formats; Print is the exported PDF.
      **Measured, not assumed:**
      - `kCGPDFContextKeywords` writes `/Keywords (hex)` as a PDF
        literal in the Info dictionary. Hex is `[0-9a-f]`, legal inside
        a literal with no escaping. The extractor (TypeScript and Swift)
        accepts both `(hex)` and `<hex>`. A `%%EOF` stamp is not a
        field and is dropped by Preview's re-save. Size: 32, 1K, 10K,
        50K, 100K, 240K, **500K** hex characters all survived a
        `PDFDocument` rewrite (`hexPresent=true` on the rewritten
        bytes). A feature script is ~240KB of hex. No attachment
        fallback. `testTheExportedPdfSurvivesAPdfReaderRewrite` is the
        test that would have caught the stamp.
      - `NSPrintOperation` over a custom view would paginate again
        against `NSPrintInfo`'s paper. Print is `PDFDocument.printOperation`
        over the bytes we already export, so print cannot drift from PDF.
      - `NSTextView.textContainerInset` width is symmetric, so the
        108/72 margins are a text view framed at x=108, width=432
        inside the card, not an inset.
      - Layer `cgColor`s are snapshots. `applyAppearance` takes them
        inside `effectiveAppearance.performAsCurrentDrawingAppearance`
        or a dark page on a dark canvas has no edge.
      - Subsequent pages are marked with a hairline every letter-page
        of height. A live `NSTextView` cannot insert the PDF's per-page
        top margin mid-element (a split action, a (MORE) break), so
        stacked cards with gaps were refused rather than faked.
- [ ] The rest of the menu bar: View modes (Page · Typewriter · Focus).
      File → Title Page and the Cast thread are done. Format → Element
      and Scene Numbers are done. There is no inspector.

*Proof, executed:* a script written entirely on the Mac, exported to PDF
via `ScreenplayPageRenderer.pdfData`, opened with `PDFDocument` and
written back out, extracts through `PdfSignal` identical — including
curly quotes, an em dash, and Japanese.
`testTheExportedPdfSurvivesAPdfReaderRewrite`. The iPhone UI was not
driven to Open that file; the import path calls the same extract.

### M3 — The desk

- [x] **A launch window, so the Mac says what it is before a word is written.**
      *Done 2026-09-05 (`04766ab`, `cff3f2c`).* A document app otherwise opens
      into a file dialog or an untitled document, and neither says what the
      application is for. `LaunchIdentity` — the margin rule at the inch and a
      half, the production revision run along the foot — moved from the phone's
      app target to `EDraftUI`, so one ground serves both machines; its colours
      resolve from the environment rather than a `UIColor` provider, because
      that package may import neither kit. **Measured:**
      - `DocumentGroupLaunchScene` is `@available(macOS, unavailable)`. The
        symbol is in the macOS interface file, marked unavailable — reading only
        the tvOS/watchOS lines above it will tell you the opposite.
      - `applicationShouldHandleReopen` returning `hasVisibleWindows` is a bug:
        with nothing on screen it answers "I handled it" and handles nothing,
        leaving a running app with no window and no way back but the Window
        menu. `openWindow` is readable only inside a view, so the action is
        captured while one exists.
      - `NSDocumentController.shared.recentDocumentURLs` is populated by launch;
        the app's `NSRecentDocumentRecords` default is not the place to look for
        it. `File → Open Recent` is the honest probe.
- [x] Title page · character thread · scene facts — without a third pane.
      *The inspector was built 2026-09-06 and retired 2026-09-06.* A
      properties column earns width when properties are what you are
      doing. The writer never formats, so there is nothing continuous
      to hold. Replaced by: File → Title Page… (`TitlePageSheet`, the
      same sheet as the phone); Cast tab → `CharacterThreadView` (the
      destination had only been wired on the phone's sheet); scene
      number and page stay on the Navigator row. The right column is
      **reserved** for comments and notes keyed to `ScriptElement.id`.
      `InspectorFocus` and `SceneInspection` went with the pane;
      `CharacterRename` stays.
- [ ] Statistics in the window's status area.
- [ ] Writing-assistance settings, shared with iOS.
- [ ] Typewriter and Focus view modes.
- [ ] Full keyboard access and VoiceOver pass.

### M4 — The production layer

- [ ] Revision colours, marks, locked pages (engine already has `RevisionDiff`,
      `SceneNumbering`).
- [ ] Scene numbering for locked pages / production (Format already
      applies numbers; this is the M4 meaning of them).
- [ ] Table read with `AVSpeechSynthesizer`, a voice per character.

### M5 — The platform

- [ ] Handoff between iPhone and Mac.
- [ ] Shortcuts actions, Spotlight indexing, Quick Look thumbnails, Services.

---

### M4 — Pages' toolbar: the window is AppKit's · *done 2026-09-08*

The owner's prototype (a Freeform-style desk with a page) showed what the Mac
window should be: the toolbar's Liquid Glass turning light as the white page
passes under it, the script softening into the chrome, the sidebar native. Every
piece of that was measured before it was built — see `SplitWindowController`'s
comment for the numbers, and `docs/images/macos-toolbar-adaptive-2026-09-08.png`
(paper page, chips light) and `macos-window-dark-page-2026-09-08.png` (dark page,
chips dark) for what it looks like.

- [x] **`SplitWindowKit`** — a new package holding the AppKit window that hosts
      SwiftUI columns under a unified toolbar, and nothing about screenplays.
      The boundary check forbids it importing any eDraft package. *Proof:* it
      is the piece a second app takes unchanged.
- [x] **`ScriptWindowController` replaces `ScriptWindow`.** Same Navigator,
      thread column, page, zoom control and title page sheet; the toolbar is
      `NSToolbar` (element menu, page/title page/export group, overflow) and
      every action is a selector validated on the responder chain, so the
      toolbar, the menu bar and a shortcut cannot disagree. The hand-drawn
      top gradient and `toolbarBackgroundVisibility(.hidden)` are gone: the
      system draws the edge now, and it is visible.
- [x] **`ScreenplayDocument` (`NSDocument`) and `MainMenu` replace
      `DocumentGroup` and the SwiftUI commands.** Save, Duplicate, Rename,
      Move To, Revert, Versions, Open Recent, tabs and the Edited subtitle
      come from the platform. The launch window is the same `LaunchWindow`,
      in an `NSWindow`.
- [x] *Proof:* `swift test --package-path apple/EDraftMacSurface` — 147, the
      two element-control tests re-pointed at the menu and the toolbar title;
      `xcodebuild` of `eDraft (macOS)` green; the app opened `Sample.fountain`,
      real scroll events put the page under the toolbar, and the chips turned
      light over paper and stayed dark over the dark page.
- [x] **The prototype's launch gallery.** A document-style window — title,
      a toolbar with the plus menu, the grid/list switch and the system search
      field (`DeclaredToolbar`, reusable for any window) — over recents as lit
      sheets in a grid, a list for those who prefer rows, and a per-script menu
      — Rename, Duplicate, Favorite, Move to Trash — wired in the app, where
      `NSDocumentController` can say whether a file is open and hand the
      operation to that document. `LaunchModel.filtered` orders starred first;
      `LaunchModelTests` cover it. *Done 2026-09-08.*
- [x] **The prototype's toolbar.** Back before the title (the library first,
      then the window closes), the element chip, Focus · Zoom in one glass,
      then page · title page · export, then the overflow. Focus folds the
      sidebar and takes the thread and zoom control off the desk.
      *Done 2026-09-08.*
- [x] **A format bar over a selection** — bold, italic, underline, centre, as
      Fountain's own marks, applied through `insertText` so the planner sees
      them as typing. `SelectionFormatBarTests`. The marks are Fountain's
      notation and nothing else, which is why no engine rule was needed; if
      the phone grows the same bar, `FormatMark` moves to the core.
      *Done 2026-09-08.*
- [x] **One window.** A script opens in the library's place — the document
      window takes the library window's frame and the library closes — and
      Back hands the frame back. "Open in New Window" on a card is the one
      explicit exception. *Done 2026-09-08.*
- [x] **The reveal mark was one line low, and faint.** `ScriptLayout.boundingRect`
      answers in view coordinates, inset included; the surface, the find bar
      and the format bar each added the inset again, and the inset is one line
      of glyph headroom. Removed at all four sites; the mark is 36% accent
      now. `RevealMarkPlacementTests` pins it. *Done 2026-09-08.*
- [x] **The page refits when the thread opens or closes**, on the next turn
      so the column has laid out. *Done 2026-09-08.*
- [ ] **Owed.** Hand-QA Versions, Rename and Duplicate on a saved `.draft`,
      iCloud Drive, and the one-window flow with an already-open script.

### M4.5 — Notes and the outline · *2026-09-07/09*

What a Final Draft file carries beside the script, and what the app was doing
with it. Both halves were found the same way: opening the owner's two
production drafts and counting.

- [x] **A Note is a line that does not print.** `Type="Note"` had no entry in
      the FDX map, so every one fell through to General — and General prints.
      Six across the two features, set in Courier among the stage directions.
      Mapped to the `note` the model already had and to Fountain's `[[ ]]`,
      both directions. *Measured:* six in, six read, six through the Fountain
      a `.draft` is stored as, six written back, no-edit resave still
      byte-identical. *Done 2026-09-07,* `c5e015f`.
- [x] **A note is beside the page, not on it.** A mark in the right margin —
      the marks margin, where revision asterisks go — beside a line washed in
      the same yellow, and a card on click: the words, Delete at the head,
      and at the foot either the way through the others or Done. Pages'
      comment minus the half that makes it a conversation; there is no author,
      date or Reply because none of the three formats has anywhere to put one.
      *Done 2026-09-07,* `284be2e`.

      Three things measured rather than reasoned about:
      **SwiftUI's `onDisappear` does not reliably run when an `NSPopover`
      closes** — a note edited and dismissed kept its old text on disk; the
      card reports every keystroke and `popoverDidClose` writes it.
      **An SF Symbol takes its colour from the view that hosts it**, so
      `NSColor.set()` before `NSImage.draw(in:)` is ignored and the mark came
      out black; `NSImageView.contentTintColor` is the mechanism.
      **Stepping to the next note revealed its line unconditionally**, which
      scrolled it to the top and took the caret with it — it now scrolls only
      when the mark is off screen.
- [x] **The outline is a writer's structure, not stage directions.**
      `Outline 1/2/3` and `Summary` had no entries either, so 82 headings and
      57 summaries printed as action — and took the page count with them,
      because a section does not paginate and General does. Mapped to the
      `section` (with its level) and `synopsis` the model already had, which
      is what Fountain's `#`/`##`/`###` and `=` mean, and they now export back
      as themselves; a page break is the only thing FDX has no paragraph for.
      *Measured on the owner's files:* unknown paragraph types 99 → 0 and
      33 → 0, pages 32 → 28 and 28 → 27, resave still byte-identical.
      Final Draft lets a writer rename the levels — the same writer sent both
      `Outline 1` and `Outline 1 (Acts)` — so the number rules and the name in
      brackets is ignored. *Done 2026-09-09,* `ebe81aa`.
- [x] **One seam for everything that is not on the page.** The outline
      mapping immediately broke the page: a section stopped paginating while
      the surface still rendered it, so the text view was four pages taller
      than the count it was drawn against. `ScriptNotes` — written for notes
      alone — became `ScriptAsides`, and the rule became total: **the page is
      the printing elements**, asked of `ScreenplayKind.isPrinting`, which
      asks the engine. An aside carries its whole element, which is what lets
      a section keep its level. *Done 2026-09-09,* `08cffc8`.
- [ ] **Owed: the outline has no home.** It is preserved, exported and off the
      page, and invisible — see HANDOFF §4. A third Navigator tab beside
      Scenes and Cast, not a mode of the page.
- [ ] **Owed: notes on iPhone.** Same shape, same reason.

### M5 — WYSIWYG emphasis · *planned 2026-09-08; Phase 0 + Phase A shipped 2026-09-10/11*

*Status update, 2026-09-11.* The plan below ran as written, under a different
name: the viewport editing model RFC (v2.1, `docs/rfc-viewport-editing-model.md`)
is this milestone's design, adopted after the `.draft` format review flipped
the storage decision to runs-in-model. Phase 0 (runs in both engines, corpus
pinned) is `d076e1f`; Phase A (the Mac surface draws them, the format bar
toggles them, typed markers live-collapse) is `7ffad02`; Centre Line as the
element's type is `4b382c6`. Still owed: the iPhone draws nothing of it (the
model carries runs losslessly — same shape as notes were), the Mac has no
Format menu or keyboard way in, and the RFC's later phases (tags, revision
marks, locks as run properties) are unbuilt. The original plan follows,
unchanged.

The owner's requirement: the page shows bold, italic and underline as type,
never as `**` and `_`; markup exists only where a file is written. Today the
model carries plain text with Fountain's marks inside it, so the surface can
only show the marks. This is an engine feature first, by rule 2, and the order
is fixed:

1. **TypeScript engine** — inline runs on an element (`{start, length,
   styles}`), parsed from and serialised to Fountain's `*`/`**`/`_`; FDX
   carries them as `<Style>`. Fixtures regenerated.
2. **Swift engine** — the same, pinned by the conformance corpus.
3. **Core** — `EditorState` and the planner keep runs through edits (a
   deletion across a run boundary is the hard case; test it first).
4. **Surfaces** — `ScriptLayout` draws runs as font traits and underline;
   `applyMark` toggles a run instead of inserting marks. iOS follows.
5. **Export** — unchanged for Fountain/FDX because the engine writes marks;
   plain text drops them.

Not to be done by hiding marks in the text view: the planner's ranges are the
storage's, and characters that exist but do not draw broke the reveal twice
already (HANDOFF §5).

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

1. **`apple/` layout (M0.6)** — do it now while the tree is churning, or later? *Answered 2026-09-08: done.*
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
| 2026-09-06 | **Reversed: two panes.** The writer never formats, so a properties pane has nothing continuous to hold. | Pages' inspector is open *while you work*. Title, scene length and a rename are transient — a sheet or a Cast destination, not a column that clips the page. The right pane is reserved for comments/notes alongside the page. |
| 2026-09-05 | Modularise before writing Mac code | 2,155 lines are portable but trapped in an app target. |
| 2026-09-05 | No Catalyst, no Electron | Catalyst would ship iOS compromises to a desktop whose whole point is not having them. |
| 2026-09-05 | Packages sit at `apple/EDraftCore` and `apple/EDraftUI` for now | The `apple/` move (M0.6) is still worth doing, but not while three other steps were in flight. |
| 2026-09-05 | Core and UI packages are main-actor-by-default; their **test** targets are not | Matches the app targets exactly, and XCTestCase cannot inherit main-actor isolation. |
| 2026-09-05 | PDF via `CGPDFContext` + hex stamp; print is that PDF | `kCGPDFContextKeywords` writes a PDF string the extractor will not read. `NSPrintOperation` over a view would paginate twice. |
| 2026-09-05 | **Reversed:** `/Keywords` is a PDF literal in the Info dict, not a `%%EOF` stamp | Measured: `(hex)` survives `PDFDocument` rewrite at 500KB. Trailing junk does not survive a re-save. Extractor widened in both engines. |
| 2026-09-05 | Page placement in `EDraftCore.ScreenplayPageLayout`, not two renderers | Two 233-line renderers would be two answers to where a line sits. iOS substitution only. |
| 2026-09-06 | The phone's surface becomes `EDraftUIKitSurface`; its public face is one view | iPadOS forces it — a second app cannot link code inside the first one's target. `ScriptSurfaceView` wraps the representable because publishing `UIViewRepresentable` publishes two dozen delegate methods with it. |
| 2026-09-06 | The touch surface holds the page only; the Mac surface holds its window too | The iPad's chrome will not be the iPhone's. Inventing a shared one before the iPad exists produces a third that fits neither. |
| 2026-09-06 | **Reversed:** the model capitalises ß to SS, as the engine always has | The refusal was a text view's UTF-16 arithmetic wearing a model's clothes, and three tests wrote it down — one saying outright that the model must follow the storage. Once the Mac shouted at the input boundary it cost a divergence: one keystroke, two files. |
| 2026-09-06 | A character's thread is a column between Navigator and page, not a pushed destination | It is something to read *alongside* the page — the test §3 sets for a column — and it costs width only while a character is selected. Notes' shape, not Pages'. |
| 2026-09-08 | The Mac's document window is `NSDocument` + `NSWindowController`, not `DocumentGroup` | Measured, not reasoned: the toolbar's glass adapts to the page only in a window AppKit created with an `NSSplitViewController` as its content — never in a SwiftUI window, whatever the split view, toolbar or style. The complexity the plan deferred was paid for by that one measurement, and Save, Duplicate, Rename, Versions, Open Recent and tabs came with it. |

---

## 4a. Building and running the Mac app

```bash
xcodebuild build -project apple/eDraft.xcodeproj -scheme 'eDraft (macOS)' -configuration Debug
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

Two amendments, 2026-09-06. `CGWindowListCreateImage` is now unavailable on
macOS — ScreenCaptureKit replaces it — so `CGWindowListCopyWindowInfo` still
*enumerates* windows with a sleeping display, and `screencapture -l<id>`
answers "could not create image from window". Enumeration is the whole of what
is left: an eye pass genuinely cannot be done without waking the display, and
waking someone's display to take a screenshot is not a decision to make on
their behalf.

The iOS Simulator is the exception worth knowing, because it renders to its own
framebuffer rather than the Mac's screen. `xcrun simctl io <device> screenshot`
returns real pixels with the display asleep, which makes the phone's surface
inspectable at any hour — and the QA fixtures drivable with it.

## 5a. Enforcement added

- **`npm run check:boundaries`** walks the three package sources and fails on a
  forbidden import: the engine may not reach for a UI framework or for the
  layers above it, the core may not draw, and a shared panel may not name UIKit
  or AppKit. It is plain Node, so it runs on the Linux box that runs CI, and it
  is wired into `npm run quality`. Verified by planting a violation and
  watching it fail.
- **A macOS CI job** now runs `swift test` over the four packages that can be
  built on a Mac host — 284 tests (99 + 88 + 18 + 79). `EDraftUIKitSurface` is
  the fifth package and is not among them: it imports UIKit and cannot compile
  for the desk at all. Its behaviour is covered by the 103 in the iOS app
  target, under the simulator.
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
- **`textDidChange` can mark a revision as rendered when the model did not
  take the edit.** If `applyIncrementalEdit` returns false *and*
  `synchronizeModelFromNativeText` bails, `renderedRevision` is still set to
  `editor.revision`. The storage changed, the model did not, and nothing will
  reconcile them. Identical shape on iOS (`ScriptTextView.swift:559-578`).
  Both-surfaces fix; own box.
- ~~**The page has no left margin.**~~ **Done** — the page is a 612pt card
  with the PDF's 108pt left margin (`testThePageIsACardAtPrintMetrics`).
- ~~**Format → Element is in the Edit menu.**~~ **Done** — `CommandGroup(after:
  .textFormatting)` (`MACOS-DESIGN.md` §3.4). Accept Suggestion stays in Edit.
- ~~**`Scene Numbers` sits in the sidebar.**~~ **Done** — the sidebar is
  destinations (`§1.1`); numbering is Format → Scene Numbers. The phone's
  Navigator sheet still has the row.

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

## 8. Scenes/Cast scope bar — measured, 2026-09-15

Find My's scope bar is the reference for the Scenes/Cast switch in the
Navigator sidebar. Everything here came from the §6 harness on macOS 26.5 /
Xcode 26.6, and every number is chip-minus-groove luminance sampled across
the control in the running app unless it says "probe".

**The reference is two appearances, not one.** Dark: a wafer slightly
lighter than the groove, every label white. Light: an *opaque white*
capsule, every label dark, all the same weight. A design that satisfies one
will not satisfy the other by itself.

**`NSSegmentedControl` cannot be the chip.** Its selected segment is
accent-tinted whenever the window is key — measured blue in all eight
`NSSegmentStyle` values at `.extraLarge` with `borderShape = .capsule`. The
neutral chip it shows in a screenshot is the *inactive* rendering; a probe
window that was never made key is what makes it look like it works.

**`selectedSegmentBezelColor` is not the way round it.** It does give a
neutral chip, but AppKit then picks a contrasting *dark* label where the
reference keeps white. It is also the painted bezel the design rules out.

**An unpainted `NSBezelStyleGlass` button renders the white capsule over an
opaque ground, and nothing on this sidebar.** In light appearance it
measured 0.87 against a 0.87 groove — no separation, no way to tell which
tab was selected. Deepening the groove from 0.08 to 0.26 bought +0.02 and
turned the control into a heavy grey pill. Removing the panel's
`.ultraThinMaterial` backdrop changed 0.87 to 0.87 — it was not the cause.
The button has no tint short of `bezelColor`, so it has no way out.

**`NSGlassEffectView` is the one that works, because it has `tintColor`.**
Tinting the material is not painting over it: the specular rim and the
refraction both survive, which `bezelColor` destroyed. One view covers both
appearances — `.regular` tinted `.white` in light, tinted white 0.16 in
dark:

| appearance | groove | chip | separation |
| --- | --- | --- | --- |
| light | 0.91 | 0.99–1.00 | **+0.08** |
| dark | 0.12 | 0.26 | **+0.14** |

**SwiftUI has no Liquid Glass surface on this toolchain.** The macOS 26.5
SDK's SwiftUI exposes `GlassButtonStyle` and `GlassProminentButtonStyle` and
nothing else — no `.glassEffect()`, no `GlassEffectContainer`, no
`glassEffectID`. Same on the iOS SDK. Any note claiming `.glassEffect`
"smears" predates this check and cannot have compiled.

**The liquid stretch is not reachable here.** In the reference the chip
deforms mid-travel with visible chromatic dispersion.
`NSGlassEffectView` translates rigidly; two chips inside an
`NSGlassEffectContainerView` at `spacing = 80` crossfade rather than bridge;
and the SwiftUI morph API that produces it does not exist in this SDK. The
chip slides as a rigid capsule and that is the current ceiling.

**Geometry.** The bar is 28pt, matching the reference; the chip insets 3pt
and grows by the same 3pt on press so the lift clears the channel. Nothing
in the view or its SwiftUI host may clip — `masksToBounds` stays false and
there is no `.clipped()`, or the lift is cut off.

**Two defects worth not repeating.** Every subview of `MacScopeBar` is
decoration, so `hitTest` must answer `self` for the whole bounds: the glass
container is added larger than the control and will otherwise swallow most
clicks as dead zones. And selection commits on **mouse-up**, not mouse-down
— lifting and sliding from the same `mouseDown` runs two animations on one
view at once, which is what made the first version feel glitchy.

**Still open.** The press-lift has been seen in a probe but never under a
real mouse press in the app; confirming it needs synthetic events in the
owner's session, which §6 forbids while they are at the machine.

