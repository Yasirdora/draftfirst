# The `.draft` production contract — an addendum

*Written 2026-09-19 on branch `rename/edraft`, under lock IL-0051, as an
addendum to [RFC-DRAFT-FORMAT.md](RFC-DRAFT-FORMAT.md). It exists because
S1 landed the container and the reserved names in FORMAT §5.7 — `revisions.json`,
`production.json`, `history/` — still had no contract. The human's brief is
that `.draft` 1.0 is pre-release and the data contract is finished **now**,
before any app wiring freezes it. This document specifies those parts, the
FDX mapping for every production field, and the two state transitions a
production actually makes.*

*It does not contradict [RFC-NOTES-SYSTEM.md](RFC-NOTES-SYSTEM.md). Notes stay
word-anchored threads. It accepts [REVISIONS-PLAN.md](REVISIONS-PLAN.md)
line 89: no sidecars, no Fountain syntax, no hidden attributes; revisions
live in the package.*

*Every claim carries its evidence, as FORMAT does: **measured**, **sourced**,
**inference**, **judgement**, **unproven**. §3 to §11 are normative. MUST,
SHOULD and MAY are RFC 2119. Every example uses invented script text and
invented names; the repository is public.*

*This addendum amends FORMAT §5.7: the reserved names are specified here as
optional parts of `.draft` **1.0**. A development file may omit them. A
prepared or issued file MUST include those that FORMAT and this document
require for its state (§3).*

---

## 0. Decisions

### Settled — the human's (2026-09-19)

| # | Decision | Source |
|---|---|---|
| P1 | **`.draft` 1.0 is pre-release.** The data contract is finished now, before any app wiring freezes it. | Human, M0. |
| P2 | **FDX origin is forever.** An FDX-originated project retains `origin/source.fdx` byte-for-byte. FDX export uses the splice path (FORMAT §12.1). | Human, M0. FORMAT §5.6, evaluation-draft-format-plan §1. |
| P3 | **Production Mode is an explicit state transition.** "Prepare for Production" assigns scene numbers, takes the white-draft snapshot, and locks layout. It is not implied by saving, numbering, or printing. | Human, M0. |
| P4 | **A revision is issued, never painted.** eDraft computes the changes, picks the next colour in the run, records the issue, and creates the delivery. Nobody colours a line by hand. | Human, M0. REVISIONS-PLAN §0, `RevisionColour` in `Revisions.swift`. |
| P5 | **The document parts are:** `script.json` (title page + elements with a permanent DraftElementID), `notes.json` (word-anchored threads with provenance), `revisions.json` (ordered sets + immutable snapshots), `production.json` (locked scene numbers, page map + layout fingerprint, omissions, delivery settings), `origin/`, `history/`. | Human, M0. |

### Confirmed by this addendum — settled unless the human reopens them

| # | Proposal | Where |
|---|---|---|
| C1 | Prepare and Issue are **two** transitions. Prepare locks numbers and layout and writes the white snapshot. Issue Revision diffs against the last issued snapshot (or the white snapshot if none has gone out), records a set, and writes `history/<id>.json`. | §3, §11 |
| C2 | The mark on the words (`runs[].revisionID`) lives on `script.json`. The **set** it names lives in `revisions.json`. Neither duplicates the other. | §2, §6 |
| C3 | An omission keeps the scene's elements in `script.json` and records the omit in `production.json`. Restore deletes the record. The body is never copied into the omission. | §7.3 |
| C4 | A page lock is a pair of DraftElementID + UTF-16 anchors plus a layout fingerprint — never a bare "page 12". | §7.2 |
| C5 | Native FDX export of a prepared or issued script **without** `origin/source.fdx` is **Blocked**. Splice is the production export. Native `writeFdx` remains for development scripts and for eDraft-born files that never had an FDX. | §9 |

Open questions that this document will not guess are §13.

---

## 1. Relation to RFC-DRAFT-FORMAT

FORMAT §4–§14 remain in force. This addendum:

- **Adds** optional parts `revisions.json`, `production.json`, and
  `history/<id>.json`, and the rules for writing them.
- **Names** `script.json`'s `id` as **DraftElementID** in production prose.
  The wire field is still `id` (§4). FORMAT §6.1 is not reopened.
- **Does not** change `notes.json` (§5.4 of FORMAT, RFC-NOTES-SYSTEM). §5
  only states the FDX mapping and the one-source rule.
- **Does not** change the ZIP profile, I-JSON, must-preserve (§8.2), the
  recovery ladder, or the `.draft` PDF.

Entry order, amending FORMAT §4.2 for a prepared or issued file:

| Path | Required when | Written |
|---|---|---|
| `mimetype`, `manifest.json`, `script.json`, `script.fountain` | always | as FORMAT |
| `notes.json` | there are notes | as FORMAT |
| `revisions.json` | prepared or issued | after `script.fountain` |
| `production.json` | prepared or issued | after `revisions.json` |
| `history/<id>.json` | each issued set, and the white snapshot | after, id order |
| `origin/…` | the document has an origin | as FORMAT |
| `ext/…` | optional | last, name order |

A development file MAY omit `revisions.json`, `production.json` and
`history/`. Opening it never writes them (FORMAT §11.2).

---

## 2. One source of truth

Every production field has exactly one source of truth, one storage
location, and one preservation/export rule. If two places could hold it,
this table picks one. Fields that cannot be assigned are §13, not a second
column here.

| Field | Source of truth | Storage | Preserve / export |
|---|---|---|---|
| Title page lines | Writer | `script.json` `titlePage` | Fountain / FDX title page as today. |
| Script text, types, runs, dual, depth | Writer | `script.json` `elements` | FORMAT §5.3. FDX splice if origin; else native. |
| DraftElementID | Writer, assigned at create | `script.json` `id` / `nextId` | Never FDX. Lost on Fountain. Said on those exports. |
| Scene number as printed | Production, after Prepare | `script.json` `sceneNumber` | FDX scene heading number; splice keeps surrounding XML. |
| Scene-number **lock** | Production | `production.json` `sceneNumbers.locked` | Not an FDX attribute of its own; implied by issued numbers. |
| Revision **set** (colour, mark, name, order, time) | Issue Revision | `revisions.json` `sets` | FDX `<Revisions><Revision>`. Splice keeps unknown attrs. |
| Revision **mark on words** | Issue Revision (computed) | `script.json` `runs[].revisionID` | FDX `Text/@RevisionID`. The id names a set in `revisions.json`. |
| Last issued snapshot | Issue Revision | `history/<set id>.json` | Not exported. The FDX file is not a snapshot store. |
| White snapshot (prepared, not yet issued) | Prepare | `history/prepared.json` | Not exported. |
| Page lock (boundaries) | Prepare / Issue | `production.json` `pages.locks` | FDX `<LockedPage>` is **Regenerated** from this map on native export; **Preserved** on splice. |
| Layout fingerprint | Prepare | `production.json` `pages.fingerprint` | Not an FDX field. Mismatch is **Warned** on open. |
| Omission | Writer, after Prepare | `production.json` `omissions` | FDX `<OmittedScene>`. Body stays in `script.json`. |
| Tag **definitions** | Production | `production.json` `tags` | FDX `<TagData><TagDefinition>`. |
| Tag **marks on words** | Writer | `script.json` `runs[].tagNumbers` | FDX `Text/@TagNumber`. FORMAT §5.3. |
| Notes (threads, anchors, messages, status) | Writer / import | `notes.json` | RFC-NOTES-SYSTEM; FORMAT §5.4, §12.1–12.2. |
| FDX origin bytes | Import | `origin/source.fdx` | Never rewritten. Export splices a **copy**. |
| Fountain origin bytes | Upgrade | `origin/source.fountain` | FORMAT §5.6. |
| Fountain rendition | Save | `script.fountain` | Never authoritative (FORMAT §5.5). |
| Delivery (Mores & Continueds, headers on/off) | Production | `production.json` `delivery` | FDX header/footer and more/continued flags: **Regenerated** from this on native; **Preserved** on splice. |
| Unknown FDX XML | The origin file | `origin/source.fdx` | **Preserved** by splice. **Blocked** on native production export without origin. |
| Unknown `.draft` parts and members | The other tool | those parts / members | FORMAT §8.2. |

The fingerprint of the **script** remains `manifest.fingerprints.script` (JCS
of `script.json`). Notes, revisions and production do not change it
(FORMAT §7.5). A second fingerprint, `fingerprints.production`, MAY be
written when `production.json` is present — JCS of that part — so two
files can be compared as "same script, same production lock". It is
optional in 1.0.

---

## 3. Script states

`production.json` `state` is one of four strings. The file's other parts
MUST match the state. A reader that sees a contradiction MUST say so and
MUST NOT silently pick one.

### 3.1 `development`

The default. Scene numbers MAY be absent, present as writer furniture, or
reassigned freely. `revisions.json`, `production.json` and `history/` are
absent, or `production.json` exists with `"state": "development"` and
`sceneNumbers.locked` false.

Saving, printing and exporting Fountain or native FDX do not change the
state. Opening never writes (FORMAT §11.2).

### 3.2 `prepared`

The writer has run **Prepare for Production**. After a successful prepare:

- every scene heading has a `sceneNumber`;
- `production.json` has `"state": "prepared"`, `sceneNumbers.locked: true`,
  and a page map with a layout fingerprint;
