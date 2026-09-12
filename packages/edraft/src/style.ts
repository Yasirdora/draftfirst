/**
 * eDraft Screenwriting Engine emphasis model.
 *
 * Runs-in-model (RFC v2.1): element text is marker-free content; styling
 * lives on StyleRuns hanging off it. Marker characters (`*`, `**`, `***`,
 * `_`, and the `~~` strikeout extension) exist only at the Fountain
 * boundary — parsed here on the way in, synthesised here on the way out.
 *
 * Grammar: the Fountain spec's Emphasis section (fountain.io/syntax), which
 * defers to Markdown with underscores reserved for underline:
 *   - `*italic*`, `**bold**`, `***bold italic***`, `_underline_`
 *   - combinations nest (`_Steel FILLS the *Leupold* scope_`)
 *   - backslash escapes (`**\*9765\***` is bold literal asterisks)
 *   - whitespace flanking is meaningful: an opener may not be followed by
 *     JS `\s`, a closer may not be preceded by it — so
 *     `He dialed *69 and then *23` italicises nothing, while
 *     `*69 and then 23*` italicises (both spec examples)
 *   - emphasis never crosses a line break; unclosed delimiters are literal
 *
 * Delimiter-run rules beyond the spec, pinned by the conformance corpus:
 *   - `*` runs of length 1–3 are delimiters; 4+ is literal text
 *   - `_` is a delimiter only as a run of exactly 1 (`__x__` stays literal —
 *     Fountain reserves underscores for underline, never bold)
 *   - `~~` (exactly 2) is the strikeout delimiter; a single `~` is literal
 *     (line-start `~` is lyrics, handled by the element parser)
 *   - a delimiter that can both open and close closes first (Markdown
 *     convention); an unmatched closer that can open becomes an opener
 *   - an empty match (`****` can never form one) styles nothing
 *
 * Coordinates are UTF-16 code units — the ContentIndex space — matching
 * `String.length` and `NSRange`, so the web editor, TextKit and both engine
 * ports share offsets exactly. Flanking uses the JS `\s` set (see the
 * engine's JSWhitespace notes: U+0085 NEL is NOT whitespace here).
 *
 * Canonical run form (the .draft wire shape): sorted by start, strictly
 * non-overlapping (overlaps split into segments carrying the union),
 * adjacent runs merged only when every property is equal (styles,
 * revisionID, tagNumbers), no zero-length runs, clamped to the text.
 * AllCaps and HiddenText have no Fountain spelling: synthesis drops them
 * (the fidelity contract's recorded loss for the Fountain boundary; FDX
 * carries them natively).
 */

import type { StyleRun, StyleToken } from './types.js';

/** Canonical token order for `StyleRun.styles` and the FDX Style attribute. */
export const STYLE_ORDER: readonly StyleToken[] = [
	'Bold',
	'Italic',
	'Underline',
	'Strikeout',
	'AllCaps',
	'HiddenText'
];

function sortStyles(styles: Iterable<StyleToken>): StyleToken[] {
	const present = new Set(styles);
	return STYLE_ORDER.filter((token) => present.has(token));
}

/** JS `\s`, per the engine's cross-port contract (NOT Unicode White_Space). */
function isWhitespaceChar(ch: string | undefined): boolean {
	return ch !== undefined && /\s/.test(ch);
}

/* Markdown's backslash convention, per the Fountain spec: a backslash
   escapes any ASCII punctuation character; before anything else it is a
   literal backslash. */
const ASCII_PUNCTUATION = /^[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~]$/;

/* ------------------------------------------------------------------ */
/* parse                                                               */
/* ------------------------------------------------------------------ */

type DelimKind = 'star' | 'under' | 'tilde';

interface TextPiece {
	readonly kind: 'text';
	text: string;
}

interface DelimPiece {
	readonly kind: 'delim';
	readonly delim: DelimKind;
	/** Raw source length of the run (1–3 stars, 1 underscore, 2 tildes). */
	readonly rawCount: number;
	/** Where the run begins in the raw source — liveCollapse needs raw
	    coordinates to remove exactly the markers it paired. */
	readonly rawStart: number;
	readonly canOpen: boolean;
	readonly canClose: boolean;
	/** Chars consumed as a closer (the run's leftmost) / as an opener (the
	    rightmost). Anything in between is literal text. */
	closerConsumed: number;
	openerConsumed: number;
	/** Absolute index into the pieces array, assigned after scanning. */
	index: number;
}

