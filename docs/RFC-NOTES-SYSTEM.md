# Notes — a design for eDraft's notes system

*Written 2026-09-18 on branch `rename/edraft`, HEAD `bd3a9ad`, after IL-0033
kept Final Draft's notes on their words through a save. It exists because
eDraft's notes are two systems that do not meet: the writer's own `[[notes]]`,
which live in the Fountain source and have no author field, no reply and no
state; and Final Draft's ScriptNotes, which eDraft now reads, anchors and
preserves but cannot answer. This RFC designs one notes system on seven
principles, and the six locks that build it.*

*Every claim carries its evidence:*

- ***measured*** — run on this machine; the command's result is quoted.
- ***measured (probe)*** — Final Draft 13.4.0 build 120, 2026-09-18: a probe
  file prepared here in the shape eDraft would write, opened and saved in Final
  Draft by the human, its bytes read back here. Where a fact comes from the
  human's observation in Final Draft rather than from the retained bytes, it
  says so.
- ***documented*** — Apple's documentation or the Human Interface Guidelines,
  or [APPLE-PLATFORM-GUIDE.md](APPLE-PLATFORM-GUIDE.md) (cited by section).
- ***inference*** — reasoned from measured facts, not itself run.
- ***judgement*** — a taste call. Where it is one, §10 offers options.
- ***unproven*** — needed and not yet known.

*Every example uses invented script text and invented names. The repository
is public.*

---

## 0. Decisions

### Settled

| # | Decision | Where it came from |
|---|---|---|
| D1 | A save keeps every Final Draft note on its words: only the Range values of notes whose words moved are rewritten. | Human, 1=B. Built in IL-0033. |
| D2 | eDraft owns the notes it wrote, and only those. It may add, rewrite or remove a note it owns; it never rewrites a note Final Draft owns. | Human, 2B. The ownership mark is the header line (§4), not an attribute — the probe decided that. |
| D3 | An unsigned note is written with the writer's own name. | Human, 3A. |
| D4 | In the editor and in Fountain, a role lives inside the author name, `Name (Role)`. **In FDX, an eDraft note's role is Final Draft's `Type`** — the note's dropdown — and its name is the author field. On Final Draft's own notes, `Type` is still a category, never a role. | Human, 4A; amended by the human after the Final Draft check of IL-0041 (IL-0042). |
| D5 | Display is `Name · Role`; colour comes from the person (the name), never from the note. | Human. |
| D6 | No login, no account, no identity service, ever. A person is the name they type. eDraft never derives a name from the system. | Human; §8. |
| D7 | Every fidelity keep from IL-0024 to IL-0033 is permanent (§2.3). | Human. |
| D8 | **The FDX carrier is the title: an eDraft note's `Name` is `[eDraft]`.** The author field is the writer's name alone; no header line; a note's words appear once, in its body. Attributes Final Draft does not define are never used. | **measured (probe)**, §3 facts 4 and 9. Amended twice: the header line of §4.1 showed as the first line of every note (IL-0042 moved the mark to the author field); the first words as title showed a short note twice, and a Final Draft edit keeps the title but not the author (IL-0043, the human's direction). |
| D9 | Final Draft's `WriterName` is the *last editor*: an edit in Final Draft re-stamps it. A note someone edits in Final Draft stays eDraft's (its title is kept) and is authored by whoever edited it, as Final Draft shows it. | **measured (probe)**, §3 facts 4 and 9, §8. Amended (IL-0042, IL-0043). |
| D10 | A quoted anchor that matches more than once is resolved by position, then by ordinal (§5.3). Stated here, not deferred. | Human directive; this RFC. |

### Open — the human's to decide

Listed in §12. None blocks stage 1.

---

## 1. The seven principles, as mechanisms

| # | Principle | Mechanism | Where |
|---|---|---|---|
| 1 | Never interrupts writing | Notes are asides, never printed, never reflowing the page. Adding a note is one shortcut; committing it returns the caret to exactly where it was. No modal, no focus stolen, nothing to sync, nothing to wait for. | §10.2 |
| 2 | Anchored to words, not positions | In FDX, a Range counted as Final Draft counts it (IL-0031) and kept on its words by every save (IL-0033) — which is also exactly how Final Draft keeps it (§3, fact 5). In Fountain, the words themselves, quoted in the header. | §5 |
| 3 | Author and role at a glance | `Name · Role` on every message, the person's colour on every card, from a name the writer typed once. | §8, §10.3 |
| 4 | Real threads, not "Re:" conventions | A thread id and `reply-to` in the header. Final Draft users still see "Re:" titles on the same words — flat, well-named notes, because Final Draft has no replies (§3, fact 7). | §6 |
| 5 | Open/Resolved — resolved fades, never deletes | `status:` in the header; resolving never removes a note from the file. | §7, §10.4 |
| 6 | Travels inside the FDX both ways, no accounts | Everything a thread is — ids, status, provenance, anchor — rides in text Final Draft preserves byte for byte (§3, fact 1). | §4, §6 |
| 7 | One-click notes report PDF | One command, one PDF, grouped by scene, built on the page renderer eDraft already prints with. | §9 |

