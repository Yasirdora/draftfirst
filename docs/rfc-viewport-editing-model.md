# RFC v2.1: The eDraft viewport editing model — runs in the model, markers at the boundary

**Status:** Draft for review · **Date:** 2026-09-10 · **Author:** Kimi
**Supersedes:** `rfc-emphasis-layout-model.md` v1 — decision **D1 is flipped**. v1 recommended markers in storage with glyph-null concealment; the `.draft` format review settled on runs-in-model instead. Everything in v1 that derives from markers-in-storage (concealment, dual index space in the editor, marker-run snapping) is withdrawn and replaced here.
**v2.1 corrections (review, 2026-09-10):** (1) **Tags and revision marks are run properties, not range attachments** — FDX puts `RevisionID` (165/239 instances in sample01/sample02) and `TagNumber` (407 in sample02) on the `<Text>` element alongside `Style` (260/258); the run↔`<Text>` mapping §3 establishes for style applies unchanged to its sibling attributes. (2) **`StyleSet` has six members** — the fixtures' distinct Style tokens are Bold, Italic, Underline, Strikeout, AllCaps, HiddenText; v2 named four. (3) Strikethrough's FDX mapping is asserted from the corpus: `Style="Strikeout"`. D6 and the fixed-point gate ratified, with D6's input-transformation constraint made explicit (§3.3).
**Depends on:** `bold-italic-underline-review.md` (Beat/landscape evidence), `evaluation-draft-format-plan.md` (tier rule: anything that points at text positions must be modelled), `work-package-1.txt` (paginator parity scorecard — gates the lock feature, §5.4).

---

## 0. Decisions requested

| # | Question | Recommendation |
|---|---|---|
| D1 | Where does emphasis live? | **Runs in the model.** Element text is marker-free content; style runs hang off it. Markers are synthesized only at the Fountain boundary (parse in, serialise out) |
| D2 | Editing experience | **Pages-style, always clean.** Unchanged from v1 — but achieved without concealment, because there is nothing to conceal |
| D3 | Concealment mechanism | **Withdrawn.** No `NSGlyphPropertyNull`, no marker runs, no reveal-on-active-line. The mechanism is deleted, not built |
| D4 | Where the rules live | Unchanged: TypeScript engine is source of truth, Swift mirrors, conformance corpus pins both |
| D5 | How do notes, colours, locks, document data anchor? | **One attachment contract** (§5) covering what is genuinely not a run property: script notes (real ranges), scene/page colour, locked pages, document-level data. Tags and revision marks are **run properties** (§1), because FDX puts them on `<Text>` |
| D6 | What happens when a writer *types* `**`? | **Live conversion as an input transformation** (§3.3): a completed marker pair collapses into a styled run on the closing delimiter and the markers cease to exist in the model. Never a display mode; no marker ever persists in the buffer awaiting render |

The headline: v1's hardest engineering — permanent concealment with an atomic caret across two index spaces, "the thing nobody has built" — was load-bearing only because markers lived in storage. Runs-in-model deletes it. What remains is a solved problem class (rich-text run boundaries, `typingAttributes` semantics) plus one boundary synthesiser we control and fixture-pin. We keep the Pages-style experience goal and lose the risk that made it ambitious.

---

## 1. The model

```swift
/// Emphasis, as data. Six members — the complete Style token set observed in
/// the FDX corpus: Bold, Italic, Underline, Strikeout, AllCaps, HiddenText.
public struct StyleSet: OptionSet, Codable, Sendable {
    // bold, italic, underline, strikeout, allCaps, hiddenText
}

/// One span of content sharing identical presentation. Offsets are
/// ContentIndex — positions in the element's own text, which is
/// marker-free by construction.
///
/// revisionID and tagNumbers live ON THE RUN because FDX puts RevisionID
/// and TagNumber on <Text> next to Style. One span mechanism, one
/// normalisation, one conformance corpus — and the model can never express
/// a span the format cannot hear.
public struct StyleRun: Codable, Equatable, Sendable {
    public var range: Range<ContentIndex>
    public var styles: StyleSet
    public var revisionID: Int?        // FDX RevisionID; nil = unrevised
    public var tagNumbers: [Int]       // FDX TagNumber; empty = untagged
}

public nonisolated struct ScriptElement {
    public var id: UUID
    public var type: ScreenplayKind
    public var text: String            // content. No markers, ever.
    public var runs: [StyleRun]        // sparse: most elements have none
    public var dual: Bool?
    public var sceneNumber: String?
    public var depth: Int?
    // attachments: [Attachment] arrives with §5
}
```