type Piece = TextPiece | DelimPiece;

interface StyleSpan {
	/** Piece indices; content coordinates are resolved during assembly. */
	opener: number;
	closer: number;
	styles: StyleToken[];
}

/** Chars a delimiter run contributes to content: the never-consumed middle. */
function literalCount(piece: DelimPiece): number {
	return piece.rawCount - piece.closerConsumed - piece.openerConsumed;
}

function starStyles(consumed: number): StyleToken[] {
	if (consumed === 2) return ['Bold'];
	if (consumed >= 3) return ['Bold', 'Italic'];
	return ['Italic'];
}

/** Scan source into text/delimiter pieces: escapes resolved, delimiter runs
    recognised, flanking judged from raw neighbours. */
function scanPieces(source: string): Piece[] {
	const pieces: Piece[] = [];
	let buffer = '';
	const flushText = () => {
		if (buffer !== '') pieces.push({ kind: 'text', text: buffer });
		buffer = '';
	};

	let i = 0;
	while (i < source.length) {
		const ch = source[i];
		if (ch === '\\' && i + 1 < source.length && ASCII_PUNCTUATION.test(source[i + 1])) {
			buffer += source[i + 1];
			i += 2;
			continue;
		}
		if (ch === '*' || ch === '_' || ch === '~') {
			let end = i + 1;
			while (end < source.length && source[end] === ch) end++;
			const count = end - i;
			const isDelim =
				ch === '*' ? count <= 3 : ch === '_' ? count === 1 : count === 2;
			if (isDelim) {
				flushText();
				pieces.push({
					kind: 'delim',
					delim: ch === '*' ? 'star' : ch === '_' ? 'under' : 'tilde',
					rawCount: count,
					rawStart: i,
					/* Flanking reads the raw source neighbours; escapes cannot
					   hide whitespace (backslash escapes punctuation only). */
					canOpen: !isWhitespaceChar(source[end]),
					canClose: !isWhitespaceChar(i > 0 ? source[i - 1] : undefined),
					closerConsumed: 0,
					openerConsumed: 0,
					index: -1
				});
			} else {
				buffer += source.slice(i, end);
			}
			i = end;
			continue;
		}
		buffer += ch;
		i++;
	}
	flushText();
	pieces.forEach((piece, index) => {
		if (piece.kind === 'delim') piece.index = index;
	});
	return pieces;
}

/** Match spans: a closing run pairs with the nearest open run of its kind,
    consuming leftmost-closer against rightmost-opener. */
function matchSpans(pieces: Piece[]): StyleSpan[] {
	const spans: StyleSpan[] = [];
	const openStack: DelimPiece[] = [];
	for (const piece of pieces) {
		if (piece.kind !== 'delim') continue;
		if (piece.canClose) {
			while (piece.closerConsumed < piece.rawCount) {
				let opener: DelimPiece | undefined;
				for (let s = openStack.length - 1; s >= 0; s--) {
					const candidate = openStack[s];
					if (
						candidate.delim === piece.delim &&
						candidate.canOpen &&
						candidate.openerConsumed < candidate.rawCount
					) {
						opener = candidate;
						break;
					}
				}
				if (!opener) break;
				const use =
					piece.delim === 'star'
						? Math.min(
								opener.rawCount - opener.openerConsumed,
								piece.rawCount - piece.closerConsumed
							)
						: piece.rawCount; // under/tilde runs consume whole
				opener.openerConsumed += use;
				piece.closerConsumed += use;
				spans.push({
					opener: opener.index,
					closer: piece.index,
					styles:
						piece.delim === 'star'
							? starStyles(use)
							: piece.delim === 'under'
								? ['Underline']
								: ['Strikeout']
				});
			}
		}
		/* Leftover that cannot close: opens if it may, else it is literal. */
		if (piece.closerConsumed + piece.openerConsumed < piece.rawCount && piece.canOpen) {
			openStack.push(piece);
		}
	}
	return spans;
}

/**
 * Parse one line of Fountain content into marker-free text plus canonical
 * style runs. Per-line by contract — emphasis never crosses element bounds.
 */
