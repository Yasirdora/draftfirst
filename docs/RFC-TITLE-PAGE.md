# RFC: The title page as a modelled section — page zero

*2026-09-14. Status: landed in part (3724908). D1 (lines as storage
truth), D3 (the sheet as a deriving view), D5 (verbatim FDX), D6
(renderer honours stored geometry), D7 (Fountain synthesises keys), and
D8 (migration) are shipped and pinned by the suites; D2 (page zero in
the canvas) and D4 (paste routes home) remain — the title page renders
through the keyed-page path it always used, now fed from lines. Witness
set: the fifteen paste-corpus
scripts (scripts-corpus/, never committed — see HANDOFF), the Chips FDX
fixture (apple/eDraftEngine/Fixtures/fdx.json), and the FDX files the
conformance work has pinned. The design principle this applies is the
tier rule from the .draft evaluation — anything that points at text
positions must be modelled, everything else carried — and the doctrine
the run-not-range decision set: one mechanism, never two that translate
between each other. This RFC is the completion of the front-matter half
of RFC-SECONDARY-SLUG §3: that pass made the pasted title page safe;
this one gives it a home.*

## 0. Decisions

- **D1 — The title page is a modelled sequence of paragraphs.** Storage
  truth becomes an ordered list of title-page lines — text, alignment,
  styled runs, and real blank lines — replacing keyed
  `{ key, values }` entries as what the file holds. Keys survive as an
  optional annotation a paragraph may carry; nothing ever fabricates
  one.
- **D2 — Page zero in the canvas.** The title page renders as an
  unnumbered sheet ahead of page 1, edited in place with the same text
  engine, the same caret, the same undo. It is not in `elements`: it
  never enters the cast, the navigator, the scene count, the page
  count, or the stats.
- **D3 — The guided sheet stays, as a view.** The sheet derives its
  fields (Title, Credit, Writers, Contact) from the paragraphs and
  rewrites only the paragraphs it can identify. Anything it cannot
  identify it leaves untouched — and the writer can see it on page
  zero, which today they cannot.
- **D4 — Paste routes home when the home is empty.** The
  credit-anchored front-matter block (RFC-SECONDARY-SLUG §3) lands in
  the title page when the document's title page is empty and the paste
  opens the document; into a non-empty title page or a mid-document
  paste it stays in the flow as centred lines, today's behaviour. The
  Social Network exception is unchanged: a credit block that IS the
  film is body, always.
- **D5 — FDX round-trips verbatim.** Title-page paragraphs import with
  their `Type`, `Alignment`, styled runs, and blank paragraphs intact,
  and export the same way. `titleKeyFor` — the positional key guess —
  dies. Our `TitleKey`/`TitleEntry` extension attributes become
  optional annotations written only for paragraphs the sheet created.
- **D6 — The renderer honours stored geometry.** The classic computed
  stack (title at ~⅓, credit, authors, contact bottom-left) stops being
  recomputed on every render and becomes the template the
  new-document and sheet paths *write* into paragraphs. Render then
  does for the title page what it does for every other page: lay out
  what the model says.
- **D7 — Fountain synthesises keys on export.** Fountain has no
  free-paragraph title page; export derives keys exactly as the sheet
  does, folds continuation lines under them, and drops what no key can
  carry with a diagnostic. Import annotates rather than restructures.
- **D8 — Migration is visual-identity.** Existing keyed entries convert
  to paragraphs deterministically, at exactly the positions the classic
  template renders them today. The gate: render the document before
  and after conversion; the pixels do not move.

## 1. What is broken today

Five facts, each verified in the tree.

**1. A foreign FDX title page never comes back.** On import,
`titlePageOf` (fdx.ts:804) reads eDraft's own `TitleKey`/`TitleEntry`
extension attributes when present — our files round-trip — and for any
file without them falls to `titleKeyFor` (fdx.ts:799), which *guesses*
a key from paragraph position: first paragraph Title, second Credit,
third Author, then Source, then Contact. The guess is fabrication: a
file whose second paragraph is "based on the novel by …" imports as the
Credit. Worse, the guess is all that survives — `Alignment`, styled
runs, and the blank paragraphs that carry the vertical rhythm are
dropped at the door. On export, `writeFdxWithDiagnostics`
(fdx.ts:1477) re-emits every paragraph as `Alignment="Center"
Type="General"` regardless of what the file said. A Final Draft title
page with a left-set contact block and a bold title comes back
centred, unstyled, and re-keyed. For a project whose thesis is that we
emit flawless FDX, the title page is currently the least faithful
surface we have.

**2. Two models, disconnected.** The FDX and Fountain paths feed keyed
entries; the paste path feeds centred body lines. A script born by
pasting — the way every corpus script was born — has its title page in
`elements`, sitting on page 1 in front of `FADE IN:`, paginated with
the script. A script born by import has its title page in a metadata
form the canvas never shows. Same object, two fates, chosen by how the
document arrived.

**3. The canvas never shows the title page.** The writer edits it
through `TitlePageSheet` — a good guided form — but what it renders to
is invisible while writing. The title page is the one page of the
document you cannot see until you export it.