- `history/prepared.json` holds the white snapshot (§8);
- `revisions.json` exists with `sets: []` (nothing has gone out yet).

Scene numbers MUST NOT be reassigned. A new scene takes a letter against
its neighbour (`SceneNumbering`, already built). Layout that would move a
locked page boundary is **Warned** and does not silently rewrite the map.

Prepare is reversible until the first Issue: **Revert to Development**
drops the lock, the page map, and `history/prepared.json`. It MUST say
what it will discard. After the first Issue, revert is **Blocked**.

### 3.3 `issued`

At least one revision set has been recorded. `state` is `issued`.
`revisions.json.sets` is non-empty. Each set names an immutable snapshot
under `history/`. The current `script.json` MAY differ from the last
snapshot — that difference is the next issue's diff.

Issue Revision is the only path that appends a set. Painting a colour onto
a run by hand is **Blocked**.

### 3.4 `archived`

A terminal copy: the production is over, or a season is closed. `state` is
`archived`. Issue Revision is **Blocked**. Edits to the script are
**Warned** (the file is a record). Export still splices. A new season is a
new document, or a future minor version that records a run-reset (§13 Q1).

---

## 4. DraftElementID

FORMAT §6.1, named here because production features point at it.

### 4.1 Format

- Wire field: `script.json` `elements[].id`.
- Alphabet: `A–Z a–z 0–9 _ -`, length 1 to 64, unique in the file.
- eDraft writes a counter in base 36 (`1`, `2`, … `z`, `10`, …) and stores
  the next unused value as `nextId`.
- An id is never reused, even after its element is deleted.
- An id carries no meaning and MUST NOT be interpreted (no "S12", no UUID
  in 1.0). *Measured, FORMAT §6.1:* counter ids are the size win against
  FDX.

### 4.2 Where it is stored

Only `script.json`. Notes, omissions, page locks, and history snapshots
**refer** to it. They MUST NOT mint a parallel id for an element.

### 4.3 Survival

A DraftElementID MUST survive save, reopen, and every edit that leaves the
element in place.

| Edit | Ids |
|---|---|
| Typing, style, split (first half) | Kept on the surviving / first element. |
| Merge | The first element's id is kept; the second is retired, never reused. |
| Paste, duplicate | New ids from `nextId`. |
| Undo / redo | Restores retired ids. |
| Prepare, Issue, omit, restore | Ids unchanged. |

Fountain has nowhere to keep an id. A text `.draft` or `.fountain` import
assigns new ids on parse (FORMAT §6.1). FDX has no element id; splice
identity is the origin paragraph, not a DraftElementID. Native FDX export
**loses ids** and MUST say so (FORMAT §12.1 "Lost, and said").

### 4.4 History snapshots

A snapshot stores the `script.json` of that moment, including ids. Diffing
Issue Revision matches elements by DraftElementID first, then by the
existing `RevisionDiff` (trim head/tail, LCS on the middle,
`Revisions.swift`). An id that exists on both sides is the same line even
if its text changed. *Inference* from P4 and FORMAT §6.1; the matching
rule is the engine's to implement, not this file's to recode.

---

## 5. `notes.json`

FORMAT §5.4 is the schema. RFC-NOTES-SYSTEM is the behaviour. This
addendum does not add members.

### 5.1 Source of truth

| Field | Storage | FDX |
|---|---|---|
| Thread id, message id, `nextId` | `notes.json` | Not FDX ids. A new ScriptNote takes the next free FDX `Id` on export (NOTES D8, probe). |
| Anchor (element, UTF-16 range, quote, prefix, suffix) | `notes.json` `anchor` | `Range` over those words, IL-0031 counting. |
| Author, role, time, text | `messages[]` | `[eDraft]` title; `WriterName`; `Type` = role; body = words (NOTES D4, D8). |
| Status history | `status[]` | No FDX carrier in 1.0. **Lost, and said** on FDX export until NOTES S4 (FORMAT §12.1). |
| Provenance | `messages[].source` | `{ "fdx": "<RefId>" }` for a Final Draft–owned note. Splice keeps that ScriptNote; eDraft never rewrites it (NOTES D2). |

### 5.2 Status against FDX ScriptNotes

**Editable** for eDraft-owned threads (`Name` = `[eDraft]`).
**Preserved** for Final Draft–owned ScriptNotes (origin bytes + Range
maintenance, IL-0033).
**Warned** when an imported note cannot be re-anchored (FORMAT §6.5
ladder).
**Blocked:** rewriting a Final Draft–owned note's body or title.

Colour of a note is display, never stored (NOTES D5). FDX `Color` on a
ScriptNote is **Preserved** on splice and **not** copied into `notes.json`.

---

## 6. `revisions.json`

