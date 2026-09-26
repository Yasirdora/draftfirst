# The `.draft` format — a specification

*Written 2026-09-18 on branch `rename/edraft`, HEAD `fbd7eb9`, under lock
IL-0044. It exists because today's `.draft` is plain Fountain text, which
cannot carry what a screenplay file must: a note on the words it is about,
a highlight, an identity for a line that survives a save. The human's brief
was a file "so good that it renders FDX obsolete, becoming a new standard" —
the best, most robust and most reliable screenplay file there is — and a PDF
that re-imports "with all the data". This RFC specifies both, and the seven
locks that build them.*

*Every claim carries its evidence:*

- ***measured*** — run on this machine on 2026-09-18; the numbers are quoted.
  Anything measured on the human's own files reports counts and sizes only.
- ***sourced*** — a published source, linked in §19.
- ***inference*** — reasoned from measured or sourced facts, not itself run.
- ***judgement*** — a design call; where it is one, the alternatives are named.
- ***unproven*** — needed and not yet known, with the check that settles it.

*§4 to §14 are normative. MUST, SHOULD and MAY are used as in RFC 2119 and
RFC 8174. Every example uses invented script text and invented names; the
repository is public.*

---

## 0. Decisions

### Settled — the human's

| # | Decision | Source |
|---|---|---|
| D1 | The native file is **`.draft`**. | Human, 2026-09-18. |
| D2 | **Fountain is an export, not the native file.** The native file is chosen for being the best, most robust and most future-proof, not for staying Fountain. | Human: "we could export fountain. I just want the best file that is optimized and efficient and future proof". |
| D3 | **An open standard.** The specification is public; eDraft is its reference implementation (the engine is MIT). | Human: "becoming a new standard". |
| D4 | **The PDF round-trips.** A PDF eDraft writes carries the whole `.draft` and re-imports with all the data. | Human, after reviewing omnipdf's living PDFs. |

*Amended 2026-09-26 (IL-0115):* D3's "the engine is MIT" no longer holds.
From this date the repository, engine included, is © 2026 eDraft, all rights
reserved (see LICENSE); versions published earlier keep the MIT License.
Whether the `.draft` specification itself stays an open standard is the
owner's open decision, not settled by that change.

### Proposed by this RFC — settled when the human approves it

| # | Proposal | Where |
|---|---|---|
| P1 | One file: a **ZIP container** in the ISO/IEC 21320-1 profile — not a folder package, not SQLite, not a CRDT, not Fountain with a trailer. | §3, §4 |
| P2 | The content is **JSON parts** (I-JSON, RFC 7493) with a **stable identity for every element**. | §5, §6 |
| P3 | A note is anchored **to words**: element id, UTF-16 offsets, and the quoted words with context. It is re-found by its words, and flagged — never moved silently — when they are gone. | §6 |
| P4 | **Deterministic**: the same document is the same bytes, on every platform. | §4.4 |
| P5 | **Must-preserve**: a conforming editor keeps every part and field it does not understand. | §8, §9 |
| P6 | **Damage stays small**: every part is checked, the script is stored twice, and a damaged file opens as far as it can — never silently. | §7 |
| P7 | **The `.draft` PDF**: the `.draft` rides inside the PDF as its source; reviewers' PDF comments come back as notes on their words. | §13 |
| P8 | Media type **`application/vnd.edraft.draft+zip`**; the UTType `xyz.edraft.screenplay` is kept. | §14 |

### Open — the human's to decide

Listed in §16, each with a recommendation. None blocks the first lock.

---

## 1. Why a new format

### 1.1 What `.draft` is today — measured

- **A `.draft` is Fountain text under eDraft's name.** `ScreenplayFile.encode`
  writes the source string as UTF-8; the UTType `xyz.edraft.screenplay`
  conforms to `public.plain-text`. The apps hold a document as that text:
  `EDraftDocument.source` is a `String`, and `EditorState` republishes
  `Fountain.serialise(currentDocumentModel)` after edits.
- **A highlight does not survive a save.** Through the TypeScript engine: one
  highlight run before `serialiseFountain`, none after save and reopen; bold
  survives. Fountain has no highlight syntax (RFC-HIGHLIGHTER D4), and a
  `.draft` is Fountain.
- **A note cannot sit on words.** Selecting words and choosing Add Note puts
  the note on the line: the selection bar calls `addNote(to: nil)`, the
  caret's element. Fountain can only place a note between paragraphs
  (RFC-NOTES-SYSTEM §2.1, measured), and an element's identity is regenerated
  on every parse, so nothing outside the text can point into it.
- **The plans assumed otherwise.** IOS-PLAN.md §7 describes `.draft` as "the
  same JSON the web app writes … with stable line IDs", and RFC-HIGHLIGHTER §5
  maps highlights to `.draft` "native, on the run". Neither was built. This
  RFC is the format those documents assumed.
- **Legacy files:** 22 `.draft` files on this Mac, none with an inline note;
  one of the 22 is XML, not Fountain. The app is unreleased (MILESTONE-S2:
  TestFlight "needed later").

### 1.2 What `.fdx` gets wrong — measured and sourced

| | Measured or sourced |
|---|---|
| **Size** | FDX is 9.5–14.1× the bytes of the same script as Fountain (3 fixtures, 12.1× in total). On 10 real Final Draft files on this Mac, the `.draft` of §4 to §6 — ids, the Fountain rendition and §16 O1's compression — is **11.4× smaller** in total. |
| **Parse cost** | Fixtures: FDX 8.6–10.4 ms to parse; the same script as JSON 0.12–0.24 ms. |
| **Anchors** | A ScriptNote is a bare offset (`Range`). Any tool that edits without recounting drifts every note after the edit: one pre-IL-0033 eDraft save moved every Range 5–33 units. |
| **Notes** | No replies, no resolved state; the author field is whoever last edited the note (RFC-NOTES-SYSTEM §3, probe). |
| **Extensibility** | Final Draft deletes every attribute it does not define on save (probe: 9 `EDraft:` occurrences before, 0 after). |
| **Openness** | One vendor's schema, undocumented, versioned by that vendor's releases. |

