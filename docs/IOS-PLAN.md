# eDraft for iOS — Product & Engineering Plan

**Status:** proposal — awaiting layout sign-off before Phase 0
**Targets:** iOS 26 (shipping baseline), forward-compatible with iOS 27 · iPhone + iPad
**North star:** feels like it was designed by Apple's own team — and writes like eDraft.

---

## 0. TL;DR

We ship a **100% native SwiftUI app** that reuses our existing TypeScript engine
(`@draftfirst/core`) **unchanged**, embedded through **JavaScriptCore**. One source of
truth for prediction, pagination, analysis, import, and export — zero logic ported to
Swift, zero drift between web and iOS. The UI follows the iOS 26 Liquid Glass rules to
the letter: **glass on chrome, matte paper on content** — which is already our design
philosophy on the web.

---

## 1. Research findings

### 1.1 iOS 26 — Liquid Glass (what Apple actually mandates)

- Biggest design-system change since iOS 7. One hard rule from the HIG and every
  serious design guide: **glass belongs only on the navigation/chrome layer** —
  toolbars, tab bars, floating panels, sheets. **Never on content** — no glass over
  text, lists, or media.
- Standard SwiftUI components inherit Liquid Glass for free when built with the
  Xcode 26 SDK. Custom surfaces use:
  - `.glassEffect()` on views, `GlassEffectContainer` for groups,
  - `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`,
  - `glassEffectID` + `@Namespace` for morphing transitions between chrome states.
- `TabView.tabViewStyle(.sidebarAdaptable)` gives a floating glass tab bar on iPhone
  and a real sidebar on iPad from one declaration.
- We must respect **Reduce Transparency** (system swaps glass for solid materials —
  free if we use system materials, broken if we custom-blur).

### 1.2 iOS 27 (WWDC June 2026, releases ~Sept 2026)

- User-adjustable **Liquid Glass transparency slider** system-wide → we use native
  materials everywhere and **never hardcode blur/opacity values**.
- Siri AI (Foundation Models + Gemini) → later opportunity: App Intents
  ("new scene in eDraft", "read my last page") — Phase 3, not v1.
- Adaptive-layout hints in beta (foldable) → size-class-driven layouts from day one.
- Deployment target stays iOS 26; any iOS 27 API behind `@available` checks.

### 1.3 Competition on iOS — the gap is confirmed

| App | Model | Strengths | Weaknesses |
|---|---|---|---|
| **Slugline** ($19.99 once) | Paid, Apple-only | Highest-rated; pure Fountain plain-text; typing-driven formatting; outline navigator; iCloud sync | No visible page breaks; Markdown-ish learning curve; **no prediction engine**; Apple-only; paid |
| **Final Draft Go** | **$1.99/mo / $9.99/yr subscription** | Real .fdx; templates; Grammarly | The exact extraction model we exist to destroy; dated UI; subscription for *typing* |
| **Fade In iPad** | One-time | Full desktop parity; revision colors; pro formats | Dense desktop UI squeezed onto glass; steep for new writers |
| **Highland 2** | Mac-only | Beautiful | No iPhone/iPad app at all |

**The gap:** there is no free, native-feeling, *prediction-driven* screenwriting app
on iOS. Slugline is the design bar; nobody has our ghost-whisper engine. Nobody on
the platform teaches formatting as you type the way we do.

### 1.4 JavaScriptCore — engine strategy confirmed viable

- `import JavaScriptCore` → `JSContext()` → `context.evaluateScript(bundleSource)`,
  then call engine functions directly and marshal results as `JSValue`/JSON.
  React Native proves this pattern at platform scale.
- **Caveats, honestly:**
  1. ObjC-era API with implicitly-unwrapped optionals — wrap it once, properly, in
     a typed `Engine.swift` facade; the rest of the app never sees `JSValue`.
  2. **No JIT in third-party apps** — interpreter only. Irrelevant for us: our
     workloads are keystroke-scale (predict on a line) and worst-case paginate on a
     feature script; we will *prove* this with a Phase 0 benchmark rather than assume.
  3. Our engine dist is **ESM** (`import`/`export`), which `evaluateScript` cannot
     parse → we add one build step to the engine package:

     ```bash
     esbuild src/index.ts --bundle --format=iife \
       --global-name=EDraftEngine --outfile=dist/ios/edraft-engine.js
     ```

     The iOS app ships that single file as a resource; CI checksum-pins it so web and
     iOS can never silently diverge.

---

## 2. Product principles (inviolable)