I-JSON, integers only, member order as FORMAT §5.1. Unknown members
survive (§8.2 of FORMAT).

```json
{
  "sets": [
    {
      "id": "1",
      "colour": "White",
      "mark": "*",
      "name": "White draft",
      "at": "2026-09-01T12:00:00Z",
      "snapshot": "history/prepared.json"
    },
    {
      "id": "2",
      "colour": "Blue",
      "mark": "*",
      "name": "Blue revisions",
      "at": "2026-09-18T10:00:00Z",
      "snapshot": "history/2.json"
    }
  ],
  "nextId": "3"
}
```

### 6.1 Fields

| Member | Rule |
|---|---|
| `sets` | Ordered. Index 0 is the first issue (white, unless the production skipped — the colour string says so). A set is immutable once written. |
| `sets[].id` | Same alphabet as DraftElementID, unique in this file. eDraft writes a counter. FDX `Revision/@Number` maps here on import when the origin is first converted; after that the `.draft` id is truth and FDX Number is regenerated on native export. |
| `sets[].colour` | A name from the run in `Revisions.swift`: White, Blue, Pink, Yellow, Green, Goldenrod, Salmon, Cherry, Buff, then Double White, Double Blue, … A production MAY skip; it MUST NOT invent a colour outside the run in 1.0. |
| `sets[].mark` | The margin mark, usually `"*"`. |
| `sets[].name` | Optional display name (`"First Revision"`). |
| `sets[].at` | RFC 3339 UTC, the issue time. This is production content, not a file-system date (FORMAT §5.2 forbids dates in the **manifest**). |
| `sets[].snapshot` | Path of the immutable snapshot in this package. |
| `nextId` | Next unused set id. |

There is no `currentColour` pointer. The last set **is** the current
issue. The next colour is `RevisionColour.next` of that set's colour,
unless Issue Revision is told to skip.

### 6.2 Marks on words

Issue Revision diffs the current script against the snapshot of the last
set (or `history/prepared.json` if `sets` is empty). Every changed element
receives a run covering its text with `revisionID` equal to the new set's
`id`. Assigning a scene number is not a change (REVISIONS-PLAN §2).
Deletions that become omissions are recorded in `production.json`, not as
a mark on a missing line.

Hand-editing `revisionID` is **Blocked**. Clearing marks except by Restore
of an omission or by Revert-to-Development (before first issue) is
**Blocked**.

### 6.3 FDX

| FDX | Status | Rule |
|---|---|---|
| `<Revisions>` / `<Revision Color Mark Name Number>` | **Editable** | Sets. Unknown attributes **Preserved** on splice. |
| `Text/@RevisionID` | **Editable** | `runs[].revisionID`. |
| Paragraph-level `Revised` | **Regenerated** | Derived from whether any run on the paragraph has a `revisionID`. Not stored separately. |
| Deleted-text marks (struck content kept in FDX) | **Preserved** | Origin only. eDraft's script is the current text. Native export without origin **Warned** (those marks will not appear). |

---

## 7. `production.json`

```json
{
  "state": "issued",
  "sceneNumbers": {
    "locked": true
  },
  "pages": {
    "fingerprint": {
      "paginator": "1.0",
      "paper": "us-letter",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    "locks": [
      {
        "label": "1",
        "start": { "element": "1", "offset": 0 },
        "end": { "element": "8", "offset": 0 }
      },
      {
        "label": "1A",
        "start": { "element": "8", "offset": 0 },
        "end": { "element": "12", "offset": 0 }
      }
    ]
  },
  "omissions": [
    {
      "id": "1",
      "number": "3",
      "elements": ["20", "21", "22"],
      "issued": "2"
    }
  ],
  "tags": [
    { "id": "t1", "label": "INT. KITCHEN kettle" }
  ],
  "delivery": {
    "moreAndContinueds": true,
    "sceneNumbersOnRight": true
  }
}
```

### 7.1 Scene-number lock

`sceneNumbers.locked` is the boolean Prepare sets. The numbers themselves
stay on the scene elements (`script.json` `sceneNumber`) so the paginator
and Fountain serialiser keep a single field (already `SceneNumbering` /
`sceneheading.json`).

After lock: existing numbers MUST NOT change; inserts take letters; an
omit keeps its number (§7.3). Number New Scenes as a separate command is
**Blocked** while locked. Whether Issue Revision also numbers new scenes
is §13 Q2; 1.0 leaves numbering to Prepare and to the lettering rule.

### 7.2 Page locks

A lock is **not** `"page": 12`. It is:

- `label` — what the page says in the corner (`"12"`, `"12A"`).
- `start`, `end` — `{ "element": "<DraftElementID>", "offset": <UTF-16> }`.
  `end` is exclusive. Offsets follow FORMAT §6.2.