The size figure is measured with the engine's model as `script.json`, counter
ids (§6.1), the rendition (§5.5) and omnipdf's deflate (§16 O1). The manifest
and the ZIP headers, about 1 KB a file, are not in it; S1 measures real files
(§15, B1).

### 1.3 The bar

The goals are the human's brief made testable. §15 turns each into a test a
build lock must pass.

| # | Goal |
|---|---|
| G1 | Smaller than `.fdx` by an order of magnitude, and faster to open. |
| G2 | A note, a highlight or any mark stays on its words through every edit, and is flagged — never silently moved — when its words are gone. |
| G3 | A damaged file never crashes a reader, never opens silently wrong, and gives back the script whenever any copy of it is intact. |
| G4 | The same document is the same bytes, on every platform, forever. |
| G5 | Nothing another tool wrote is lost by opening and saving in a conforming tool. |
| G6 | Readable in fifty years with no eDraft: open standards only, self-describing, with a plain-text copy of the script inside. |
| G7 | Every existing `.draft` opens, and opening never changes a file. |
| G8 | The PDF of a script is also the script: it re-imports whole, and its reviewers' comments come back as notes. |

---

## 2. Prior art — sourced

| Product | Native file | What it shows |
|---|---|---|
| Final Draft | `.fdx`, one XML file | The de facto standard by market share, not by design (§1.2). |
| Fade In | `.fadein`: a ZIP holding XML in the Open Screenplay Format | A zipped, open schema works for screenplays. |
| Highland | `.highland`: a zipped TextBundle — the Fountain text plus JSON (`info.json` and others) | Plain text inside a zip, metadata as JSON beside it. |
| Beat | `.fountain` with a JSON block in a trailing `/* … */` | The only in-text precedent. *Source read:* review ranges are bare offsets, and the only check for an outside edit is the text's length at save — it warns and does not re-anchor. |
| Sketch | SQLite up to v42; a ZIP of JSON from v43 | Left SQLite for a format others could read and write. |
| Apple iWork | Folder packages in 2013; a single compressed file again from 2014 | Single files travel (mail, web, other systems); packages do not. |
| LibreOffice | "Hybrid PDF": the ODF document embedded in the PDF | A PDF that reopens as its editable source. Only LibreOffice reads it back. |
| omnipdf | "Living PDFs": `document.json` embedded with `AFRelationship /Source`, PDF/A-3 | The human's own library; §13 builds on it. |
| Factur-X / ZUGFeRD | PDF/A-3 with an embedded XML invoice | A legal standard built on a PDF carrying its data. |

Apple's iCloud design guide recommends a file package when a document has
distinct parts, because only changed parts sync. The Library of Congress
lists SQLite, JSON, XML and CSV as recommended storage formats for datasets,
and judges formats on seven sustainability factors: disclosure, adoption,
transparency, self-documentation, external dependencies, patents, and
technical protection.

---

## 3. The container — options considered