---

## 2. Where notes stand

### 2.1 The writer's own notes — measured

- A native note is Fountain `[[ ]]`. Its author is a `Name:` prefix inside its
  own text (IL-0016), because `[[ ]]` has no attribute space and an element's id
  is regenerated on every parse. A prefix is believed only when it matches the
  writer's signature or prefixes two or more notes.
- Colour is assigned in order down the sorted roster of names, collision-free up
  to six authors.
- On the Mac, a line's notes open into one card per line (`NoteCard`), Pages'
  comment card "minus the half that makes a comment a conversation": no reply,
  and no author field or date on the writer's own notes.
- **Add Note** is ⇧⌘K on the Mac (`MainMenu.swift`), and in the context menu
  and the selection format bar.
- Settings holds a note signature ("Not Set" by default) and **Sign My Notes**.

Measured 2026-09-18 for this RFC, through the engine:

- **A note can span lines.** `[[A (Director): too slow\nB (Writer): agreed]]`
  parses as one note element with a line break, and serialises back
  identically.
- **A note typed mid-sentence does not stay there.** `She waits [[Dir: why
  here?]] by the door.` parses as a note element *before* the paragraph, and
  the paragraph becomes `She waits  by the door.` — a double space where the
  note was. Typed inside dialogue, the note lands between the cue and the
  speech. A note's position inside a line cannot be carried by where it sits.
  And there it ended the block: the next open read the cue and the speech as
  Action, and an FDX save wrote them into the file that way. Fixed by
  IL-0040. A one-line note inside a block is written inline on the line after
  it; anything else is written in front of the block's cue.
- **A native note saves into FDX as a script paragraph,**
  `<Paragraph Type="Note"><Text>Dir: too slow</Text></Paragraph>`, never into
  `<ScriptNotes>`. Final Draft shows it as a line of the script, not as a note.
  A ScriptNote since IL-0041 (§11, stage 1).
- **A note whose text ends in `]` breaks the next parse.** `[[… see [scene
  4]]]` closes at the first `]]`: the note loses its last character and a
  stray `]` becomes an action line of the script. A header-only note
  `[[[eDraft …]]]` does the same. This is a live bug in today's notes, not
  only a hazard for the new ones. Fixed by IL-0038, which built §4.4's rules
  for every note.

### 2.2 Final Draft's notes — measured

- **Read** (IL-0024): each `<ScriptNote>` with its `WriterName`, title, `Type`,
  colour, dates, Range and body. `WriterID` is worthless (one id across two
  writers); `Type` is a free-text category; colour carries no identity.
- **Shown** (IL-0026): read-only, coloured by author, on the lines they are
  about.
- **Anchored** (IL-0031): Final Draft counts a Range in UTF-16 units over the
  script's top-level paragraphs, one per paragraph break, End of Act included,
  two for each embedded `<DualDialogue>` or `<OmittedScene>`.
- **Kept on their words** (IL-0033): a save rewrites the Range of each note
  whose words moved, and nothing else in `<ScriptNotes>`.
- **Threads, as found** in a file Final Draft wrote: replies are separate notes
  titled `Re: <title>`, then `Re: Re: <title>`, sharing one Range — typed by
  hand, since Final Draft has no reply feature (§3, fact 7).

### 2.3 The permanent constraints

Every one of these holds through every stage below. A stage that cannot keep
one stops and asks.

| Lock | Keep |
|---|---|
| IL-0024 | Final Draft's notes are read with their authors; reading them writes nothing. |
| IL-0025 | End of Act cards are kept, never given the writer's edit. |
| IL-0026 | Final Draft's notes are shown read-only, and a save never writes an imported note back — never a duplicate. |
| IL-0027 | A paragraph nobody edited is written as its own bytes; a save with no edit returns a Final Draft file byte for byte, through the engine and through Fountain, in both engines. |
| IL-0028/IL-0030 | An edited paragraph changes only the writer's characters; tags, revision marks, run splits, casing and whitespace stand. |
| IL-0031 | A Range is counted as Final Draft counts it, embedded blocks two units. |
| IL-0032 | Dual dialogue is in the script; a save keeps its block, dissolves it only when the writer un-duals it, and says so. |
| IL-0033 | A save keeps every note on its words; in `<ScriptNotes>` only Range values change. |

IL-0029 committed the commit-message hook and holds no fidelity keep.

One keep changes shape, deliberately, at stage 1: IL-0033's "in
`<ScriptNotes>` only Range values change" becomes **"a note Final Draft owns
changes only in its Range value; a note eDraft owns (§4.3) is eDraft's to
write."** The byte-for-byte rule for every note eDraft did not write is
unchanged.

---

## 3. What Final Draft does — the probe

*measured (probe)*, Final Draft 13.4.0 build 120, 2026-09-18. The probe was
the anonymised Final Draft-written fixture `finaldraft-sample01.fdx`, plus
`xmlns:EDraft` on the root, `EDraft:Highlight` on one run, `EDraft:Thread` and
`EDraft:Status` on one of Final Draft's own notes, and a two-note thread in the
shape eDraft would write — each note tagged with `EDraft:` attributes and
opening with a header line such as `[eDraft thread:t-probe-2 status:open]`.
Final Draft opened it without a repair dialog. The human saved it once
unchanged (`probe-A-saved.fdx`), then again after edits (`probe-B-edited.fdx`);
the files stay outside the repository.