- The ordered `locks` array is the whole issued script, every page, in
  reading order. A gap is a bug; a reader MUST say so.

`fingerprint` records the paginator identity (`"1.0"`), the paper, and a
SHA-256 of the canonical inputs that produced this map (paper, margins,
element text, scene numbers). *Judgement:* the exact input list is the
paginator's, pinned when S? (page-lock implementation) writes fixtures.
If the current script + current paginator do not hash to `sha256`, the
file opens, the map is kept, and the writer is **Warned** that pages may
not match the issued binder. The map is never silently rebuilt.

On FDX splice, `<LockedPages>` in the origin is **Preserved** (byte for
byte) while the origin exists — the origin **is** the FDX page lock.
`production.json` `pages` is still written, as eDraft's own map, so a
Mac/iOS print uses it. They can disagree; that is **Warned**, not merged.
On native FDX export (development only, or eDraft-born), `<LockedPage
Number>` is **Regenerated** from `label`s that parse as integers; `"12A"`
has no FDX Number and is **Warned**.

### 7.3 Omissions

An omission is a reversible scene-range record.

| Member | Rule |
|---|---|
| `id` | Unique in `omissions`. |
| `number` | The scene number as locked. Kept so schedules do not grow a hole. |
| `elements` | DraftElementIDs of the omitted range, in script order, inclusive. MUST be a contiguous span starting at a scene heading. The elements **remain** in `script.json` with their text. This is the retained body. |
| `issued` | Optional set id: which issue omitted them. Provenance. |

Rendering: the span prints as an OMITTED card carrying `number`
(`SceneNumbering` already maps `OMIT` / `OMITTED` / `OMIT-` to the card).
The body MUST NOT print. Restore removes the record; the elements print
again; ids unchanged.

Omit is **Blocked** in `development` (numbers are not addresses yet).
Restore of an omission that was in an issued snapshot is itself a change
and MUST go out on the next Issue.

FDX `<OmittedScene>`: **Editable** as this record. Nested heading text
inside the FDX block is **Preserved** on splice; eDraft's body is
`script.json`. On native export, write `<OmittedScene>` wrapping the
retained heading as today's tests do (`fdx.test.ts`).

*Shipped, and not yet this record:* the engine reads an FDX
`<OmittedScene>` into `Screenplay.omissions` as a span of **element
indices** (`{ start, end }`), not DraftElementIDs — IL-0071 (`cdcc477`),
written before an element carried an identity. `.draft` is unaffected:
`production.json` carries the id-shaped record above, and `script.json`
holds `titlePage`, `elements` and `nextId` only, so the index span is
never written to a file. Migrating it onto M1's identities is **Q13**.

### 7.4 Tags

`tags` is the definition list (`id`, `label`). Marks on words stay
`runs[].tagNumbers` (FORMAT §5.3) — integers that name `tags[].id` when
the id is numeric as FDX writes it, or a 1.0 **judgement**: FDX
`TagDefinition/@Id` is stored as the string `id` here and as the same
token in `tagNumbers` when it is an integer. Non-integer FDX ids are
§13 Q3.

FDX `<TagData>`: **Editable** (definitions) + **Editable** (marks).
Unknown TagData children: **Preserved** on splice.

### 7.5 Delivery

`delivery` holds print behaviour the paginator already understands or
will: Mores & Continueds on/off, scene numbers on the right, header
visibility. It is not ElementSettings XML.

FDX `ElementSettings`, `HeaderAndFooter`, page size and margins:
**Preserved** on splice; **Regenerated** from `delivery` + the app's
current page setup on native export. Watermarks, view state, zoom, caret:
not in `.draft`. **Preserved** in origin if present.

---

## 8. `history/` snapshots

Each file is a JSON object:

```json
{
  "kind": "snapshot",
  "of": "script",
  "set": "2",
  "script": { "titlePage": [], "elements": [], "nextId": "9" }
}
```

| Member | Rule |
|---|---|
| `kind` | Always `"snapshot"`. |
| `of` | `"script"`. 1.0 snapshots the script only. |
| `set` | The `revisions.json` set id, or `"prepared"` for `history/prepared.json`. |
| `script` | A complete `script.json` object (same schema as FORMAT §5.3), the document at that issue. |

Snapshots are **immutable**. A writer MUST NOT save over an existing
`history/<id>.json`. A new Issue writes a new path.

`of: "script"` means notes, revisions and production are not inside the
snapshot. Diffing Issue Revision compares script elements. Whether a
later minor version also snapshots notes is §13 Q4.

The white snapshot is `history/prepared.json`, written by Prepare, with
`"set": "prepared"`. The first Issue MAY point its `snapshot` at that
file (the white draft going out unchanged) or MAY write `history/1.json`
if the script moved between Prepare and Issue.

