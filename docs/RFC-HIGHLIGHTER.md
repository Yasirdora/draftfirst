# RFC: The eDraft highlighter

**Status:** Ratified 2026-09-12 · **Author:** Ysr, reviewed by Kimi
**Depends on:** `rfc-viewport-editing-model.md` (the run model it extends),
`evaluation-draft-format-plan.md` (the tier rule: anything that points at
text positions must be modelled)

---

## 0. Decisions

| # | Question | Decision |
|---|---|---|
| D1 | How many colors? | **One** — yellow. The note system will carry author/department colors; a second palette on the same page would collide with it. Yellow = attention mark; any other color = a note with an author. |
| D2 | Where does it live? | **On the run.** `StyleRun` gains `highlight`, beside `styles` — the tier rule's own sibling to `revisionID` and `tagNumbers`. No parallel annotation system. |
| D3 | Toggle rule | One click applies; clicking a fully covered selection removes; a partial selection splits runs — the exact rule the styles use. |
| D4 | Fountain | Dropped at export, documented. Fountain has no highlight syntax; the text always survives. |
| D5 | FDX | Round-trips through the eDraft extension namespace: `EDraft:Highlight="Yellow"` on `<Text>`. |
| D6 | PDF | Prints. A highlight that vanishes on paper is a lie. |
| D7 | v1 forecloses nothing | The field carries a color *value* (locked to `yellow` in v1). A future palette is an additive UI change, never a format migration. |

## 1. Why one color, and why it is the better answer

Multi-color highlights fake semantic layers — yellow=fix, pink=verify,
green=love — but a color can only ever say *that*, never *why*. Notes say
why, and notes are where author and department colors belong (Final
Draft's ScriptNote model, which our FDX boundary already carries). Two
rainbow systems on one page would make every colored passage ambiguous:
attention mark or note? One highlight color keeps the reading instant.

The one thing this decision does not cover is Final Draft's *character*
highlighting — every line of one character in their color, computed from
the character map for table reads and scheduling. That is a different
feature, which FD itself keeps separate, and it would live on our
character thread if we ever build it. It does not conflict with D1.

## 2. The model

`StyleRun` in both engines:

```swift
public struct StyleRun {
    public var start: Int
    public var end: Int
    public var styles: StyleSet
    public var revisionID: Int?
    public var tagNumbers: [Int]?
    public var highlight: HighlightColor?   // v1: .yellow only
}
```

`HighlightColor` is an enum, not a boolean: v1 has one case, `yellow`.
The canonical invariants are unchanged — sorted, clamped, non-overlapping,
merged **only when every property is equal**, highlight included. All run
arithmetic (`Emphasis.propagate`, slicing, toggling) treats `highlight` as
it treats `revisionID`: carried, compared, never interpreted.

## 3. Edit survival

The donor rule owns inheritance, exactly as for styles (RFC v2.1 §4):

- Typing **inside** a highlighted run **extends** the highlight. Pages
  does this; so do we. (The draft RFC's proposed test #1 asserted a split
  around unhighlighted insertion — that is the *paste* case, not the
  typing case, and it was corrected before ratification.)
- Typing at the **trailing edge** inherits; at the **leading edge** it
  does not — the character before the caret donates.
- A paste of unhighlighted text mid-run splits the run: inserted content
  carries its own (absent) highlight.
- Deleting the last character of a run destroys the run; no zero-width
  highlight may persist.

## 4. The note-wash stacking rule

A noted line carries a *temporary* background wash on the layout manager;
a highlight is a *storage* background on the run. TextKit lets the
temporary attribute win on overlap, which would silently erase a
highlight sitting on a noted line. The rule: **the highlight is the more
specific mark and always wins; the wash yields to highlighted ranges.**
One rule, one surface test per surface.

## 5. Format mapping

| Format | Mapping |
|---|---|
| `.draft` | Native, on the run (D2). |
| Fountain | Not carried; export drops it (D4). No paste/import parsing either — there is no marker to read. |
| FDX | `EDraft:Highlight="Yellow"` on `<Text>` — write on export, read on import (D5). |
| PDF | Drawn: the background rect behind the glyph run, ink unchanged (D6). |

### The FDX round-trip risk, resolved

Two round-trips exist, and they have different answers:

- **eDraft → FDX → eDraft** is ours end to end. The attribute is written
  and read by our own code; CI pins it. This is the loop that matters.
- **eDraft → FDX → Final Draft saves → eDraft** may lose the attribute if
  Final Draft discards unknown inline attributes. No CI can answer this —
  it needs Final Draft installed. It is a manual validation item, honestly
  labeled, and its worst case is confined to FD-resave loops: the `.draft`
  is never affected. If the manual check ever fails, the answer is
  documentation, not a format redesign.

## 6. UI (Phase 2)

- The format bar's Center slot becomes the highlighter swatch. Center
  Line stays reachable through the element menu.
- The swatch shows yellow always; it lights when the whole selection is
  covered (the same lit rule as the styles).
- One click applies; covered re-click removes (D3).

## 7. Test plan

**Engine (both languages, conformance-pinned):**

1. Canonicalisation: adjacent runs with equal properties *except*
   highlight do not merge; with equal everything, do.
2. Typing mid-run extends the highlight (§3, the Pages case).
3. FDX: model with highlights → FDX → model, runs intact, attribute
   present in the XML.
4. Fountain: model with highlights → Fountain → model, text intact,
   highlight absent.
5. PDF: a highlighted run draws a background rect behind its glyphs.

**Surfaces (Phase 2):**

6. The bar toggles per D3, one named undo step.
7. The note wash yields to a highlighted range (§4), on both surfaces.

## 8. Phases

- **Phase 1 (this document's execution):** engine model + canonicalisation
  + FDX round-trip + PDF draw, both engines, test-first.
- **Phase 2:** format bar swatch (Mac), rendering on both surfaces,
  lit state, note-wash stacking tests.