| # | Fact | Evidence |
|---|---|---|
| 1 | **Final Draft strips every unknown attribute on a plain Save As.** `EDraft:` occurs 9 times in the probe and 0 times in both saved copies; `xmlns:EDraft` is gone. The `[eDraft thread:…]` header lines survive byte for byte. | byte-verified here |
| 2 | **Highlights are collateral damage.** `EDraft:Highlight`, the highlighter's carrier (RFC-HIGHLIGHTER D5), is stripped by the same save. A Final Draft round trip erases eDraft highlights. | byte-verified here |
| 3 | **Notes survive whole:** all 14 notes, with their ids, Ranges, titles, colours, `Type`s and `WriterName`s — the probe's `Probe Writer (Director)` included. | byte-verified here |
| 4 | **`WriterName` is the last editor.** A note created in Final Draft is stamped with the macOS account name. Editing a note in Final Draft re-stamps its `WriterName` to the Final Draft user; untouched notes keep theirs through any number of saves. | new notes: byte-verified (a one-character name matching the account). The edit re-stamp: byte-verified too, in `probe-B-edited.fdx` — note 900 was edited in Final Draft, and its `WriterName` became the account's one-character name and its `WriterID` changed, while its `RefId`, `Type` and text header stayed. (Corrected by IL-0042: this row first said the retained file did not hold the edit.) |
| 5 | **Final Draft keeps notes on their words by position, as IL-0033 does.** A 46-unit insertion moved every note after it by exactly +46 (1303→1349, 2824→2870, and the zero-length 31820→31866); notes before it did not move. Summary paragraphs are inside the Range space. | the shifts: byte-verified here. That the insertion was in a Summary paragraph: the human's observation. |
| 6 | **Final Draft's own notes carry user-defined categories.** Two notes created in Final Draft: `Type="Tester"`, Name as typed, Range = the selected words (5 and 7 units). | byte-verified here |
| 7 | **Final Draft 13.4 has no reply feature.** "Re:" is a title convention only. | the human's observation; nothing new was written |
| 8 | **Final Draft shows the probe notes** with their full authors, and the header line as each note's visible first line — "reads as metadata, not garbage". | the human's observation, with screenshots |
| 9 | **What a Final Draft edit keeps.** Editing a note there keeps its `Name` (title), `Type`, `RefId`, `Color`, `Range` and `DateTime`; it re-stamps `WriterName`, `WriterID` and `DateModified`. Final Draft's own notes: of 677 on this Mac, 308 are untitled and none repeats its opening words as a title. | byte-verified here: `probe-B-edited.fdx`, note 900; the count across 60 files Final Draft wrote (IL-0043) |

What follows from it:

- **Everything a thread needs must live in text Final Draft preserves.** Note
  text does (fact 1); attributes do not. There is no fallback to switch to: the
  header line is the carrier.
- **A thread degrades gracefully in Final Draft:** flat notes, well named, on
  the same words (facts 3, 7, 8). Threading is eDraft-side value, invisible but
  harmless to a Final Draft user.
- **IL-0033 and Final Draft agree about Ranges** (fact 5). A file can pass back
  and forth and every note stays on its words at every step. This is the
  compatibility foundation for principle 2.
- **Authorship must not trust `WriterName`** (fact 4), and must never do what
  Final Draft does — take it from the system.

---

## 4. The carrier — the header line

*Amended by IL-0042 and IL-0043: in FDX the carrier is the note's title
(§4.2, §4.3), and no header line is written into a Final Draft note. The grammar below stays as
the design considered for Fountain threads (§4.4, stage 2); it is not built.*

### 4.1 Grammar

A header line is the first line of a note's text, alone on its line:

```
header   = "[eDraft" *( SP field ) "]"
field    = key ":" value
key      = 1*( a-z / "-" )
value    = token / quoted
token    = 1*( any character except SP, "]", DQUOTE )
quoted   = DQUOTE *( any character except DQUOTE and "\" / "\" DQUOTE / "\\" ) DQUOTE
```

| Key | Value | Meaning |
|---|---|---|
| `thread` | `t` + 6 lowercase base-32 characters, e.g. `t4k9qz` | The thread this message belongs to. Generated once, random, never derived from a Final Draft id. |
| `status` | `open` / `resolved` | The thread's state (§7). |
| `by` / `at` | quoted name; `YYYYMMDDTHHMMSS` | Who resolved it, and when — only with `status:resolved`. |
| `reply-to` | a Final Draft note `Id` | The note this message answers. Ids survived Final Draft's save (§3, fact 3). |
| `from` | quoted `Name (Role)` | Who wrote this message — provenance that a Final Draft edit cannot re-stamp (§3, fact 4). |
| `on` | quoted words | Fountain only: the words the thread is anchored to (§5). |
| `nth` | a positive integer | Fountain only: which occurrence of `on`, when the words occur more than once (§5.3). |