export function parseEmphasis(source: string): { text: string; runs: StyleRun[] } {
	const pieces = scanPieces(source);
	const spans = matchSpans(pieces);

	/* ---- assemble: content string, then spans in content coordinates ---
	   A run's chars order as [closer-consumed][literal middle][opener-
	   consumed]; only the literal middle reaches content. A closed span
	   therefore ends where its closer's piece begins, and an opened span
	   begins after its opener's literal middle. */
	const pieceStart: number[] = new Array(pieces.length);
	let text = '';
	pieces.forEach((piece, index) => {
		pieceStart[index] = text.length;
		if (piece.kind === 'text') {
			text += piece.text;
		} else {
			const marker = piece.delim === 'star' ? '*' : piece.delim === 'under' ? '_' : '~';
			text += marker.repeat(literalCount(piece));
		}
	});

	const runs: StyleRun[] = [];
	for (const span of spans) {
		const opener = pieces[span.opener] as DelimPiece;
		const start = pieceStart[span.opener] + literalCount(opener);
		const end = pieceStart[span.closer];
		if (end > start) runs.push({ start, end, styles: span.styles });
	}

	return { text, runs: normaliseRuns(runs, text.length) };
}

/* ------------------------------------------------------------------ */
/* normalise                                                           */
/* ------------------------------------------------------------------ */

/**
 * Bring runs to canonical form: clamp to the text, drop empties, split
 * overlaps into union segments, merge adjacent runs whose every property is
 * equal. Deterministic under conflict: where covering runs disagree on
 * `revisionID`, the earliest-starting run wins (styles and tagNumbers
 * union). O(runs²) worst case over one element's runs — a handful in
 * practice; the paginator never sees this path.
 */
export function normaliseRuns(runs: readonly StyleRun[], textLength: number): StyleRun[] {
	const clamped = runs
		.map((run) => ({ ...run, start: Math.max(0, run.start), end: Math.min(textLength, run.end) }))
		.filter((run) => run.end > run.start);
	if (clamped.length === 0) return [];

	const boundaries = new Set<number>();
	for (const run of clamped) {
		boundaries.add(run.start);
		boundaries.add(run.end);
	}
	const points = [...boundaries].sort((a, b) => a - b);

	const out: StyleRun[] = [];
	for (let b = 0; b + 1 < points.length; b++) {
		const start = points[b];
		const end = points[b + 1];
		const covering = clamped.filter((run) => run.start <= start && run.end >= end);
		if (covering.length === 0) continue;

		const styles = sortStyles(covering.flatMap((run) => run.styles));
		const tagNumbers = [
			...new Set(covering.flatMap((run) => run.tagNumbers ?? []))
		].sort((a, b) => a - b);
		covering.sort((a, b2) => a.start - b2.start);
		const revisionID = covering.find((run) => run.revisionID !== undefined)?.revisionID;
		/* One color per point: where covering runs disagree, the
		   earliest-starting wins — the revisionID rule (RFC HIGHLIGHTER §2). */
		const highlight = covering.find((run) => run.highlight !== undefined)?.highlight;

		if (
			styles.length === 0 &&
			tagNumbers.length === 0 &&
			revisionID === undefined &&
			highlight === undefined
		) {
			continue;
		}
		const candidate: StyleRun = { start, end, styles };
		if (revisionID !== undefined) candidate.revisionID = revisionID;
		if (tagNumbers.length > 0) candidate.tagNumbers = tagNumbers;
		if (highlight !== undefined) candidate.highlight = highlight;

		const previous = out[out.length - 1];
		if (
			previous &&
			previous.end === start &&
			previous.styles.join() === candidate.styles.join() &&
			previous.revisionID === candidate.revisionID &&
			(previous.tagNumbers ?? []).join() === (candidate.tagNumbers ?? []).join() &&
			previous.highlight === candidate.highlight
		) {
			previous.end = end;
		} else {
			out.push(candidate);
		}
	}
	return out;
}

/* ------------------------------------------------------------------ */
/* edit arithmetic (RFC v2.1 §1 rules 1–4 / §4 — runs under typing)     */
/* ------------------------------------------------------------------ */

