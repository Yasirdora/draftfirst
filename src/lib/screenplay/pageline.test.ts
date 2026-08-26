/**
 * The printed-line contract. A stray `^` on a production page is the kind
 * of defect that reaches a reader before it reaches a bug report, so the
 * strip is pinned here for every renderer that shares it.
 */
import { describe, expect, it } from 'vitest';
import { printedLineText } from './pageline';
import { paginate } from '@edraft/core/layout';
import type { PageLine } from '@edraft/core/layout';
import type { Screenplay } from '@edraft/core';

function line(type: PageLine['type'], text: string): PageLine {
	return { type, text, indent: 0, element: 0 };
}

describe('printedLineText', () => {
	it('removes the dual marker the paginator appends to a cue', () => {
		expect(printedLineText(line('character', 'JOAN ^'))).toBe('JOAN');
	});

	it('leaves an ordinary cue untouched', () => {
		expect(printedLineText(line('character', 'JOAN'))).toBe('JOAN');
	});

	it('keeps a caret the writer typed in action or dialogue', () => {
		expect(printedLineText(line('action', 'She points up ^ at the sign.'))).toBe(
			'She points up ^ at the sign.'
		);
		expect(printedLineText(line('dialogue', 'Up ^ there.'))).toBe('Up ^ there.');
	});

	it('keeps a caret that is part of the cue name itself', () => {
		/* only the generated ' ^' suffix is bookkeeping; '^' with no space is
		   text the writer put there */
		expect(printedLineText(line('character', 'M^LLY'))).toBe('M^LLY');
	});

	it('leaves generated (MORE) and blank lines alone', () => {
		expect(printedLineText(line('more', '(MORE)'))).toBe('(MORE)');
		expect(printedLineText(line('blank', ''))).toBe('');
	});
});

describe('paginated dual dialogue', () => {
	const script: Screenplay = {
		titlePage: [],
		elements: [
			{ type: 'character', text: 'MOLLY' },
			{ type: 'dialogue', text: 'We speak—' },
			{ type: 'character', text: 'JOAN', dual: true },
			{ type: 'dialogue', text: '—at the same time.' }
		]
	};

	it('carries the marker through pagination but never into printed text', () => {
		const lines = paginate(script).flatMap((p) => p.lines);
		/* the paginator still wraps the cue at its true width … */
		expect(lines.some((l) => l.text.endsWith(' ^'))).toBe(true);
		/* … and no renderer ever shows it */
		expect(lines.map(printedLineText).some((t) => t.includes('^'))).toBe(false);
		expect(lines.map(printedLineText)).toContain('JOAN');
	});
});
