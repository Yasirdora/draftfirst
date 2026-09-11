# RFC: Emphasis layout model for eDraft (bold / italic / underline)

> **⚠ SUPERSEDED 2026-09-10 by `rfc-viewport-editing-model.md` (v2).** Decision D1 flipped to runs-in-model after the `.draft` format review; the concealment mechanism (D3) and dual-space caret rules (§4) are withdrawn. This file is kept for the audit trail — §3's consumer list remains the Phase 0 checklist and §6's Beat analysis stands.

**Status:** Superseded · **Date:** 2026-09-10 · **Author:** Kimi
**Depends on:** the peer review in `bold-italic-underline-review.md` (claims verdicts, Beat architecture, landscape survey)

---

## 0. Decisions requested

| # | Question | Recommendation |
|---|---|---|
| D1 | Markers in the model text, or parsed out at the boundary? | **In the model** (Beat's storage choice), with the stripped representation sealed behind the engine boundary |
| D2 | Editing experience: markers visible (Beat/Slugline), reveal-on-active-line (Obsidian/Beat opt-in), or never visible (Pages)? | **Never visible — Pages-style — as the ship target**, built through a dimmed-markers milestone, with Beat-style reveal as the documented fallback |
| D3 | Concealment mechanism | TextKit 1 glyph-nulling (`NSGlyphPropertyNull`) in our `NSLayoutManager` subclass — Beat's shipping mechanism; TextKit 2 explicitly out of scope |
| D4 | Where the length rule lives | In the TypeScript engine source of truth; fixtures regenerated; Swift mirrors; CI freshness gate already exists |

---

## 1. Model

The document text stays raw Fountain, markers included — the file on disk, the string in memory, and the string the parser sees are identical. Beat proves this model round-trips perfectly by construction and paginates correctly, because correctness comes from *what downstream consumers are fed*, not from where markers live.

The engine gains one new derived value per element, computed at parse time:

```
LayoutLine {
    content: String            // text with all emphasis markers removed
    styles:  [StyleRange]      // (ContentIndex range, {bold, italic, underline})
    map:     RawContentMap     // bidirectional RawIndex ↔ ContentIndex
}
```

**The engine's public interface changes:** pagination, statistics, export, and prediction consume `LayoutLine`, never raw element text. Raw text crosses the boundary only for serialisation (which is marker-faithful by definition) and for the editor surface (which needs both spaces — see §4).

This is the one place we improve on Beat rather than copy it: Beat enforces "use the stripped string" by convention, and its code shows the cost — guardrail comments, a self-described convoluted re-parse, a save-time desync fallback. We make it a module boundary with fixtures. Convention becomes type system.

### 1.1 RawIndex / ContentIndex as distinct types

Swift:

```swift
public struct RawIndex: Comparable, Sendable { public let value: Int }
public struct ContentIndex: Comparable, Sendable { public let value: Int }
```

TypeScript:

```ts
export type RawIndex     = number & { readonly __brand: 'raw' };
export type ContentIndex = number & { readonly __brand: 'content' };
```

The *only* conversions are `RawContentMap.contentIndex(for: RawIndex)` and `.rawIndex(for: ContentIndex)`. Every existing API that touches element text is re-typed to take one of the two — the compiler then enumerates the consumer audit for us (§3). Marker runs have **no** valid ContentIndex interior: mapping a raw index inside a marker run returns the run's boundary (rule: closer edge; tie → trailing edge), which is also the hit-testing rule (§4.2).

### 1.2 Emphasis parsing rules (engine, per line)

Per the Fountain spec, and pinned by fixtures:

- `*i*`, `**b**`, `***bi***`, `_u_`; combinations nest.
- Backslash escapes (`\*`) produce literal content characters — an escaped marker is content, never a style boundary.
- Emphasis never carries across a line break; an unclosed opener is literal text.
- Whitespace-flanking rules follow the spec's examples (`*69 and then *23` does not italicize).
- Empty pairs collapse: `****` after an edit is normalised away (see §4.4).

## 2. Conformance plan

New and regenerated fixtures, exported by `scripts/engine-conformance-export.mjs`, freshness already CI-gated:

- `emphasis.json` — **new**: marker detection, escapes, nesting, unclosed openers, flanking rules, per element type.
- `paginate.json` — **regenerated**: wrap operates on `content`; a fixture line with markers asserts identical page geometry to its marker-free twin.
- `serialise.json` — round-trip including escaped markers.
- `fdx.json` — styled runs emitted as `<Text Style="…">`.
- Swift-side pure unit tests for `RawContentMap` (no window required — the lesson from the zoom drift work: logic in Core as pure functions, the display link is just a clock).

## 3. Consumer audit (grep-verified baseline, 2026-09-10)

Every module referencing element text, classified by what markers would do to it. "Content" = must consume `LayoutLine.content` / ContentIndex. "Raw" = correctly sees raw text; no change. "Semantics" = text comparison/matching that markers would pollute — must compare content.

| Consumer | `.text` refs | Class | Required change |
|---|---:|---|---|
| `paginate.ts` + Swift `Paginate.swift` (`wrapLines`, call sites L287/289/307/321) | 6 | **Length-critical** | Wrap on `content`; emit `LayoutLine` |
| `pdf.ts` (L256 centres via `text.length`) + `pageline.ts` | 4 | **Length-critical** | Content length; styled-run drawing |
| `choreography.ts` | — | Indirect | Inherits paginate's output; verify only |
| `continuity.ts` | 7 | **Semantics** | Compare content (`*word*` ≡ `word`) |
| `classify.ts` | 5 | **Semantics** | Classify on content (a `**MARA**` cue is still a cue) |
| `validation.ts` | 5 | **Semantics** | Lint content |
| `structural.ts` | 6 | **Semantics** | Outline/compare on content |
| `predict.ts` | 31 | **Semantics + raw emit** | Predict on content; never split a marker pair in a ghost suffix |
| `smarttype.ts` | 3 | Semantics | Match on content |
| `rename.ts` | 2 | Semantics + raw emit | Base-name rule (B4) applies to content; rewritten cue re-emitted raw |
| `parse.ts` / `fountain.ts` | 1 | Parser | Now *emits* `LayoutLine` per element |
| `serialise.ts` | 15 | Raw | None — marker-faithful by definition; add round-trip fixtures |
| `fdx.ts` | 27 | Export | Emit/consume `Style` runs (its multiple-`Text`-element model already fits) |
| `docx.ts` / `docxwrite.ts` | 1 | Import/export | Map DOCX runs ↔ markers at the boundary |
| `normalize.ts` | — | Raw | Must not trim inside marker pairs |
| `zip.ts` / `zipwrite.ts` / `crc32.ts` | — | Raw | None (container/checksum) |
| Mac surface: `ScriptSurface.swift`, `FindBarClient.swift`, `SelectionFormatBar.swift`, `ScreenplayPageRenderer.swift`, `ScriptLayout.swift`, `PageCanvasView.swift` | — | **Both spaces** | §4 |
| Web surface: `src/lib/screenplay/*`, `src/lib/components/*` | — | Both spaces | Same mapping rules; web concealment via CSS/CM6-style decorations is a separate, later decision |

Per-file conversion detail is Phase 0 work; this table is the checklist it must close out.

## 4. The editor — Pages-style permanent concealment, with atomic caret

This is the part nobody has shipped in a plain-text screenplay editor, and the reason Beat defaults its concealment to off (§6). We spec it fully here.

### 4.1 Concealment

Marker glyph runs get `NSGlyphPropertyNull` in our `NSLayoutManager` subclass (`shouldGenerateGlyphs:…`) — permanently, not line-gated. Storage is untouched; the characters remain real. Selection rendering needs no work: zero-width glyphs produce no selection rects.

### 4.2 Caret and selection are ContentIndex citizens

All selection state is stored in ContentIndex and mapped to RawIndex only at the storage boundary. Rules:

- **Arrow keys:** move one grapheme in *content* space. Marker runs are not content; the caret never lands inside them. Option-arrow word motion likewise in content space.
- **Click hit-testing:** `characterIndex(for:)` yields a RawIndex; if it falls inside a marker run, snap per the map rule (closer edge, ties trailing). The caret can never be placed inside a marker.
- **Selection extension** (shift-arrows, shift-click, drag): endpoints snap identically. A styled run is selected by its content; marker inclusion is derived at copy/serialise time, with markers opened/closed balanced at the selection boundaries.
- **Typing at a run edge:** adopt `typingAttributes` semantics — the caret at the content-end of a bold run types bold (extends the run); the user exits the style with ⌘B. This matches Pages' feel exactly, and costs us nothing because the storage already inherits attributes this way.

### 4.3 Deletion

- **Backspace at a run's trailing edge** deletes the last content character; the run shrinks.
- **Backspace at a run's leading edge** skips the concealed opener and deletes the preceding content character.
- **Empty-run collapse:** an edit that empties a run deletes the marker pair atomically, caret preserved in content space. Engine-normalised, fixture-tested.

### 4.4 Boundaries

- **Paste in:** rich text → markers synthesized from traits (Beat's `NSAttributedString+ConvertToFountain` is the reference implementation); plain text paste goes in raw.
- **Copy out:** serialise selection with balanced markers — copied text is valid Fountain.
- **Find bar:** matches on content; results highlighted in content space; the find field itself shows content, not markers.
- **Accessibility:** VoiceOver speaks `content`; marker runs are excluded from accessibility text.

### 4.5 Rollback position

If atomicity proves fragile in dogfooding, the fallback is Beat's shipping behaviour — conceal except the edited line — which is a one-line gate in the layout manager (`!currentlyEditing`), not a redesign. We do not ship the dimmed-markers milestone as the final experience; it is Phase A scaffolding.

## 5. Phases

- **Phase 0:** `RawIndex`/`ContentIndex` types, `LayoutLine` in the TS engine, fixtures (`emphasis.json`, regenerated `paginate.json`); audit table §3 closed out line by line. No UI change.
- **Phase A:** rendering — style runs applied between markers, markers dimmed (Slugline-style); wrap/stats/PDF on content. Conformance green. Internal milestone.
- **Phase B:** permanent concealment + §4 atomicity. **Ship target.**
- **Phase C (optional):** source-mode toggle for power users (Typora-style).

## 6. Appendix: why Beat defaults concealment to OFF

Three evidence-based reasons, in order of weight:

1. **Stated philosophy.** Beat's own documentation: "Beat is not a WYSIWYG application… The main editor view in Beat shows raw Fountain content." Concealment is offered as a preference, not an identity. [beat-app.fi docs](https://www.beat-app.fi/docs/what-is-fountain/syntax/what-is-fountain/)
2. **The author doesn't trust the mechanism.** The glyph code carries "SOME WEIRD GUARDRAILS" and "I'm very bad with core stuff", and bails out on any multi-line glyph run. Defaulting that on would make every editing edge case a support burden. [BeatLayoutManager.m](https://github.com/lmparppei/Beat/blob/master/Frameworks/BeatCore/BeatCore/Editor/BeatLayoutManager.m)
3. **Non-atomic concealment has a visible cost.** Beat's caret machinery does nothing special around concealed ranges, so concealment must reveal on the edited line — and line-gated reveal makes text shift when the caret enters a line (the documented Obsidian complaint). Off-by-default confines that cost to users who opted in.

Point 3 is precisely our opportunity: with §4's atomicity, the reveal-on-edit compromise disappears, and default-on Pages-style editing becomes safe. That is beating Beat on experience, not only on architecture.
