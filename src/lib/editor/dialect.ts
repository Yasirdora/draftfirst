/**
 * Dialect contract — what Writing Desk promises to understand.
 *
 * Visible in the status bar so writers never wonder “will this open on GitHub?”
 * Core dialect is CommonMark + GFM essentials (tables, task lists, strikethrough).
 * Future packs (math, footnotes) will be opt-in and labeled separately.
 */

export interface DialectPack {
	/** Short machine id */
	id: string;
	/** Status bar label */
	label: string;
	/** One-line human explanation */
	summary: string;
	/** Features included for tooltips / help */
	features: readonly string[];
}

/** Default dialect — always on, never silent. */
export const CORE_DIALECT: DialectPack = {
	id: 'commonmark-gfm',
	label: 'CommonMark + GFM',
	summary: 'CommonMark baseline with GitHub tables, task lists, and strikethrough.',
	features: [
		'Headings, lists, quotes, code fences',
		'Emphasis, links, images',
		'GFM tables with alignment',
		'Task lists',
		'Strikethrough',
		'Raw HTML escaped (never executed)',
		'Truth mode checks page → source fidelity'
	]
};

/** Footnotes — the first opt-in pack. Off means `[^id]` stays literal text. */
export const FOOTNOTES_PACK: DialectPack = {
	id: 'footnotes',
	label: 'Footnotes',
	summary:
		'Inline [^id] references and [^id]: definitions, numbered by first reference and back-linked.',
	features: [
		'[^id] references become numbered superscripts',
		'[^id]: definitions collect at the end',
		'Numbered by first reference, not by definition order',
		'Back-links return to the reference'
	]
};

/** Compact badge text for narrow status bars. */
export const DIALECT_BADGE = CORE_DIALECT.label;
