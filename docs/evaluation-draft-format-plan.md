# Evaluation — file-format & data-model plan for eDraft

**Date:** 2026-09-10 · **Reviewer:** Kimi · **Subject:** the five-point `.draft` zip + rich-JSON plan
**Method:** plan premises verified against the eDraft repo (`packages/edraft/src/fdx.ts`); prior art verified against Beat's source (GitHub API), vendor documentation, and industry reporting. Related prior work this session: `bold-italic-underline-review.md` and `rfc-emphasis-layout-model.md` — question F intersects the RFC directly.

---

## 1. What's sound, and what the expensive mistakes would be

**Sound:**

- **The zip container with a versioned manifest and split JSON documents** (`screenplay` / `settings` / `production`, optional `origin/source.fdx`, optional assets). Precedented (Fade In's native format is a zipped XML bundle; iWork is a zipped protobuf bundle), tooling-friendly, and the settings/content split is the right granularity.
- **"Model the meaning" for ~90% of the surface** — style runs instead of `<Text Style="Bold+Italic">` fragmentation, revision generations instead of ID-into-lookup. Right instinct.
- **Retaining `origin/source.fdx`.** This preserves the current splice capability, which is the strongest fidelity asset eDraft owns (see below).
- **The stated goal** — "not storing .fdx; the app that produces flawless .fdx" — is the correct ambition for a *native* path. It just isn't the whole story.

**The expensive mistakes, in descending order of cost:**

1. **Letting native generation displace splicing.** Verified in the repo: `openFdx()` retains the original and `rewrite()` *edits it in place* — "The screenplay written back into the file it came from. Unchanged paragraphs keep their bytes. A paragraph whose text changed keeps its attributes and its nested blocks — a scene heading keeps its `<SceneProperties>` and its arc beats" (`fdx.ts:955-965`, "the file is not rebuilt, it is edited", line 945). That is byte-identical no-edit resave, today, proven on a real production draft. **The plan must state explicitly what it currently only implies: when `origin/source.fdx` exists, export splices; native generation is for eDraft-born documents only.** Native generation starts life inferior to the splice path on real files and stays there for a long time.
2. **Dropping unknown/unsupported data on import.** A meaning-model that silently discards what it doesn't understand guarantees lossiness at exactly the edges the plan cares about — and FDX is a moving target (FD 12/13 added navigator beats and alts). Rule: every level of the model carries a verbatim passthrough for unrecognised elements/attributes, re-emitted on export. This is the single cheap decision that makes "flawless" asymptotically reachable.
3. **Treating byte-identity as the acceptance bar for the native path** (see G). Byte-identity is right for splice-no-edit; wrong for native generation, where attribute order, whitespace, and GUIDs are not meaning.
4. **Scope creep at point 5** (see A). PDF "reproduction" and arbitrary-.docx round-trip are not file-format problems; they're layout-analysis problems. Writing them into the plan's promise is how trust in the format dies.

**Premise check (done):** the plan's description of current FDX handling is accurate. One correction of emphasis: eDraft's engine already partially understands the long tail — `fdx.ts` references `SceneProperties`, `CharacterArcBeat`, `ElementSettings`, `DualDialogue`, `LockedPage` — so the plan is extending real coverage, not starting from zero. Also note `fdx.ts` currently shows no revision/tag vocabulary in its hot paths — the production layer is the genuine gap the plan must close.

## 2. (B) FDX completeness — enumeration with keep/drop

Compiled from: the Arqo open FDX conformance suite's fixture categories, the Final Draft user guides (SmartType, Mores & Continueds, custom elements, reports), the lexington/fdx and screenplay-parser format docs, and two source-verified coverage baselines — eDraft's `fdx.ts` and Beat's `FDXImport.m` (which handles only `Content/Paragraph/Text/Style/DualDialogue/ScriptNote/SceneProperties(partial)` — authoring surface only).

| FDX feature | What it carries | Verdict |
|---|---|---|
| `Content > Paragraph @Type`, incl. custom types | Element structure | **Keep** — core |
| `Text @Style` runs (B/I/U/strike, combined) | Inline emphasis | **Keep** — plan point 3/4 |
| `DualDialogue` pairing | Structural two-column layout | **Keep** — it is structure, not a trait |
| `SceneProperties` — `Title`, `Length`, `Color`, `Locked` | Per-scene production metadata | **Keep** |
| Scene numbers incl. letter-suffixed locks (42A), `OmittedScene` + `Length="0"` | Locked numbering, omits | **Keep** |
| `SceneArcBeats` / `CharacterArcBeat` | FD 12/13 navigator beats | **Keep** — authoring data, small |
| `StartsNewPage="Yes"` | Forced breaks | **Keep** |
| `<Revisions>` sets: colour, mark, date, active-set pointer | Revision *generations* | **Keep** — identity and order are meaning |
| `<Paragraph Revised>` + per-run `<Text RevisionID>` | Revision application | **Keep** |
| Deleted-text marks | Struck content retained in file | **Keep** — production diffing reads it |
| Locked pages / A-B pages | Positional page locks | **Keep** — position *is* the meaning |
| `ScriptNote` (anchored, ID, ARGB colour, styled body) | Notes | **Keep** — anchors are structural |
| Tags: `TagNumber` → `<TagData>` categories | Production breakdown tags | **Keep** — typed refs, plan point 3 |
| Cast list (`CastMember`) | Character↔actor mapping | **Keep** — production data |
| `AttributedTitle`, title-page `HeaderAndFooter` + visibility attrs | Rich title page | **Keep** |
| `ElementSettings` + `FontSpec` | Per-type indent/spacing/case/font | **Keep** — user-editable document data |
| Page layout (size, margins), headers/footers, watermark | Presentation | **Keep** |
| Mores & Continueds settings | Render-affecting document behaviour | **Keep** |
| Alts (alternate lines) | Authoring variants | **Keep** |
| Bookmarks | Writer-created navigation | **Keep** (cheap) |
| `DocumentRef` / `XRef` | Navigator cross-refs | **Keep via passthrough** if not modelled |
| SmartType lists | Auto-complete caches | **Drop — regenerate.** FD itself offers "Rebuild SmartType Lists"; they are derived data, not authoring intent. |
| `<Macros>` | Keyboard macros | **Drop** — application preference |
| Spell-check exceptions / dictionaries | App-level tooling | **Drop** |
| View/window state, zoom, caret position | Session state | **Drop** |
| **Any unrecognised element or attribute** | Forward-compat (FD 14+) | **Preserve verbatim, always** — the passthrough rule |

The plan's "enumerable completeness" claim is credible **only** if the passthrough rule and the keep-list above are both in; the drop-list is where lossiness is *legitimate* and should be declared, not discovered.

## 3. (A) Recommended scope line

**Draw it between "authoring formats" and "recovery formats":**

- **Round-trip commitments (fidelity-tested):** `.fountain`, `.fdx`, screenplay-shaped `.docx`, `.md`. These have document models eDraft can natively span.
- **Recovery tools (explicitly best-effort):** PDF import and arbitrary `.docx` import. Highland's PDF "melt" ships with documented caveats ("Not every PDF can be converted… some apps generate really strange PDFs") — that is the honest ceiling, and it is a different discipline (layout analysis), not a file-format feature.
- **Excluded entirely:** PDF *reproduction*. eDraft's PDF story is export-only, from the authoritative paginator.

**Communicating lossiness:** every import produces a visible report — the sibling project notedown already ships the pattern: classify the round trip `identical | normalized | changed | lossy` and warn on suspected loss (`fidelity.ts`). Recovery formats always land with that report; commitment formats land silent when clean.

## 4. (C) Where "model the meaning" breaks down

Right as an instinct; breaks where **FDX's structure is the meaning**:

1. **Revision identity and order.** A revision set's ID, colour, and *position in the ordered set* are what production boards diff against. "The meaning" (this text changed) is insufficient — *which generation* it changed in is the data.
2. **Locked-page positions.** An A-page break is a physical position in a paginated artefact, not an attribute of content. Model it positionally or lose it.
3. **Dual dialogue pairing.** Two paragraph sequences laid out as columns — a structural relation, not a paragraph trait.
4. **Deleted text.** Content that exists but must not render or paginate. Meaning-models tend to drop it on sight; production diffing depends on it surviving.
5. **Note/tag anchors.** A `ScriptNote` is meaningless without its anchored character range — the anchor is structural.

And the counter-example where meaning-modelling is *correct* against FDX's structure: **SmartType lists** — a derived cache FDX persists; regenerate, don't model.

Amendment to the plan's slogan: **model the meaning, preserve the structure verbatim wherever you don't, and treat identity — IDs, ordering, positions, anchors — as meaning.**

## 5. (D) Prior art

| App | FDX depth | Evidence |
|---|---|---|
| **Beat** | Import covers authoring surface only: `Content/Paragraph/Text/Style/DualDialogue/ScriptNote`, partial `SceneProperties`. No revision, tag, SmartType, settings handling in its 510-line importer. Original not retained. | Source-read, `FDXImport.m` |
| **Highland 2** | Exports `.fdx` for production handoff; **no page locking by design** — John August: locking "clashes with its plain-text philosophy". Import melts FDX/PDF to Fountain; production data dropped. | Filmmaker Magazine; Highland switching guide |
| **Fade In** | Native revisions + page/scene locking; FDX import/export; closest to parity. Native format is its own zipped XML. No lossless round-trip claim. | Filmmaker Magazine; Storyflow |
| **WriterDuet** | Production features used through *Pig*'s production; FDX as handoff interchange. Import "almost perfectly with just the odd thing sometimes misformatted". | Filmmaker Magazine; Music Gateway |
| **Arc Studio** | FDX import/export as interchange. | Script Reader Pro |
| **Movie Magic Screenwriter** | Explicitly warns: exporting a locked production script to FDX, "do NOT expect production features like locked pages and scene numbers in FD to correspond". | Screenwriter 6.5 manual |
| **Causality** | Proprietary model, FDX interchange. Not independently verified this review. | — |

**Has anyone achieved lossless FDX round-trip without retaining the original?** No one credibly claims it. Every vendor treats FDX as interchange, and the production layer is exactly what dies in transit (Screenwriter's warning; "a handoff fails when scene numbers vanish, dual dialogue collapses" — ScreenWeaver). eDraft's splice is the existence proof that *retention* is what buys fidelity. **What they all got wrong is the same thing:** they modelled the authoring surface and let production data fall off the truck. eDraft's counter-move is already in hand: the splice path. There is also announced prior art for the test harness — the **Arqo FDX conformance suite** (21 fixtures, 33 tracked features, parse→canonicalize→emit→re-parse→deep-equal scoring, per-fixture scorecard). **Availability caveat (verified 2026-09-10):** the suite's site advertises "MIT-licensed · Forkable" and links to `github.com/ahujatries/Arqo1`, but that repo is private — 404 both anonymously and authenticated, and the author's own `arqo-releases` repo states the source repo "stays private". So the suite is *documented* but currently **not obtainable**: the fixtures cannot be run, adopted, or audited, and the claimed 21/21 pass rate is unverifiable. Treat its published taxonomy (locked 42A numbers, omits with `Length="0"`, revision sets/marks/`RevisionID` stamps, `SceneArcBeats`, styled title-page header/footer, cue extensions, dual dialogue with parentheticals, Unicode/RTL, entity escaping) as a checklist for fixtures we build ourselves from files we have rights to, and re-check for a public release periodically.

## 6. (F) Inline runs vs. the paginator — and the collision with my RFC

The plan's point 4 contradicts the RFC I delivered this morning (D1: markers in the model). I'm updating D1, and I want to be precise about why: **the premise changed.** The RFC assumed `.draft` remains Fountain-text-canonical. If this plan is adopted, canonical storage becomes rich JSON — and raw-marker text inside a rich model is the worst of both worlds. **Under this plan, runs-in-model is right**, and it makes the editor strictly simpler: there are no markers in storage, so ContentIndex is the only index, and §4's caret atomicity (the hard part) becomes ordinary attributed-text editing — Pages' own mechanics. The cost relocates to the Fountain boundary: import must parse markers into runs *and* escape literal asterisks; export must synthesize markers *and* escape content asterisks. That boundary is exactly what the conformance corpus exists to pin — extend `serialise.json`/`parse.json` fixtures accordingly.

**What does not change, under either storage model:** the paginator counts content only. Beat proves markers-in-text can satisfy that invariant (its paginator measures stripped text); Word/Pages/Final Draft prove runs satisfy it. The expensive mistake is neither choice — it's letting any consumer measure text that still contains markup. (And note Beat's model buys *it* something eDraft doesn't need: `.fountain` *is* Beat's identity. eDraft's identity is the authoritative page count.)

## 7. (G) The acceptance test

**Two bars, not one:**

1. **Splice path (origin present):** byte-identical no-edit resave. Already achieved; keep it as a permanent CI gate on the real production draft (19 revisions / 171 revised runs / 25 locked pages / 73 deleted marks / 248 tags / 6 dual-dialogue blocks / 136 emphasis runs / 3 script notes — these counts become the regression tripwires).
2. **Native path (origin deleted):** **semantic equivalence, not byte-identity.** Canonicalise both sides (sort attributes, normalise whitespace, strip GUIDs/timestamps via an explicit, reviewed ignore list), then diff with a schema-aware comparer. Structure it as a **per-feature-class scorecard** — table §2's rows are the scorecard rows — over a corpus of real production files, plus property tests (`native → .fdx → import → model equality`). Never a single pass/fail: the report says *which* class dropped *what* on *which* path. The Arqo suite's published taxonomy is the external checklist for fixture coverage (see §5's availability caveat — the suite itself is currently private, so our corpus must be our own).

Byte-identity for native generation is the kind of bar that looks rigorous and is actually noise: it fails on attribute ordering that no consumer can observe.

## 8. What the plan hasn't considered

1. **Export preference order.** State it: origin present → splice; origin absent → native. Forever.
2. **Migration of existing `.draft` files.** Old format needs a reader forever; migration is read-old/write-new with the original left untouched.
3. **Atomic saves.** Zip + partial write = corrupted document. Write-temp-then-rename, always.
4. **Unknown-element passthrough** (mistake #2 above) — the only defence against FD 14.
5. **Diff-friendliness.** Fountain text was git-diffable; a zip is not. Pretty-printed JSON with stable key order recovers most of it — writers do version-control their drafts.
6. **Quick Look / Spotlight** for the new container (register a UTI; previews need a rendering path that doesn't open the app).
7. **Asset dedup:** never rewrite unchanged blobs on save; content-hash `assets/`.
8. **FDX is a moving target.** Assign schema-watch ownership; new FD versions get fixture days.
9. **The RFC collision** (§6) — decide the storage model once, coherently, across both documents.

---

### Sources

- eDraft repo: `packages/edraft/src/fdx.ts` (openFdx/rewrite, lines 945, 955–965, 1141–1160)
- Beat source (github.com/lmparppei/Beat): `Frameworks/BeatFileExport/.../FDXImport.m`, `FDXInterface.m`, `BeatFDXExport.m`
- Arqo, "FDX Conformance" (tryarqo.com/es/fdx-conformance) — announced suite; linked repo `ahujatries/Arqo1` is private as of 2026-09-10 (404 verified anonymously and authenticated)
- Filmmaker Magazine, "Is Final Draft the Final Answer?" (2023) — August on Highland locking; Sarnoski/WriterDuet on *Pig*
- Movie Magic Screenwriter 6.5 User's Manual, §8 (FDX export warnings)
- Final Draft user guides FD10–FD13 (SmartType lists, Mores & Continueds, custom elements, reports)
- Cast & Crew blog, Final Draft interview (FDX openness)
- Highland 2 "Switching from Final Draft" guide (PDF melting caveats; FDX export)
- ScreenWeaver, "Fade In vs WriterDuet" (handoff failure modes)
- Music Gateway, WriterDuet review (import fidelity)
- Script Reader Pro / Storyflow (Arc Studio, Fade In format support)
- pkg.go.dev/github.com/LaPingvino/lexington/fdx; DeepWiki screenplay-parser (FDX structure)
