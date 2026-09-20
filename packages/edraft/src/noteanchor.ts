/**
 * Notes pinned to words — RFC-NOTES-SYSTEM §5 (stage 4).
 *
 * A note is anchored to words *inside one paragraph*: the paragraph that
 * follows it (§5.2). This module holds the two halves of that, and nothing
 * else:
 *
 *   - `resolveAnchor` — the disambiguation rule (§5.3), used wherever an
 *     anchor has to become a span: the FDX writer computing a Range, the
 *     editor placing a thread.
 *   - `anchorFor` — its inverse, used wherever a span has to become an
 *     anchor: the FDX reader deriving `on:`/`nth:` from a Range.
 *
 * The two are exact inverses on the same paragraph, and both count
 * occurrences the same way, so a note written and read back lands on the
 * words it started on.
 *
 * WHY NOT ATTRIBUTES. The Final Draft 13.4.0 probe measured every unknown
 * attribute stripped by Final Draft's first save (RFC §3, fact 1: `EDraft:`
 * nine times in the probe, zero in both saved copies). Anchors therefore
 * live in text Final Draft preserves — the Range in FDX, the header line in
 * Fountain — and this engine writes no `EDraft:` attribute anywhere.
 */

import type { NoteAnchor } from './types.js';

/** Where an anchor lands: a half-open span in UTF-16 units of the
    paragraph's own text, the same coordinate space as `ContentIndex`. */
export interface AnchorSpan {
	start: number;
	end: number;
}

/**
 * Every position where `words` occurs in `paragraph`, in order.
 *
 * Overlapping occurrences each count: in `aaa`, the word `aa` occurs at 0
 * and at 1, and `nth:2` means the second of those. Writer and reader share
 * this function, so the ordinal a header carries always means the same
 * position it did when it was written.
 */
function occurrencesOf(paragraph: string, words: string): number[] {
	if (words === '') return [];
	const out: number[] = [];
	for (let at = paragraph.indexOf(words); at !== -1; at = paragraph.indexOf(words, at + 1)) out.push(at);
	return out;
}

/**
 * The anchor's span in its paragraph — §5.3, rules 1 to 5.
 *
 * 1. Only this paragraph is searched, from its start.
 * 2. The first occurrence, unless `nth` selects another.
 * 4. Exact on UTF-16 units, casing included: `MARA` does not land on `Mara`.
 * 5. Words gone, or fewer than `nth`: `null`. The caller anchors to the whole
 *    paragraph and says "words changed" — it is never moved to another
 *    paragraph and never guessed.
 */
export function resolveAnchor(paragraph: string, anchor: NoteAnchor): AnchorSpan | null {
	const nth = anchor.nth ?? 1;
	if (!Number.isInteger(nth) || nth < 1) return null;
	const at = occurrencesOf(paragraph, anchor.on)[nth - 1];
	if (at === undefined) return null;
	return { start: at, end: at + anchor.on.length };
}

/**
 * The anchor for a span of a paragraph — the inverse of `resolveAnchor`.
 *
 * `null` when the span is the whole paragraph or is empty: a note about its
 * whole paragraph carries no anchor at all, which is what every note written
 * before stage 4 is.
 *
 * §5.3 rule 3: `nth` is written exactly when the words occur more than once
 * in the paragraph at the time of writing, so a header never depends on an
 * ordinal it does not need.
 */
export function anchorFor(paragraph: string, start: number, end: number): NoteAnchor | null {
	if (start < 0 || end > paragraph.length || end <= start) return null;
	if (start === 0 && end === paragraph.length) return null;
	const on = paragraph.slice(start, end);
	const occurrences = occurrencesOf(paragraph, on);
	const ordinal = occurrences.indexOf(start);
	if (ordinal === -1) return null;
	return occurrences.length > 1 ? { on, nth: ordinal + 1 } : { on };
}

/* ---- the Fountain header line (§4.1, the `on`/`nth` fields) ------------- */

