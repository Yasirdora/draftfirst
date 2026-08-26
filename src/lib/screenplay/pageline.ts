/**
 * How a paginated line becomes printed text.
 *
 * The paginator appends Fountain's dual-dialogue caret to a cue so the line
 * wraps at its true width, but the caret is source syntax — it belongs to
 * the .fountain file, never to a rendered page. Every renderer that draws
 * paginator output (PDF, plain text, and their Swift counterparts) shares
 * this one strip, so no exporter can quietly grow a stray `^` again.
 *
 * Dual speeches print sequentially until a true side-by-side layout exists;
 * nothing is lost or mislabelled, only laid out linearly.
 */

import type { PageLine } from '@edraft/core/layout';

/** The marker the paginator appends to a dual cue — never authored text. */
const DUAL_MARKER = ' ^';

/**
 * The text of a paginated line as it should appear on the page. Only a
 * character cue can carry the generated marker, so a caret the writer typed
 * in action or dialogue is left exactly where they put it.
 */
export function printedLineText(line: PageLine): string {
	if (line.type === 'character' && line.text.endsWith(DUAL_MARKER)) {
		return line.text.slice(0, -DUAL_MARKER.length);
	}
	return line.text;
}