**4. The renderer recomputes the layout every time.**
`ScreenplayPageLayout.titlePageRuns` (ScreenplayPageLayout.swift:295)
derives the classic stack from keys on every render: title uppercased
at 32% of page height, credit, authors, remaining keys in document
order, contact bottom-left. The result is handsome and wrong — the
file's own geometry is discarded and recomputed from a schema. Two
documents whose keys match and whose paragraphs differ render
identically.

**5. Real title pages overflow five slots.** The corpus has already
told us: "SECOND DRAFT" stood as a pasted cue (named residue of the
camera-grammar pass) because the model has nowhere to put a draft
designation. Production title pages carry draft names, dates,
copyright lines, "based on" credits, episode cards, and contact blocks
on both sides. The keyed model covers Title/Credit/Author/Source/
Contact and guesses the rest.

## 2. The model

```
TitlePageLine {
    text: string
    alignment: 'left' | 'center' | 'right'   // default 'center'
    runs?: StyleRun[]                        // the same runs the body uses
    key?: string                             // annotation, never required
}
```

`Screenplay.titlePage: TitlePageLine[]`. Blank lines are real lines
with empty text — they carry the vertical rhythm, exactly as they do in
FDX, which is why they must exist in the model rather than being
recomputed. There is no paragraph type: every title-page line is what
FDX calls `Type="General"`, and nothing else is expressible. That
restriction is the FDX correspondence the run-not-range decision set:
the model must not be able to say things the format cannot hear.

Keys demote to annotations. A line the sheet created may carry
`key: "Title"`; a line imported from a foreign file carries none.
Nothing in the engine *requires* a key, and nothing invents one. This
is the sentence that kills `titleKeyFor`.

The StyleRun reuse is deliberate and total: a bold title, an italic
"based on the novel by", an underlined copyright line — the emphasis
work already bought this machinery, and the title page should not grow
a second way to say "this span is bold".

In the document file, `screenplay.json` gains the new shape under a
format-version bump; §8 covers the migration. Validation's
`maxTitleEntries: 100` becomes `maxTitleLines`, same number — a title
page longer than a hundred lines is a paste accident, not a title page.

## 3. Page zero

The canvas gains one sheet ahead of page 1. It is a sheet in every
physical sense — same paper, same margins, same zoom, same shadow —
and a page in no narrative sense: unnumbered, uncounted, absent from
the navigator, the cast, the scene filter, the page-occupancy stats,
and `CONTINUED` logic. The grid overview shows it first; double-click
opens it.

Editing is in place, with the body engine and three local rules:

- Return opens a new line, centred by default.
- Alignment is a property of the line (centre, left, right), set from
  the format bar's alignment control — the same control the body will
  want for centred elements, not a new mechanism.
- Emphasis is the body's runs, live-collapse and all (RFC v2.1, D6):
  `**TITLE**` types as a bold title, markers never persist.

The sheet's include-in-PDF toggle already exists
(`ScreenplayExportPreference.includeTitlePageKey`) and keeps its
meaning: page zero prints first, or not at all.

What page zero is not: a second editing mode. No ruler, no drag
handles, no frame. The writer who wants the classic stack gets it from
the sheet or from a new document; the writer who wants to nudge one
line clicks it and types.

## 4. The sheet derives

The guided sheet is the right tool for the writer who does not want to
think about layout, and it stays — but as a view over the paragraphs,
not a parallel store. Derivation, stated exactly:

- **Title** — the first non-blank line.
- **Credit** — the first line matching a standard credit phrase
  (`TitleCredits.StandardCredit`), else the line immediately above the
  authors.
- **Writers** — the run of non-blank lines directly under the credit,
  parsed by the existing `TitleCredits.parseAuthors` (which already
  understands `&` and `and`).
- **Contact** — the trailing left-aligned block, if any.
- **Additional credits** — any line carrying a `key` annotation, keyed
  by it; plus, view-only, anything derived by the patterns the sheet
  templates write ("based on", "additional writing by").

When the writer edits a field, the sheet rewrites the paragraphs it
identified and no others. When derivation identifies nothing (an
exotic foreign title page), the sheet shows the fields empty and the
paragraphs untouched — and page zero shows the truth. This is the
honesty property: the sheet can decline, because the canvas is the
fallback that always shows what is actually there. Today a failed
guess is invisible; under page zero it is merely unassisted.

## 5. Paste routing

RFC-SECONDARY-SLUG §3 built the detector: the credit-anchored
front-matter block, twenty-five lines of forty characters, stopping at
the first structural or extension cue. This RFC changes only its
destination:

- Document title page empty **and** the paste opens the document →
  the block becomes title-page lines, verbatim, centred, blanks
  included. No key guessing; the sheet will derive on demand.
- Otherwise → today's behaviour, centred lines in the flow.

The Social Network opening is untouched: not credit-anchored in the
rule's sense, so it is body, as the gate pins it. The asymmetry is the
point — the detector decides *what* the block is, the destination
decides *where* it goes, and neither invents content.

