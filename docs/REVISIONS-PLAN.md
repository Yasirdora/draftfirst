# Revisions — Production Drafts, Marks & Coloured Pages

**Status:** blocked on one decision — where revision state is stored (§4)
**Targets:** iOS first (engine is platform-neutral and already builds for macOS)
**Why it matters:** this is the single feature that separates "a good writing app"
from "software a production can run on". Everything else in the app is ready for
professional use; without this, a distributed script cannot be revised safely.

---

## 0. TL;DR

Nobody picks a revision colour. **Colour is a consequence, not a choice.** A person
issues a revision; the app diffs against the last issued draft, marks what changed,
locks the pages, and reissues the changed ones on the next colour in the run.

The objective half is built and tested. The blocker is that **revision state has
nowhere to live** — `.draft` is plain Fountain, which has no revision syntax, and our
FDX codec carries none either. That is a storage decision (§4), not a rendering one,
and it needs answering before the rest is wiring.

---

## 1. What a production actually does

Once a script is distributed it stops being a document and becomes a controlled
artefact. Every department works from a page and a scene number.

- The original goes out on **white**.
- Each subsequent revision goes out on the next colour: **blue, pink, yellow, green,
  goldenrod, salmon, cherry, buff** — then round again as *double* white, double blue,
  and so on.
- Only **changed pages** are reissued. A crew member swaps the blue page into their
  binder and keeps the rest.
- Changed lines carry an **asterisk** in the margin, so a reader finds the change
  without re-reading the page.
- Pages are **locked**: existing page numbers never move. An inserted page becomes
  `12A`, exactly as an inserted scene becomes scene `12A`.
- A deleted scene is not removed — it becomes **OMITTED**, keeping its number so
  nobody's schedule develops a hole.

---

## 2. What is already built

Both pieces are objective industry standard, correct under any answer to §4, and
fully tested. Nothing here gets thrown away by the storage decision.

| Piece | Location | Tests |
|---|---|---|
| Colour run + `.next`, double/triple passes | `DraftFirstEngine/…/Editor/Revisions.swift` | `RevisionsTests` (10) |
| Change detection (which lines get an asterisk) | same file, `RevisionDiff` | same |
| Scene numbering, locked lettering (`12A`) | `…/Editor/SceneNumbering.swift` | `SceneNumberingTests` (8) |
| Margin drawing on the printed page | `DraftFirst/Document/DraftFirstDocument.swift` | `SceneNumberRenderingTests` (4) |

Notes on the diff: it trims the common head and tail first, then runs an exact LCS on
what remains. A revision touches a small part of a long script, so the middle is
usually tiny. Past `exactLimit` (1,500 elements a side) it reports the whole changed
span rather than allocating millions of cells — honest, because a rewrite that large
genuinely is all new. Assigning a scene number is deliberately **not** a change, or
every scene would gain an asterisk the first time a production locked its numbers.

The scene-number work also delivered the margin-drawing path the asterisks will use:
numbers resolve through `PageLine.element` back into the screenplay, so the paginator
stays byte-identical to its conformance corpus. **Asterisks must follow the same
route** — never by teaching the paginator to emit them.

---

## 3. The user-facing flow

One action: **Issue Revision**.

1. The writer picks *Issue Revision* (Settings → Page & Format, beside Scene Numbers).
2. A sheet appears pre-filled with the next colour in the run, editable — productions
   skip (plenty start at blue) and restart the run for a new season.
3. On confirm:
   - diff current script against the last issued snapshot,
   - stamp changed elements with the revision index,
   - lock page numbering,
   - store a new snapshot.
4. Export offers **Full Script** or **Changed Pages Only**. Both print asterisks and
   name the colour and date on each page.

A colour is never chosen retroactively. A blue page that went out is blue forever.

---

## 4. The blocker — where does revision state live?

Two things must persist: **the marks** (which revision each element last changed in)
and **the snapshots** (the last issued draft, to diff against). Neither has a home.

- `.draft` is plain Fountain. Fountain has no revision syntax.
- Our FDX codec carries no revision data — verified, zero occurrences in `Fdx.swift`
  — although the FDX format itself defines `Revision` attributes we could adopt.

| | Approach | Gains | Costs |
|---|---|---|---|
| **a** | Metadata block inside `.draft` | Single file, no migration | Breaks the promise that a `.draft` is valid Fountain any tool can open |
| **b** | Sidecar file (`.draft` + `.revisions`) | Fountain stays pure | A file that *can* be separated from its script *will* be |
| **c** | Fountain notes `[[rev:blue]]` per element | Interoperable, survives round-trips | Visible clutter; other apps render them as notes |
| **d** | Package document — `.draft` becomes a wrapper holding script, snapshots, marks | Room to grow; matches what Final Draft effectively does | Changes the document type; existing files need migrating |

**Recommendation: (d).** Revisions will not be the last thing needing to live beside
the script — locked page maps, production notes and per-draft snapshots all want a
home. A package gives room; a metadata block gets renegotiated every time something
is added.

Migration is the real cost and the reason this is a decision rather than a task:
every existing `.draft` on a device must open unchanged and upgrade cleanly.

---

## 5. Still to build, once §4 is answered

Roughly in order:

1. **Storage** — the model from §4, plus migration for existing documents.
2. **Snapshots** — keep the last issued draft; the diff is inert without it.
3. **Marks on the page** — asterisks via the `PageLine.element` route, so the
   paginator and its conformance corpus stay untouched.
4. **Page locking** — page numbers freeze; inserted pages become `12A`. This is the
   page-level twin of the scene lettering already in `SceneNumbering`.
5. **Omitted scenes** — a deleted scene keeps its number and prints `OMITTED`.
6. **Changed-pages-only export**, with the colour and date printed on each page.
7. **Title-page revision line** — "Blue Revised 3/9/26", as productions expect.
8. **FDX revision attributes** — read and write them, so a script arriving from Final
   Draft keeps its revision history instead of silently losing it.

---

## 6. Open questions

- **§4 storage model** — the blocker.
- Do we adopt FDX's `Revision` attributes as our internal model, so import/export is
  lossless by construction?
- Should issuing a revision also run *Number New Scenes*, or stay separate? A
  production locks numbers and issues revisions at the same moment, so coupling them
  may be right — but it makes one action do two things.
- Per-episode or per-season colour runs for television: does the run reset, and where
  is that recorded?

---

## 7. Sequencing note

This should land **before** the macOS port (see `MACOS-PLAN.md`). The engine is
already platform-neutral — its tests run on macOS today — but `ScriptTextView.swift`
is ~1,950 lines of UIKit that a Mac version must replace. Porting first would mean
maintaining two copies of the keystroke path while this feature is still changing it.

The keystroke path is now pinned by `KeystrokePathCharacterisationTests` (12 tests),
which is the asset that makes both this work and the eventual port safe: it defines
what the editor must do, with no UIKit in the assertions.