/**
 * A note's anchor in Fountain is a header line — the first line of the
 * note's text, alone on its line (§4.1):
 *
 *     [[[eDraft on:"doesn't move"]
 *     Dana Reyes (Director): Too still? She should flinch.]]
 *
 * WHAT THIS BUILDS, AND WHAT IT LEAVES ALONE. §4.1's grammar also carries
 * `thread`, `status`, `by`, `at`, `reply-to` and `from` — stage 2 and stage
 * 3's carrier, which the RFC says is not built (§4, the amendment note).
 * So a header is read here only when every field in it is one stage 4 owns
 * (`on`, and `nth` beside it). A header carrying anything else is left
 * exactly where it is, as the note's own first line of text, byte for byte:
 * nothing this stage does not understand is parsed, rewritten or dropped.
 */
export interface NoteHeaderReading {
	anchor: NoteAnchor;
	/** The note's words, with the header line taken off. */
	body: string;
}

/** The mark that opens a header, matched case-insensitively. */
const HEADER_MARK = '[edraft';

const isKeyChar = (c: string): boolean => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '-';

/**
 * The anchor a note's first line carries, and the words left after it —
 * `null` when the note has no header this stage owns, which is every note
 * written before stage 4.
 *
 * Hand-scanned, one pass, no backtracking: a header is attacker-controlled
 * text in any file eDraft opens, and a regular expression for this grammar
 * needs nested quantifiers.
 */
export function readNoteHeader(text: string): NoteHeaderReading | null {
	const brk = text.indexOf('\n');
	const first = brk === -1 ? text : text.slice(0, brk);
	if (first.length <= HEADER_MARK.length) return null;
	if (first.slice(0, HEADER_MARK.length).toLowerCase() !== HEADER_MARK) return null;
	if (!first.endsWith(']')) return null;

	const close = first.length - 1;
	let at = HEADER_MARK.length;
	let on: string | undefined;
	let nth: number | undefined;

	while (at < close) {
		if (first[at] !== ' ') return null;
		at++;
		const keyFrom = at;
		while (at < close && isKeyChar(first[at])) at++;
		if (at === keyFrom || first[at] !== ':') return null;
		const key = first.slice(keyFrom, at).toLowerCase();
		at++;

		let value = '';
		if (first[at] === '"') {
			at++;
			for (;;) {
				if (at >= close) return null;
				const c = first[at];
				if (c === '"') {
					at++;
					break;
				}
				if (c === '\\') {
					at++;
					if (at >= close) return null;
				}
				value += first[at];
				at++;
			}
		} else {
			const from = at;
			while (at < close && first[at] !== ' ' && first[at] !== '"' && first[at] !== ']') at++;
			value = first.slice(from, at);
		}

		if (key === 'on') {
			if (on !== undefined) return null;
			on = value;
		} else if (key === 'nth') {
			if (nth !== undefined) return null;
			if (!/^[1-9][0-9]*$/.test(value)) return null;
			nth = Number(value);
		} else {
			/* Stage 2's fields, or a key this build has never heard of: not
			   ours to read, and not ours to rewrite. */
			return null;
		}
	}

	if (on === undefined || on === '') return null;
	return {
		anchor: nth === undefined ? { on } : { on, nth },
		body: brk === -1 ? '' : text.slice(brk + 1)
	};
}

/** A value in the header's spelling. Exported so a diagnostic naming the
    words reads the same in both ports. */
export function quoteAnchorWords(value: string): string {
	return `"${value.replace(/([\\"])/g, '\\$1')}"`;
}

/** The header line for an anchor, written with lowercase keys (§4.1). */
export function writeNoteHeader(anchor: NoteAnchor): string {
	const nth = anchor.nth === undefined ? '' : ` nth:${anchor.nth}`;
	return `[eDraft on:${quoteAnchorWords(anchor.on)}${nth}]`;
}
