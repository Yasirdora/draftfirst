# RFC: Secondary slugs, the title-page block, and the closing card

*2026-09-13. Status: landed (738f91d). The pass this RFC describes is the third
paste-routing pass, after the cue-confirmation pass (1e0dc85) and the
camera-grammar pass (23d0b78). Corpus witness set: the fifteen scripts of
the paste corpus (scripts-corpus/, never committed — see HANDOFF). The
design principle this applies — a screenplay's own typography is the
grammar, and the engine reads the grammar rather than guessing at it —
is the one RFC-ACT-BREAK §2 states.*

## 0. Decisions

- **D1.** A secondary slug (`COURTYARD - 1612 HAVENHURST - DAY`, `MINUTES
  LATER`) is typed `.scene`, not given a new element type. The navigator
  already reads the distinction: `SceneRow.isSecondary` (`setting == nil`)
  renders it lighter and the row's own documentation says a secondary
  "takes a scene number" is what it does *not* do. This pass makes the
  numbering honour that sentence — see D3.
- **D2.** A pasted title page is detected as a **block**: the opening run
  of short lines, engaged only when a credit line (`by`, `Written by`,
  `Adapted Screenplay by`) appears inside it. Engaged, every line of the
  block is `.centered`. The title is never a speaker again.
- **D3.** Scene numbering numbers a `.scene` only when it opens with a
  scene intro (`INT./EXT./EST./I/E` family) or is an OMITTED card. An
  OMITTED card keeps its number — that is the production semantics of
  the card. This changes numbering for forced Fountain dot-scenes: a
  line the writer forced to `.scene` without an intro is no longer
  numbered. Named here so the change is a decision, not a surprise.
- **D4.** `THE END` / `THE END.` — the whole line, nothing after — is a
  `.centered` card, on paste and on typing. It is never a speaker and
  never fuses into the scene's last speech.
- **D5.** Typing `Omit`, `Omitted`, or `OMITTED.` as a whole line promotes
  the element to `.scene`. The text stays as the writer typed it; the
  model's canonical spelling (`OMITTED`, SceneNumbering) is the import
  boundary's normalisation, not a rewriting of the writer's hand.
- **D6.** Where paste and typing disagree, they disagree on purpose.
  Paste gates the secondary-slug grammar on uppercase — a pasted
  mixed-case line is prose until proven otherwise. Typing is the
  writer's own hand, so the whole-line cards (`THE END`, `OMITTED`, the
  LATER family) promote case-insensitively, while the dash-form
  secondary slug (`X - DAY`) keeps the uppercase gate even on typing —
  the convention that slugs are typed in caps is the writer's signal,
  not our guess.

## 1. What is broken today

Three classes of line arrive in every pasted script and are read wrong.

**The secondary slug.** A master scene heading opens a new setup; a
secondary slug names somewhere inside it — `BASIN - DAY` (no-country),
`THE NEW YORK HARBOR - DAY` (godfather-2), `OFFICE HALLWAY - DAY`
(no-country), `COFFEE SHOP - EL PASO - NIGHT` (no-country), `MINUTES
LATER` / `A MINUTE LATER` (no-country). None opens with INT./EXT., so
rule 2 never fires; the cue shape adopts them (uppercase, short, no
terminal punctuation), and cue confirmation rescues only the ones whose
following block fails the speech interview. The rest sit in the cast
panel. The user's report: "many things that should appear as scene
headings are being tagged as character."

**The title page.** A plain-text paste carries no title page — only its
lines. `MANCHESTER BY THE SEA` / `Written & Directed` / `by` / `Kenneth
Lonergan` arrives as four lines; the cue shape takes `MANCHESTER BY THE
SEA`, speech position takes `Written & Directed` as its dialogue, and
the 17-character speech passes cue confirmation's width test, so the
film's title enters the cast as a speaker. Every corpus file with a
title block shows it: godfather-2 (8 lines), heat (6), breaking-bad (6),
no-country (5), gone-girl (the title three times, then the credits),
whiplash, lalaland, episode-101 (title, credits, dotted-leader cast
table, set list). The user's report: "it picks up the name of the film."

**The closing card.** `THE END` stands at the document's end, where
cue confirmation already demotes it — "the document ends under it — a
card, not a speaker" — but demotion lands it in *action*, fused into or
adjacent to the final scene's words. It is a card; it should print
centered, the way every printed script shows it.

And one typing gap: the writer types `Omit` or `Omitted` and nothing
happens — the navigator never shows it. `SceneNumbering.
parseNumberedHeading` already knows the card (`OMIT`, `OMITTED.`, the
dash-heading form `139 OMIT- INT. …`, 27 witnesses in gone-girl);
the promotion layer simply never asks.

