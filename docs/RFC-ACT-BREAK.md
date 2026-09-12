# RFC: Act breaks

*2026-09-12. Status: phases 1–2 landed. Phase 1 — the model and the
boundaries (the type, the paginator's break-before, FDX both directions,
Fountain out, the Core bridge) — pinned b3d1fc5 → de1406a → 442d720.
Phase 2 — the derivation (§4's ordinals, canonical spelling, renumber),
the selector entry, the delete hook, and the navigator's outline, Mac
first per §8, the shared list serving the phone's sheet as it stands —
pinned 1f90e5c → e6babe6 → e58b3d9 → 0558928 → d3da099. Phase 3 (§5's
paste route, with the corpus gate) remains, as does the iOS port of the
insert affordance. Corpus witness:
breaking-bad.txt (ACT ONE … END ACT FOUR, between page numbers). The design
principle this applies — the model stores the semantic minimum, every format
boundary derives what it can — is stated in §2 and meant to be reused.*

## 0. Decisions

- **D1.** An act break is a new **printing** element type, `actbreak`, whose
  content is the card text (`ACT TWO`). It is not a spelling of `section`:
  sections are non-printing organisation, and a writer's `Outline 1` headings
  must not suddenly print cards. Two ideas, two types.
- **D2.** An act break always starts a new page. Break-before is a paginator
  rule on the type, not a stored `pagebreak` the writer could delete.
- **D3.** There is no End-of-Act element and there never will be. An act ends
  where the next act begins, or where the document ends. The fact is derived,
  never stored — stored facts go stale on the next edit.
- **D4.** Any number of acts. The model is a list; nothing counts to three.
- **D5.** Card text is editable (`TEASER`, `COLD OPEN`, `ACT TWO: THE
  INTERROGATION`). Teaser and cold-open support falls out of this for free.
- **D6.** Inserting or deleting an act renumbers the cards that are still
  spelled canonically (`ACT <ordinal>`); a card the writer rewrote is never
  touched. Exact rule in §4.

## 1. Why an element, not a convention

Today, act breaks arrive in eDraft three ways and survive none of them. On
paste, `ACT ONE` passes the cue test — all-caps, ≤48 characters, no trailing
`.` or `:` — and becomes a *character*; Breaking Bad's pilot puts four acts
and four act-ends in the cast panel. On FDX import, Final Draft's `New Act`
and `End of Act` paragraph types read as `general` refined to `centered`
(fdx.ts FDX_TO_MODEL; Swift port Fdx.swift:196-197) — they print right but
the structure is gone. And the writer has no way to say one at all: the
element selector offers nothing.

A screenplay's act structure is real data. It drives navigation, page
counting per act, and the production conversation ("the Act Two turn"). The
element is the honest way to keep it.

## 2. The model

```
ElementType += 'actbreak'     // printing; content is the card text
```

Semantics:

- **Break-before, always.** The paginator forces a new page at every
  `actbreak` — the same machinery the structural `pagebreak` element already
  drives (paginate.ts:219 buffers it as a break), promoted from an element
  the writer places to a property the type carries.
- **Card placement.** Top of the new page, two blank lines down, centered —
  the Final Draft convention the corpus shows. Pinned by a layout test, not
  by taste.
- **Block boundary.** An act break is never straddled: no dialogue carries
  across it, no `MORE`/`CONT'D` pair spans it. The paginator treats it as it
  treats the end of a page's last block, unconditionally.
- **Act boundaries are derived.** Act *n* runs from its `actbreak` to the
  next one or to the document end. Navigation, per-act page counts, and any
  future act-aware UI all read the derivation; none of it is stored.

`section` keeps its meaning: organisation that does not print. An outline
full of `Outline 1 (Acts)` headings from an FDX import must not start
printing cards — D1 exists to keep that impossible.

## 3. The boundaries

The principle, stated once here because it is meant to be reused: **the model
stores the semantic minimum, and each format derives whatever that format
speaks.** Scene numbers, dialogue `(CONT'D)`s, `(MORE)` furniture and
revision marks are the next candidates; this RFC is the template.

### FDX out

Each `actbreak` writes `<Paragraph Type="New Act" Alignment="Center">` with
its card text. Immediately before each act break after the first, the writer
**generates** `<Paragraph Type="End of Act" Alignment="Center">END OF ACT
<ordinal></…>` — derived from the boundary, never stored (D3). Final Draft
users opening the file see exactly what their own software would have
written. No End of Act is generated at document end; `THE END` is the
writer's text, not ours.

### FDX in

`New Act` maps to `actbreak`, card text kept. `End of Act` maps to **nothing**
— absorbed, because it carries no fact the model lacks (D3). The preserving
rewrite is untouched: a file we import and never edit keeps its bytes,
`End of Act` paragraphs included; only a fresh export generates them.

Both changes land in the TS engine and the Swift port in the same pass,
pinned to the same commit — the port is a port, not a fork.

### Fountain

Out: the card as centred text, `>ACT TWO<` — it prints correctly in every
Fountain tool. In: centred text stays centred; the act structure flattens.
Named and accepted: Fountain has no act spelling, exactly as it has no
revision marks and no locked pages. This is what `.draft` is for. A
standalone pasted line reading `ACT ONE` still routes to `actbreak` (§5) —
the paste boundary is smarter than the format.

### .draft

Native type, full fidelity, nothing to derive.

### Print / PDF

The card, centred, at the top of its page, on every platform's renderer.

## 4. Numbering

Default card text is `ACT <ordinal in words>` — ONE through TWENTY, digits
beyond. The canonical spelling is:

```
^ACT (ONE|TWO|…|TWENTY|[0-9]+)$
```

On insert or delete of an `actbreak`, every later card still matching the
canonical spelling is renumbered to its new ordinal; any card that doesn't
match is the writer's text and is left alone (D6). The rule is deterministic,
runs once per edit, and never rewrites text a writer customised.

## 5. The paste route

Two rules, both corpus-witnessed:

- A standalone line matching `^(ACT\s+(ONE|…|TWENTY|[0-9]+))$`, blank lines
  on both sides, becomes an `actbreak`. (breaking-bad.txt, five witnesses.)
- A standalone line matching `^END (OF )?ACT\b.*$` is dropped — derivable
  (D3), and dropping it is what keeps it out of the cast panel.

`TEASER` / `COLD OPEN` as standalone card lines route to `actbreak` with
their text kept. The corpus gate: after the paste, Breaking Bad's golden
panels hold — cast without a single ACT, four acts in the structure.

## 6. UI

- The element selector gains **Act Break**. Choosing it inserts the break at
  the caret — new page, centred card, caret after it in action.
- Typing choreography: the ring treats `actbreak` the way it treats
  `centered` — off the ring, joining at action (choreography.ts:70 is the
  precedent; an act's card never tabs into a cue).
- The navigator lists acts as top-level entries, derived (§2), labelled by
  card text with per-act page ranges.
- No End-of-Act affordance exists anywhere.

## 7. Test plan

- Engine: break-before pagination; FDX round-trip (`New Act` ↔ `actbreak`,
  generated `End of Act`); Fountain spelling and its named degradation;
  canonical renumber on insert and on delete, custom card untouched; a
  dialogue block hard-stopped at an act break (no straddle, no MORE).
- Swift port: same suite, pinned to the same commit.
- Corpus: breaking-bad.txt golden panels (cast, scene count, four acts);
  no other script in the fourteen moves.
- Fixed-point: export → import → export is stable on a script with acts.

## 8. Phases

1. **Model + boundaries** — the type, the paginator rule, FDX both
   directions, Fountain out, .draft, the engine tests.
2. **UI** — selector entry, choreography answer, navigator listing, the
   renumber rule, Mac first.
3. **Paste route** — §5's two rules with the corpus gate; lands with or
   after the routing pack, never before phase 1.
