import { describe, expect, it } from 'vitest';
import {
	highlightCovered,
	liveCollapse,
	propagateRuns,
	sliceRuns,
	styleCovered,
	toggleHighlight,
	toggleStyle
} from './style.js';
import type { StyleRun } from './types.js';

/* Offsets are UTF-16 code units (the ContentIndex space), half-open. */

describe('propagateRuns — runs under an element-local edit', () => {
	const bold = (start: number, end: number): StyleRun => ({ start, end, styles: ['Bold'] });

	it('leaves runs before the edit untouched and shifts runs after it', () => {
		/* "aa bb cc", bold "aa" and "cc"; insert one char at 3. */
		const out = propagateRuns([bold(0, 2), bold(6, 8)], { start: 3, end: 3 }, 1, 9);
		expect(out).toEqual([bold(0, 2), bold(7, 9)]);
	});

	it('extends the run typed inside of — interior insertion merges back', () => {
		/* bold [1,5) of "abcdef"; type two chars at 3. */
		const out = propagateRuns([bold(1, 5)], { start: 3, end: 3 }, 2, 8);
		expect(out).toEqual([bold(1, 7)]);
	});

	it('extends at the trailing edge — §4.1, the caret grows the bold run', () => {
		const out = propagateRuns([bold(0, 4)], { start: 4, end: 4 }, 1, 5);
		expect(out).toEqual([bold(0, 5)]);
	});

	it('does NOT extend at the leading edge — §4.2 inherits the preceding character', () => {
		/* "  bold": caret at 2 (the run's start) types plain. */
		const out = propagateRuns([bold(2, 6)], { start: 2, end: 2 }, 1, 7);
		expect(out).toEqual([{ start: 3, end: 7, styles: ['Bold'] }]);
	});

	it('at content position 0 inherits the following run', () => {
		const out = propagateRuns([bold(0, 4)], { start: 0, end: 0 }, 2, 6);
		expect(out).toEqual([bold(0, 6)]);
	});

	it('between two runs inherits the preceding one', () => {
		const out = propagateRuns(
			[bold(0, 2), { start: 2, end: 4, styles: ['Italic'] }],
			{ start: 2, end: 2 },
			1,
			5
		);
		expect(out).toEqual([bold(0, 3), { start: 3, end: 5, styles: ['Italic'] }]);
	});

	it('shrinks a run through a deletion and drops a fully deleted one', () => {
		/* "aXbXc", bold [0,5); delete [1,4). */
		expect(propagateRuns([bold(0, 5)], { start: 1, end: 4 }, 0, 2)).toEqual([bold(0, 2)]);
		expect(propagateRuns([bold(1, 4)], { start: 1, end: 4 }, 0, 2)).toEqual([]);
	});

	it('replacing selected text inside a run keeps the style (donor heals)', () => {
		/* bold [0,5); replace [2,4) with three chars. */
		const out = propagateRuns([bold(0, 5)], { start: 2, end: 4 }, 3, 6);
		expect(out).toEqual([bold(0, 6)]);
	});

	it('inserted text carries the donor’s revision and tags too', () => {
		const run: StyleRun = { start: 0, end: 4, styles: ['Bold'], revisionID: 2, tagNumbers: [7] };
		expect(propagateRuns([run], { start: 4, end: 4 }, 1, 5)).toEqual([
			{ start: 0, end: 5, styles: ['Bold'], revisionID: 2, tagNumbers: [7] }
		]);
	});
});

describe('sliceRuns — head/tail extraction', () => {
	it('clamps and rebases to the slice', () => {
		const runs: StyleRun[] = [
			{ start: 2, end: 6, styles: ['Bold'] },
			{ start: 8, end: 10, styles: ['Italic'] }
		];
		expect(sliceRuns(runs, 4, 9)).toEqual([
			{ start: 0, end: 2, styles: ['Bold'] },
			{ start: 4, end: 5, styles: ['Italic'] }
		]);
	});
});

