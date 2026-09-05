# iOS Completeness Assessment

**Date:** 2026-08-24
**Scope:** Full audit of the iOS app (`ios/eDraft/`, `ios/eDraftEngine/`) against one question: *what stands between today's build and a truly complete professional screenwriting app for iPhone and iPad?*
**Method:** line-level review of the app surface, engine modules, document types, keyboard handling, and test coverage. Every claim below was verified in code, not assumed.

---

## 1. What is already strong (verified)

These are done and tested. They are the foundation, not the gap list.

**Writing core**
- Element choreography with context-aware Tab / Shift+Tab cycles (closed cycle after Action: `{action, character, transition}`), parenthetical auto-wrap/unwrap on conversion, intelligent casing memory (user casing preserved; caps applied only where the craft requires).
- Ghost prediction engine (SmartType) ported from the TS engine and conformance-tested against it.
- Caret, scroll stability, QuickType, haptics — hardened through the QA-fixture program (`-qa-action-lowercase`, `-qa-character-uppercase`, `-qa-quicktype-scene`, `-qa-scroll-stability`).

**Production-grade pagination**
- Dialogue splits across pages with `(MORE)` / `NAME (CONT'D)` — the detail most free tools get wrong (Paginate.swift).
- US Letter / A4, print via `UIPrintPageRenderer`.

**Documents & export**
- Native `.draft` document type with iCloud sync-merge; open-in-place for Fountain/TXT.
- Export: `.draft`, PDF (paginated, title-page optional), Fountain, RTF, TXT.

**App surface**
- Story panel (Scenes + Cast + stats), Settings, Title Page sheet, find-in-document (`isFindInteractionEnabled`), spellcheck/autocorrect, Dynamic Type, light/dark, app icon.
- Multi-window enabled in Info.plist (`UIApplicationSupportsMultipleScenes`).

**Test coverage (current counts)**
- 53 app XCTest cases, 9 engine conformance suites (+ shared fixture store), 400 TS package tests, 19 web app tests, 4 device QA fixtures.

This is already past every free competitor's *writing* experience. The gaps below are about the *professional* promise: migrate in, deliver out, never lose work.

---

## 2. Tier 1 — Professional blockers

Things a working writer hits in week one. Ordered by severity.

### 2.1 FDX interchange — the trust feature
- **State:** The TS engine has conformance-tested `fdx.ts` (read + write). The Swift engine has **no FDX module** (sources: Choreography, Normalize, CRC32, FountainDetect, Parse, Serialise, JSWhitespace, TitleCredits, Types, Paginate, Predict, SmartType). iOS document types are `.edraftScreenplay` + `.plainText` only.
- **Why it blocks:** Professionals' existing work is `.fdx`; delivery to production is `.fdx`. If a real script imports wrong once, nothing else matters. This is also the moat-crossing feature: Final Draft's lock-in is a file format, not a toolbar.
- **Work:** Port `fdx.ts` → `EDraftEngine/Fdx/` (reader first, writer second), regenerate conformance fixtures via `npm run engine:conformance`, register an FDX UTType, add import (open-in-place) and export (share sheet).

### 2.2 Scene numbers — stored, never rendered
- **State:** `sceneNumber` exists in `Model/Types.swift` and round-trips through Fountain Parse/Serialise losslessly. **Paginate.swift contains zero `sceneNumber` references** — numbers are never laid out, and there is no UI to assign/lock/renumber them.
- **Why it blocks:** Numbered scenes are how every department references the script. A "professional" app that can't show scene numbers is a drafting tool, not a production tool.
- **Work:** render numbers in the paginator (left margin, industry position), auto-number on demand, renumber command, toggle in Script options. Locking belongs with 2.3.