**The two tokens v2 missed, and why they are not optional:**

- **AllCaps** is load-bearing, not cosmetic. Final Draft stores what the writer typed and applies capitals *through style* — `fdx.ts:995-1000` already documents this, which is why casing must never be treated as an edit. A `StyleSet` without AllCaps removes the thing that invariant depends on: the engine could no longer distinguish "the writer typed SHOUTING" from "Final Draft is displaying caps," and would risk rewriting text on export.
- **HiddenText** is carried so a round-trip never loses it. Its rendering/pagination treatment (Final Draft hides it from print) is pinned by conformance fixtures rather than asserted here.
- **Strikeout** (Fountain `~~`) was already shipped by the format bar as literal text; the corpus settles the FDX spelling: `Style="Strikeout"`.

**Canonical form** (engine-normalised, fixture-pinned):

1. Runs are sorted by start, non-overlapping. Overlapping spans split into segments, each carrying the union of properties — the FDX `<Text Style="Bold+Italic" RevisionID="…">` model exactly, so the FDX boundary is a 1:1 mapping with no algebra.
2. Adjacent runs merge only when **every** property is equal — styles, revisionID, and tagNumbers alike.
3. Zero-length runs do not exist (empty-run collapse is normalisation, not an editing rule).
4. Runs are clamped to the text they hang off; any edit re-clamps.

**Edit-survival for run-borne marks is inherited, not specified.** Styles, revision marks, and tags move with their text and shrink to surviving text by construction, through normalisation rules 1–4 — which is exactly the semantics FDX expresses by putting them on `<Text>`. The attachment contract (§5) is thereby relieved of its two most contested clients; what remains there is what genuinely is not a run property.

**Why runs beat v1's markers-in-model** — the honest accounting:

| | Markers in model (v1) | Runs in model (v2.1) |
|---|---|---|
| Round-trip fidelity | Perfect by construction | Perfect by *fixture*: synthesis is canonical (§3), byte-stable re-export is a corpus gate |
| Pagination correctness | Correct if every consumer strips | Correct by construction: there is nothing to miscount |
| Every consumer | Must be strip-aware forever (Beat's guardrail comments, desync fallback) | Consumes content by construction |
| Concealment | NSGlyphPropertyNull machinery + fallback plan | Deleted |
| Caret atomicity | Dual-space snapping rules | Standard run-edge semantics (§4) |
| Tags / revisions | (not addressed) | Run properties — one mechanism, FDX-isomorphic |
| `.draft` serialisation | Text blob + strip metadata | Text + sparse runs array |

The one thing markers-in-model bought for free — fidelity — is recoverable at the boundary because *we* control the synthesiser. Canonical emission rules make round-trips deterministic; the conformance corpus makes that a CI gate rather than a hope.

---

## 2. Index spaces — three, not two, and only one is user-facing

v1 defined `RawIndex`/`ContentIndex` as the permanent editing pair. Under the flip, the editor never sees markers, so the spaces re-form around where offsets actually live:

```swift
/// Offset within one element's content text. The ONLY space the caret,
/// selection, style runs, and range-anchored attachments ever use.
public struct ContentIndex: Comparable, Sendable { public let value: Int }

/// Offset in the editor's flattened storage (the NSTextView string).
/// ScriptLayout.ElementRange — which already exists — is the map
/// between DocumentIndex and (element, ContentIndex).
public struct DocumentIndex: Comparable, Sendable { public let value: Int }

/// Offset in Fountain source text. Exists only transiently inside the
/// parser and serialiser; never stored, never crosses the boundary.
public struct FountainIndex: Comparable, Sendable { public let value: Int }
```

Rules:

- The editor's selection is a `DocumentIndex` range (as today); everything model-side — runs, attachments, FDX ranges — is `(elementID, ContentIndex range)`. `ElementRange` converts between them; it already does this for reveal highlights and the format bar.
- `FountainIndex` never escapes `Parse`/`Serialise`. The parser produces runs and records no permanent map; the serialiser synthesises markers from runs. This is the v1 dual-space problem relocated to the one place it is trivial: a pure function with fixtures.
- TypeScript mirrors with branded types, as v1 specified.

---

## 3. The Fountain boundary — the only place markers exist

### 3.1 Parse (in)

Per the Fountain spec, unchanged from v1 §1.2 — `*i*`, `**b**`, `***bi***`, `_u_`, nesting, backslash escapes, no cross-line emphasis, whitespace-flanking rules — except the output is `runs`, not marker-bearing text. An escaped marker (`\*`) is a literal content character and never a style boundary. Fountain has no spelling for revision marks or tags; those enter only through FDX import or eDraft's own UI, and a Fountain round-trip legitimately drops them (recorded as expected-loss in the fidelity contract).

### 3.2 Serialise (out) — canonical synthesis

Deterministic emission, fixture-pinned both directions:

- Bold+italic emits as `***…***`; bold as `**…**`; italic as `*…*`; underline as `_…_`; strikeout as `~~…~~`. FDX mapping asserted from the corpus, incl. `Style="Strikeout"`.
- AllCaps and HiddenText have no Fountain spelling; they survive Fountain round-trips only as literal casing/text — an accepted, documented loss class (Fountain itself cannot say otherwise).
- Adjacent runs sharing a delimiter merge into one pair (canonical form rule 2 governs).
- A literal `*`, `_`, or `~` in content that would re-parse as a marker is backslash-escaped on emission. This is the flip's one new obligation: markers-in-model never had to decide this; we do, once, in the corpus.
- **Byte-stability gate:** import `x.fountain` → serialise → import → serialise: the second output equals the first, for every corpus file. First-generation import of a foreign file may differ from the original (their marker style may be non-canonical — Fountain has multiple valid spellings of the same emphasis, so first-import canonicalisation is legitimate); the *steady state* must be fixed-point stable.

### 3.3 Live conversion (D6) — an input transformation, never a display mode

Typing `**world**` in the editor: on the closing delimiter, the pair collapses and `world` becomes a bold run — **and the marker characters cease to exist in the model**. The constraint that keeps the flip honest: live-collapse transforms input; it is never a rendering choice. If any marker were allowed to persist in the buffer awaiting render, the dual index space this design deletes would come straight back. This is Word's autoformat of `*x*`, and the notedown approach: typing it works, seeing it never does.

Escape hatch: `\*` types a literal asterisk; undo immediately after a collapse restores the typed markers (one undo step, the expected gesture).

### 3.4 Paste / copy

- Paste rich text → runs from traits (Beat's `NSAttributedString+ConvertToFountain` remains the reference for the trait mapping).
- Paste Fountain source → parsed through §3.1 (markers become runs).
- Copy out as Fountain → selection serialised through §3.2; copy as rich text → attributed string. Both are valid outputs of the same selection; the clipboard carries both representations.

---

## 4. Caret and selection — the atomicity spec, shrunk to its truth

v1 §4 specified four mechanisms (hit-test snapping, arrow-key skipping, marker-aware deletion, edge typing) because concealed characters could never be caret stops. With no concealed characters, three of the four evaporate. What remains:

1. **Typing at a run's trailing edge** adopts `typingAttributes` semantics — the caret extends the bold run; ⌘B exits. Matches Pages, matches Final Draft, costs nothing: NSTextView inherits attributes this way already.
2. **Typing at a leading edge** inherits from the preceding character; at content position 0, from the following run. One documented rule, no affinity UI.
3. **Backspace** deletes the character to the left. Always. There is no concealed opener to skip — v1's hardest deletion rule is now the trivial case. A run that empties is removed by normalisation (§1, rule 3), not by editor logic.
4. **Selection across runs** is unremarkable: rendering applies run attributes, copy serialises per §3.4, the format bar re-runs the range.

Also honest consequences, stated once: the **find bar** matches content because storage *is* content; **accessibility** speaks content for the same reason; **hit-testing** is stock TextKit. v1 needed a paragraph each for these; v2 needs a sentence, and the deletion of that complexity is the flip's dividend.

---

## 5. The attachment contract — only what is not a run property

The `.draft` tier rule says: anything that points at text positions must be modelled, or it rots under editing. Position-anchored *span* data — styles, revision marks, tags — is modelled **on runs** (§1), FDX-isomorphically. The attachment contract covers the remainder:

```swift
public enum AttachmentAnchor: Codable, Sendable {
    case document                              // macros, SmartType lists, cast table
    case element(UUID)                         // scene colour
    case range(UUID, Range<ContentIndex>)      // script notes — real ranges in FDX,
                                               // independent of run boundaries
    case page(Int)                             // locked pages, page colour sets
}

public struct Attachment: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: Kind
    public var anchor: AttachmentAnchor
    public var payload: Payload               // per-kind Codable
}
```

Every kind declares its **edit-survival behaviour** — this is the behaviour spec the fidelity contract's edit-stress matrix tests against. (Tags and revision marks no longer appear here: they moved onto runs in v2.1 and inherit move/shrink survival from run normalisation.)

| Behaviour | Meaning | Used by |
|---|---|---|
| `moveWithText` | Edits before/at the anchor shift or resize it | script notes |
| `dieWithAnchor` | Deleting the anchored element deletes the attachment | script notes, scene colour (delete the scene, its colour and arc beats go with it — which is right) |
| `reanchorToPage` | Repagination moves the attachment to wherever its content now lives | locks (with the lock's hard-break semantics — §5.4) |

### 5.1 Script notes — the one breaking change

Today's notes (`ScriptAside`) anchor to an **element** and live in a separate split. FDX `ScriptNote` anchors a **range** (e.g. `Range="174,194"`) with author, date, type, colour — a real range, independent of run boundaries. The attachment model supersedes `ScriptAside`: element anchor becomes the degenerate range case (whole element), preserving current behaviour and UI while gaining FDX parity. A migration maps existing asides forward; nothing a writer has made is lost.

### 5.2 Revision tracking — run-borne marks, page-borne colours

Two halves, each in its right place. **Revision marks** are `revisionID` on runs (§1): they move and shrink with their text, and export is the same 1:1 `<Text RevisionID="…">` mapping as style. **Coloured revision pages** are page-anchored attachments — a colour set per page, rendered in the margin, zero pagination impact, zero height impact. A revision whose text is fully retyped dies with its runs — the correct semantics, since the revision was *about* those words.

### 5.3 Tags — run-borne references, document-borne definitions

**References** are `tagNumbers` on runs (§1), FDX-isomorphic. **Definitions and categories** are document-anchored data (Tier-2 carried today, graduating to modelled). No range machinery anywhere; deleting text deletes its tags by normalisation.

### 5.4 Locked pages — the only feature that touches pagination

Page-anchored, implemented as paginator hard breaks. **This RFC specifies the anchor, not the semantics:** lock semantics are designed against the WP1 paginator-parity scorecard (segmented at `LockedPage@Position` anchors), per the agreed sequencing — measure our paginator against Final Draft's *recorded* pages before designing the mechanism that overrides it. Nothing here pre-commits the design.

### 5.5 Scene / page colouring

Element-anchored (scene) or page-anchored (page) rendering attribute. No text impact, `dieWithAnchor`.

### 5.6 Cast

**Not attachments.** Cast rows are *derived* from character cues (as `CastRow` already is); document-level cast data (table-read actors, voices) is document-anchored carried data. Storing derived facts as attachments would create a synchronisation problem we don't need.

---

## 6. Consumer audit — v1's checklist, reclassified

The consumer list from v1 §3 stands as the Phase 0 checklist (it was grep-verified). The flip rewrites the *mechanism* column:

| Consumer class | v1 requirement | v2.1 requirement |
|---|---|---|
| `paginate` / `Paginate.swift` | Strip before wrap | **None** — text is content. One fixture asserts styled-line geometry ≡ unstyled |
| `pdf` / page renderers | Content length + styled drawing | Draw runs as attributes (incl. Strikeout; HiddenText per its fixture); metrics unchanged — Courier fixed advance means style never changes width |
| `continuity`, `classify`, `validation`, `structural`, `predict`, `smarttype`, `rename` | Compare stripped text | **None** — comparison is content comparison. AllCaps stays a style, never a text rewrite |
| `parse` / `serialise` | Emit `LayoutLine` | §3.1 / §3.2 — the only modules that change shape |
| `fdx` | Style runs ↔ markers | Runs ↔ `<Text Style/RevisionID/TagNumber>` 1:1 — canonical form was designed for this; Strikeout mapping asserted |
| `docx` | Runs ↔ markers | Runs ↔ DOCX runs — direct |
| `SelectionFormatBar` | — (v1 missed it) | **Rewire:** `onApply` currently inserts literal marker characters (`SelectionFormatBar.swift:136-143`); it becomes a run adjustment on the model. The code's own comment names this milestone ("until M5 gives the model inline runs", `:8-9`) — this RFC is that milestone |
| Mac/web surfaces | Both spaces + concealment | One space, no concealment. Web (CM6 decorations) decision deleted with it |

The v1 table's deeper claim also survives: TypeScript engine remains source of truth, Swift mirrors, corpus pins both (D4 unchanged).

---

## 7. Conformance plan

New/updated fixtures, exported by `scripts/engine-conformance-export.mjs`, freshness CI-gated as today:

- `emphasis.json` — parse: detection, nesting, escapes, unclosed openers, flanking rules, per element type → runs. Covers all six StyleSet members' Fountain-spellable subset.
- `emphasis-synthesise.json` — **new:** runs → canonical markers; byte-stable fixed-point cases; literal-asterisk escaping.
- `paginate.json` — styled line ≡ unstyled twin geometry.
- `serialise.json` — round-trips including escaped markers and strikeout.
- `fdx.json` — `<Text>` runs both directions: `Style` unions (`Bold+Italic`, `Strikeout`, `AllCaps`, `HiddenText`), `RevisionID`, `TagNumber`, and the invariant that AllCaps never rewrites stored text.
- Swift-side pure tests for normalisation (sort/split/merge/clamp, merge requiring equality of *all* run properties) — logic in Core as pure functions, display machinery as a clock (the standing lesson from the zoom drift work).

---

## 8. Performance posture

- **Pagination hot path:** untouched. Runs are not consulted by wrapping; the styled≡unstyled fixture makes that a gate, not an intention.
- **Storage:** runs are sparse — most elements carry none; absent array encodes as nothing. A heavily styled or heavily tagged script adds a few bytes per span, versus v1's permanent per-element map.
- **Editing:** run adjustment on edit is O(runs in that element); normalisation is linear in the element's run count. No global passes, nothing on the display link.
- **Synthesis cost** is paid only at serialise/export, linear in run count.

---

## 9. Phases

- **Phase 0 — model & types.** `ContentIndex`/`DocumentIndex`/`FountainIndex` types; six-member `StyleSet`; `StyleRun` (styles + revisionID + tagNumbers); normalisation invariants; engine parse/synthesise + fixtures. No UI change. Consumer audit §6 closed out line by line.
- **Phase A — viewport.** Render runs in the page renderer; rewire `SelectionFormatBar` to runs; `typingAttributes` at edges; live marker conversion (§3.3). The format bar's marker-insertion path is deleted in the same change — no hybrid state ships.
- **Phase B — boundaries.** Paste/copy (§3.4), find, accessibility. Byte-stable corpus green.
- **Phase C — attachment foundation.** `Attachment`/`AttachmentAnchor` + edit-survival rules; `ScriptAside` migration (§5.1). No new user-facing feature yet.
- **Then, each its own work package:** range-anchored notes UI → revision tracking (run-borne marks + page colours) → scene/page colouring → tags UI (run-borne references) → **locked pages, gated on WP1's scorecard** (§5.4).
- Phase C-optional: source-mode toggle for power users. Cheap now (serialise the script through §3.2 into an editing surface), but not a launch commitment.

**Rollback:** trivial at every phase — runs are additive data; an absent runs array is exactly today's behaviour. v1 needed a fallback *experience* (Beat-style reveal) because concealment was the risky centre. The risky centre is gone.

---

## 10. What we are explicitly NOT doing

- No glyph-nulling layout-manager subclass (v1 D3 — deleted).
- No dual index space in the editor — including no markers-persisting-in-buffer "display modes"; D6 is an input transformation (§3.3).
- No marker characters in any storage, cache, or serialised form except transiently at the Fountain boundary.
- **No second span mechanism.** Styles, revision marks, and tags share one run model; range attachments exist only for what FDX itself ranges (script notes).
- No lock semantics in this RFC (WP1 first).
- No TextKit 2 migration (the surface stays TextKit 1 per `ScriptLayout`'s measured decision).

---

## Appendix: why the flip is safe to make *now*

v1 was written against a model whose text field was the file. Since then three things landed: the `.draft` evaluation fixed the tier rule (position-anchored data must be modelled — emphasis is position-anchored data); the format bar shipped markers-as-text, making the cost of *not* having runs visible in the product today; and the code itself left the door open ("until M5 gives the model inline runs"). The v2.1 corrections follow the same discipline one step further: FDX already told us where tags and revisions live — on the run — and which styles exist — all six. The design gets smaller and more FDX-isomorphic at once, which is the surest sign it is converging on the truth of the format.