## 2. The secondary-slug grammar

A line is a secondary slug when all of these hold (paste path;
uppercase-gated per D6):

1. **Uppercase form** — the ASCII reading the camera grammar uses: at
   least one A–Z, no a–z.
2. **No colon, no terminal sentence punctuation** — the cue shape's own
   guards, so a shout or a label never qualifies.
3. **Not itself a scene heading** — rule 2 answers first; this arm
   catches only what the intro missed.
4. **One of three shapes:**
   - **The time-of-day ending** — the line ends ` - DAY | NIGHT | DAWN |
     DUSK | MORNING | EVENING | LATER | CONTINUOUS | SAME | SAME TIME |
     MOMENTS LATER` (the existing `HEADING_TIME_ENDING` /
     `PasteHeuristics.hasTimeOfDayEnding`). Witnesses: `COURTYARD -
     1612 HAVENHURST - DAY` (corpus-1), `THE NEW YORK HARBOR - DAY`
     (godfather-2), `MARCIAN0'S OFFICE - MARCIANO - DAY` (heat),
     `BASIN - DAY`, `2ND HOTEL EAGLE ROOM - NIGHT`, `OFFICE HALLWAY -
     DAY`, `SHERIFF BELL'S OFFICE - DAY`, `COFFEE SHOP - EL PASO -
     NIGHT` (no-country).
   - **The quantity-LATER card** — the whole line is optional
     quantifiers (`A`, `AN`, a number word ONE…TEN, digits, `FEW`,
     `SEVERAL`, `COUPLE`), then a time unit (`SECOND(S)`, `MINUTE(S)`,
     `MOMENT(S)`, `HOUR(S)`, `DAY(S)`, `WEEK(S)`, `MONTH(S)`,
     `YEAR(S)`), then `LATER`: `MINUTES LATER`, `A MINUTE LATER`
     (no-country). The last word before LATER must be the unit, so
     `LATER THAT NIGHT` and `SEE YOU LATER` never match.
   - **The ANOTHER PART insert** — `ANOTHER PART OF …`, whole line:
     `ANOTHER PART OF THE CASINO` (godfather-2). Narrow because the
     witness list is narrow.

Placement in the cascade matters and is the same in both engines:
**after** the wrapped-heading tail fold, **before** the act card, the
transition, the camera and the cue. The tail fold answers first, so
`CORLEONE - DAY` attached under an open `INT.` heading still folds into
its heading (the 2½ behaviour pinned by the camera-grammar pass); only
the standalone card is promoted. Ahead of the cue shape, the slug is
never interviewed as a speaker at all.

### What the grammar refuses, on purpose

- **`BEDROOM - JUSTINE`, `HALLWAY - NEIL`** — `X - NAME` cards where the
  tail is a person, not a time. They collide with real cues
  (`HAGEN'S SON` is a speaker in godfather-2) and stay residue.
- **Possessive inserts** — `NEIL'S HAND`, `CERRITO'S FOOT` (heat). Same
  collision class.
- **`SEVEN YEARS LATER -- THE PRESENT`** (manchester) — a LATER card
  with a tail. The whole-line family is anchored; tailed cards stay
  action. Residue, named.
- **`LATER` bare** — unwitnessed on paste as a standalone line in the
  corpus; the family requires a quantity. If it arrives, cue
  confirmation still interviews it.
- **Mixed case on paste** — `Minutes later` pasted mid-document is prose
  until the writer's own capitalisation says otherwise (D6).

## 3. The title-page block

### The rule

Walk the document's opening lines (blanks and pagination artifacts
skipped), collecting a block:

- **A line joins the block** when it is a credit lead, a dotted leader,
  or runs no longer than 40 characters.
- **The walk stops** at the first structural line — scene intro,
  numbered heading, act card, transition (including `FADE IN…`), title
  card marker, camera line — at the first extension-carrying cue
  (`NICK (V.O.)`), at the first line that qualifies under none of the
  joining shapes, or after 25 lines, whichever comes first.
- **The block engages only if a credit line appeared inside it.** No
  credit, no block, and every line classifies exactly as it does today.

Engaged, every collected line types `.centered` — high confidence, the
reason named ("title-page front matter").

### Why the credit line is the anchor