Examples, all invented:

```
[eDraft thread:t4k9qz status:open from:"Dana Reyes (Director)"]
[eDraft thread:t4k9qz reply-to:902 from:"Sam Okafor (Writer)"]
[eDraft thread:t4k9qz status:resolved by:"Sam Okafor" at:20260920T101500 from:"Dana Reyes (Director)"]
```

Rules:

- Keys are read case-insensitively and written lowercase. Unknown keys are
  kept verbatim when eDraft rewrites a header — the grammar can grow without
  breaking older files.
- A malformed header is not a header: the note is read as plain text, owned by
  nobody but the file, and never repaired silently. If a Final Draft user edits
  a header by hand and breaks it, the thread shows as a plain note and eDraft
  says why.
- The header is metadata the writer never types or reads in eDraft; the app
  shows the messages, not the line. In Final Draft and in other Fountain tools
  it is visible, and reads as metadata (§3, fact 8).

### 4.2 In FDX

- **One `<ScriptNote>` per message.** Its paragraphs are the message, one to a
  line — the writer's words and nothing else.
- **The root:** `Name` = the first words of the first message, trimmed at a
  word boundary to 40 characters (*judgement*) — superseded: `Name` =
  `[eDraft]`, the words never copied into the title (D8, IL-0043).
  `WriterName` = the writer's name alone, empty when none is given. `Type` =
  the role, empty when there is none (D4). `Range` = the anchor (§5).
- **A reply:** `Name` = `Re: ` + the root's `Name` — one `Re:`, never
  stacked — and the root's `Range`, so Final Draft shows it beside its root on
  the same words (§3, facts 3 and 8).
- **Colour** stays unset, as Final Draft's own unset value: colour is eDraft
  display (D5).
- **Ids:** a new note takes the next free `Id` and a fresh `RefId`, as the
  probe's did; `WriterID` is written as a fixed placeholder, since it carries
  nothing (IL-0024).
- **Attributes: none.** Not `EDraft:`, not anything else Final Draft does not
  define (D8).

### 4.3 Ownership (D2)

- **A note is eDraft's if and only if its `Name` (title) is `[eDraft]`.**
  Nothing else — not the words, not the author, not a colour, not a `Type` —
  makes a note eDraft's.
- eDraft adds, rewrites and removes only notes it owns. A note Final Draft owns
  keeps every byte but its Range value (IL-0033).
- A Final Draft user can edit a note eDraft owns. Final Draft keeps its title
  and re-stamps its `WriterName` (facts 4, 9), so it stays eDraft's, authored
  by whoever edited it, as Final Draft itself shows it (D9). Retitling it
  there makes it Final Draft's.

### 4.4 In Fountain

- **One `[[ ]]` per thread.** The header on the first line, then one message
  per line: `Name (Role): text` — the prefix IL-0016 already recognises.
  Measured to parse as one note and serialise back identically (§2.1).

```
[[[eDraft thread:t4k9qz status:open on:"doesn't move"]
Dana Reyes (Director): Too still? She should flinch.
Sam Okafor (Writer): She's frozen — that's the beat.]]

The kettle screams. Mara doesn't move.
```

- **Writer strict — a written note's only `]]` is its close** (§2.1, measured;
  built in IL-0038 for every note, ahead of stage 1). The writer puts a space
  between every two adjacent `]` inside a note, so `]]` is written `] ]`, and
  a space before the close when the text ends in `]`. A build from before
  IL-0038, and any reader that closes at the first `]]`, reads the note whole.
- **Reader liberal — a run of `]` closes a note at its end;** the `]`s before
  the last two are text. The `]]]` the old writer left on disk for a note
  ending in `]` therefore reads exactly. The reader trims the space before the
  close, and reads `] ]` back as `]]` on every line of a note, header
  included — lossy one way, by choice (§13).
- **A blank line inside a note is Fountain's connected blank line** (IL-0111).
  Each whitespace-only line strictly between a note's first and last lines is
  written as two spaces. The reader gives a line of nothing but spaces inside
  a note back empty. A note with no interior blank line is written as before.
  Lossy one way: a line the writer filled with spaces comes back empty (§13).
  A note an older build already broke — the blank line closed it, so its
  words reopened as script — stays broken.
- **Legacy notes stay valid.** `[[Dir: too slow]]` is a thread of one open
  message by `Dir`, anchored to the paragraph it precedes. Replying to it gives
  it a header; nothing converts a note the writer did not touch.

### 4.5 In PDF

The notes report (§9). Script pages never print notes (principle 1).

---

## 5. Anchors — words, not positions

### 5.1 In FDX

A Range, counted as Final Draft counts it (IL-0031) and kept on its words by
every eDraft save (IL-0033) and by every Final Draft save (§3, fact 5). eDraft
computes a new thread's Range from its anchor when it first writes the note;
from then on the Range is authoritative in FDX, and the header carries no
`on:`. If the anchored words are edited in Final Draft, Final Draft moves the
Range and the words change with it; a quoted `on:` would then contradict the
file, so FDX never carries one.