1. **Glass on chrome, matte on content.** The page is paper, not plastic.
2. **The engine is the app.** Swift renders and collects input; the engine decides
   everything about screenplays. No formatting logic in Swift. Ever.
3. **Touch is not a keyboard.** Tab doesn't exist on glass — the prediction system
   gets a first-class touch expression, not a crippled port (§5).
4. **Your words are yours.** Plain files in iCloud Drive, visible in Files.app,
   openable on the web app, exportable to everything. No lock-in, no account, no
   subscription, no server.
5. **iOS 27-proof by construction.** System materials, size classes, `@available` —
   nothing custom that Apple's next release can break.

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────────┐
│  SwiftUI app (iOS 26 SDK)                                │
│                                                          │
│  LibraryView ─ EditorView ─ ScenesSheet ─ ShareSheet     │
│       │            │             │            │          │
│       └────────────┴──────┬──────┴────────────┘          │
│                           ▼                              │
│                   EngineFacade (Swift)                   │
│              typed API: parse / predict / paginate /     │
│              analyze / import / export                   │
│                           │                              │
│                  JavaScriptCore (JSContext)              │
│                           │                              │
│              edraft-engine.js  ◄── IIFE bundle of        │
│              @draftfirst/core  ── the exact engine       │
│              that ships on the web, 393 tests green      │
└─────────────────────────────────────────────────────────┘
```

**Engine surface the app consumes** (already exported today):
`parse`, `predict` (ghost whispers + context), `paginate` (Courier metrics),
`analyze` (scenes/cast), `import` (.fdx / .docx / .txt / .fountain),
`export` (.draft / .fdx / .docx / .pdf via the layout engine).

**Rejected alternatives:**

- *WKWebView wrapping the web app* — not "Apple's own team", wrong text behavior,
  throws away the reason we're doing this.
- *Porting the engine to Swift* — two codebases, guaranteed drift, every web fix
  needs a twin. JSC gives us one brain.
- *Capacitor/cross-platform shell* — same rejection as WKWebView, with extra
  dependency weight.

**The one real UI spike:** SwiftUI `TextEditor` cannot do inline ghost text,
per-element paragraph styling, or Tab-interception. The editor will be a custom
**`UITextView` wrapped in `UIViewRepresentable`** (fully supported on iOS 26),
with `NSTextStorage` attributes driven by the engine's element model. Phase 0
proves the ghost-whisper rendering inside it.

---

## 4. Information architecture & layout

Five surfaces. Nothing else. The web app's borderless-canvas philosophy carries over:
full-bleed continuous page, hairline page guides, chrome floats above and gets out
of the way.

### 4.1 Library (iPhone)

```
┌─────────────────────────────────────┐
│  eDraft                         ⌄ + │ ← glass nav bar; + = New ▾ (New / Open / Sample)
│ ┌─────────────────────────────────┐ │
│ │  Search                         │ │
│ └─────────────────────────────────┘ │
│  ┌───────────┐  ┌───────────┐       │
│  │  page 1   │  │  page 1   │       │ ← 2-col grid, live thumbnails
│  │  preview  │  │  preview  │       │
│  └───────────┘  └───────────┘       │
│  The Heist      Untitled 2          │
│  42 scenes · ✓  3 scenes · local    │
└─────────────────────────────────────┘
```

SwiftUI `DocumentGroup` + iCloud Drive. Files appear in Files.app. No accounts.

### 4.2 Editor (iPhone) — the heart

```
┌─────────────────────────────────────┐
│   ◂            eDraft            ⋮  │ ← floating glass bar, auto-hides on scroll,
│                                     │   reveals on tap/scroll-up (no timers)
│   INT. SCHOOL HALLWAY - DAY         │
│                                     │
│   Students RUSH past, late slips    │
│   flying. MARA fights the current.  │
│                                     │
│                MARA (CONT'D)▏       │ ← ghost whisper inline, dim;
│                                     │   tap whisper or ↪ to accept
│   ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪    │ ← hairline page guide (pageless)
│                                     │
├─────────────────────────────────────┤
│ [Character ▾]   (CONT'D) ↪    ⠿    │ ← glass accessory bar (§5)
│ ┌─────────────────────────────────┐ │
│ │           keyboard              │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

`⋮` menu (mirrors web): Title Page · Fountain Source · Page Guides · Theme ·
Keyboard Shortcuts · Undo/Redo.

### 4.3 Scenes / Cast (iPhone) — bottom sheet, not a drawer

```
┌─────────────────────────────────────┐
│ ╲                                   │ ← sheet, detents 25% / 50% / 90%,
│  Scenes          Cast               │   glass background, over the page
│  ─────────────────────────────      │
│  1  INT. SCHOOL HALLWAY - DAY   1/8 │
│  2  EXT. PARKING LOT - DUSK     2/8 │
│  3  INT. PRINCIPAL'S OFFICE ... 3/8 │
│  ─────────────────────────────      │
│  MARA ·········· 12 lines  ✎ rename │
│  DAVID ·········  8 lines  ✎        │
└─────────────────────────────────────┘
```

Rename a character here → engine rewrites every cue + suggestion table, exactly
like web. Tap a scene → editor scrolls, sheet drops to 25%.

### 4.4 Export — the share sheet, nothing custom

`⋮ → Export…` → engine renders the file → native `UIActivityViewController`:
**.draft · .fdx · .docx · .pdf · Fountain**. AirDrop to a Mac, save to Files,
send to a producer. We build zero export UI.

### 4.5 iPad — one layout declaration away

```
┌──────────────────────────────────────────────────────────┐
│  eDraft                                               ⋮  │
│ ┌────────────┐  ┌──────────────────────────────────────┐ │
│ │ Scenes     │  │                                      │ │
│ │  1 INT.…   │  │       INT. SCHOOL HALLWAY - DAY      │ │
│ │  2 EXT.…   │  │                                      │ │
│ │  3 INT.…   │  │       Students RUSH past…            │ │
│ │ ────────── │  │                                      │ │
│ │ Cast       │  │                MARA (CONT'D)▏        │ │
│ │  MARA  12  │  │                                      │ │
│ │  DAVID  8  │  │                                      │ │
│ └────────────┘  └──────────────────────────────────────┘ │
│   sidebarAdaptable glass sidebar — collapses to tab bar  │
└──────────────────────────────────────────────────────────┘
```

Same code, `TabView.tabViewStyle(.sidebarAdaptable)`. Hardware keyboard attached →
**the full web choreography works untouched**: Tab cycles elements contextually,
Enter advances, ⌘1–9 jump to any element, `/` opens the element menu.

---

## 5. Interaction design — the ghost without a Tab key

This is the design problem that decides whether we feel native. Our answer:

**The accessory bar is the Tab key.** A single glass row pinned above the keyboard:

```
[  Character ▾  ]        (CONT'D) ↪           ⠿
      ↑                       ↑                ↑
  current element —    the whisper, full-   element picker:
  tap to re-target     size, tap or ↪       the ⌘1–9 grid as
  it (rare)            to accept            a glass popover
```

- **Predictions appear inline as today** (engine unchanged), and the *same* whisper
  is mirrored large on the accessory bar where thumbs live.
- **Accept:** tap the inline whisper, tap the accessory pill, or press Return when
  the line is empty-but-whispered. Three ways, zero modes.
- **Element changes:** contextual cycling is automatic (scene → action → character →
  dialogue/parenthetical → transition), driven by the engine's context logic —
  identical to web. The `⠿` popover is the manual override: Scene Heading, Action,
  Character, Parenthetical, Dialogue, Transition, Shot, General, Centered,
  **Page Break** — with ⌘ shortcuts shown when a keyboard is attached.
- **Parentheticals stay bracketless while typing**; engine wraps on commit — the
  rule we already shipped on web, inherited for free.
- **Undo/redo:** `UndoManager` on the text view + shake-to-undo + `⋮` menu items.

---

## 6. Design system

| Layer | Rule |
|---|---|
| **Content** | Matte paper (light: warm white / dark: true-black-adjacent), never glass, never translucency. Courier Prime (OFL, bundled) at fixed 12 pt for the page — metrics are sacred. |
| **Chrome** | System materials only: `.glassEffect()`, `.toolbar`, sheets, `sidebarAdaptable`. No custom blurs, no hardcoded opacity — survives the iOS 27 transparency slider. |
| **Typography (UI)** | SF Pro, Dynamic Type on all chrome. Page text is exempt (screenplay metrics are a professional contract, not a preference). |
| **Color** | Semantic system colors. Accent: single eDraft ink-blue, used for whispers and selection only. |
| **Motion** | `glassEffectID` morphing for chrome state changes; whisper fade ≤ 150 ms; **zero** ambient/gimmick effects — we killed the glow on web for a reason. |
| **Accessibility** | VoiceOver announces whispers as suggestions, never traps focus; Reduce Transparency → solid materials (free via system materials); full keyboard navigation on iPad; contrast ≥ 4.5:1 on whisper text. |
| **Auto-hide chrome** | Scroll-driven only (hide on scroll down, show on scroll up / tap). **No idle timers** — the web bug we fixed stays fixed. |

---

## 7. Documents & data

- **`.draft` is native** — registered UTType (exported UTI), owned by the app.
  Same JSON the web app writes; a screenplay round-trips web ↔ iOS byte-identical.
- **Storage:** `DocumentGroup` + iCloud Drive; local-only documents supported;
  files visible and movable in Files.app.
- **Import:** .fdx, .docx, .txt, .fountain — engine importers, zero Swift parsing.
- **Export:** .draft, .fdx, .docx, .pdf, .fountain — engine renderers + share sheet.
- **Conflicts:** iCloud last-writer-wins at the file level; because `.draft` is
  JSON with stable line IDs, a later merge pass is possible (post-v1).

---

## 8. Phased roadmap

**Phase 0 — foundation spike (COMPLETE, 2026-08-12)**
- [x] Verify toolchain: **Xcode 26.6, iOS 26.5 SDK + simulator runtime, Swift 6.3.3**
      (developer dir override: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).
- [x] Engine bundle step: `npm run ios:engine` — tsc → esbuild IIFE (25 KB) →
      `ios/eDraft/Resources/edraft-engine.js`, sha256-pinned in `ENGINE-CHECKSUM.txt`,
      **auto-verified in the real JavaScriptCore CLI on every build** (12-check smoke).
- [x] Xcode project: iOS 26 target, SwiftUI, `EngineFacade` over JSC
      (classic pbxproj; all engine calls serialized on one queue).
- [x] Proof screen: parse → predict → ghost → paginate round-trip on every
      keystroke — screenshot-verified on iPhone 17 simulator.
- [x] **Spike A:** ghost whisper lives inside `UITextView` (`ScriptTextView`) —
      caret can never enter the ghost; typing strips it; accept commits it.
- [x] **Spike B:** interpreter-mode (`--useJIT=false`, honest iOS conditions),
      195-page / 4,713-element document: parse 61 ms, full paginate 61 ms,
      ~4.8 ms per end-of-document prediction. **Verdict:** no-JIT is a non-issue
      for typing; pagination runs on a background queue, exactly as planned.

**Phase 1 — the writer (IN PROGRESS, started 2026-08-12)**
Editor core: custom text view, element styling, choreography, whispers + accessory
bar, undo/redo, autosave, Library with iCloud, new/open/sample, dark mode.

Done so far: styled screenplay surface (Courier Prime, engine GEOMETRY),
swipe-right / tap-to-accept whispers + WhisperBar, cue-in-progress prediction
and styling, line-accurate BlockMapper, autosave, theme, rename, diagnostics.
Next: undo/redo, empty-line next-element whispers, Library with iCloud.

**Phase 2 — the professional**
Import all four formats, export all five, Scenes/Cast sheets, character rename,
title page, page guides toggle, themes, VoiceOver pass, iPad sidebar + hardware-keyboard
choreography parity.

**Phase 3 — the platform**
App Store submission (free, no IAP, no account — the whole point). Then iOS 27:
App Intents for Siri AI ("new scene", "read last page"), transparency-slider
validation on beta hardware, foldable/adaptive layout check.

---

## 9. Risks & open questions

| # | Risk / question | Mitigation |
|---|---|---|
| 1 | **Xcode presence on this machine unverified** — everything is blocked until it is | First command of Phase 0; if absent, we install before any other work |
| 2 | ESM engine can't run in JSC | IIFE bundle step (§1.4) + a Swift-side smoke test that fails CI if the bundle and package versions diverge |
| 3 | No-JIT performance | Phase 0 benchmark; paginate on background queue if needed |
| 4 | `UITextView` ghost rendering proves fragile | Phase 0 Spike A, before any other editor work; fallback is attributed-attachment rendering (heavier but proven) |
| 5 | iOS 27 beta APIs beyond the keynote are unknown | iOS 26 deployment target; every 27-only API behind `@available`; nothing in v1 depends on 27 |
| 6 | iCloud file conflicts corrupt a script | `.draft` JSON is append-friendly; v1 ships conflict-copy UI (both versions kept, user picks) — never silent loss, that is the one unforgivable sin in this product |

---

## 10. What v1 will NOT do (written down so nobody relitigates it)

- No AI writing features (the user's call — the engine is the intelligence for now).
- No collaboration/realtime (that's what the production layer is for — later, and
  it's the moat, not a v1 checkbox).
- No Android (engine is ready when we are; the team is not).
- No subscription, no account, no analytics SDK. **Free means free.**
