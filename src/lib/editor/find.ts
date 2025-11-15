/**
 * Find-in-document — pure helpers over the Markdown source string.
 * UI jumps to matches; page view scrolls via heading/line heuristics.
 */

export interface FindMatch {
	/** Character offset of the match in the source */
	index: number;
	line: number;
	column: number;
	/** Surrounding line text for the results list */
	preview: string;
}

/** Case-insensitive search; empty query → no matches. */
export function findMatches(doc: string, query: string, limit = 200): FindMatch[] {
	const q = query.trim();
	if (!q) return [];

	const hay = doc;
	const needle = q;
	const lowerHay = hay.toLowerCase();
	const lowerNeedle = needle.toLowerCase();
	const out: FindMatch[] = [];
	let from = 0;

	while (from <= lowerHay.length && out.length < limit) {
		const index = lowerHay.indexOf(lowerNeedle, from);
		if (index === -1) break;

		const upto = hay.slice(0, index);
		const line = upto.split('\n').length;
		const column = index - upto.lastIndexOf('\n');
		const lineStart = upto.lastIndexOf('\n') + 1;
		let lineEnd = hay.indexOf('\n', index);
		if (lineEnd === -1) lineEnd = hay.length;
		const preview = hay.slice(lineStart, lineEnd).trim() || '(empty line)';

		out.push({ index, line, column, preview });
		from = index + Math.max(1, needle.length);
	}

	return out;
}

/** Map a character offset to line number (1-based for display). */
export function offsetToLine(doc: string, offset: number): number {
	return doc.slice(0, Math.max(0, offset)).split('\n').length;
}