### 5.2 In Fountain

Where a note sits within a line cannot be carried (§2.1), so a thread in
Fountain is anchored by **its position between paragraphs, and the words it
quotes**:

- The thread's paragraph is **the paragraph that follows the note** — the one
  the parser moves a mid-sentence note in front of (§2.1). A note before a cue
  belongs to the speech that follows.
- `on:` quotes the words within that paragraph. Without `on:`, the thread is
  anchored to the whole paragraph.

### 5.3 The disambiguation rule (D10)

Stated now, because an identity rule left open becomes accidental behaviour:

1. **Search only the thread's paragraph**, from its start.
2. **The first occurrence of the quoted words is the anchor,** unless the header
   carries `nth:N`, which selects the Nth occurrence.
3. **eDraft writes `nth` exactly when the words occur more than once** in that
   paragraph at the time of writing, and omits it otherwise — so a header never
   depends on an ordinal it does not need.
4. Matching is exact on UTF-16 units, casing included: a thread quoting `MARA`
   does not land on `Mara`.
5. **If the words are not in the paragraph, or there are fewer than N**, the
   thread anchors to the whole paragraph and is flagged "words changed". It is
   never moved to another paragraph and never guessed.
6. An anchor never spans paragraphs in Fountain. A Final Draft Range that
   spans several paragraphs, exported to Fountain, anchors to its first
   paragraph with the words it covers there; FDX keeps the full Range.

### 5.4 From one to the other

- **FDX opened in eDraft:** each thread eDraft owns (§4.3) is placed in the
  editor before the first paragraph its Range covers, with `on:` and `nth:`
  derived from the words the Range covers in that paragraph.
- **Saved to FDX:** the Range comes from `on:`/`nth:` in the thread's
  paragraph, counted by IL-0031's rule — then kept by IL-0033.
- **Note elements never pair with script paragraphs** in the save's alignment.
  A thread is written through `<ScriptNotes>`; a Final Draft `Note` paragraph
  in the body (a note Final Draft keeps as a script line) stays a body
  paragraph with its own bytes, exactly as today.

---

## 6. Threads

- **A thread is a root and its replies,** in the order written. In FDX that
  order is the order of the notes carrying the thread's id; in Fountain, the
  order of the lines.
- **Replying to a Final Draft note is allowed.** The root stays Final Draft's,
  read-only (IL-0026); the reply is eDraft's, with `reply-to:` the root's `Id`
  and `thread:` new. Final Draft shows the reply as `Re: <title>` on the same
  words.
- **Final Draft users see flat notes** (§3, fact 7). eDraft's threading adds
  nothing they must understand and hides nothing from them.
- **Legacy "Re:" chains** — notes a Final Draft user titled `Re: X`,
  `Re: Re: X` on one Range — are *shown* as one thread when the titles chain
  exactly (after stripping repeated `Re: `) and the Ranges are identical. That
  grouping is display only (*inference* from the file Final Draft wrote,
  §2.2); nothing is written back, and the notes stay Final Draft's.
- **Deleting a message** removes that message's note. Deleting a root with
  replies removes the thread — an explicit, confirmed action, never a side
  effect of resolving (§7).

---

## 7. Open / Resolved

- **A thread's status is the `status` of its most recent message that eDraft
  owns.** A root that is Final Draft's cannot carry a header (D2); resolving it
  adds an eDraft message — "Resolved" by default — whose header carries
  `status:resolved by:… at:…`. Final Draft's note is untouched.
- **Reopening** writes a new message with `status:open`. History is never
  rewritten; the thread shows when it was resolved and reopened, and by whom.
- **Resolved fades, never deletes.** Resolving removes nothing from the file.
  The interface fades it (§10.4); the report can include or omit it (§9).
- **Final Draft sees** the status as header text on the note (§3, fact 8) — no
  state it must honour.

---

## 8. Authorship and roles — no accounts

- **The name is asserted by the writer:** "Your name for notes", asked once —
  the first time they add a note, if Settings has none — stored locally, and
  editable. "Your role" beside it, optional. This extends today's note
  signature (§2.1). No account, no email, no server.
- **Never derived from the system.** Final Draft stamps notes with the macOS
  account name (§3, fact 4); eDraft does not read the account name, the
  computer name or a contact card — a name the writer did not give is not
  theirs to have written.
- **Written (FDX):** `Name` = `[eDraft]`, `WriterName` = the writer's name,
  `Type` = the role (D4, D8). An unsigned note is written with the writer's
  name (D3).
- **Read:**
  - a note eDraft owns is authored by its `WriterName`, with its `Type` as the
    role, and reaches the editor as `Name (Role): words`;
  - a Final Draft note is authored by its `WriterName`, and its `Type` stays a
    category (D4);
  - in the editor and in Fountain, a role is read only from the `Name (Role)`
    form, never from "Name, Role".
- **Colour** is keyed on the name alone, ordered down the roster (IL-0016), so
  a person's role can change without their colour changing.
- **Two people with the same name are one person** to eDraft. That is the
  price of having no accounts, and the right one (D6). The writer can tell them
  apart by adding a role.