describe('styleCovered / toggleStyle — the format bar’s verbs', () => {
	const bold = (start: number, end: number): StyleRun => ({ start, end, styles: ['Bold'] });

	it('answers coverage only when every offset carries the style', () => {
		const runs = [bold(0, 4)];
		expect(styleCovered(runs, 0, 4, 'Bold')).toBe(true);
		expect(styleCovered(runs, 1, 3, 'Bold')).toBe(true);
		expect(styleCovered(runs, 0, 5, 'Bold')).toBe(false);
		expect(styleCovered(runs, 4, 6, 'Bold')).toBe(false);
		expect(styleCovered(runs, 0, 0, 'Bold')).toBe(false);
		expect(styleCovered(runs, 0, 4, 'Italic')).toBe(false);
	});

	it('adds the style to an uncovered range, unioning with what is there', () => {
		/* italic [2,4); bold toggled over [0,6). */
		const out = toggleStyle([{ start: 2, end: 4, styles: ['Italic'] }], 0, 6, 'Bold', 6);
		expect(out).toEqual([
			{ start: 0, end: 2, styles: ['Bold'] },
			{ start: 2, end: 4, styles: ['Bold', 'Italic'] },
			{ start: 4, end: 6, styles: ['Bold'] }
		]);
	});

	it('removes the style from a covered range, splitting at the edges', () => {
		const out = toggleStyle([bold(0, 6)], 2, 4, 'Bold', 6);
		expect(out).toEqual([bold(0, 2), bold(4, 6)]);
	});

	it('keeps a run that still carries a revision after the style comes off', () => {
		const out = toggleStyle(
			[{ start: 0, end: 4, styles: ['Bold'], revisionID: 9 }],
			0,
			4,
			'Bold',
			4
		);
		expect(out).toEqual([{ start: 0, end: 4, styles: [], revisionID: 9 }]);
	});

	it('merges back when toggling reunites identical neighbours', () => {
		/* Removing Italic from the middle leaves three Bold segments, which
		   normalisation must merge into one. */
		const runs = [
			bold(0, 2),
			{ start: 2, end: 4, styles: ['Bold', 'Italic'] },
			bold(4, 6)
		];
		expect(toggleStyle(runs, 2, 4, 'Italic', 6)).toEqual([bold(0, 6)]);
	});

	it('adds over a styled middle, unioning rather than replacing', () => {
		const runs = [bold(0, 2), { start: 2, end: 4, styles: ['Italic'] }, bold(4, 6)];
		expect(toggleStyle(runs, 2, 4, 'Bold', 6)).toEqual([
			bold(0, 2),
			{ start: 2, end: 4, styles: ['Bold', 'Italic'] },
			bold(4, 6)
		]);
	});
});

