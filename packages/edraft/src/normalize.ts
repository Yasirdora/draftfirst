/**
 * Idempotent commit-time normalization for parentheticals and cue extensions.
 * Other text is returned unchanged.
 */

import type { ElementType } from './types.js';

/** Canonical cue extensions, keyed by their letters with punctuation stripped. */
const EXTENSION_CANONICAL: Record<string, string> = {
	VO: 'V.O.',
	OS: 'O.S.',
	OC: 'O.C.',
	CONTD: "CONT'D",
	PRELAP: 'PRE-LAP',
	SUBTITLE: 'SUBTITLE',
	FILTERED: 'FILTERED'
};

// Bare trailing extension: whitespace + the extension letters (dots optional)
// at end of string. The whitespace boundary keeps names like CARLOS safe.
const BARE_EXTENSION = /\s+(V\.?O\.?|O\.?S\.?|O\.?C\.?|CONT'?D\.?|PRE[\s-]?LAP|SUBTITLE|FILTERED)$/i;

function canonicalExtension(raw: string): string | null {
	const key = raw.toUpperCase().replace(/[.\s'-]/g, '');
	return EXTENSION_CANONICAL[key] ?? null;
}

/**
 * Wrap a parenthetical's text in exactly one pair of brackets.
 * Strips one layer of partial outer brackets first, so partial states the
 * writer typed ('(beat', 'beat)', '()') all converge. Idempotent.
 */
export function normalizeParenthetical(text: string): string {
	let s = text.trim();
	if (s.startsWith('(')) s = s.slice(1);
	if (s.endsWith(')')) s = s.slice(0, -1);
	s = s.trim();
	return s ? `(${s})` : '';
}

/**
 * The inverse of normalizeParenthetical, for conversion OUT of the
 * parenthetical lane: sheds exactly one outer wrapper — '(beat)' → 'beat',
 * '((beat))' → '(beat)'. A text holding several directions, '(a) (b)',
 * keeps them: only a first '(' that closes at the very end is a wrapper.
 * Partial states shed one stray end bracket, so '(beat' and 'beat)' both
 * converge to 'beat'; anything unbalanced is left exactly as written.
 */
export function unwrapParenthetical(text: string): string {
	const s = text.trim();
	if (!s) return '';
	const opens = s.includes('(');
	const closes = s.includes(')');
	if (!opens && !closes) return s;
	if (!opens) {
		// One stray closer: 'beat)' → 'beat' (one layer only).
		const i = s.lastIndexOf(')');
		return (s.slice(0, i) + s.slice(i + 1)).trim();
	}
	if (!closes) {
		// One stray opener: '(beat' → 'beat' (one layer only).
		const i = s.indexOf('(');
		return (s.slice(0, i) + s.slice(i + 1)).trim();
	}
	// Both present: strip only a true outer wrapper.
	let depth = 0;
	for (let i = 0; i < s.length; i++) {
		const ch = s[i];
		if (ch === '(') depth++;
		else if (ch === ')') {
			depth--;
			if (depth < 0) return s;
			if (depth === 0) {
				return i === s.length - 1 ? s.slice(1, -1).trim() : s;
			}
		}
	}
	return s;
}

/**
 * Normalize a character cue's extension:
 *   'MARA (V.O'        → 'MARA (V.O.)'   (close + canonicalize)
 *   'MARA (WHISPERING' → 'MARA (WHISPERING)' (close any unclosed extension)
 *   'MARA ('           → 'MARA'          (drop a dangling empty bracket)
 *   'MARA VO'          → 'MARA (V.O.)'   (bracket a bare known extension)
 *   'MARA (V.O.)'      → unchanged
 *   'VO'               → unchanged       (an extension with no name is a name)
 */
export function normalizeCue(text: string): string {
	const s = text.trim();
	if (!s) return '';

	// Preserve already-closed extensions.
	if (s.endsWith(')')) return s;

	const open = s.indexOf('(');
	if (open >= 0) {
		const name = s.slice(0, open).trim();
		const tail = s.slice(open + 1).trim();
		if (!tail) return name; // dangling '(' — drop it
		if (!name) return s; // '(' at the very start — not a cue shape, leave it
		const canon = canonicalExtension(tail);
		return `${name} (${canon ?? tail})`;
	}

	// No bracket at all — a bare known extension gets brackets.
	const m = s.match(BARE_EXTENSION);
	if (m) {
		const name = s.slice(0, m.index).trim();
		const canon = canonicalExtension(m[1]);
		if (name && canon) return `${name} (${canon})`;
	}

	return s;
}

/**
 * A wryly lane holding an ALL-CAPS name is not a wryly — it is a cue that
 * took the wrong lane (after dialogue, Tab lands on parenthetical, and a
 * writer thinking about the next speaker may not notice the indent).
 * Wrylies are lowercase by convention; cues are uppercase. The shape test
 * is deliberately strict — mixed-case direction like '(to JOHN)' is never
 * hijacked, and neither is a genuine shouted wryly typed with a bracket.
 */
export function looksLikeCue(text: string): boolean {
	const t = text.trim();
	if (t.length < 2 || t.startsWith('(')) return false;
	if (!/[A-Za-z]/.test(t)) return false;
	return t === t.toUpperCase();
}

/**
 * Commit-time normalization for a block's text, dispatched by element type.
 * Scene / action / dialogue / transition are returned untouched.
 */
export function normalizeElementText(type: ElementType, text: string): string {
	if (type === 'parenthetical') return normalizeParenthetical(text);
	if (type === 'character') return normalizeCue(text);
	return text;
}

/**
 * The kinds a screenplay writes in capitals.
 *
 * A slug, a cue, a transition and a shot are shouted; action and dialogue keep
 * whatever casing the writer chose. This is the one place that list lives, so
 * the editor's conversion rule and the importer cannot disagree about what a
 * cue looks like.
 */
export const UPPERCASE_TYPES: readonly ElementType[] = Object.freeze([
	'scene',
	'character',
	'transition',
	'shot'
]);

/**
 * A line in the casing its kind is written in, for text arriving from
 * elsewhere.
 *
 * Final Draft stores what the writer typed and shouts it in the *view*: an
 * .fdx can hold `cUT TO:` and `UnCLE` and look immaculate on screen. Opened
 * anywhere else — including here — the file shows what it really says, which
 * is how a script that looked right for years suddenly reads as though it were
 * typed with a broken shift key.
 *
 * It matters beyond appearances. Fountain detects a transition by its capitals
 * (`TRANSITION_DETECT` has no `/i`), so `cUT TO:` is not a transition to any
 * Fountain tool, and the only way to keep it one is to write it with a forcing
 * marker — a clean script exported into a thicket of `>` and `@`.
 *
 * Deliberately *not* applied on every commit: while a writer is typing, casing
 * is theirs, and the editor's conversion rule keeps their original so that
 * converting a line back restores what they wrote. This is for the moment a
 * document arrives from somewhere else.
 */
export function canonicalCasing(type: ElementType, text: string): string {
	return UPPERCASE_TYPES.includes(type) ? text.toLocaleUpperCase() : text;
}