---

## 9. The notes report

**One command, one PDF.** On the Mac, File ▸ Export Notes Report…; on iOS and
iPadOS, the same in the document's share menu. eDraft already renders pages to
PDF on both platforms (`ScreenplayPageRenderer`, *measured* to exist in
`EDraftMacSurface` and `EDraftUIKitSurface`); PDF output itself is documented
platform capability (`NSPrintOperation`, `UIGraphicsPDFRenderer` — *documented*).

**Contents (A below, *judgement*):** a title block (script, date, "Open" or
"All"), then the threads grouped by scene in script order. Each thread shows:
page number (from eDraft's paginator), the anchored words quoted, status, and
every message as `Name · Role — date`, marked with the person's colour.

Options for its shape — a taste call:

| Option | What | For | Against |
|---|---|---|---|
| **A. A notes memo** (recommended — *judgement*) | Threads only, grouped by scene | Fast to read, fast to send, like a producer's notes document | Loses the line's context beyond the quoted words |
| B. An annotated script | Every page, notes in the margin | Full context | Long; margins at screenplay width are narrow; heavy to render |
| C. Both, chosen at export | An option in the export sheet | Serves both uses | A choice where the brief asks for one click |

"One click" (principle 7) means the command exports A with the current
filter; B or C would be a second, deliberate step.

---

## 10. Interface — judgement

Mechanics are settled above; how they look is a taste call. Each option
states its evidence. Principles from
[APPLE-PLATFORM-GUIDE.md](APPLE-PLATFORM-GUIDE.md) §0 apply throughout:
"the platform does the work", and "controls float over a canvas, never over
the thing being read" (§0.3).

### 10.1 Where threads live on the Mac

| Option | What | Evidence | For | Against |
|---|---|---|---|---|
| **A. The card grows a conversation** | Today's one-card-per-line `NoteCard` gains replies, authors and status | `NoteCard`'s own doc comment models it on Pages' comment card (*the code's claim, not checked here; no official guidance on comments — my judgement*) | Continuity; the card is already where writers look; one line's notes stay together | A long thread makes a tall card beside a short line |
| B. A trailing inspector | A notes inspector listing threads, the selected line's first | Inspector presentation is a documented API (`NSSplitViewItem` inspector, SwiftUI `inspector` — *documented*) | Room for long threads, filters, the report command | Takes page width; separates a note from its line |
| C. A popover from a margin mark | A small mark per line; click opens the thread | Popovers: *documented* (HIG, Popovers — transient, dismissed by clicking outside) | Minimal chrome while writing | Transient: a thread disappears when you click back into the script |

*Judgement:* A, with B as the list view for many threads and the report — the
card for "what did we say about this line", the inspector for "what is still
open".

### 10.2 Adding a note without interrupting

| Option | What | Evidence | For | Against |
|---|---|---|---|---|
| **A. ⇧⌘K opens the line's card, focus in a new message** | Return commits; Escape cancels; either way the caret returns exactly where it was | ⇧⌘K is eDraft's current shortcut (*measured*, `MainMenu.swift`); that Pages uses it for comments is my recollection, *unverified here; no official guidance — my judgement* | Known shortcut; no new surface | The card appears beside the page |
| B. A quick-note field at the line | A one-line field attached to the line; Return commits | *No official guidance — my judgement* | Fastest capture | A second editing surface to maintain |
| C. Type `[[` in the script | The note is written inline, Fountain-native | *Measured:* the parser moves it before its paragraph (§2.1) | Zero UI; a keyboard writer never leaves the text | The note jumps when parsed; the words must then be quoted |

*Judgement:* A, keeping C working for writers who already type `[[`.

### 10.3 Author at a glance

`Name · Role` and the person's colour are decided (D5). The choice is density:

| Option | For | Against |
|---|---|---|
| **A. Colour dot + `Name · Role` on every message** | Unmissable | Wide on a narrow card |
| B. Colour dot + initials; full `Name · Role` on hover | Compact | Hover does not exist on iOS; initials collide |
| C. Colour bar on the card edge + `Name · Role` | Colour readable at a distance | Weaker than a dot for one message among many |

*No official guidance — my judgement:* A on the Mac, A on iOS.

### 10.4 Resolved fades

| Option | For | Against |
|---|---|---|
| **A. Dimmed, replies collapsed** | Still findable in place; "fades, never deletes" literally | Visual noise on lines with many resolved threads |
| B. A one-line "Resolved" chip | Quiet | One click from the words |
| C. Hidden unless the filter is "All" | Cleanest page | Resolved threads disappear from view, which reads as deletion |

*Judgement:* A, with the Open/All filter (default Open) in the inspector (10.1B).
Dimming uses the system's secondary label colours, not a hand-set opacity, so
Increase Contrast and Dark Mode keep it legible (*documented:* dynamic system
colours adapt to accessibility settings).

### 10.5 iOS and iPadOS