### 2.3 Revision colors, locked pages, OMITTED — the actual moat
- **State:** nothing. No revision sets, no colored pages, no page/scene locking, no OMITTED handling.
- **Why it matters:** This is why Final Draft survives mediocrity — revision colors keep page 45 meaning page 45 for every department across a shoot. No free competitor ships it. Shipping it free *is* the disruption.
- **Work (milestone-sized):** revision sets (color per set, mark revised lines with `*` in the margin), page lock (freeze pagination, A-pages), scene lock + OMITTED (retain number, blank body), PDF/FDX must carry revision marks.

---

## 3. Tier 2 — iPad as a first-class citizen

The stated bar is "iPhone **and** iPad." Today the app runs on iPad; it is not yet *native* to it.

### 3.1 Hardware-keyboard parity + discoverability
- **State:** `keyCommands` (ScriptTextView.swift:1745) = Tab, ⇧Tab, ⌘→ only, and **none pass `title:`** — so iPad's hold-⌘ overlay shows nothing. The web app already has ⌘1–9 element shortcuts; iOS does not.
- **Work:** add `title:` to every command (free discoverability), add ⌘1–9 matching web, ⌘⇧S/E export affordances. Small, high-value.

### 3.2 Layout, pointer, Pencil
- **State:** panels are sheets on all idioms; only share/print popovers are idiom-aware (EditorChrome.swift). Pointer hover and Scribble are unverified (Scribble should be free via UITextView — must be QA'd, not assumed).
- **Work:** sidebar/column layout on regular width (Scenes/Cast as a trailing sidebar, Settings as a form column), hover states, Scribble verification fixture.

### 3.3 Multi-window QA
- **State:** enabled in the plist, never exercised. Two windows editing one iCloud document is exactly where sync-merge bugs live.
- **Work:** a QA pass: two scenes, same document, concurrent edits; verify merge, no duplication, no lost undo stacks.

---

## 4. Tier 3 — Workflow trust

- **4.1 Dual dialogue UI** — `dual` is modeled and round-trips losslessly (ScreenplayModels.swift:110), but nothing in the UI can set or render it side-by-side. Add "Dual Dialogue" to the element menu when a character block is selected; paginator lays out two columns.
- **4.2 Document duplicate** — the browser lacks Duplicate; writers fork drafts constantly ("Draft 3 — notes pass"). One UIDocumentBrowser action.
- **4.3 Outline / structural view** — the engine already carries section/synopsis/note structural types (Fountain Parse). Expose a Beats/Outline tab in the Story panel; zero new model risk.

---

## 5. Tier 4 — Polish

- **5.1 Focus / typewriter mode** — Highland's signature; dim all but the current element, keep the caret centered. Cheap on top of existing layout.
- **5.2 Localization** — screenplay format is English-centric, but UI strings should be catalogued now while the surface is small.
- **5.3 First-run onboarding** — one interactive scene teaching Tab, swipe, ghost-accept. The three promises start here.

---

## 6. Recommended order

| Milestone | Content | Why first |
|---|---|---|
| **M-A** | FDX import + export (engine port + conformance) | The trust feature; unblocks every professional migration story and the macOS app later |
| **M-B** | iPad parity: ⌘1–9 + titles, sidebar layout, Scribble/pointer/multi-window QA | Cheap, visible, required by the stated bar |
| **M-C** | Scene numbers (render, assign, renumber) | Professional credibility; prerequisite for revisions |
| **M-D** | Revision colors + locked pages/scenes + OMITTED | The moat-crossing milestone |
| **M-E** | Dual dialogue UI, duplicate, outline, focus mode | Workflow completeness |

**Recommendation: start M-A (FDX).** It is the only gap where the proof asset already exists (the conformance-tested TS implementation), it is pure engine work with an established port playbook, and it converts "free and lovely" into "safe to bet a production on."

---

## 7. Non-goals confirmed for this phase

No model-backed AI, no collaboration/server, no pricing surface — prediction is
SmartType over the document's own vocabulary, on-device and deterministic
(`packages/edraft/src/predict.ts`, `smarttype.ts`; [VISION.md](VISION.md)).
Voice drafting is deferred to a later release by owner decision.
