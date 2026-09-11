# Peer Review — "Goal: support bold / italic / underline" recommendation

**Date:** 2026-09-10 · **Reviewer:** Kimi · **Subject document:** `Goal support bold i.txt` (another assistant's recommendation)
**Method:** every "measured" claim re-checked against the repos at `~/Documents/development`; every "from memory" claim checked against primary sources (format specs, Apple documentation, and the actual Beat source tree at github.com/lmparppei/Beat @ HEAD, read via the GitHub API).

---

## 1. Verdicts on the numbered claims

### MEASURED claims (against the sibling repos)

| # | Claim (abridged) | Verdict |
|---|---|---|
| 1 | writedown conceals markers via `Decoration.replace({})` for 7 node types | **True in substance, structurally imprecise** |
| 2 | Concealment gated on `selectionTouchesLine(...)` | **True** |
| 3 | Decorations built only over `view.visibleRanges` | **True** |
| 4 | README: JSON-tree editors "can't round-trip markdown losslessly" | **True, verbatim** |
| 5 | notedown: `sheet.innerHTML = renderMarkdown(...)`; `pageChanged()` → `serialiseMarkdown(sheet)` | **True** |
| 6 | `serialise.ts`: `if (isBold(child)) out += wrapRun('**', inner)` | **True** |
| 7 | `fidelity.ts` classifies `identical \| normalized \| changed \| lossy` | **True** |
| 8 | screenplay/types.ts: "Emphasis markers are preserved raw for now" | **True, verbatim** |
| 9 | ScriptEditor.svelte uses `textContent` throughout, not `innerHTML` | **True with one small overstatement** |

Notes on the two imperfections:

- **Claim 1** lists seven node types as if they share one mechanism. In `live-preview.ts` the `CONCEALED` set is `EmphasisMark`, `CodeMark`, `StrikethroughMark` (line 82); `HeaderMark`, `QuoteMark`, `LinkMark`, `URL` are concealed in separate code paths (lines ~114, ~135, ~176). All seven do end up as `Decoration.replace({})`, so the conclusion stands; the node list conflates two mechanisms.
- **Claim 9** says `textContent` "throughout". `textContent` is indeed the block-text accessor (12 uses), but `innerHTML` appears twice for clearing elements (lines ~276, ~334). Cosmetic, but "throughout" is not literal.

### FROM-MEMORY claims (against primary sources)

| # | Claim (abridged) | Verdict |
|---|---|---|
| 10 | Word / Pages / Google Docs model inline styling as styled runs over plain text | **True** (Pages partially by inference — see below) |
| 11 | Obsidian and Typora use conceal-on-inactive-line | **True for Obsidian; approximate for Typora** |
| 12 | A permanently clean viewport requires rich model + serialise-on-save, or atomic concealed ranges | **True** — confirmed by Beat's own source comments |
| 13 | TextKit 1 hiding = `NSGlyphProperty.null` from `shouldGenerateGlyphs:...`; asked to verify currency on macOS 26 + TextKit 2 equivalent | **Mechanism real and current; phrasing imprecise; TextKit 2 has no equivalent** |

**Claim 10 evidence:**
- **Word / OOXML (ISO/IEC 29500):** a run (`<w:r>`) is a contiguous region of text with identical properties (`<w:rPr>`); the text contains no markup. (Microsoft Learn, "Working with runs".)
- **LibreOffice / ODF:** `<text:span text:style-name="T1">` wraps attributed portions; direct formatting becomes *automatic styles* with `fo:font-weight` etc. (OASIS OpenDocument v1.3, §6.1.7.)
- **Google Docs:** the public API exposes `ParagraphElement.textRun` → `TextRun{textStyle}` with boolean `bold` / `italic` / `underline`; text content is plain. (Google Docs API reference.)
- **Pages / iWork:** `.pages` is a ZIP of Snappy-compressed protobuf "IWA" streams; the format is publicly **undocumented** and known through reverse engineering (obriensp/iWorkFileFormat, psobot/keynote-parser). Reverse-engineered schemas show the same attributed-run shape, but there is no Apple-published spec to cite — the claim's inclusion of Pages rests on reverse-engineered evidence, not documentation.

**Claim 11 evidence:**
- **Obsidian:** Live Preview conceals syntax except where the cursor/selection is — true, and the failure mode (cursor jumps, text shifting when markers toggle) is a documented, long-running user complaint on the Obsidian forum.
- **Typora:** reveals markup when the cursor enters the *element* (word/span), not the whole line. Same family, different granularity. Grouping them under one named approach is coarse.
- Bonus, source-verified this review: **Beat** implements exactly this pattern natively (details in §2).

**Claim 12 evidence:** Beat's output builder adds a `BeatEditorRange` attribute mapping every rendered range back to its raw editor range, with the comment that this is groundwork for a "possible upcoming more WYSIWYG-like experience" — i.e., the closest prior art explicitly treats the raw↔rendered range mapping as the hard prerequisite for a permanently clean viewport. The Obsidian cursor-jump complaints document what happens when concealed ranges are *not* atomic. The dichotomy in claim 12 is real.

**Claim 13 evidence:**
- The mechanism is real: `layoutManager(_:shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:)` is an `NSLayoutManagerDelegate` method; setting `NSGlyphPropertyNull` on a glyph makes it undrawn and zero-width. The phrasing "return `NSGlyphProperty.null`" is imprecise — you copy the properties array, OR the flag onto the entries for the character indexes you want hidden, install them with `setGlyphs(_:properties:characterIndexes:font:forGlyphRange:)`, and return the glyph *count*.
- **Currency on macOS 26:** the delegate method is not deprecated and TextKit 1 remains fully supported; eDraft's own surface instantiates `NSLayoutManager` directly (`ScriptLayout.swift:224`), so this path is available to us today.
- **TextKit 2 equivalent: there is none.** WWDC22 states there are "zero glyph APIs in TextKit 2". An Apple Developer Forums thread from March 2025 (also filed as FB16905066) is precisely this use case — hiding Markdown characters — and the poster found no TK2 interception point. The TextKit 2 answer is a different mechanism: substitute content at the `NSTextContentStorage`/`NSTextElement` level (the WWDC21 sample app hides comments this way). That is "atomic concealed ranges" implemented as custom elements, not glyph suppression.

### Independent research (A, B, D)

**A — how the big editors represent inline formatting:** covered under claim 10. All four families converged on the same model: plain character stream + disjoint styled ranges. None embed markers in the text.

**B — markdown editor survey:**

| App | Behavior |
|---|---|
| Obsidian | Conceal except cursor line (Live Preview); documented cursor-jump complaints |
| Typora | True WYSIWYG; reveals source of the *element* under the cursor; separate source mode |
| Beat | Markers visible by default; **optional** conceal-except-edited-line (`hideFountainMarkup`, default `NO`) via glyph-nulling |
| iA Writer | Never hides markers; styles them and the run |
| Ulysses | Cannot fully hide markup — its own help pages state themes can only dim tags |
| Bear | Optional "Hide Markdown" setting (per its FAQ) |
| Zettlr | WYSIWYM: renders formatting inline but markers stay visible; a "hide heading characters" request was declined ("Zettlr is fundamentally a WYSIWYM-editor", issue #856) |
| MarkText | True WYSIWYG with a separate source-code mode |

Takeaway: *reveal-on-cursor* is the dominant compromise among apps that conceal; several respected apps chose never to conceal. Nobody serious conceals permanently without either a rich model (Typora/MarkText, which are document-model editors) or glyph-level tricks plus reveal-on-edit (Obsidian, Beat).

**D — scale (500–3000 pages):**
- **CodeMirror visible-range decorations** (writedown, Obsidian): decoration work is bounded by the viewport, not the document — scales fine.
- **contenteditable `innerHTML` re-render + full serialise per edit** (notedown's WritingDesk path): O(document) work per keystroke plus an unbounded DOM — this is the pattern that gets dangerous at 900–3000 pages. Not recommended for eDraft's main surface.
- **Beat's per-line parse + incremental, cached, background pagination** (block heights cached per block, line heights per line UUID): built for exactly this domain.
- **TextKit 1 glyph substitution** is per-layout-pass and Beat guardrails it to single-line glyph runs — negligible cost.
- **eDraft's char-count wrap** is O(n) with tiny constants; parsing emphasis per element keeps it O(n). The risk is not CPU; it is *correctness drift between consumers* (see §3).

---

## 2. What Beat actually does (research C — read from source, not inferred)

Beat is the closest possible prior art — open-source macOS Fountain editor, AppKit, TextKit 1, same file format, same problem. Its architecture, verified file by file:

**Storage.** The editor's `NSTextStorage` holds the **raw Fountain text, markers included**. There is no separate rich document model.

**Per-line parse.** Each `Line` carries `formattedRanges` — a dictionary of `NSMutableIndexSet` per format type (italic, bold, bold-italic, underline) — parsed per line by `resetFormatting` (`Line.m`, ~line 380) using `InlineFormatting` patterns `*` / `**` / `_` (`Line.h` lines 49–74). It also computes **`contentRanges`**: the index set of real content characters, i.e. the string *minus* formatting markers, notes, and omissions (`Line+RangeLookup.m` lines 64–67, 121+).

**Editor styling.** `BeatEditorFormatting` applies font traits (Courier bold/italic/bold-italic) and underline to the parsed ranges — but only **between** the markers: `stylize:value:line:range:formattingSymbol:` trims `symLen` characters off both ends of each range before applying the attribute (`BeatEditorFormatting.m`, ~lines 603–616 and ~896–921). The marker characters themselves receive no styling in this pass and remain visible, default-colored.

**Concealment — optional, line-gated, glyph-level.** `BeatLayoutManager` (an `NSLayoutManager` subclass) implements `shouldGenerateGlyphs:properties:characterIndexes:font:forGlyphRange:` (line 835, commented "Generate customized glyphs, includes all-caps lines for scene headings and **hiding markup**"). It computes `currentlyEditing` (selection intersects the line, line 852); when the `hideFountainMarkup` preference is on **and** the line is not being edited, every glyph whose character index is in the line's formatting ranges gets `prop |= NSGlyphPropertyNull` — invisible, zero width (lines 900–911). The minimap (`BeatMiniMap.swift`) uses the same trick. **Default is OFF** (`BeatSettingHideFountainMarkup: @NO`, `BeatUserDefaults.m` line 136). So Beat's default experience is "markers visible, run styled"; Obsidian-style live preview is an opt-in.

**Caret.** No special caret or hit-testing machinery around markers anywhere in `BeatTextView.m`. It doesn't need any: markers are real characters, visible (or revealed) exactly where editing happens. Claim 12's "atomic ranges" problem is sidestepped, not solved.

**Print / PDF / pagination — the decisive part.** Rendering never uses the editor string. `Line+AttributedStrings.m:183`, `attributedStringForOutputWith:` — documented "Returns an attributed string **without formatting markup**" — builds the output by appending **only `contentRanges`** substrings (attributes carried across), so marker characters are physically absent from the printed text. Each emitted range is stamped with a `BeatEditorRange` attribute mapping it back to the raw editor range — with the telling comment that this is "an experimental part of the possible upcoming more WYSIWYG-like experience". The paginator (`BeatPagination2`) then **measures rendered heights**: per-line heights cached by line UUID, block heights, `remainingSpace` vs `maxPageHeight` (`BeatPagination.m` ~273–286, ~501–516; `BeatPaginationBlock.m` `heightForLine:`). It does **not** count characters. Consequently markers can never affect page breaks — the paginator never sees them.

**Paste boundary.** `NSAttributedString+ConvertToFountain.m` converts pasted rich text to Fountain by emitting `**` / `*` / `_` around runs whose font traits / underline attribute demand it. Markers are generated at the system boundary, exactly where attributed text enters.

**Beat's answer to our question, in one sentence:** markers live in the storage; the parser derives per-line style ranges and content ranges; the editor styles (and optionally glyph-hides) markers; and every downstream consumer — renderer, paginator, exporter — is fed the marker-stripped representation, with an explicit raw↔rendered range map for the way back.

---

## 3. The pagination question — is a "printed length" function the right fix?

**The diagnosis is correct.** eDraft's engine wraps by counting characters (60/line, 55 lines/page), pagination is authoritative (PDF generation and production scheduling depend on it), and `**bold**` in element text would inflate line length and wrap early. That must not ship.

**The proposed fix is directionally right but materially understated.** Three things the "one function" framing omits:

1. **It cannot be Swift-only.** eDraft's paginator is conformance-pinned to a TypeScript twin (`apple/eDraftEngine/Fixtures/paginate.json`, exported by `scripts/engine-conformance-export.mjs`, and fixture freshness is now CI-gated). A printed-length rule is part of the *engine's definition*; it must land in the TypeScript source of truth, with fixtures regenerated and both implementations proven identical. A Swift-side-only helper silently forks the engine.
2. **It cannot be wrap-only.** Every consumer of element text must agree on which string it is looking at: wrap, serialise, statistics, PDF export, and — the one everyone forgets — **caret and hit-test mapping in the editor**, which needs a raw↔content index map, not just a length. Beat implements the complete version of this pattern: `formattedRanges` + `contentRanges` + `BeatEditorRange` back-mapping + a separate render path. "One length function" is the tip of that iceberg.
3. **The invariant must be stated correctly.** Beat proves markers do **not** need to leave the model text — claiming "markers shouldn't be in the model at all" is false as a necessity claim. The real invariant is: *the paginator (and every layout/statistics/export consumer) must never see marker characters.* Two architectures satisfy it:
   - **(a) Boundary parsing (Word/Pages/Google Docs model):** parse markers into style ranges at the file boundary; the model text is clean; the paginator *cannot* miscount by construction. Cost: serialise-on-save must regenerate markers perfectly — this is exactly where notedown needed a `fidelity.ts` classifier and where writedown's README claims loss is unavoidable for tree models.
   - **(b) Beat's model (markers in storage + derived ranges):** raw text stays authoritative (perfect round-trip for free); the parser derives style/content ranges per line; all layout and export consume the stripped representation via an explicit mapping. Cost: discipline — every consumer must use the derived representation, forever.

**Recommendation: (b), implemented Beat-style, with eDraft's conformance harness as the guardrail Beat lacks.** Concretely:

1. **Engine (TS first, Swift mirrors):** a per-line emphasis parser implementing Fountain's actual rules — `*` / `**` / `***` / `_`, backslash escapes, no cross-line carry-over (per the Fountain spec's Emphasis section) — emitting style ranges and a content string per element. Wrap, stats, and export consume the content string. Regenerate `paginate.json` and add emphasis fixtures; CI freshness gate already exists.
2. **PDF export** renders from content + style ranges (it already consumes engine output; keep it that way).
3. **Editor surface (TextKit 1, which eDraft already uses):** apply bold/italic/underline traits to the styled ranges; dim the markers (iA Writer-style) as the safe default. Then, as an opt-in, add conceal-except-edited-line via an `NSLayoutManager` subclass implementing `shouldGenerateGlyphs:…` with `NSGlyphPropertyNull` — Beat's exact, shipping, same-platform mechanism. The edited-line reveal makes caret atomicity unnecessary. Do **not** pursue TextKit 2 for this: there is no glyph hook; hiding would require element substitution and is a different, riskier project.
4. **Explicitly rejected:** contenteditable `innerHTML` round-trip per keystroke (notedown's WritingDesk pattern — O(document) per edit, unacceptable at 900+ pages) and a tree-model rewrite (round-trip fidelity risk without delivering anything Beat's pattern doesn't).

---

## 4. Hallucination / overstatement assessment

**No fabrications found.** All nine "measured" claims verified against the repos, including two verbatim quotes that match exactly. For a document of this specificity, that is a strong result. The issues are precision, not invention:

1. **Claim 1** merges the `CONCEALED` set and three separate concealment code paths into one node list — right conclusion, wrong structure.
2. **Claim 9**'s "throughout" ignores two `innerHTML` clearing calls. Trivial.
3. **Claim 11** groups Typora with Obsidian under "conceal-on-inactive-line"; Typora reveals at element granularity, not line granularity. Material if someone were designing to the claim.
4. **Claim 13**'s mechanism is real but the phrasing ("return `NSGlyphProperty.null`") mis-describes the API shape, and — more importantly — the claim did not flag that the mechanism is **TextKit 1-only with no TextKit 2 equivalent**. For eDraft (TextKit 1 surface today) this is fine; as general guidance it has a shelf life.
5. **The "printed length" fix** is presented as a small, local change. It is not wrong; it is scope-understated — it omits the TypeScript source-of-truth requirement, the fixture regeneration, the consumer audit, and the caret-mapping problem. Beat's source shows what the complete version of the idea actually consists of.
6. The Fountain-spec paraphrase ("emphasis markers are not printed") is true in substance; the spec demonstrates marker-free formatted output by example rather than stating the sentence verbatim. Worth being precise when the spec is the authority being cited.

**Confidence:** high on all local-repo and Beat claims (read from source this review); high on format-spec claims (primary specs cited); moderate only on Pages internals (reverse-engineered format, no Apple documentation exists to cite).


---

## Addendum (2026-09-10, second pass — challenge response)

The conclusion was challenged; the two links that had been inferred rather than read are now closed, and the wider screenwriting landscape was surveyed.

### Evidence chain — now complete end-to-end

1. **Markers are inserted as literal characters.** ⌘B/⌘I/⌘U → `makeBold:`/`makeItalic:`/`makeUnderlined:` → `format:startingSymbol:endSymbol:style:`, which calls `[_delegate.textActions addString:startingSymbol atIndex:…]` and `replaceRange:withString:` on the document text; toggling off *removes* the literal symbols (`BeatEditorFormattingActions.m` lines 236–252, 382–460). The toggle logic includes the edge cases (bold-italic disambiguation) one only writes when the markers are real text.
2. **Storage = raw text.** `Line.attributedString` is built from `self.string` (raw) with `Style` attributes stamped over the formatted ranges (`Line+AttributedStrings.m` ~82–108).
3. **Editor styles between markers only** (`stylize:…formattingSymbol:` trims `symLen` off both ends, `BeatEditorFormatting.m` ~896–921).
4. **Optional concealment is glyph-level and line-gated** (`BeatLayoutManager.m` 835/852/900–911; default OFF, `BeatUserDefaults.m:136`).
5. **`contentRanges` = full line range minus `formattingRanges`** (`Line+RangeLookup.m:41–57`) — this is the base set the output builder enumerates.
6. **The paginator measures marker-stripped text.** `heightForLine:` builds its measurement string from `[line stripFormattingWithSettings:]` and measures `heightWithContainerWidth:` (`BeatPaginationBlock.m` ~155–175). Not inferred — read.
7. **The saved file is the raw text verbatim.** `dataOfType:` → `createDocumentFile` → `parser.screenplayForSaving` (falling back to `textView.string` if editor and parser desync) (`Document.m:275–294`, `BeatDocumentBaseController.m:702–733`).

### Landscape survey (research C completed: the commercial apps)

- **Slugline** (official docs): "you're seeing the raw text file you're creating… Slugline shows these characters in **light gray**" — markers visible and dimmed, never concealed.
- **Highland 2** (official switching guide): "Because it's a plain-text editor, Highland shows the markup in the document… When you switch to Preview, these extra symbols are gone." — markers visible, never concealed.
- **Final Draft (.fdx)**: rich model — `<Paragraph Type="…">` containing multiple `<Text Style="Bold">` runs; no markers anywhere. (lexington/fdx package docs: "A paragraph can have multiple text elements for styling purposes".) Fade In is likewise a rich-model editor.

**Conclusion:** within the plain-text-native family, Beat is the *most* sophisticated implementation — Slugline and Highland do strictly less (dim or show, never conceal). The rich-model alternative (Final Draft / Pages / Word) is the only architecturally "better" display path, and it requires abandoning plain-text-canonical storage — for a Fountain app that is a product regression, not an improvement.

**Where eDraft can genuinely do better than Beat:** Beat enforces the stripped representation by *convention* — every consumer must remember to call `stripFormatting` / `attributedStringForOutputWith:`, and the code shows the cost (guardrail comments, a convoluted macro re-parse, desync fallbacks). eDraft has something Beat lacks: a sealed engine module with a conformance twin and CI-gated fixtures. Make the engine's *public output* the layout triple — content string + style ranges + raw↔content index map — and no consumer can touch raw text by construction. Convention becomes boundary; discipline becomes type system. That is the improvement worth making, and it is architectural, not a different storage model.
