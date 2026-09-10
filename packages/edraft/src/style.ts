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

/**
 * Parse one line of Fountain content into marker-free text plus canonical
 * style runs. Per-line by contract — emphasis never crosses element bounds.
 */
export function parseEmphasis(source: string): { text: string; runs: StyleRun[] } {
	const pieces: Piece[] = [];
	const spans: StyleSpan[] = [];

	/* ---- scan: escapes resolved, delimiter runs recognised ------------ */
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

	/* ---- match: a closing run pairs with the nearest open run of its
	   kind, consuming leftmost-closer against rightmost-opener --------- */
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

		if (styles.length === 0 && tagNumbers.length === 0 && revisionID === undefined) continue;
		const candidate: StyleRun = { start, end, styles };
		if (revisionID !== undefined) candidate.revisionID = revisionID;
		if (tagNumbers.length > 0) candidate.tagNumbers = tagNumbers;

		const previous = out[out.length - 1];
		if (
			previous &&
			previous.end === start &&
			previous.styles.join() === candidate.styles.join() &&
			previous.revisionID === candidate.revisionID &&
			(previous.tagNumbers ?? []).join() === (candidate.tagNumbers ?? []).join()
		) {
			previous.end = end;
		} else {
			out.push(candidate);
		}
	}
	return out;
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