---

## 9. FDX mapping — the five statuses

### 9.1 Statuses

| Status | Meaning |
|---|---|
| **Editable** | eDraft models it. The writer can change it. Export writes it from the model. |
| **Preserved** | eDraft does not edit it. Origin bytes (or unknown members) round-trip. Splice re-emits them. |
| **Regenerated** | Derived. eDraft recomputes it. The FDX copy is not truth. |
| **Warned** | Import or export loses or disagrees; the writer is told. The file still opens. |
| **Blocked** | eDraft refuses the action. The destructive path is not offered. |

A feature MAY have a different status on the **splice** path and the
**native** path. The table says so. Default for unknown XML: **Preserved**
on splice, **Blocked** on native export of a prepared/issued file without
origin (C5).

### 9.2 Feature table

| FDX feature | Status | `.draft` home |
|---|---|---|
| Revision sets (`<Revisions>`, Color/Mark/Name/Number) | **Editable** | `revisions.json` `sets` |
| `Text/@RevisionID` | **Editable** | `script.json` `runs[].revisionID` |
| Paragraph `Revised` | **Regenerated** | from runs |
| Deleted-text marks | **Preserved** (splice); **Warned** (native without origin) | origin only |
| Locked pages (`<LockedPage Number>`) | **Preserved** (splice); **Regenerated** / **Warned** for A-pages (native) | `production.json` `pages` is eDraft's map |
| A/B page labels | **Editable** in eDraft; FDX Number cannot hold `"12A"` | `pages.locks[].label` |
| Scene numbers, including `12A` | **Editable** after Prepare | `script.json` `sceneNumber` |
| Scene-number lock | **Editable** | `production.json` `sceneNumbers.locked` |
| Omissions (`<OmittedScene>`, `Length="0"`) | **Editable** | `production.json` `omissions`; body in `script.json` |
| ScriptNotes, eDraft-owned (`Name="[eDraft]"`) | **Editable** | `notes.json` |
| ScriptNotes, Final Draft–owned | **Preserved** | origin + Range; `source.fdx` |
| Thread status on FDX | **Warned** (lost on export, FORMAT §12.1) | `notes.json` `status` |
| Tags (`TagNumber` / `<TagData>`) | **Editable** | runs + `production.json` `tags` |
| Dual dialogue (`<DualDialogue>`) | **Editable** | `script.json` `dual` (already) |
| `SceneProperties` Title, Color | **Preserved** (splice). Not in 1.0 model | origin. §13 Q5 |
| `SceneProperties` Length | **Regenerated** | paginator |
| `SceneProperties` Locked | **Editable** as scene-number lock, not a per-scene FDX flag | `sceneNumbers.locked` |
| `SceneArcBeats` / `CharacterArcBeat` | **Preserved** | origin |
| `StartsNewPage` | **Editable** | `script.json` type `pagebreak` / existing pagebreak elements |
| Title page paragraphs | **Editable** | `script.json` `titlePage` |
| Title-page header/footer XML, `AttributedTitle` | **Preserved** (splice); **Regenerated** (native from `delivery`) | `production.json` `delivery` |
| Page layout, margins, watermark | Layout **Regenerated** from app + `delivery`; watermark **Preserved** in origin | `delivery` + origin |
| `ElementSettings` / `FontSpec` | **Preserved** (splice); **Regenerated** (native) | not modeled |
| Mores & Continueds | **Editable** as a boolean | `delivery.moreAndContinueds` |
| Custom paragraph `Type` | **Warned** on import; stored as `general` plus unknown member `fdxType` if present | `script.json` element; must-preserve the member |
| Unknown XML, future FD elements | **Preserved** (splice); **Blocked** (native production export without origin) | `origin/source.fdx` |
| SmartType lists | **Regenerated** | not stored. *Sourced:* FD's own "Rebuild SmartType Lists"; evaluation-draft-format-plan §2. |
| Macros, spell-check dictionaries, view/window/caret | **Preserved** in origin if present; not in `.draft` | origin |
| Cast list (`CastMember`) | **Preserved** (splice). Not in 1.0 model | origin. §13 Q6 |
| Alts, bookmarks, `DocumentRef` | **Preserved** (splice). Not in 1.0 model | origin. §13 Q6 |
| Dual-dialogue parentheticals and emphasis | **Editable** | ordinary elements/runs inside the dual pair |
| Unicode / RTL in text | **Editable** | `script.json` `text` is Unicode. FDX entities as today's codec. |

### 9.3 Export preference — forever

1. If `origin/source.fdx` exists → **splice**. Unchanged paragraphs keep
   their bytes (IL-0024–IL-0033). *Measured:* rebuilding from the
   screenplay drops revisions, locked pages, tags, deleted marks (fdx.ts
   comment; `fdx.test.ts` production fixture).