describe('liveCollapse — D6, the input transformation', () => {
	it('collapses a completed pair on the closing delimiter', () => {
		const collapsed = liveCollapse('**world**', 8);
		expect(collapsed).toEqual({
			text: 'world',
			run: { start: 0, end: 5, styles: ['Bold'] },
			removed: [
				{ start: 0, end: 2 },
				{ start: 7, end: 9 }
			],
			caret: 5
		});
	});

	it('collapses each Fountain spelling to its style', () => {
		expect(liveCollapse('*x*', 2)?.run.styles).toEqual(['Italic']);
		expect(liveCollapse('**x**', 4)?.run.styles).toEqual(['Bold']);
		expect(liveCollapse('***x***', 6)?.run.styles).toEqual(['Bold', 'Italic']);
		expect(liveCollapse('_x_', 2)?.run.styles).toEqual(['Underline']);
		expect(liveCollapse('~~x~~', 4)?.run.styles).toEqual(['Strikeout']);
	});

	it('completes ~~ on the second tilde', () => {
		/* The writer typed the second ~ at 4; the closer consumes both. */
		const collapsed = liveCollapse('~~x~~', 4);
		expect(collapsed?.text).toBe('x');
		expect(collapsed?.removed).toEqual([
			{ start: 0, end: 2 },
			{ start: 3, end: 5 }
		]);
	});

	it('returns null when the typed character closes nothing', () => {
		expect(liveCollapse('a *b', 2)).toBeNull(); // opened, never closed
		expect(liveCollapse('2 * 3', 2)).toBeNull(); // flanked out
		expect(liveCollapse('x*', 1)).toBeNull(); // a closer with no opener
		expect(liveCollapse('y ~', 2)).toBeNull(); // a lone tilde is literal
	});

	it('returns null when the typed char is not the consumed part of the closer', () => {
		/* `*a**` — the closer consumed one star for italic; the typed second
		   star of the pair is literal leftover, so no collapse. Wait: closer
		   `**` consumes min(opener avail 1, 2) = 1, so only the FIRST closer
		   star pairs; the typed one (at 3) is beyond the consumed portion. */
		expect(liveCollapse('*a**', 3)).toBeNull();
	});

	it('refuses delimiter soup shared between spans', () => {
		/* `*a**b*` — the middle run closes one span and opens the next, so
		   neither pair collapses; the writer sees what they typed. */
		expect(liveCollapse('*a**b*', 5)).toBeNull();
	});

	it('refuses a half-consumed delimiter — the literal middle waits', () => {
		/* `**a*` pairs only one star of the opener in the grammar, and at the
		   keyboard that answer is wrong: typing `**word**` would italicise
		   the word the moment the first closer arrived and never reach bold.
		   A pair collapses on its whole delimiter or not at all. */
		expect(liveCollapse('**a*', 3)).toBeNull();
		expect(liveCollapse('**world*', 7)).toBeNull();
		/* …and the completed pair collapses once, to bold. */
		expect(liveCollapse('**world**', 8)).toEqual({
			text: 'world',
			run: { start: 0, end: 5, styles: ['Bold'] },
			removed: [
				{ start: 0, end: 2 },
				{ start: 7, end: 9 }
			],
			caret: 5
		});
	});

	it('does not disturb markers outside the completed pair', () => {
		/* An unclosed opener from earlier typing survives the later collapse. */
		const collapsed = liveCollapse('*keep **this**', 13);
		expect(collapsed?.text).toBe('*keep this');
		expect(collapsed?.run).toEqual({ start: 6, end: 10, styles: ['Bold'] });
	});

	it('never collapses an empty pair', () => {
		expect(liveCollapse('****', 3)).toBeNull(); // 4+ stars: literal run
		expect(liveCollapse('**' + '**', 3)).toBeNull(); // empty match
	});
});

describe('toggleHighlight', () => {
	it('applies the mark, splitting at the range edges', () => {
		const runs = toggleHighlight([], 3, 9, 'yellow', 12);
		expect(runs).toEqual([{ start: 3, end: 9, styles: [], highlight: 'yellow' }]);
	});

	it('one color per point: an apply clears first, then sets', () => {
		const marked = toggleHighlight([], 0, 12, 'yellow', 12);
		const over = toggleHighlight(marked, 4, 8, 'yellow', 12);
		expect(over).toEqual([{ start: 0, end: 12, styles: [], highlight: 'yellow' }]);
	});

	it('fully covered comes off clean, styles keep their span', () => {
		const base = [
			{ start: 0, end: 6, styles: ['Bold' as const] },
			{ start: 6, end: 12, styles: [], highlight: 'yellow' as const }
		];
		expect(toggleHighlight(base, 6, 12, undefined, 12)).toEqual([
			{ start: 0, end: 6, styles: ['Bold'] }
		]);
	});

	it('a partial clear splits the mark around the gap', () => {
		const marked = [{ start: 0, end: 10, styles: [], highlight: 'yellow' as const }];
		expect(toggleHighlight(marked, 3, 7, undefined, 10)).toEqual([
			{ start: 0, end: 3, styles: [], highlight: 'yellow' },
			{ start: 7, end: 10, styles: [], highlight: 'yellow' }
		]);
	});

	it('highlightCovered answers the bar’s one decision', () => {
		const marked = [
			{ start: 0, end: 5, styles: [], highlight: 'yellow' as const },
			{ start: 5, end: 10, styles: [], highlight: 'yellow' as const }
		];
		expect(highlightCovered(marked, 2, 8)).toBe(true);
		expect(highlightCovered(marked, 2, 11)).toBe(false);
		expect(highlightCovered([], 0, 1)).toBe(false);
	});
});
