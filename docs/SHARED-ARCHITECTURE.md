# eDraft — Shared architecture

*Status: **partly built** — `EDraftCore` and `EDraftUI` exist and compile for macOS; see [MACOS-EXECUTION.md §0](MACOS-EXECUTION.md) for exactly how far. Companion to [MACOS-DESIGN.md](MACOS-DESIGN.md) (what the Mac app is) and [MACOS-EXECUTION.md](MACOS-EXECUTION.md) (the order of work).*

The macOS app must not be a second codebase that happens to open the same file.
This document defines the boundary that makes iOS and macOS **one product with
two surfaces**, and the migration that gets us there without a rewrite.

---

## 1. Where the code actually is today

Measured, not estimated — every Swift file in the iOS app target, by what it
imports (`ios/eDraft`, 8,141 lines):

| File | Lines | Imports | Verdict |
|---|---:|---|---|
| `Editing/EditorState.swift` | 1,124 | Foundation · Observation · EDraftEngine | **Portable, unchanged** |
| `Editing/ScreenplayEditPlanner.swift` | 438 | Foundation · EDraftEngine | **Portable, unchanged** |
| `Models/ScreenplayModels.swift` | 386 | Foundation · os · EDraftEngine | **Portable, unchanged** |
| `Editing/SceneHeadingSeparator.swift` | 87 | Foundation | **Portable, unchanged** |
| `Editing/ElementCaseMemory.swift` | 64 | Foundation | **Portable, unchanged** |
| `Document/DocumentArrival.swift` | 56 | Foundation | **Portable, unchanged** |
| `Views/StoryPanel.swift` | 360 | SwiftUI | Portable · one iOS-only modifier |
| `Views/TitlePageSheet.swift` | 357 | SwiftUI · EDraftEngine | Portable · iOS-only modifiers |
| `Views/CharacterThreadView.swift` | 212 | SwiftUI | Portable, unchanged |
| `Views/SettingsPanel.swift` | 156 | SwiftUI | Portable · one iOS-only modifier |
| `Views/ScanReaderView.swift` | 102 | SwiftUI · PDFKit | Portable (PDFKit is on macOS) |
| `Editing/ScriptTextView.swift` | 2,335 | SwiftUI · UIKit · EDraftEngine | **Per-platform** |
| `Views/EditorChrome.swift` | 669 | SwiftUI · UIKit · EDraftEngine | **Per-platform** |
| `Document/EDraftDocument.swift` | 434 | SwiftUI · UIKit · UTType · EDraftEngine | Split: model portable, thumbnail iOS |
| `Views/EditorView.swift` | 271 | SwiftUI · UIKit | **Per-platform** |
| `App/EDraftApp.swift` | 227 | SwiftUI · UIKit | **Per-platform** |
| `Document/ScanCreation.swift` | 222 | Vision · VisionKit · … | iOS-only (no VisionKit scanner on Mac) |
| `Views/ScreenplayLaunchActions.swift` | 174 | SwiftUI · UIKit · VisionKit | iOS-only |
| `Document/ScreenplayImport.swift` | 189 | PDFKit · CoreGraphics · EDraftEngine | Portable with small edits |
| `Views/ElementModeControl.swift` | 151 | UIKit | **Per-platform** |
| `Editing/RevealHighlight.swift` | 72 | UIKit | Per-platform view, shared *rule* |
| `Document/ScanDocument.swift` | 55 | PDFKit · SwiftUI · UTType | iOS-only today |

**The finding:** 2,155 lines were already platform-agnostic, and 1,087 more were
plain SwiftUI. They were portable in principle and unusable in practice, because
they lived inside an iOS **app target** — a macOS target cannot link them. The
single most valuable pre-macOS act was not writing Mac code; it was moving that
code across a package boundary where both platforms can reach it.

**Done, 2026-09-05.** `EDraftCore` holds the six Foundation-only files;
`EDraftUI` holds the four SwiftUI panels and the platform shims they needed.
Both compile for iOS and macOS. 35 of the app's tests now run on the Mac. What
remains of this table is the document split (M0.3) and the surfaces themselves,
which are per-platform by definition.

---

## 2. The boundary

```
┌─────────────────────────────────────────────────────────────┐
│ EDraftEngine        rules of the craft. Foundation only.    │
│                     Parse · paginate · predict · choreo ·   │
│                     normalise · number · revise · export.   │
│                     Pinned byte-for-byte to the TypeScript  │
│                     engine by the conformance corpus.       │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│ EDraftCore          the app's mind. Foundation +            │
│                     Observation. No UI framework, ever.     │
│                     EditorState · models · edit planner ·   │
│                     case memory · separator · document      │
│                     model · arrival.                        │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│ EDraftUI            shared SwiftUI. Navigator · character   │
│                     thread · title page · settings.         │
│                     Chrome differences behind small         │
│                     platform shims, never forked views.     │
└─────────────────────────────────────────────────────────────┘
              ▲                                   ▲
┌──────────────────────────┐      ┌──────────────────────────┐
│ eDraft (iOS)             │      │ eDraft (macOS)           │
│ UITextView surface ·     │      │ NSTextView surface ·     │
│ nav-bar chrome · scan ·  │      │ menu bar · inspector ·   │
│ keyboard bar             │      │ windows · pointer        │
└──────────────────────────┘      └──────────────────────────┘
```