A paste over a non-empty title page never overwrites it. The block
stands in the flow where the writer can see it and cut what they want;
silently merging two title pages is a judgement the engine has no
basis for.

## 6. FDX parity

Import keeps paragraphs verbatim: `Type` (asserted `General`, anything
else diagnosed), `Alignment` mapped to the three alignments, styled
runs read exactly as body runs are, blank paragraphs preserved as blank
lines. Export writes the same. The Chips fixture's three centred
paragraphs round-trip byte-identically; a foreign title page with a
left contact block, a bold title, and twelve blanks of rhythm now
survives — today it does not.

The extension attributes invert their meaning. Today they are the only
thing standing between a foreign file and the key guess. Under the
paragraph model they are redundant for round-trip — the paragraphs are
the truth — and remain useful only as sheet hints, so we write them
only on paragraphs the sheet created. `titleKeyFor` is deleted, and
`FDX_CONFLICTING_TITLE_METADATA` with it: without fabricated keys there
is nothing to conflict.

The conformance corpus gains a foreign-FDX title-page fixture — left
contact, styled title, blank rhythm — with the round-trip asserted
paragraph by paragraph, blanks included. That is the test that would
have caught today's behaviour.

## 7. Fountain

Fountain's title page is `Key: value` lines; there is no free paragraph
to map to. Export synthesises keys by the sheet's derivation (§4):
Title, Credit, Author from the identified lines, Contact from the
bottom block, each multi-line value continuing indented under its key
as `parseTitlePage` already reads. A line no key can carry — a stray
free paragraph — drops with a diagnostic naming it, so the loss is
announced rather than silent. Import annotates: each key's lines become
paragraphs at the classic positions carrying `key` annotations, which
is what the sheet wrote anyway. The Fountain fixed-point gate is
unaffected: first-import canonicalisation was already the rule.

## 8. Migration

Every existing document holds keyed entries. The conversion writes the
classic template as paragraphs: Title's values as centred lines at 32%,
a blank, Credit's lines, a blank, Author's lines, each remaining key's
block in document order, Contact as left lines at the bottom — with
`key` annotations on everything, because the sheet created it, in
effect, long ago. Deterministic, one direction, no user prompt.

The gate is visual-identity: for a document converted from the keyed
model, page zero renders pixel-identical to what
`titlePageRuns` produced from the keys. That test is constructible
today — run the current renderer, run the conversion plus the new
renderer, diff the runs. If the pixels move, the migration is wrong,
not the writer's document.

*Landed record (3724908).* Two consequences measured at landing, both
accepted. First, the gate as written could not hold to the pixel: the
classic computed stack placed the title at 32% of the frame, which is
1.44pt off the line grid, while the template writes real lines — so a
migrated title *settles onto the grid*, moving exactly that 1.44pt, and
the pinned test is the grid position (textTop + 15 × lineHeight), not
the old float. The grid is the truth; the old stack was the
approximation. Second, stored equals printed: the title's values are
the capitals the page shows, so `Screenplay.title` reads back the
printed form for migrated or sheet-edited documents — window titles and
export filenames included. That matches Final Draft's own convention
and the rule that what the page shows is what the model holds, but it
is a visible change and it is recorded here rather than discovered.*

## 9. Tests

- **Model round-trips.** FDX: the Chips fixture byte-stable; the new
  foreign fixture verbatim — alignment, runs, blanks. Fountain: key
  synthesis on export, annotation on import, fixed-point intact.
- **Migration identity.** The classic-template documents render
  unchanged; keyed entries with empty values, custom keys, and a
  four-line contact each convert and re-render identically.
- **Derivation.** Every title page in the paste corpus, derived: the
  sheet's four fields asserted by hand on the fifteen, including the
  ones with no contact block and the ones with production furniture.
  Derivation never mutates what it did not identify.
- **Paste routing.** Empty document + full-script paste → title page,
  not flow; non-empty title page → flow; the Social Network pin stands;
  the corpus gate's cast counts do not move (title lines were already
  out of the cast; now they are out of the body too — the expectedSplits
  pins move, re-recorded name by name).
- **Exclusion.** Page zero contributes no scenes, no cast, no page
  count, no navigator rows; scene numbering starts at the body's first
  intro, as D3 of the secondary-slug pass already promises.
- **Undo.** Sheet edit, canvas edit, and paste each undo as one step —
  the discipline the sheet already keeps.

## 10. What this pass is not

- Not images, logos, or a cover designer. Text, alignment, emphasis.
- Not multiple title pages. FDX has one; the model has one.
- Not vertical drag or a ruler. Blanks carry rhythm; the writer who
  wants lower adds a blank line, as Final Draft's own files do.
- Not production-draft *furniture* as a feature. "SECOND DRAFT",
  revision dates, copyright lines — all expressible as ordinary
  title-page lines from today forward, but revision tracking is its own
  RFC and this pass gives it nothing to collide with.
- Not a change to body pagination, and not a touch of the Social
  Network rule. The credit block that is the film is body, full stop.
- Not a second text engine. Page zero runs the body's engine with three
  local rules; anything more is a new mechanism, and the doctrine
  forbids it.