| Option | What | Evidence | For | Against |
|---|---|---|---|---|
| **A. The inspector** | Same inspector as the Mac; presents as a sheet in compact width | SwiftUI `inspector` adapts to a sheet in compact size classes (*documented*) | One implementation, both platforms | A sheet covers the script on iPhone |
| B. A notes list in the navigator | Threads beside the scene list (today's StoryPanel) | *My judgement* | Already where iOS shows notes (IL-0026) | Far from the line |
| C. Inline cards between lines | The thread expands below its line | *No official guidance — my judgement* | Closest to the words | Breaks the page's reading |

Resolving: a swipe action on a thread in the list (*documented:* HIG, swipe
actions on list rows), and a button in the card.

---

## 11. The stages — one lock each

Each stage is its own lock with its own Vibe Check; each keeps every
constraint in §2.3; each proves itself on the anonymised Final Draft-written
fixtures, in both engines (TypeScript and Swift, pinned by the shared corpus)
and through the app's path; and each new proof fails on the code before it.
Where a stage writes something Final Draft will read, eDraft prepares a probe
file and the human opens and saves it in Final Draft before the lock is
committed.

### Stage 1 — round trip

- **Builds:** the header grammar (§4.1), reader and writer, in both engines.
  eDraft's notes in an FDX document are written into `<ScriptNotes>` (§4.2),
  one message each — no longer as body `Note` paragraphs. Notes eDraft owns
  come back editable on reopen; Final Draft's stay read-only. The Fountain
  writing rules of §4.4, including the fix for today's `]]]` bug. "Your name
  for notes", asked once. D3, D4 on write.
- **Anchor for now:** a new thread's Range is its whole paragraph; words come
  in stage 4.
- **Proofs:**
  - a save with no edit stays byte-identical;
  - a note added, saved and reopened comes back identical, editable, with its
    author and role;
  - Final Draft's notes keep every byte but their Ranges;
  - a body `Note` paragraph stays a paragraph;
  - a note ending in `]` round-trips.
- **Final Draft check:** eDraft's notes open in Final Draft as notes, with
  their authors; the header and every note survive a Final Draft save; eDraft
  reads them back as its own.
- **Built in IL-0041 (2026-09-18, a clean re-run of the first attempt), cut
  to the FDX notes and the name; committed in `fbd7eb9` with IL-0042 and
  IL-0043:**
  - A note written in eDraft is one ScriptNote: header, message, the writer's
    name, a Range over its line's paragraph. No attribute Final Draft does not
    define. `writeFdx` writes notes the same way.
  - eDraft's notes come back as the writer's own on reopen. Stage 1 pairs them
    by line and words, so an edited note is written again as a new note (new
    Id and date). Keeping a note's identity through an edit waits for the
    carrier stages 2 and 3 need (below).
  - Amended by IL-0042 and IL-0043, after the human's Final Draft checks: no
    header line. The title reads `[eDraft]`, the author field is the name, the
    role is `Type`, and the words appear once (D4, D8, D9).
  - A note after the last line is anchored to the last paragraph, so it
    reopens in front of that line.
  - "Your name for notes", with an optional role, is asked on the Mac at the
    first note. Cancel adds no note. The account-name seed is gone. The phone
    writes ScriptNotes signed with the name its Settings holds, and has no
    prompt yet.
  - `Name (Role):` is read as an author, and colour keys on the name.
  - Fountain is unchanged: its notes keep §4.4's spelling and have no header
    yet.

### Stage 2 — threads

- **Carrier reopened (IL-0042).** Stages 2 and 3 were designed on the header
  line (`thread`, `reply-to`, `from`, `status`), which is no longer written
  into Final Draft notes. They need a new carrier before they are built.
  **Decided for `.draft` by [RFC-DRAFT-FORMAT.md](RFC-DRAFT-FORMAT.md)
  (§5.4, §12.1):** a thread is an anchor, its messages and a status history
  in `notes.json`. In FDX, later messages are further `[eDraft]` notes on the
  root's Range — decided in that RFC's S4, with a Final Draft check. The
  header fields below are superseded there.
- **Builds:** replies in the header (`thread`, `reply-to`, `from`), in FDX as
  "Re:" notes on the root's Range and in Fountain as lines of the thread's
  `[[ ]]`. Replying to a Final Draft note. Legacy "Re:" chains shown as
  threads, display only.
- **Proofs:** a thread of three messages round-trips in both formats; a reply
  to a Final Draft note leaves that note's bytes unchanged; a thread survives a
  Final Draft save.
- **Final Draft check:** the thread shows as flat, named notes on the same
  words.

### Stage 3 — resolve

- **Builds:** `status`, `by`, `at` (§7); resolving a Final Draft note by
  adding a message; reopening; the fade and the filter.
- **Proofs:** resolving writes one header change, or one new message, and
  nothing else; a resolved thread survives a Final Draft save; a note never
  leaves the file by being resolved.

### Stage 4 — range anchors

- **Builds:** `on`/`nth` in Fountain (§5.2); the disambiguation rule (§5.3);
  FDX Ranges from the selected words; placement of an FDX thread in the editor
  (§5.4).
- **Proofs:** the rule's cases each pinned (first match, `nth`, words gone,
  fewer than N); a thread on a selection survives edits around its words in
  both formats; FDX ↔ Fountain conversion keeps the words.