| Option | For | Against | Verdict |
|---|---|---|---|
| **ZIP of JSON parts** (P1) | ISO standard (21320-1) and universal; every language reads ZIP and JSON; one file travels anywhere; the engine already reads and writes ZIP (for `.docx`); parts separate concerns; the Fountain rendition keeps the script readable with no software. | Not diffable as a whole (mitigated: §5.5's plain-text rendition). The whole file is rewritten on save (inference: under 1 ms for a script at these sizes). | **Chosen.** |
| Folder package | Apple syncs only changed parts. | Breaks in mail, web downloads, Windows, most cloud web views; at 30–80 KB per script, partial sync saves nothing. | Rejected. |
| SQLite | LoC-recommended; transactional; incremental writes. | The web engine would need a WebAssembly SQLite — a dependency the engine does not take; journal side files need care under sync services; opaque to people; Sketch left it. At screenplay sizes incremental writes buy nothing. | Rejected. |
| A CRDT document (Automerge) | Merging and full history built in. | A heavy dependency in both engines; a young format; history only grows; opaque. | Rejected now. Stable ids (§6) keep the door open. |
| Fountain + a trailing JSON block (Beat's shape) | One text file, diffable. | The JSON rides in a comment other tools may edit or drop; offsets rot on any outside edit; no room for binary parts (the origin FDX, fonts). | Rejected. |
| Open Screenplay Format (Fade In's XML) | An existing open schema. | XML — FDX's size and parse cost (§1.2); adopted mainly by Fade In; no notes model. | Rejected as native; an export candidate later. |
| One JSON file | Simplest. | One damaged byte loses everything; no binary parts; no rendition. | Rejected. |

Against the Library of Congress's factors (*judgement*): ZIP, JSON and UTF-8
are fully disclosed, universally adopted, transparent, patent-free and carry
no technical protection; the manifest (§5.2) and the published schema (§17,
S7) make the file self-documenting; the only external dependency is an unzip
tool.

---

## 4. The container profile — normative

### 4.1 ZIP

A `.draft` file MUST be a ZIP archive that:

1. conforms to **ISO/IEC 21320-1**: entries are stored (method 0) or deflated
   (method 8); no encryption; not split or spanned; ZIP64 only in its
   version-1 form, and a writer SHOULD NOT need it;
2. sets general-purpose bit 11 (UTF-8) on every entry whose name has a byte
   above 0x7F;
3. has no directory entries, symbolic links or extra fields, and a writer
   MUST NOT write any;
4. has no two entries with the same name, compared case-insensitively after
   Unicode NFC normalisation.

### 4.2 Entries

| Path | Required | Written | Content |
|---|---|---|---|
| `mimetype` | yes | first, **stored** | exactly `application/vnd.edraft.draft+zip`, ASCII, no newline |
| `manifest.json` | yes | second | §5.2 |
| `script.json` | yes | third | §5.3 |
| `notes.json` | when there are notes | fourth | §5.4 |
| `script.fountain` | yes | fifth | §5.5 |
| `origin/…` | when a document has an origin | after | §5.6 |
| `ext/<reverse-domain>/…` | optional | last, in name order | §9 |

The `mimetype` rule is EPUB's: stored and first, so the media type sits at a
fixed offset (byte 38) and a file identifies itself from its first bytes.
The script is written before everything else of size, so a truncated file
still holds it (§7.2).

Names are relative, use `/`, and MUST NOT begin with `/`, contain `..` as a
segment, contain `\`, a drive letter, NUL or any control character.

### 4.3 Limits

A reader MUST refuse, with a stated reason, an archive over these limits,
and MAY lower them. All but two are the engine's existing ZIP limits
(`zip.ts`) and screenplay limits (`validation.ts`); the compression ratio and
the JSON depth are new:

| Limit | Value |
|---|---|
| Entries | 512 |
| One entry, uncompressed | 64 MiB |
| All entries, uncompressed | 128 MiB |
| Compression ratio of any entry | 200:1 |
| JSON nesting depth | 64 |
| Elements | 100,000 |
| Characters in one element | 1,000,000 |
| Title-page lines | 100 |

### 4.4 Determinism

The same document MUST produce the same bytes, on every platform and in
every conforming writer of the same version (G4). A writer:

- writes entries in §4.2's order;
- stamps every entry 1980-01-01 00:00:00 (DOS date `0x0021`, time `0x0000`),
  version-made-by `20`, external attributes `0`, no comment;
- writes JSON in the canonical form of §5.1;
- compresses with the one deflate implementation §16 O1 settles, or stores.

Determinism is what makes the fingerprint (§7.5) mean something, what lets a
writer prove two drafts are the same, and what lets a test pin a file byte
for byte in both engines — the pattern every conformance fixture in this
repository already follows.

---

## 5. The parts — normative

### 5.1 JSON

Every `.json` part MUST be I-JSON (RFC 7493): UTF-8 with no byte-order mark;
no duplicate member names; integers only, within ±2⁵³; no lone surrogates.

**Canonical form**, for writing: two-space indentation, `\n` line ends and a
final newline; members in the order the schema below lists them, then any
members this version does not know, in the order they were read (§8.2);
strings escaped as ECMAScript's `JSON.stringify` escapes them. Readers MUST
accept any valid I-JSON.

Offsets and lengths are **UTF-16 code units** (§6.2).

### 5.2 `manifest.json`

```json
{
  "format": "draft",
  "version": "1.0",
  "minReader": "1.0",
  "writer": { "name": "eDraft", "version": "2.0.0" },
  "title": "The Kettle",
  "parts": [
    { "path": "script.json", "sha256": "…", "size": 61840 },
    { "path": "notes.json", "sha256": "…", "size": 2210 },
    { "path": "script.fountain", "sha256": "…", "size": 33846 }
  ],
  "fingerprints": { "script": "…", "notes": "…" }
}
```

- `title` is the document's title, so a list of files can show it without
  reading the script.
- `version` is this specification's version; `minReader` is the lowest
  version that can **edit** the file without losing anything (§8.1).
- `parts` lists every entry except `mimetype` and the manifest, with the
  SHA-256 of its uncompressed bytes (lowercase hex) and its size.
- `fingerprints.script` is the SHA-256 of `script.json` in the JSON
  Canonicalization Scheme (RFC 8785); `fingerprints.notes` likewise, and
  omitted when there is no `notes.json`. Two files
  with the same script fingerprint hold the same script, whatever their
  notes, compression or writer (§7.5).
- No timestamps. A file's dates are the file system's, and a date in the
  bytes would break G4.

### 5.3 `script.json`

```json
{
  "titlePage": [
    { "key": "Title", "text": "The Kettle", "alignment": "center" }
  ],
  "elements": [
    { "id": "1", "type": "scene", "text": "INT. KITCHEN - NIGHT", "sceneNumber": "1" },
    { "id": "2", "type": "action", "text": "The kettle screams. Mara doesn't move.",
      "runs": [ { "start": 4, "end": 10, "styles": [], "highlight": "yellow" } ] },
    { "id": "3", "type": "character", "text": "MARA", "dual": true }
  ],
  "nextId": "4"
}
```

- `elements` is the script in order. `type` is one of the engine's element
  kinds, whose names are already the wire strings (`Types.swift`):
  `scene`, `action`, `character`, `dialogue`, `parenthetical`, `transition`,
  `shot`, `general`, `centered`, `lyrics`, `actbreak`, `section`,
  `synopsis`, `pagebreak`. **`note` is not an element type in this format**:
  notes live in `notes.json` and point into the script (§6).
- `id` and `nextId` — §6.1.
- `text` is the element's text without markup. Emphasis and marks are
  `runs`, the engine's `StyleRun`: `start` and `end` in UTF-16 units of
  `text`; `styles`, a list in the order `Bold`, `Italic`, `Underline`,
  `Strikeout`, `AllCaps`, `HiddenText` (empty when a run only marks); and
  the optional `highlight`, `revisionID` and `tagNumbers`. The names are the
  engine's, so the file and the model need no mapping. Runs are canonical:
  sorted, non-overlapping, never empty, and merged where every property is
  equal (RFC-HIGHLIGHTER §2).
- `dual`, `sceneNumber` and `depth` are the engine's fields of the same
  names.
- The title page is `titlePage`, the engine's `TitlePageLine`s.

### 5.4 `notes.json`

```json
{
  "threads": [
    {
      "id": "1",
      "anchor": {
        "element": "2", "start": 25, "end": 37,
        "quote": "doesn't move", "prefix": "screams. Mara ", "suffix": "."
      },
      "messages": [
        { "id": "2", "by": "Dana Reyes", "role": "Director",
          "at": "2026-09-18T10:02:00Z", "text": "Too still? She should flinch." },
        { "id": "3", "by": "Sam Okafor", "role": "Writer",
          "at": "2026-09-18T10:05:00Z", "text": "She's frozen — that's the beat." }
      ],
      "status": [
        { "state": "resolved", "by": "Dana Reyes", "at": "2026-09-18T11:00:00Z" }
      ]
    }
  ],
  "nextId": "4"
}
```

- Threads and messages take ids from `notes.json`'s own counter, by §6.1's
  rule.
- A **thread** is an anchor, one or more messages, and a status history.
  Its state is the last entry of `status`, or `open` when there is none. A
  resolved thread is never deleted by being resolved (RFC-NOTES-SYSTEM §7).
- An **anchor** is §6.3's object. A thread on a whole line carries only
  `element`.
- A **message** has an `id`, the author as typed (`by`, with an optional
  `role`), the time (`at`, RFC 3339 UTC), and `text`. An author is never
  derived from the system (RFC-NOTES-SYSTEM D6); a message whose author is
  unknown omits `by`.
- An imported message MAY carry `source`, naming where it came from
  (`{ "fdx": "<RefId>" }`, `{ "pdf": "<annotation key>" }`), so importing
  the same file twice adds nothing (§13.7).
- Final Draft's own notes, carried through a `.draft` from an FDX origin,
  are threads like any other; their `source` names the ScriptNote.

### 5.5 `script.fountain`

A Fountain rendition of `script.json` and `notes.json`, written with every
save by the engine's serialiser. It exists for three readers: a person with
only an unzip tool (G6), Quick Look and Spotlight (§14), and recovery
(§7.2). It is **never authoritative**: a reader MUST use `script.json` when
that part is valid, and MUST NOT treat edits made to the rendition alone as
edits to the document.

### 5.6 `origin/`

The file a document came from, byte for byte, kept so nothing it held is
lost:

| Path | When | Why |
|---|---|---|
| `origin/source.fdx` | converted from Final Draft | FDX export splices into it (§12.1), keeping every byte eDraft does not model — revisions, locked pages, tags, SmartType — as IL-0024 to IL-0033 keep them for an `.fdx` today. |
| `origin/source.fountain` | upgraded from a text `.draft` or a `.fountain` | The upgrade is reversible (§11.3). |

A writer MUST NOT change an origin part. How long an origin is kept is §16
O3.

### 5.7 Reserved for later versions

`revisions.json` (revision sets, colours and marks), `production.json`
(locked scene numbers and pages, omitted scenes, breakdown tags) and
`history/` (named drafts — "Studio draft, 1 Sep" — from which eDraft can
show what changed since) are reserved names. They are specified by later
versions of this document, never as extensions, and until then a reader
MUST preserve them if present (§8.2).

---

## 6. Identity and anchors — normative

### 6.1 Element identity

- Every element has an `id`: 1 to 64 characters from `A–Z a–z 0–9 _ -`,
  unique in the file. eDraft writes a counter in base 36 (`1`, `2`, … `z`,
  `10`, …) and records the next unused value as `script.json`'s `nextId`.
  An id is never reused, even after its element is deleted, so a detached
  thread can never attach itself to a newer line.
- *Measured, on the 10 real scripts:* counter ids cost 57 KB compressed in
  total, eight random characters 137 KB — 11.4× smaller than FDX against
  10.0×. Random ids would avoid collisions when two diverged copies are
  merged; a merge instead renumbers the new elements of one side, which it
  can, because they are new.
- An id is **stable**: it survives saves, reopening, and every edit that
  leaves the element in place. Splitting an element keeps the id on the
  first half; merging two keeps the first one's; pasting creates new ids;
  undo restores the ids it removed.
- An id carries no meaning and MUST NOT be interpreted.

Fountain has nowhere to keep an id, which is why today's ids are regenerated
on every parse and why nothing outside the text can point into it
(note-author design, IL-0016). `script.json` keeps them; that single fact is
what makes §6.3 possible.

### 6.2 Offsets

Offsets are **UTF-16 code units** within one element's `text`. They are the
engine's own coordinate (`StyleRun`, `NSRange`, JavaScript strings) and
Final Draft's (a ScriptNote's `Range`, IL-0031). A reader in a language with
other string units MUST convert. *Judgement:* code points would be neutral
across languages, but every implementation that exists today, and FDX,
counts UTF-16; converting at each boundary would be the larger source of
error.

### 6.3 The anchor

```json
{ "element": "2", "start": 25, "end": 37,
  "quote": "doesn't move", "prefix": "screams. Mara ", "suffix": "." }
```

It carries both of the W3C Web Annotation selectors: the position
(`element`, `start`, `end`) and the quote (`quote`, with a `prefix` and a
`suffix` from the same element, each at most 32 units). eDraft writes the
whole words that fit within 16 units on each side — in the example,
`screams. Mara ` and `.`. A whole-line anchor carries only `element`.

### 6.4 Keeping an anchor — the editor's duty

While a document is edited, the editor moves every anchor with its words, as
it moves style runs today. On save, `quote`, `prefix` and `suffix` are
refreshed from the text, so a file on disk is always self-consistent.

### 6.5 Re-finding an anchor — the reader's duty

On open, and after any import that may have changed the text:

1. **The element exists and its text at `start…end` is `quote`:** the anchor
   holds.
2. **The element exists, the quote does not match:** search the element for
   `quote` with its `prefix` and `suffix`. **One** match → the anchor moves
   to it; the words and their context are found exactly, in their own
   element, so this is the same anchor, not a move. None, or more than one → the anchor stays at its offsets, clamped
   to the text, and the thread is flagged **"words changed"**.
3. **The element is gone:** search the whole script for `prefix + quote +
   suffix`. **One** match → the thread moves there and is flagged **"moved"**.
   Otherwise the thread is **detached**: kept, listed, flagged, on no line.
4. A thread is never deleted, and never moved to other words or another
   element without a flag.

This is RFC-NOTES-SYSTEM D10's rule — never guess — applied to anchors that,
unlike Fountain's, carry both a position and the words.

### 6.6 Legacy notes

An inline Fountain note `[[…]]` read from a legacy `.draft` or a `.fountain`
becomes a thread anchored to the whole of the element after it (the one the
parser places it in front of). Its author is read as today: a `Name:` or
`Name (Role):` prefix is taken as the author when it matches the writer's
signature or prefixes two or more notes (IL-0016); otherwise the whole text
is the message and `by` is omitted.

---

## 7. Integrity and recovery — normative

### 7.1 What a reader checks

In order: the ZIP structure and §4.3's limits; each entry's CRC-32; each
part's SHA-256 against the manifest; that each JSON part is I-JSON; that it
matches its schema; that every anchor names an existing element or is
flagged (§6.5).

### 7.2 The recovery ladder

| Found | The reader |
|---|---|
| Everything valid | opens the file. |
| A part's SHA-256 differs from the manifest, but its CRC holds and it is valid | uses it: this is an edit made outside a conforming writer, not damage. Anchors are re-found (§6.5), and the writer is told. |
| A part other than `script.json` fails its CRC, I-JSON or schema check | opens the script; keeps the failed part's bytes and writes them back unchanged on save; says which part and what it lost (notes shown as unavailable). |
| `script.json` fails its CRC, I-JSON or schema check | opens from `script.fountain` if that is valid; says that ids and word anchors are lost and threads are detached; keeps the failed bytes. |
| The central directory is missing (a truncated file) | reads entries from their local headers in order; the script comes first (§4.2), so it survives any truncation after it. |
| Nothing readable | refuses, saying why. It never opens an empty document in place of a damaged one. |

Any rung below the first MUST be said to the writer, and the document MUST
NOT be saved over its file without the writer choosing to (G3). A repaired
copy is offered.

### 7.3 Atomic saves

A writer MUST write a complete new file and replace the old one in one step
(a temporary file in the same directory, then a rename; `NSDocument`'s and
`UIDocument`'s safe save do this). A save never leaves a half-written
`.draft`.

### 7.4 Checksums

The ZIP's per-entry CRC-32 detects damage in transit; the manifest's
per-part SHA-256 detects damage the CRC could miss and any edit made outside
a conforming writer.

### 7.5 The fingerprint

`fingerprints.script` names a draft independently of its notes, its
compression and its writer. "Is this the draft the studio has?" is answered
by comparing two strings. *Judgement:* signatures (proving who produced a
draft) build on the fingerprint later; they are not in version 1.

---

## 8. Versions and compatibility — normative

### 8.1 Versions

`version` is `major.minor`. A minor version adds optional members or parts;
a major version may change meaning. A reader:

- of the same major and a minor at or above `minReader`: opens and edits;
- of the same major and a minor below `minReader`: opens **read-only** and
  says a newer eDraft is needed to edit it;
- of a lower major: refuses, saying which version is needed.

A reader never "upgrades" a file by losing what it could not read.

### 8.2 Must-preserve

A conforming **editor** MUST:

- write back every part it does not understand, byte for byte;
- write back every member it does not understand, in every object it keeps,
  after the members it knows, in the order it read them;
- drop unknown members only with the object that holds them (a deleted
  element takes its unknown members with it).

This is the rule FDX lacks — Final Draft deletes what it does not define
(§1.2) — and the rule that lets other tools adopt the format without losing
their own data (D3).

### 8.3 Conformance classes

| Class | Must |
|---|---|
| Reader | §4, §5, §7.1–7.2, §8.1; open and display the script. |
| Editor | Reader, plus §6.4–6.5, §7.3, §8.2. |
| Writer | Produce files that satisfy §4 to §7, deterministically (§4.4). |

The conformance suite (§17, S7) tests each class.

---

## 9. Extensions — normative

- **Parts:** under `ext/<reverse-domain>/`, e.g. `ext/com.example.tool/…`.
- **Members:** in an `ext` object keyed by reverse domain, at the document,
  element, thread or message level:
  `"ext": { "com.example.tool": { "colour": "teal" } }`.
- An extension MUST NOT change the meaning of a standard member. A reader
  that does not know an extension ignores it and preserves it (§8.2).
- eDraft's own later data is specified in later versions of this document
  (§5.7), never as an extension.

---

## 10. Security — normative

- §4.3's limits, enforced before anything is decompressed or parsed.
- §4.2's path rules; a reader never writes an entry to disk by its name.
- The format has no executable content, no scripts, no macros, and no
  external references: a reader MUST NOT fetch, open or execute anything a
  file names.
- A reader treats every string as text to display, never as markup to
  interpret.
- Fuzzing is part of acceptance (§15, B3).

---

## 11. Legacy files and migration — normative

### 11.1 Recognise by bytes, not by name

For every file opened, whatever its extension:

| First bytes | Read as |
|---|---|
| `PK\x03\x04` and `mimetype` = this media type | `.draft` 1.x |
| `%PDF-` | a PDF: the `.draft` PDF (§13) or recovery import |
| `<?xml` or `<FinalDraft` | FDX |
| valid UTF-8 text | Fountain — a text `.draft` (format 0) or a `.fountain` |
| anything else | refused, with the reason |

*Measured:* one of the 22 `.draft` files on this Mac is XML. An
extension is a hint; the bytes are the truth.

### 11.2 Opening never writes

Opening a file of any version never changes it (G7). A text `.draft`
opened and closed without an edit is byte-identical afterwards.

### 11.3 Upgrading

The first save **after an edit** writes `.draft` 1.x and keeps the old
bytes in `origin/source.fountain`, so nothing is lost and the upgrade can be
undone by exporting the origin. This is iWork's rule — open old documents
untouched, convert when the writer edits — without its prompt, because
there is no released user to protect yet; §16 O6 decides the prompt before
release. Format 0 is readable forever.

---

## 12. Conversions — normative

### 12.1 To FDX

- **With `origin/source.fdx`:** splice, as `.fdx` saves do today — unchanged
  paragraphs keep their bytes, and every IL-0024 to IL-0033 keep holds.
- **Without:** the engine's native `writeFdx`.
- **Notes:** each thread's first message is a ScriptNote in RFC-NOTES-SYSTEM's
  form — title `[eDraft]`, the author in `WriterName`, the role in `Type`,
  the words only in the body (D8). **A word anchor becomes a `Range` over
  exactly those words**, counted by IL-0031's rule — so a note on selected
  words shows on those words in Final Draft too. *Recommendation, decided in
  S4 with a Final Draft check:* later messages are further `[eDraft]` notes
  on the same Range, in time order, which is how Final Draft users thread by
  hand (probe: "Re:" titles sharing a Range).
- **Final Draft's own notes:** a thread whose `source` is a ScriptNote of the
  origin *is* that note. The splice keeps it as IL-0033 does, and only the
  messages added in eDraft are written, as `[eDraft]` notes — eDraft never
  rewrites a note Final Draft owns (RFC-NOTES-SYSTEM D2).
- **Lost, and said:** element ids; thread status until S4 decides its
  carrier. Highlights are written as `EDraft:Highlight` (RFC-HIGHLIGHTER D5)
  and last until Final Draft saves the file, which strips them
  (RFC-NOTES-SYSTEM §3; §11, stage H).

### 12.2 From FDX

As today, and the file's bytes are kept in `origin/source.fdx`. Notes titled
`[eDraft]` come back as the writer's own threads; Final Draft's notes come
back as threads with `source` naming their ScriptNote (§5.4).

### 12.3 To Fountain

The engine's serialiser, notes inline (RFC-NOTES-SYSTEM §4.4): one `[[ ]]`
per thread, one line per message as `Name (Role): text`, in front of the
anchored element. **Lost, and said in the export notice:** ids, highlights,
the position of an anchor within its line, and thread status.

### 12.4 From Fountain

As today; notes become threads by §6.6.

### 12.5 PDF

§13.

---

## 13. The `.draft` PDF — normative

### 13.1 What it is

A PDF of the script, printed exactly as eDraft paginates it, that also
carries the `.draft` it was printed from. It opens in any PDF viewer as a
screenplay. Opened in eDraft, it is the document again — and any comments a
reviewer added in Acrobat, Preview or on an iPad come back as notes on the
words they marked (G8).

### 13.2 The carrier — the `.draft` inside

The `.draft` is an **embedded file** in the PDF's `/EmbeddedFiles` name
tree and an **associated file** of the document (the catalog's `/AF`):

- file specification `/F` and `/UF`: the document's title + `.draft`;
- `/AFRelationship /Source`;
- embedded stream `/Subtype /application#2Fvnd.edraft.draft+zip`, with
  `/Params` `/Size` and `/CheckSum`;
- the PDF conforms to **PDF/A-3b**, which permits associated files, with
  every font embedded (§13.5).

*Measured (PDFKit, the framework under Preview):* a PDF carrying a 10,240-byte
binary attachment with `/AFRelationship /Source` was opened, given a new
highlight comment, and saved: the attachment came back byte for byte, still
`/Source`, still in `/AF`.

### 13.3 The page map

A second associated file, `page-map.json` (`/AFRelationship /Supplement`),
records where every line was drawn:

```json
{
  "fingerprint": "…",
  "pages": [
    { "number": 1, "width": 612, "height": 792,
      "lines": [
        { "y": 676, "x": 108, "element": "2", "start": 0, "end": 38 }
      ] }
  ],
  "font": { "size": 12, "advance": 7.2, "lineHeight": 12 }
}
```

Courier is monospaced — every character 7.2 points wide at 12 points — so a
point on a page names a character with arithmetic: the line from `y`, the
offset from `(x − line.x) / 7.2`. The page map is written by the paginator
that drew the page, so it cannot disagree with the page.

### 13.4 The fallback — `/Keywords`

The existing carrier stays: the Info dictionary's `/Keywords` holds the
Fountain source (`PdfSignal`, `pdfsignal.ts`). *Measured:* it survives a
PDFKit annotate-and-save; eDraft's own test measured 500,000 hex characters
surviving a PDFKit rewrite. It is read only when the attachment is absent,
and gives back the script without ids or anchors.

### 13.5 Writing

- **eDraft's paginator decides every page.** eDraft's identity is the
  authoritative page count (evaluation-draft-format-plan §6); nothing else
  paginates. omnipdf's screenplay template, which has its own Fountain parser
  and layout, is not used.
- **omnipdf's core writes the bytes**: text, the embedded font with its
  ToUnicode map, the attachments, XMP and PDF/A-3 — all deterministic,
  matching §4.4. This also closes two gaps in today's web exporter, which
  refuses characters outside WinAnsi and prints dual dialogue one speech
  after the other.
- **The font is Courier Prime** (SIL Open Font License; designed for
  screenplays), embedded and subset. PDF/A requires embedded fonts; the
  base-14 Courier cannot be embedded.
- One writer, ported to Swift like every engine module, so the Mac, the phone
  and the web write the same PDF bytes (§16 O2).

### 13.6 Reading

1. Find the associated file whose subtype is this media type (or whose name
   ends in `.draft`); read it as §7 reads any `.draft`, including its
   recovery ladder.
2. If there is none, read `/Keywords` (§13.4).
3. If there is neither, the PDF is a foreign PDF: the existing recovery
   import (best effort, said as such).

A reader MUST parse the PDF properly — cross-reference tables and streams,
object streams, filters. *Measured:* omnipdf's current reader scans for the
exact bytes its own writer produces, and finds nothing in any PDF another
program has saved, including a PDFKit rewrite of its own output; its source
says a full reader is "a separate, later component". On Apple platforms
Core Graphics' own parser reads the attachment; the TypeScript reader is
built in S5.

### 13.7 Comments become notes

| PDF annotation | Becomes |
|---|---|
| `Highlight`, `Underline`, `Squiggly`, `StrikeOut` | a thread anchored to the words under its `/QuadPoints` |
| `Text` (a sticky note), `FreeText`, `Caret` | a thread anchored to the line under its point |
| `Ink`, `Square`, `Circle`, `Line`, `Stamp`, others | not converted in version 1; counted in the import notice |
| `Popup` | ignored (it shows its parent) |

- `/Contents` is the message; `/T` its author, as the reviewer's app wrote
  it; `/M` (else `/CreationDate`) its time.
- An annotation with `/IRT` (in reply to) is a message in its parent's thread.
- `/State` in the `Review` model: `Completed` or `Accepted` resolves the
  thread; `Rejected` or `Cancelled` is recorded as a status message; `None`
  reopens it.
- **Mapping:** each quad's lines come from the page map by `y`, its
  characters from `x` (§13.3). Quads that fall in one element make one
  anchor; an annotation across several elements anchors to the first, and
  the import notice says so (RFC-NOTES-SYSTEM §5.3 rule 6).
- **Verification:** where the platform can extract the PDF's text under a
  quad, it is compared with the anchored words; a mismatch flags the thread
  "words not verified". *Measured:* PDFKit returned exactly the words under a
  reviewer's highlight.
- **Idempotence:** each imported message's `source` records the annotation's
  key — its `/NM` when present, otherwise a hash of its page, quads, author,
  time and contents — so importing the same PDF twice adds nothing.
- *Measured:* a thread of a highlight, a reply by `/IRT`, and a `/State
  Completed` — with authors, dates and contents — survived a PDFKit
  annotate-and-save intact.

*Inference:* the industry's review loop is a PDF marked up by producers,
executives and actors, retyped by the writer. §13.7 removes the retyping. No
screenwriting application found in this research imports PDF comments as
notes; that is a search result, not a proof.

### 13.8 Unproven — each with its check

| Unknown | Check |
|---|---|
| Acrobat (Reader and Pro) keeps the associated file through a comment and save | The human comments on a `.draft` PDF in Acrobat and saves; its bytes are read back here — the Final Draft probe's protocol. |
| iPad and iPhone Markup keep it | The same, in Files' Markup. |
| Mail systems deliver a PDF with an embedded file | Send one through the studios' usual mail (Gmail, Outlook/Exchange); some corporate filters flag PDFs with attachments. If it fails, §16 O4's alternative. |
| PDF/A-3b validity | veraPDF on every fixture PDF (omnipdf's README marks its PDF/A as pre-certification). |
| Print to PDF, flattening, scanning | Expected to strip everything (inference); such a PDF is foreign (§13.6). |

---

## 14. Platforms

- **UTType:** `xyz.edraft.screenplay` is kept, so iCloud and Files keep their
  associations; it changes from conforming to `public.plain-text` to
  `public.data` and `public.composite-content` (*judgement*: not to
  `com.pkware.zip-archive`, so the Finder never offers to unzip a script).
  The phone's and the Mac's declarations stay identical (HANDOFF rule 4).
- **Media type:** `application/vnd.edraft.draft+zip` (`+zip` is registered
  by RFC 6839); registered with IANA at S7.
- **Quick Look and Spotlight:** a preview extension and an importer read
  `script.fountain` (S6).
- **iCloud:** a `.draft` is one file, so it syncs as one item through the
  eDraft Location (RFC-EDRAFT-LOCATION, the writer's own iCloud). Stable ids
  make an element-by-element merge of two conflicting copies possible later
  (IOS-PLAN §7).
- **Web:** the same bytes, downloaded and opened by §11.1.

---

## 15. Acceptance — the tests the build locks must pass

| # | Bar | Test | `.fdx` today |
|---|---|---|---|
| B1 | Size | On the real-file corpus, the `.draft` is at least **10× smaller** than the FDX in total (measured basis: 11.4× with counter ids, the rendition and §16 O1's recommendation). Counts only, never content. | the baseline |
| B2 | Speed | The whole open — unzip, checks, parse — is measured on the fixtures and reported against the FDX parse. Reported, not a timed gate. *Measured basis, the parse alone:* 0.12–0.24 ms against 8.6–10.4 ms. | 8.6–10.4 ms |
| B3 | Damage | Every single-byte change and every truncation of the fixture `.draft`s: no crash; nothing opens silently wrong; the script comes back whenever `script.json` or `script.fountain` is intact. Both engines. | — |
| B4 | Determinism | The same document writes identical bytes in TypeScript and Swift; conformance fixtures pin them. | — |
| B5 | Must-preserve | A file with unknown parts and members survives open, edit and save with every unknown byte intact. | Final Draft deletes them (measured) |
| B6 | Anchors | Random edit sequences (property tests): every thread ends on its words, or flagged; none on wrong words. | offsets only |
| B7 | Legacy | Every legacy fixture — text `.draft`, the XML-in-`.draft` case — opens; opening writes nothing. | — |
| B8 | FDX | A Final Draft-born document saves to FDX with no edit byte-identical (IL-0024); a word anchor becomes a Range over its words; a Final Draft check confirms it. | — |
| B9 | PDF | `.draft` → PDF → `.draft` gives the same script fingerprint; after a PDFKit comment and save, the same, plus the comment as a note on its words. | — |
| B10 | Standards | Every fixture passes the §4 profile checker and I-JSON validation; every PDF passes veraPDF as PDF/A-3b. | — |

---

## 16. Open decisions — the human's

| # | Decision | Options | Recommendation |
|---|---|---|---|
| O1 | Compression | Stored; omnipdf's deterministic fixed-Huffman deflate, ported to Swift; a platform zlib | **omnipdf's deflate.** *Measured on the 10 real scripts, before ids:* stored is 3.2× smaller than FDX, omnipdf's deflate 12.7×, zlib's dynamic deflate 15.9×. zlib's output is not promised byte-stable across versions, which would break G4; omnipdf's is deterministic by design. |
| O2 | omnipdf in the engine | Depend on `@omnipdf/core`; copy the needed modules into `@edraft/core` | **Depend** (MIT, zero dependencies, the same owner): the engine's rule becomes "no third-party dependencies". Swift ports the modules it needs, as it ports the engine. |
| O3 | How long an origin is kept | Forever; until eDraft models everything in it; the writer's choice | **Until the writer removes it**, with the size shown. Removing an FDX origin makes later FDX exports native instead of spliced; the notice says so. |
| O4 | The PDF's attachment | The `.draft` as one file; its parts as separate JSON attachments | **One `.draft`** — one fingerprint, one reader path. Switch only if §13.8's mail check fails. |
| O5 | Publishing | In this repository now; a site with schema, validator and suite at S7; IANA at 1.0 | **All three, in that order.** The specification stays in `docs/` until S7 freezes 1.0. |
| O6 | The upgrade prompt | None; iWork's "Edit a copy / Upgrade" | **None until release; decide before release.** |
| O7 | The Fountain rendition | Keep it in every file; leave it out | **Keep it.** *Measured:* it is 224 KB of the 575 KB compressed across the 10 real scripts — without it the file is 18.7× smaller than FDX, with it 11.4×. It is the second copy the recovery ladder (§7.2) stands on, and the part a person with no software reads (G6). Robustness over bytes. |
| O8 | Persistent identity in plain Fountain | Fountain has no spelling for IDs. M1 resolves this as **session-stable only**: mint on open, retain through edits and undo, and mint anew in a new editing session. `.draft` persists `id` and the high-water `nextId`; application save wiring is a later stage. |
| O9 | Counter rollback on undo and foreign counter spellings | M1 resolves this as **never rewind**: undo/redo restores the original element IDs but retains the maximum allocation counter. A divergent edit consumes a new value. Writers emit canonical lower-case base-36 counters; the identity-bearing boundary rejects a noncanonical counter and advances a stale counter beyond existing generator-compatible ID spellings. Other valid IDs remain opaque. |

---

## 17. The stages — one lock each

### S1 — the engine

- **Builds:** §4 to §11 in both engines — the container, the parts, the
  canonical form, checksums, the recovery ladder, limits, must-preserve,
  legacy detection. No app change.
- **Proofs:** B3, B4, B5, B7; B1 and B2 measured and reported, which settles
  O1. Conformance fixtures, identical in both ports.

### S2 — the apps hold the document

- **Builds:** the Mac, the phone and the web hold the script with its ids
  instead of Fountain text; `EditorState` keeps ids through every edit
  (§6.1's split, merge, paste and undo rules); `.draft` opens and saves as
  1.x; a text `.draft` upgrades on the first save after an edit (§11.3).
- **Proofs:** a highlight survives save and reopen (fails today, measured);
  ids are identical after save, reopen and each edit rule; a text `.draft`
  opened and closed is byte-identical; the upgraded file's origin equals the
  old bytes.

### S3 — notes on the words the writer selected

- **Builds:** Add Note with a selection anchors to it (§6.3); anchors kept
  through edits (§6.4) and re-found on open (§6.5); FDX Ranges from word
  anchors (§12.1). RFC-NOTES-SYSTEM's stage 4, built here.
- **Proofs:** B6; the §6.5 cases each pinned; **Final Draft check:** a note
  eDraft anchored to words shows on those words in Final Draft and keeps them
  through a Final Draft save.

### S4 — threads and resolve

- **Builds:** RFC-NOTES-SYSTEM's stages 2 and 3 on `notes.json`: replies,
  resolve, reopen, the fade and the filter; their FDX carrier (§12.1),
  decided with a Final Draft check.
- **Proofs:** a thread of three messages and its status round-trip in
  `.draft`; a reply to a Final Draft note leaves that note's bytes unchanged.

### S5 — the `.draft` PDF

- **Builds:** §13 — the omnipdf writer driven by eDraft's paginator, Courier
  Prime, PDF/A-3, the attachment and the page map; the PDF reader (Core
  Graphics on Apple; a full cross-reference reader in TypeScript); comments
  to notes.
- **Proofs:** B9, B10; the §13.7 table's cases each pinned; **human checks:**
  §13.8's Acrobat, Markup and mail rows.

### S6 — the platforms

- **Builds:** §14 — the UTType's conformance, Quick Look preview and
  thumbnail, the Spotlight importer.
- **Proofs:** APPLE-PLATFORM-GUIDE.md §7's definition of done.

### S7 — the standard

- **Builds:** the specification published outside this repository; a JSON
  Schema for every part; a validator (command line and web); the
  conformance suite for the three classes (§8.3); the IANA registration;
  version 1.0 frozen.
- **Proofs:** eDraft's TypeScript engine and its Swift port pass the suite.
  They share fixtures, so they are not independent; the adoption test of a
  standard is a third party's implementation passing it.

---

## 18. Risks still unproven

- **Id stability through the editor.** Every edit path — typing, splits,
  merges, paste, undo, the Return and Tab choreography — must keep ids.
  If an id churns, its threads fall back to §6.5's search by words: safe,
  but S2 must prove it does not.
- **§13.8's five rows.**
- **Whole-file rewrite on very large documents.** *Inference:* a script is
  tens of kilobytes (§1.2); a multi-episode document of several megabytes
  still writes in milliseconds. Measured in S1.
- **Asynchronous decompression on the web.** The engine's ZIP reader already
  inflates through the platform's `DecompressionStream`; the document open
  path becomes asynchronous where it is not.
- **An outside tool edits `script.json`.** Its SHA-256 no longer matches the
  manifest (§7.1); the file opens, the anchors are re-found by their words
  (§6.5), and the writer is told the file was changed outside eDraft.

---

## 19. Sources

- Fade In and the Open Screenplay Format:
  <https://github.com/severdia/Open-Screenplay-Format>
- Highland's format: <https://quoteunquoteapps.com/highland-pro/highland-format>
- Beat's file format and document settings (source read):
  <https://github.com/lmparppei/Beat> — `Developer Documentation/Beat File
  Format Specification.md`, `BeatDocumentSettings.m`,
  `BeatDocumentBaseController.m`
- Sketch's file format: <https://developer.sketch.com/file-format/>
- iWork '14 review (single-file format): <https://mjtsai.com/blog/2014/11/29/iwork-14-review/>
- Apple, Designing for Documents in iCloud:
  <https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html>
- SQLite as an application file format: <https://sqlite.org/appfileformat.html>
- SQLite, LoC recommended storage format: <https://www.sqlite.org/locrsf.html>
- Library of Congress, sustainability factors:
  <https://www.loc.gov/preservation/digital/formats/sustain/sustain.shtml>
- ISO/IEC 21320-1:2015, Document Container File: <https://www.iso.org/standard/60101.html>
- RFC 7493, I-JSON: <https://www.rfc-editor.org/rfc/rfc7493>
- RFC 8785, JSON Canonicalization Scheme: <https://www.rfc-editor.org/rfc/rfc8785>
- RFC 6839, `+zip`: <https://www.rfc-editor.org/rfc/rfc6839>
- W3C Web Annotation Data Model: <https://www.w3.org/TR/annotation-model/>
- Automerge binary format: <https://automerge.org/automerge-binary-format-spec/>
- LibreOffice hybrid PDF:
  <https://blog.documentfoundation.org/blog/2024/04/16/quick-tip-creating-hybrid-pdf-files-in-libreoffice/>
- omnipdf: <https://github.com/omnipdf/omnipdf>
- Courier Prime: <https://github.com/quoteunquoteapps/CourierPrime>
- In this repository: [RFC-NOTES-SYSTEM.md](RFC-NOTES-SYSTEM.md),
  [RFC-HIGHLIGHTER.md](RFC-HIGHLIGHTER.md),
  [evaluation-draft-format-plan.md](evaluation-draft-format-plan.md),
  [IOS-PLAN.md](IOS-PLAN.md), [HANDOFF.md](HANDOFF.md).
