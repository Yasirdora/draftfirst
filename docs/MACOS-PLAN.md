# eDraft on macOS — Plan

*Status: planning · Owner: Ysr · Engine readiness: EDraftEngine already declares `.macOS(.v26)`; `EditorState` and `ElementCaseMemory` are platform-agnostic (Foundation + Observation only).*

---

## 1. The market gap — why macOS, why now

The Mac is where professional screenwriting lives, and nobody occupies the
triangle **free + native + production-grade**:

| App | Price | Native Mac design | Production layer | Continuity |
|---|---|---|---|---|
| Final Draft | $199.99 + $79.99/upgrade | No — Windows carbon copy, PE extraction | Yes (the moat) | Separate iOS app, sync complaints |
| Fade In | $79.95 | Utilitarian | Yes | Weak |
| Highland 2/Pro | Subscription | Yes — the design benchmark | No | Companion-grade iOS |
| Slugline | $39.99 | Yes, minimal | No | Weak |
| Arc Studio | Subscription | Web tech | Partial | Cloud-locked |
| Movie Magic | $99+ | Abandoned feel | Yes | No |

Highland proved Mac writers pay a premium for Apple-like design — and then
stopped at the writing surface. Final Draft proved the production layer is a
moat — and then priced it for extraction. **The open position: Highland's
taste, Final Draft's machinery, eDraft's price (free), and continuity no one
has.**

The fourth gap is architectural: every incumbent treats the screenplay as a
word-processing document and bolts structure on. Ours is born as data — the
engine already knows scenes, cues, and locations — so navigator, stats, and
later breakdowns are consequences, not features.

## 2. Our unfair advantages

1. **The engine is already macOS-ready.** `EDraftEngine` declares
   `.macOS(.v26)`; the conformance corpus runs on macOS via `swift test`
   today. Parsing, pagination, prediction, choreography, normalization —
   51 pinned test suites before a single UI line exists.
2. **The app logic is platform-agnostic.** `EditorState` (undo, casing
   memory, predictions, stats), `ElementCaseMemory`, and the models import
   only Foundation/Observation. They compile for macOS unchanged.
3. **The document is already iCloud-native.** The iOS app opens `.draft`
   from iCloud Drive; the Mac app turns one document into a platform —
   start a scene on the phone, finish it at the desk. No competitor does
   this credibly.
4. **The hardest iOS problems don't exist on macOS.** No software keyboard,
   no keyboard avoidance, no touch scroll pinning — the scroll-stability
   war is simply not fought on the desktop.

## 3. Product design — the "Apple's own team" test

**Launch.** A document browser, like Pages: recents, iCloud Drive, New
Document. No onboarding, no account, no upsell.

**The window.** The page centered on a neutral canvas (Pages/Freeform
idiom), comfortable measure, generous margins. A sidebar — Scenes ·
Characters — hidden by default, toggled with the system's sidebar button;
it exists for navigation, never for clutter. macOS 26 materials, semantic
colors, full dark mode, accent-color respect.

**The toolbar.** Almost empty: the element control, view options, share.
Everything else lives where Mac pros actually look — **the menu bar**:
Format → Element with ⌘1–⌘9, Edit → Writing Assistance, File → Export,
standard Window/Help. Keyboard-first throughout: Tab/⇧Tab choreography
(engine-exact), the `/` summon menu, full keyboard access in every panel.

**Prediction.** The same ghost engine, rendered as inline gray text —
the Xcode/Swift-completion idiom every Mac user already knows. Tab or →
accepts, Esc dismisses, typing ignores.

**Continuity.** The same `.draft` document on iCloud Drive; edit on iPhone,
open on Mac, undo history and casing memory are per-session by design so
no merge semantics are needed. Handoff as polish, not promise.

**Accessibility.** VoiceOver with element rotor announcements, full
keyboard navigation, text-size preference, reduce-motion respect. Ship it
in M1, not as a retrofit.

## 4. Architecture

```
EDraftEngine (Swift package — unchanged, already macOS 26)
        ▲
        │ shared as-is
eDraft app logic: EditorState · ElementCaseMemory · models ·
ScreenplayExporter · document store (Foundation-only)
        ▲
        │ per-platform surface
iOS: ScriptTextView (UITextView)      macOS: ScriptTextViewMac (NSTextView)
```

- **Editor:** `NSTextView` (TextKit 2) inside `NSViewRepresentable`,
  mirroring the iOS `ScriptTextView` Coordinator: same edit planner, same
  range map, same ghost overlay. The port is mechanical; the behavioral
  differences are all deletions (no keyboard traits, no avoidance) plus
  mouse affordances (hover, cursor rects, context menu).
- **Document:** SwiftUI `DocumentGroup` first — it shares the document
  model with iOS and gives New/Open/iCloud panels. Evaluate an
  `NSDocument` bridge only if Browse All Versions or window tabs become
  demands; do not pay that complexity up front.
- **Menus/toolbar:** SwiftUI `Commands` API (`CommandGroup`, `MenuBarExtra`
  not needed) so element conversion, export, and settings are menu-native
  from day one.
- **No Electron, no Catalyst.** Catalyst would ship the iOS compromises to
  the desktop; the point of this app is that the desktop has none.

## 5. Milestones

**M1 — The page on the Mac.** macOS target; document open/save through
DocumentGroup; NSTextView editor with element layout, Tab choreography,
casing + parenthetical conversion (shared code), ghost prediction;
native menus (⌘1–9); export PDF · FDX · Fountain · TXT. Narrow and
excellent — the writing surface alone must beat Highland's.

**M2 — The writer's desk.** Sidebar navigator (scenes, characters); title
page editor; native print; find (⌘F, system find bar); stats in the
status area; writing-assistance settings.

**M3 — The production layer.** Revision colors, locked pages, scene
numbers — the moat, free. Table read with AVSpeechSynthesizer casting
(each character a voice).

**M4 — The platform.** Handoff, Shortcuts actions, Spotlight indexing,
share extensions, Services menu.

## 6. Risks, honestly

- **The NSTextView port is the only real unknown.** Spike it first: one
  day to prove element styling + ghost overlay + planner on TextKit 2
  before committing the milestone.
- **Scope discipline.** M1 must not touch the production layer; a
  half-built revision system is worse than none.
- **Menu-bar conventions are a contract.** Mac pros measure us against
  Pages' keyboard behavior exactly; deviations read as amateur, not
  innovative.