/**
 * Re-seat runs after an element-local edit: `replaced` (old coordinates)
 * was swapped for `insertedLength` new characters, yielding a text of
 * `newTextLength`.
 *
 * Deleted text takes its runs with it; text after the edit shifts. Inserted
 * characters inherit their donor per the platform's own rule (§4), so the
 * model and the text view cannot disagree: the character before the
 * insertion point, or — at content position 0 — the character after it.
 * The donor's *whole* property set transfers (styles, revisionID,
 * tagNumbers): one span mechanism, and normalisation merges the new span
 * back into the donor run when they abut, which is exactly "typing extends
 * the bold run".
 *
 * Precondition: `runs` are canonical over the pre-edit text.
 */
export function propagateRuns(
	runs: readonly StyleRun[],
	replaced: { start: number; end: number },
	insertedLength: number,
	newTextLength: number
): StyleRun[] {
	const { start, end } = replaced;
	const delta = insertedLength - (end - start);
	const canonical = normaliseRuns(runs, Number.MAX_SAFE_INTEGER);

	const donor =
		start > 0
			? canonical.find((run) => run.start <= start - 1 && start - 1 < run.end)
			: canonical.find((run) => run.start <= end && end < run.end);

	const out: StyleRun[] = [];
	for (const run of canonical) {
		if (run.start < start) {
			out.push({ ...run, end: Math.min(run.end, start) });
		}
		if (run.end > end) {
			out.push({
				...run,
				start: Math.max(run.start, end) + delta,
				end: run.end + delta
			});
		}
	}
	if (insertedLength > 0 && donor) {
		const inserted: StyleRun = { start, end: start + insertedLength, styles: donor.styles };
		if (donor.revisionID !== undefined) inserted.revisionID = donor.revisionID;
		if (donor.tagNumbers !== undefined) inserted.tagNumbers = donor.tagNumbers;
		if (donor.highlight !== undefined) inserted.highlight = donor.highlight;
		out.push(inserted);
	}
	return normaliseRuns(out, newTextLength);
}

/** The runs' coverage of `[start, end)`, rebased to 0 — the planner's
    head/tail extraction when an element splits. Precondition: canonical. */
export function sliceRuns(
	runs: readonly StyleRun[],
	start: number,
	end: number
): StyleRun[] {
	const out: StyleRun[] = [];
	for (const run of runs) {
		const s = Math.max(run.start, start);
		const e = Math.min(run.end, end);
		if (e > s) out.push({ ...run, start: s - start, end: e - start });
	}
	return out;
}

/**
 * Whether every offset in `[start, end)` carries `style` — the format bar's
 * toggle decision and active-state query. Empty ranges cover nothing.
 * Precondition: canonical runs (sorted, non-overlapping).
 */
export function styleCovered(
	runs: readonly StyleRun[],
	start: number,
	end: number,
	style: StyleToken
): boolean {
	if (end <= start) return false;
	let cursor = start;
	for (const run of runs) {
		if (run.end <= start) continue;
		if (run.start >= end) break;
		if (run.start > cursor) return false; // a gap inside the range
		if (!run.styles.includes(style)) return false;
		cursor = Math.max(cursor, run.end);
		if (cursor >= end) return true;
	}
	return cursor >= end;
}

/**
 * The format bar's verb. If the range is fully covered, the style comes off
 * (a run left with no styles but a revisionID or tagNumbers survives — it
 * is still a run); otherwise the style is overlaid on the whole range and
 * normalisation unions it with whatever was there. Precondition: canonical.
 */
export function toggleStyle(
	runs: readonly StyleRun[],
	start: number,
	end: number,
	style: StyleToken,
	textLength: number
): StyleRun[] {
	const canonical = normaliseRuns(runs, textLength);
	if (end <= start) return canonical;

	if (!styleCovered(canonical, start, end, style)) {
		return normaliseRuns([...canonical, { start, end, styles: [style] }], textLength);
	}

	const out: StyleRun[] = [];
	for (const run of canonical) {
		if (run.end <= start || run.start >= end) {
			out.push(run);
			continue;
		}
		if (run.start < start) out.push({ ...run, end: start });
		const inner: StyleRun = {
			...run,
			start: Math.max(run.start, start),
			end: Math.min(run.end, end),
			styles: run.styles.filter((s) => s !== style)
		};
		if (
			inner.end > inner.start &&
			(inner.styles.length > 0 ||
				inner.revisionID !== undefined ||
				(inner.tagNumbers ?? []).length > 0 ||
				inner.highlight !== undefined)
		) {
			out.push(inner);
		}
		if (run.end > end) out.push({ ...run, start: end });
	}
	return normaliseRuns(out, textLength);
}