**Rules that keep the boundary honest**

1. `EDraftCore` may not import SwiftUI, UIKit or AppKit. Enforced by a build
   check (§5), not by discipline. CoreGraphics is the one allowance, for paper
   geometry — `CGRect` is a measurement, not a view.
2. Anything that decides *screenplay behaviour* belongs in `EDraftEngine` and is
   pinned by the corpus. A view may never re-decide a rule — the empty-line
   escape that briefly lived in `ScriptTextView` and now lives in
   `Choreography.emptyLineEscape` is the template.
3. A per-platform surface owns only what the platform genuinely differs in:
   text system, chrome, input. Where behaviour is shared but the view is not
   (the reveal mark), the *rule* moves to `EDraftCore` and each platform draws
   it.
4. One document format. No macOS-only fields, ever.

---

## 3. Directory layout

The `ios/` folder becomes wrong the moment there is a Mac app. Proposed:

```
apple/
  EDraftEngine/           Swift package (moved verbatim)
  EDraftCore/             Swift package (new — §1's portable rows)
  EDraftUI/               Swift package (new — the SwiftUI panels)
  iOS/                    iOS app sources + Info.plist + assets
  macOS/                  macOS app sources + Info.plist + assets
  eDraft.xcodeproj        one project · targets: eDraft-iOS, eDraft-macOS,
                          EDraftCoreTests, EDraftUITests, app UI tests
```

One project, two app targets, three packages. Optional but recommended at M0,
while the tree is already moving; deferring it costs a second churn later.

---

## 4. Migration — moves, not rewrites

Each step ends green. No step mixes a move with a behaviour change.

| Step | Action | Proof it worked |
|---|---|---|
| M0.1 ✅ | Create `EDraftCore`; move the six Foundation-only files verbatim | iOS builds; tests pass (`b96012c`) |
| M0.2 ✅ | Move the app tests that only exercise core into `EDraftCoreTests` | Same count, now running on **both** platforms via `swift test` (`0e8485e`) |
| M0.3 | Split `EDraftDocument`: model + serialisation into core, drawing stays per-platform | Document tests pass — member-by-member plan in the execution doc |
| M0.4 ✅ | Create `EDraftUI`; move the four SwiftUI panels; shim the iOS-only modifiers | Both packages build for macOS (`57534d0`); screenshot check owed |
| M0.5 | Lift the reveal *rule* (which element, which range, when to mark) into core; leave `RevealHighlightView` per-platform | `NavigatorJumpTests` pass unchanged |
| M0.6 | Optional: move to the `apple/` layout | Everything builds from a clean checkout |

Nothing in M0 changes what the app does. If a screenshot differs, the step is
wrong.

---

## 5. Invariants and how they are enforced

| Invariant | Enforcement |
|---|---|
| Engine parity with TypeScript | `npm run engine:conformance` regenerates `Fixtures/`; 86 Swift tests replay it |
| Core imports no UI framework | CI grep: `grep -rl "import \(UIKit\|AppKit\|SwiftUI\)" Sources/EDraftCore` must be empty |
| Both apps behave alike | `EDraftCoreTests` run on iOS **and** macOS in CI; a platform-specific failure is a bug in the boundary |
| Rules are not re-decided in views | Code review checklist; new `Choreography`/`SmartType` calls only |
| One document format | `EDraftDocumentTests` round-trip on both platforms |

Today's baseline, for comparison after every step: **406** TypeScript · **89**
engine · **35** core (macOS) · **89** app tests green.

**A name worth fixing.** The boundary immediately exposed that `Screenplay`
names two different types — the engine's and the app's — and that nine call
sites had been resolving it by luck of import order. They now say
`EDraftCore.Screenplay` explicitly. That is a label, not a repair; renaming one
of the two is a small focused pass worth doing before the Mac app doubles the
number of call sites.

---

## 6. What the Mac adds that has no iOS counterpart

These are the only places where new architecture — not new views — is needed.

- **The AppKit text surface.** `ScriptTextViewMac` mirrors the iOS coordinator:
  same `ScreenplayEditPlanner`, same range map, same ghost overlay, same reveal.
  Note the iOS surface deliberately uses **TextKit 1**
  (`usingTextLayoutManager: false`) because its scroll and reveal maths read
  `NSLayoutManager` rectangles directly. The Mac port must either use TextKit 1
  for exact parity or re-derive those rectangles through `NSTextLayoutManager` —
  this is the one real unknown and is spiked first (see the execution plan).
- **Menus and key equivalents.** SwiftUI `Commands`, one command per verb the
  app already has; no new behaviour, only new access.
- **The inspector.** A right-hand pane whose content is a function of the
  selection — the same data the iOS sheets already show, in a persistent pane.
- **Windows.** Multiple windows and tabs per document, state restoration.

## 7. What stays iOS-only, on purpose

Document scanning (VisionKit has no Mac scanner UI of this kind), the keyboard
accessory bar, and touch gesture choreography. The Mac equivalent of scanning is
**Import** — already portable — plus Continuity Camera later.