- **Final Draft check:** a note eDraft anchored to words shows on those words
  in Final Draft, and keeps them through a Final Draft save.

### Stage 5 — report export

- **Builds:** §9 option A (or as decided), on both platforms.
- **Proofs:** the report lists every open thread with its page and words; the
  page numbers match the printed script; no real script text in any fixture.

### Stage 6 — polish

- **Builds:** the §10 options as chosen; accessibility (VoiceOver reads
  author, role, status; Dynamic Type on iOS); keyboard navigation between
  threads.
- **Proofs:** the checks in APPLE-PLATFORM-GUIDE.md §7 ("definition of done
  for any piece of UI"), measured with the harness in §6 of that guide.

### Stage H — the highlight carrier (follow-up, after stage 1)

Final Draft erases eDraft highlights on its first save (§3, fact 2), so the
highlighter's FDX carrier (RFC-HIGHLIGHTER D5) is not a carrier at all for a
file that visits Final Draft. Options:

| Option | What | For | Against |
|---|---|---|---|
| **A. Final Draft's own highlighting**, if it has one | Write whatever attribute Final Draft itself writes for a highlighted word | Survives by definition; Final Draft users see it | *Unproven:* whether Final Draft 13.4 has text highlighting, and in what attribute. A probe answers it: highlight a word in Final Draft, save, read the bytes. |
| B. A ScriptNote per highlight | A note with a header `[eDraft highlight]` and the highlighted Range | Survives (fact 3); Ranges kept (fact 5) | Fills Final Draft's notes list with highlights |
| C. Warn, and keep them in eDraft only | A notice when an FDX document with highlights is saved | Honest | The loss stays |

The lock starts with A's probe; B is the fallback if Final Draft has no
highlight of its own. Until then, C's notice should ship with stage 1, since
stage 1 is when writers start sending eDraft files through Final Draft on
purpose.

---

## 12. Open decisions

1. **§10 choices:** the Mac surface (10.1), capture (10.2), density (10.3),
   the fade (10.4), and iOS (10.5). The *judgement* rows are recommendations,
   not decisions.
2. **The report's shape** (§9): A, B or C.
3. **The highlight carrier** (§11, stage H): run the probe first, then A or B.
4. **Root titles** (§4.2): the first 40 characters of the first message, or a
   title the writer types, as Final Draft users do.
5. **Default category** (§4.2): `Writer`, or the writer's own role when set.
6. **Where "Your name for notes" is first asked** (§8): at the first note (the
   recommendation), or in onboarding.

## 13. Risks still unproven

- **A Final Draft user edits a header by hand.** The note degrades to a plain,
  read-only note (§4.1). Measured: nothing yet — stage 1's Final Draft check
  includes an edited header.
- **Final Draft renumbering ids** on some save not yet seen. The probe kept
  every id (fact 3); `reply-to` depends on it. If it ever happens, the thread
  id still groups the messages; only reply order falls back to dates.
- **A Range deleted in Final Draft.** How Final Draft moves a note whose words
  it deletes is not yet probed (fact 5 covers an insertion before notes).
  Stage 4's Final Draft check includes a deletion.
- **Very long threads** in the card (10.1A). Measured when stage 2's UI
  exists.
- **The header seen raw** in other Fountain apps. It reads as metadata in
  Final Draft (fact 8); other tools are not checked.
- **`] ]` inside a note comes back as `]]` — a chosen asymmetry, not a
  discovered one** (IL-0038). The writer spells `]]` as `] ]` and the reader
  reads it back, so a note whose own text holds `] ]` returns as `]]`. A
  lossless spelling needs an escape for the escape, raw in every other
  Fountain tool. When this was chosen, 0 of 131 notes in 83 files held `] ]`.
- **A dialogue block a note already broke stays broken** (IL-0040). A file
  saved by a build before IL-0040 with a note inside a dialogue block holds
  `CUE`, the note and `Speech` as three paragraphs: in Fountain,
  blank-separated; in FDX, the cue and the speech as Action. That reads the
  same way as an action line in capitals followed by a note, so the reader
  cannot tell them apart. Recorded as permanent. A scan of 74 files found it
  only in sample02 and its copies, which are repaired by hand.
- **A line of spaces inside a note comes back empty — a chosen asymmetry**
  (IL-0111). The writer spells an interior blank line as two spaces, and the
  reader gives any line of nothing but spaces back empty, so a line the
  writer filled with spaces does not survive. A note an older build already
  broke stays broken: the blank line closed it, and its words reopened as
  script. A scan of the 12 text scripts on the owner's Mac found none.
- **A note the old writer already cut stays cut.** A file reopened and saved
  by a build before IL-0038 holds the note without its last `]`, followed by
  a paragraph that is only `]` (in FDX, an Action `]` after a Note). The
  pattern can be detected but not proven, because a writer could type exactly
  that: a note with more `[` than `]`, directly followed by a paragraph of only
  `]`. Recorded as permanent, since none was found in 83 files. If one
  appears, its repair is a lock of its own: an engine detector that reports,
  and a writer's click that repairs. Never automatic.
