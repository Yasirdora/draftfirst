/**
 * Outline reorder — split a Markdown document into heading sections and reassemble.
 *
 * A section starts at an ATX heading and runs until the next ATX heading
 * (any level), or end of file. Leading material before the first heading is
 * a preamble section (not listed in the outline control list).
 *
 * Pure string transforms — unit-tested without DOM.
 */

export interface OutlineSection {
	/** 0 for preamble; 1–6 for ATX headings */
	level: number;
	/** Heading text without `#` markers; empty for preamble */
	title: string;
	/** Full source of this section */
	body: string;
	/** Original start line (0-based) */
	startLine: number;
}

const ATX = /^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$/;

function sliceLines(lines: string[], start: number, end: number, source: string): string {
	const chunk = lines.slice(start, end).join('\n');
	if (end < lines.length) return chunk + '\n';
	if (source.endsWith('\n')) return chunk + '\n';
	return chunk;
}

/**
 * Split source into optional preamble + one section per ATX heading.
 */
export function splitOutlineSections(source: string): OutlineSection[] {
	const lines = source.split('\n');
	// Document that is only a trailing empty split from final \n
	if (lines.length === 1 && lines[0] === '' && source === '') {
		return [{ level: 0, title: '', body: '', startLine: 0 }];
	}

	const headingAt: { index: number; level: number; title: string }[] = [];
	for (let i = 0; i < lines.length; i++) {
		const m = ATX.exec(lines[i]);
		if (m) {
			headingAt.push({
				index: i,
				level: m[1].length,
				title: (m[2] || '').trim()
			});
		}
	}

	if (headingAt.length === 0) {
		return [{ level: 0, title: '', body: source, startLine: 0 }];
	}

	const sections: OutlineSection[] = [];

	if (headingAt[0].index > 0) {
		sections.push({
			level: 0,
			title: '',
			body: sliceLines(lines, 0, headingAt[0].index, source),
			startLine: 0
		});
	}

	for (let h = 0; h < headingAt.length; h++) {
		const start = headingAt[h].index;
		const end = h + 1 < headingAt.length ? headingAt[h + 1].index : lines.length;
		sections.push({
			level: headingAt[h].level,
			title: headingAt[h].title,
			body: sliceLines(lines, start, end, source),
			startLine: start
		});
	}

	return sections;
}

/**
 * Reorder heading sections (excluding preamble).
 * `from` / `to` are indices into the *heading-only* list (same order as outlineOf).
 */
export function reorderOutlineSections(
	source: string,
	fromHeadingIndex: number,
	toHeadingIndex: number
): string {
	if (fromHeadingIndex === toHeadingIndex) return source;

	const sections = splitOutlineSections(source);
	const hasPreamble = sections[0]?.level === 0;
	const preamble = hasPreamble ? sections[0] : null;
	const headings = hasPreamble ? sections.slice(1) : sections;

	if (
		fromHeadingIndex < 0 ||
		toHeadingIndex < 0 ||
		fromHeadingIndex >= headings.length ||
		toHeadingIndex >= headings.length
	) {
		return source;
	}

	const next = headings.slice();
	const [item] = next.splice(fromHeadingIndex, 1);
	next.splice(toHeadingIndex, 0, item);

	const parts: string[] = [];
	if (preamble) parts.push(preamble.body);
	for (const h of next) parts.push(h.body);
	return parts.join('');
}

/** Move a heading section up (−1) or down (+1) in outline order. */
export function moveOutlineSection(
	source: string,
	headingIndex: number,
	direction: -1 | 1
): string {
	return reorderOutlineSections(source, headingIndex, headingIndex + direction);
}