2. If no origin and `state` is `development` → native `writeFdx`.
3. If no origin and `state` is `prepared`, `issued` or `archived` →
   **Blocked**. The writer is told to keep the origin or to export Fountain
   / PDF / changed-pages from eDraft.

P2 is this list. Native generation of a shooting script is not a 1.0
promise.

---

## 10. Versioning

FORMAT §8.1–§8.2 apply. This section states how they read for production
parts.

`version` remains `1.0` for files this addendum describes. The contract is
pre-release (P1) but the **major.minor** is 1.0, so shipping readers and
this specification do not fork.

### 10.1 A 1.0 reader and a 1.1 file

A later minor version may add optional members or parts (FORMAT §8.1).
`minReader` says whether 1.0 may **edit**.

- Same major, `minReader` ≤ 1.0: 1.0 opens and edits. Unknown parts and
  members are **Preserved** (FORMAT §8.2). A 1.0 writer MUST NOT strip
  `revisions.json`, `production.json`, `history/`, or unknown members of
  those objects.
- Same major, `minReader` > 1.0: 1.0 opens **read-only** and says a newer
  eDraft is needed to edit.
- Higher major: 1.0 **refuses**.

A 1.0 reader MUST NOT rebuild a page map, reissue a colour, or "helpfully"
drop `history/` to save space.

### 10.2 A 1.1 reader and a 1.0 file

Opens and edits. Missing `revisions.json` means `development` (or
`production.json.state` if present). The first Prepare or Issue writes
the 1.0 parts this addendum specifies. Opening still writes nothing.

### 10.3 Must-preserve, applied

A conforming editor MUST write back every production part it does not
understand, every history snapshot it did not create, and every unknown
member of `sets[]`, `omissions[]`, `locks[]`, and `tags[]`, in the order
read, after the members it knows.