/* ------------------------------------------------------------------ */
/* live collapse (RFC v2.1 §3.3 — D6, an input transformation)          */
/* ------------------------------------------------------------------ */

export interface LiveCollapse {
	/** The line with the paired markers removed — all other text, including
	    any other delimiter characters, is verbatim. */
	text: string;
	/** The styled span the pair became, in the new text's coordinates. */
	run: StyleRun;
	/** The raw ranges removed from the input, ascending — the surface
	    propagates the element's pre-existing runs through these deletions. */
	removed: Array<{ start: number; end: number }>;
	/** Where the caret belongs afterwards: the end of the styled span. */
	caret: number;
}

/**
 * The typed character at `insertedAt` may complete a marker pair. If it is
 * part of a closing delimiter that pairs — and the pair's delimiters serve
 * no other span — the markers collapse into a style run and cease to exist
 * as text. Otherwise `null`: the character is literal and the edit proceeds
 * untouched.
 *
 * Sole-consumer restriction, deliberately: delimiter runs shared between
 * spans (`*a**b*`-style soup, reachable only from pasted marker text) are
 * left for the writer to see rather than half-converted by a convenience.
 * Whole delimiters only: a half-consumed `**` — the grammar's
 * literal-middle answer to `**word*` — would italicise the word the moment
 * the first closer key arrives, and typing `**word**` would end italic,
 * never bold. At the keyboard a pair waits for its full delimiter or does
 * not happen. Collapse is an input transformation, never a parser
 * second-guess.
 */
export function liveCollapse(text: string, insertedAt: number): LiveCollapse | null {
	const pieces = scanPieces(text);
	const spans = matchSpans(pieces);

	for (const span of spans) {
		const opener = pieces[span.opener] as DelimPiece;
		const closer = pieces[span.closer] as DelimPiece;
		/* The typed character must be one of the closer's consumed chars —
		   they are the run's leftmost. */
		if (insertedAt < closer.rawStart || insertedAt >= closer.rawStart + closer.closerConsumed) {
			continue;
		}
		/* Sole consumers only: a piece serving another span stays literal. */
		const shared = spans.some(
			(other) =>
				other !== span &&
				(other.opener === span.opener ||
					other.opener === span.closer ||
					other.closer === span.opener ||
					other.closer === span.closer)
		);
		if (shared) continue;
		if (opener.rawCount !== opener.openerConsumed) continue;
		if (closer.rawCount !== closer.closerConsumed) continue;

		/* Consumed chars: an opener's are its rightmost, a closer's its
		   leftmost — and the whole-delimiter rule above means there is no
		   surviving literal middle. */
		const openerLiteral = opener.rawCount - opener.openerConsumed;
		const removedOpener = {
			start: opener.rawStart + openerLiteral,
			end: opener.rawStart + opener.rawCount
		};
		const removedCloser = { start: closer.rawStart, end: closer.rawStart + closer.closerConsumed };

		const start = opener.rawStart + openerLiteral;
		const end = start + (closer.rawStart - (opener.rawStart + opener.rawCount));
		/* An empty match styles nothing — the markers stay literal. */
		if (end <= start) continue;

		const collapsed =
			text.slice(0, removedOpener.start) +
			text.slice(removedOpener.end, removedCloser.start) +
			text.slice(removedCloser.end);
		const run: StyleRun = { start, end, styles: span.styles };
		return { text: collapsed, run, removed: [removedOpener, removedCloser], caret: end };
	}
	return null;
}

/* ------------------------------------------------------------------ */
/* synthesise                                                          */
/* ------------------------------------------------------------------ */

/**
 * Escape content characters that would re-parse as markup. Backslash first
 * (so later escapes are not themselves escaped), then every `*` and `_`
 * (rare in screenplays; the Fountain spec itself recommends escaping), and
 * every tilde in a run of two or more (a lone `~` is harmless: only `~~`
 * is a delimiter).
 */