The failure this rule must never have is centering a pasted fragment
that begins at a cue: `ELI` over `DO YOU ACCEPT JESUS CHRIST AS YOUR
SAVIOR?`, `MARK (V.O.)` over `FROM THE BLACK WE HEAR--`'s Social
Network opening, `JOHN` over `Yeah.`. Line length cannot tell a film's
title from a speaker — both are short, uppercase, unpunctuated. The
credit line can: fragments of script do not open with `by`, `Written
by`, `Adapted Screenplay by`, `based on the novel by`, `A musical
written and directed by`, `Created by`. Every corpus title block
carries one (manchester line 2, heat line 2, breaking-bad line 2,
no-country lines 2/4, emilia-perez line 2, whiplash line 2, gone-girl,
episode-101); no corpus script opening carries one. The two-line
length rule was tried first and died on emilia-perez: `A musical
written and directed by Jacques Audiard` is 49 characters, over any
honest length ceiling, and the credit words inside it are the tell that
survives.

The credit grammar:

- **Lead** (case-insensitive): `by`, `written`, `screenplay`,
  `teleplay`, `based`, `directed`, `produced`, `story`, `adapted`,
  `adaptation`, `created`.
- **Mid-line**: `written | directed | screenplay | teleplay` followed by
  `by`, `&`, or `and` — emilia-perez's `A musical written and directed
  by …`, no-country's `Adapted Screenplay by`.

### Witnesses, walked

- **manchester** — `MANCHESTER BY THE SEA` / `Written & Directed` /
  `by` / `Kenneth Lonergan`; `EXT. MANCHESTER HARBOR` stops the walk.
  Four centered lines.
- **emilia-perez** — title, the 49-character musical credit,
  collaboration, song credits, `Page114 Why Not Productions`;
  `EXT. MEXICO CITY - NIGHT` stops it. Seven centered lines, junk
  footer included — centered is where a junk footer does least harm.
- **no-country** — the quoted title, `Adapted Screenplay by`, the Coens,
  `Based on the Novel by`, `CORMAC MCCARTHY`; the page number is
  skipped, `FADE IN:` stops it. Five centered lines, and `VOICE OVER`
  after FADE IN stays the cue it is today.
- **lalaland** — `LA LA LAND` / `by` / `Damien Chazelle`, the loose
  `A1` centers with them, `FADE IN...` stops it.
- **breaking-bad** — six lines through `Sony Pictures Television`;
  `TEASER` (act card) stops it.
- **heat** — six lines through `March 3, 1994`; `EXT. CEDARS-SINAI`
  stops it.
- **gone-girl** — the three `GONE GIRL` cards and the credit lines;
  `NICK (V.0.)` is an extension cue and stops it — the speech that
  follows classifies exactly as today.
- **episode-101** — `Episode 101`, `"PILOT"`, the `Written by` card,
  date/colour/page rows, the dotted-leader cast table; the set list's
  first scene intro stops it.
- **from-the-black** — `FROM THE BLACK WE HEAR--` qualifies by length,
  `MARK (V.O.)` is an extension cue: the walk stops at line 2, no
  credit ever appears, the block never engages. The Social Network
  opening is untouched — this is the regression the anchor exists to
  prevent.
- **corpus-6 / foryourcon** — the opening junk lines run past 40
  characters before any credit; the block never engages, and `TITLE:
  There Will Be Blood` keeps the title-card marker it already has.

### The known cost

A script whose story opens with dialogue — no FADE IN, no slug — whose
first speaker is a bare cue *and* whose opening lines include a credit
lead would center that cue. It takes all three at once; unwitnessed in
fifteen files. Named, not handled.

## 4. The closing card

`/^(THE END)\.?$/i` — the whole line, one optional period, nothing
before or after. On paste it answers after the camera arm and before
the parenthetical, in both engines; typed, `ScenePromotion` promotes it
to `.centered`. `THE END OF A THIRTY FOOT METAL POLE-` (corpus-6) is
not the card and never matches. Under a cue the card still answers
first — a speech whose entire text is `THE END` is a misread waiting to
happen, and cue confirmation would have flagged it anyway.

## 5. The OMITTED card, typed

`ScenePromotion` gains three tells, all whole-line:

- `OMIT` / `OMITTED`, one optional period, any case → `.scene`.
- `THE END` / `THE END.` → `.centered` (D4).
- The secondary-slug grammar → `.scene`, uppercase-gated for the dash
  form, case-insensitive for the quantity-LATER family (D6).

The enum keeps its name — it already owns "when a line becomes a scene
heading because of what it says"; the doc comment widens to own the
card promotions beside the slug. Renaming the type touches files
carrying other lanes' uncommitted work; the name is honest enough.

Numbering (D3) is what makes the promoted card production-real: an
OMITTED card is numbered, a bare secondary slug is not.

## 6. Numbering honours the secondary

`SceneNumbering.numberingAll` and `numberingNewScenes` today number
every `.scene`. The new predicate:

```
type == .scene && (hasSceneIntro(text) || isOmittedCard(text))
```

`hasSceneIntro` already exists (private, line 116); `isOmittedCard` is
new and small — trimmed, one trailing period dropped, uppercased is
`OMITTED` or `OMIT`. Everything else about numbering is untouched:
lettering against neighbours, the never-reuse rule, the empty-script
fallthrough.

This is the numbering half of `SceneRow.isSecondary`'s doctrine. A
writer who forced `.BLACK SCREEN` to a scene keeps the row, loses the
number — the same information, presented as a decision now instead of a
suggestion. Stated in D3 so it is a choice.

## 7. Where each surface gets it

- **TypeScript engine** (`packages/edraft/src/classify.ts`): the
  secondary-slug arm (rule 2¾), the closing-card arm (rule 5½), the
  block pre-pass in `classifyLines` with the verdict pushed before
  `classifyLine` runs (an explicit source style still outranks it).
  Every TS consumer — paste, `.txt` import, the gate — gets all three
  at once.
- **Swift paste** (`PasteReassembly` + `PasteHeuristics`): the same
  three, mirrored helper for helper, in all three routes — the indented
  scheme, the hard-wrapped scheme, and the planner's raw route, where
  block membership and the closing card reuse the card channel
  (`pasteKinds = .centered`, attachment boundary included).
- **Swift paste classifier** (`EditorState.kindForInsertedElement`):
  the secondary-slug and closing-card arms after the camera arm, before
  speech position — the camera pass's own doctrine.
- **Swift typing** (`ScenePromotion`): §5.
- **Numbering** (`SceneNumbering`): §6.
- **Web typing**: the TS engine has no ScenePromotion analogue (the Mac
  editor promotes; choreography.ts:39 says so by design). Web typing
  tells are a later, smaller pass and are named here so they are not
  forgotten.
- **iOS**: shares EDraftCore; the paste and numbering changes arrive
  with it. Nothing iOS-specific is touched.

## 8. The camera grammar grows one lead

heat's insert idiom — `ON AMBULANCE`, `ON DODGE PICK UP`, `ON SIDE
DOOR`, `ON STATION WAGON` (×5) — is the camera framing a surface, and
it currently sits in speeches. `ON` + a word joins the camera grammar,
uppercase-gated, in both engines (`CAMERA_LINE`,
`PasteHeuristics.looksLikeCameraShot`). The OCR twin `PAN 0N KEY`
(zero for O) stays unseen — OCR repair is not this pass. The corpus
gate's diff is the check on `ON`'s blast radius; any all-caps action
line it steals will show there by name.

## 9. Tests

- **TS**: witness tests per shape (the eight time-ending slugs, both
  LATER cards, `ANOTHER PART OF THE CASINO`, `THE END` / `THE END.`,
  `ON AMBULANCE`); block tests (a godfather-2-style title block centers
  whole, credits and draft dates included; the two-line fragments —
  `ELI` + shout, `MARK (V.O.)` — never engage; an extension cue closes
  the block; the block closes at the first slug).
- **The paste-corpus gate** is the regression instrument: re-recorded,
  then reviewed **name by name** — every cast member who leaves must be
  a title, a card, or a slug, and every scene that arrives must be a
  secondary slug. Only then is the golden rewritten.
- **Swift**: the mirrored witnesses in the paste tests; ScenePromotion
  tests for `Omit`/`OMITTED`/`THE END`/a typed secondary; numbering
  tests — secondaries unnumbered, OMITTED numbered, forced dot-scenes
  unnumbered (D3's named change).
- The existing cast-table alternation test pastes a bare table; under
  the block rule a table at document start is front matter. The test is
  restructured to paste its table after `FADE IN:`, and a new test pins
  the table-at-start behaviour instead of losing it.

## 10. What this pass is not

- **Not a title-page model.** The block centers the lines in the flow; a
  real title page — a document section, edited as one, exported as one —
  is the deferred RFC. This pass stops the bleeding (titles out of the
  cast), it does not build the feature.
- **Not script history.** Auto-generating OMITTED cards when numbered
  scenes are deleted belongs to the revision-locks work. §5 is only the
  typing tell, which is independent and ships now.
- **Not OCR repair, not fused-line splitting.** `PAN 0N KEY` and
  `-- Mr. White? DR. BELKNAP` (a cue fused at a dialogue line's end)
  are named residue, each its own future pass.