Dropping a scene drops its id. Omissions and page locks that name a
missing id are **Warned** and kept (the record is the production's, not
the script's). They are not silently deleted.

---

## 11. Prepare for Production, and Issue Revision

### 11.1 Prepare for Production

Offered only in `development`. On confirm, eDraft MUST:

1. Assign scene numbers (`SceneNumbering`) to every scene heading that
   lacks one, without treating that assignment as a revision mark.
2. Set `production.json` `state` to `prepared`, `sceneNumbers.locked` to
   true.
3. Paginate, write `pages.locks` from real page boundaries (element +
   offset) and `pages.fingerprint`.
4. Write `history/prepared.json`.
5. Ensure `revisions.json` exists with empty `sets`.

It MUST NOT pick a colour. It MUST NOT write `runs[].revisionID`.

### 11.2 Issue Revision

Offered in `prepared` or `issued`. On confirm, eDraft MUST:

1. Diff current `script.json` against the last snapshot (prepared, or
   `sets[last].snapshot`).
2. Pick the next colour in the run (pre-filled, editable to skip).
3. Append an immutable set; stamp changed runs with that `revisionID`.
4. Record new omissions; letter new pages (`12A`) without moving existing
   labels.
5. Write `history/<id>.json`; set `state` to `issued`.
6. Offer delivery: full script or changed pages only (REVISIONS-PLAN §3).
   Both print asterisks via `PageLine.element`, not by teaching the
   paginator (REVISIONS-PLAN §2).

The colour of a set that has gone out is forever. There is no "paint this
line blue."

### 11.3 Title-page revision line

**Regenerated** at print/export from the last set (`"Blue Revised
18/9/26"`). Not stored as a title-page line unless the writer typed it.
If they typed it, it is ordinary `titlePage` text (**Editable**) and
Issue MUST NOT overwrite it. *Judgement:* prefer generated header over
mutating the title page; Q7 if productions require the line in
`script.json`.

---

## 12. Fixture inventory

Invented names only in anything we add. Counts only for files the human
already has.

| Need | In the repo today | Must be made |
|---|---|---|
| Clean script (development `.draft`) | `Fixtures/draft.json` kettle sample (S1) | — |
| Fountain parse corpus | `parse.json` and the named sources it pins | — |
| FDX authoring surface, dual dialogue, ScriptNotes, RevisionID on runs | `finaldraft-sample01.fdx`, `finaldraft-sample02.fdx` (Final Draft–written, anonymised; comment forbids resave through eDraft) | — |
| FDX splice of LockedPages + Revisions + TagData | Inline `PRODUCTION_FDX` in `packages/edraft/src/fdx.test.ts` (not a fixture file) | Promote to `Fixtures/` as a named FDX, invented text |
| Omitted scenes | Grammar in `sceneheading.json`; `<OmittedScene>` in `fdx.test.ts` | A dedicated FDX and a `.draft` with `production.json` omissions |
| Revised script (issued, marks on words, history snapshot) | — | `history/` + `revisions.json` case in the draft corpus |
| Locked shooting script (page map + fingerprint) | — | prepared/issued `.draft` fixture |
| Tags as TagData + TagNumber | sample01/02 carry TagNumbers; definitions in the inline production FDX | One `.draft` with `production.json` `tags` |
| Notes, word-anchored | `draft.json` notes; RFC-NOTES-SYSTEM probes | Production-state notes (status + fdx provenance) in the draft corpus |
| Dual dialogue | sample01/02; kettle has `dual: true` | Issued-state dual pair (ids stable across Issue) |
| Unicode | kettle (`doesn’t`, emoji in S1 detect) | RTL / combining marks in a production `.draft` |
| Malformed FDX | Hostile/recovery tests exist for `.draft` ZIP; FDX errors are codec tests | A truncated FDX and a dual-dialogue cut in half, as named fixtures |
| Real production draft (19 revisions, 25 locked pages, 248 tags) | **Not in the repo.** *Measured* in `fdx.ts` comments against a file on this machine. Counts only. | Do not add that file. Build invented fixtures that hit the same **classes**. |

Implementation locks after this charter MUST add the "Must be made"
rows to `apple/eDraftEngine/Fixtures/` via `engine:conformance`, not by
hand-editing JSON.

---

## 13. Open questions

Named, not guessed. None blocks encoding P1–P5.

| # | Question | Why it is open |
|---|---|---|
| Q1 | Per-episode / per-season colour run reset: does the run restart, and where is that recorded? | REVISIONS-PLAN §6. `archived` then a new file is the 1.0 answer; a `run` object is a later minor. |
| Q2 | Does Issue Revision also Number New Scenes, or stay separate? | REVISIONS-PLAN §6. 1.0: Prepare numbers; lock letters inserts; Issue does not renumber. |
| Q3 | Non-integer FDX `TagDefinition/@Id` | FORMAT `tagNumbers` is an array of integers. A string id has no home without changing FORMAT §5.3. |
| Q4 | Do snapshots include `notes.json`? | 1.0 diffs script only. Notes-on-words across an issue may want a snapshot later. |
| Q5 | SceneProperties Title and Color as eDraft-editable scene cards | Preserved in origin. Modeling them needs a scene metadata object this charter did not invent. |
| Q6 | Cast list, alts, bookmarks, DocumentRef | Preserved in origin. No production.json member in 1.0. |
| Q7 | Title-page revision line stored vs generated | §11.3 generates at print. Some productions type it. |
| Q8 | `fingerprints.production` required or optional | Optional in 1.0 (§2). |
| Q9 | How a 1.0 writer fills `pages.fingerprint.sha256` | Paginator inputs are an implementation fixture, not a hash recipe here. |
| Q10 | Deleted-text marks as a first-class span in `script.json` | Preserved in origin only. Modeling them would be a new run kind. |
| Q11 | Identity lifetime for Fountain and undo counter ownership | **Resolved for M1:** FORMAT O8–O9. One document allocator owns `nextId` outside both undo timelines. Restoring a snapshot revives its IDs without rewinding the counter; paste/import adopts new destination IDs. Fountain identities last for the editing session. |
| Q12 | Existing parser fixtures and UI UUIDs | **Resolved for M1:** raw parse/import projections remain identity-free; adoption produces the identity-bearing document model. Every live script element in Core has a `DraftElementID`, including nonprinting script structure. Notes keep their separate namespace. UI UUIDs remain transient surface handles; the planner assigns persistent split/merge ownership independently. No omission-by-ID migration or application `.draft` save wiring is implied. |
| Q13 | The engine's omission span is element indices, not DraftElementIDs | §7.3 addresses an omission by DraftElementID. The engine ships `Screenplay.omissions` as `{ start, end }` over the elements array (IL-0071, `cdcc477`), written before any element carried an identity; M1 (IL-0073, `348a38d`) has since given every element one, in both ports, so the migration is now possible. The two coexist today: `production.json` carries the id-shaped record, the index span is FDX-facing and derived at read, and `script.json` never stores it. Open because it changes the model, both ports' fixtures and every consumer that reads a span — and because an index span is invalidated by any edit that inserts or deletes elements before it, which is a reason to move it rather than to keep it. |

---

## 14. What this lock does not build

No engine, no app, no fixture files, no Prepare UI, no Issue Revision
command. Those are later locks, each proving a slice of this contract
the way S1 proved the container.

The next engine lock, when asked, is: read and write `revisions.json` and
`production.json` in both ports, generate fixtures, keep S1's ZIP and
must-preserve tests green, and **not** wire Production Mode in the apps.