export function escapeFountainContent(text: string): string {
	return text
		.replace(/\\/g, '\\\\')
		.replace(/\*/g, '\\*')
		.replace(/_/g, '\\_')
		.replace(/~{2,}/g, (run) => '\\~'.repeat(run.length));
}

/** Marker per style token; AllCaps/HiddenText have no Fountain spelling and
    are dropped here (recorded fidelity-contract loss, like whitespace
    tightening below). */
const MARKER: Record<StyleToken, string> = {
	Bold: '**',
	Italic: '*',
	Underline: '_',
	Strikeout: '~~',
	AllCaps: '',
	HiddenText: ''
};

interface Zone {
	start: number;
	end: number;
	styles: StyleToken[];
}

/**
 * Emit canonical Fountain source for marker-free content plus runs.
 *
 * Emission is event-based over style-set changes, not per run: a style
 * shared by adjacent segments stays open across the boundary (properly
 * nested, minimal markers — `_a *b* c_`, never `_a _*b*_ c_`, whose
 * close/reopen pairs would mis-pair on re-parse). New styles open on top of
 * kept ones in canonical order; closed styles pop innermost-first, so the
 * marker stream always nests properly.
 *
 * Fountain's flanking rule cannot express a run that starts or ends with
 * whitespace, so marker coverage is tightened past boundary whitespace —
 * a recorded Fountain-boundary loss (the model keeps the run; FDX carries
 * it exactly).
 *
 * The fixed-point gate (corpus-pinned): parseEmphasis(synthesiseEmphasis(t, r))
 * returns (t, normaliseRuns(r)) for runs that neither hug whitespace nor use
 * Fountain-less styles.
 */
export function synthesiseEmphasis(text: string, runs: readonly StyleRun[]): string {
	const canonical = normaliseRuns(runs, text.length);

	/* Zones: run segments plus the plain gaps between them, covering the
	   whole line. Boundary-whitespace handling lives in the emission loop. */
	const zones: Zone[] = [];
	const pushZone = (start: number, end: number, styles: StyleToken[]) => {
		if (end > start) zones.push({ start, end, styles });
	};

	let pos = 0;
	for (const run of canonical) {
		pushZone(pos, run.start, []);
		pushZone(run.start, run.end, run.styles);
		pos = run.end;
	}
	pushZone(pos, text.length, []);

	let out = '';
	let active: StyleToken[] = []; // the marker stack, outermost-first
	let pendingWhitespace = ''; // trailing whitespace of the zone just emitted
	for (const zone of zones) {
		/* Marker coverage tightens past boundary whitespace: a marker pair
		   may not hug whitespace (flanking), so edge whitespace emits
		   outside the markers. Interior whitespace is unaffected — the
		   style simply stays open across it. */
		let coreStart = zone.start;
		let coreEnd = zone.end;
		while (coreStart < coreEnd && isWhitespaceChar(text[coreStart])) coreStart++;
		while (coreEnd > coreStart && isWhitespaceChar(text[coreEnd - 1])) coreEnd--;
		/* An all-whitespace styled zone opens no markers at all. */
		const styles = zone.styles.length > 0 && coreStart === coreEnd ? [] : zone.styles;

		const next = new Set(styles);
		/* Longest prefix of the active stack whose styles all continue —
		   everything above it closes, innermost first. */
		let kept = 0;
		while (kept < active.length && next.has(active[kept])) kept++;
		for (let i = active.length - 1; i >= kept; i--) out += MARKER[active[i]];
		out += pendingWhitespace;
		pendingWhitespace = '';
		if (styles.length > 0) out += escapeFountainContent(text.slice(zone.start, coreStart));
		/* New styles open on top, outermost-first in canonical order. */
		const keptStyles = new Set(active.slice(0, kept));
		const opening = sortStyles(styles.filter((s) => !keptStyles.has(s)));
		for (const style of opening) out += MARKER[style];
		active = [...active.slice(0, kept), ...opening];

		if (styles.length > 0) {
			out += escapeFountainContent(text.slice(coreStart, coreEnd));
			pendingWhitespace = escapeFountainContent(text.slice(coreEnd, zone.end));
		} else {
			out += escapeFountainContent(text.slice(zone.start, zone.end));
		}
	}
	for (let i = active.length - 1; i >= 0; i--) out += MARKER[active[i]];
	out += pendingWhitespace;
	return out;
}
