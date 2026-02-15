import { describe, expect, it } from 'vitest';
import { parseHTML } from 'linkedom';
import { renderMarkdown } from './render';
import { serialiseMarkdown } from './serialise';
import {
	assessFidelity,
	compactHunks,
	diffLines,
	groupTruthChanges,
	changeVisualPair,
	humanChangeDescription,
	minimalEditPair,
	normalizeCosmetic,
	normalizeEol,
	plainTextSkeleton,
	restoreTruthChange
} from './fidelity';

/** Render → serialise round-trip using a minimal DOM (linkedom). */
function roundTrip(source: string): string {
	const { document } = parseHTML('<!DOCTYPE html><html><body></body></html>');
	const root = document.createElement('article');
	root.innerHTML = renderMarkdown(source);
	return serialiseMarkdown(root);
}

describe('normalizeEol / normalizeCosmetic', () => {
	it('normalises CRLF and trailing blank noise', () => {
		expect(normalizeEol('a\r\nb\r\n')).toBe('a\nb\n');
		// Hard breaks (`  \n`) are preserved; stray trailing spaces are not.
		const cos = normalizeCosmetic('Hello  \n\n\nWorld   \n');
		expect(cos).toBe('Hello  \n\nWorld\n');
	});

	it('rewrites emphasis style cosmetically', () => {
		expect(normalizeCosmetic('__bold__ and _italic_\n')).toBe('**bold** and *italic*\n');
	});
});

describe('plainTextSkeleton', () => {
	it('strips markup but keeps words', () => {
		const plain = plainTextSkeleton('# Title\n\nA **bold** [link](https://x.test) word');
		expect(plain).toContain('title');
		expect(plain).toContain('bold');
		expect(plain).toContain('link');
		expect(plain).toContain('word');
		expect(plain).not.toContain('**');
		expect(plain).not.toContain('https');
	});
});

describe('diffLines', () => {
	it('detects simple line replace', () => {
		const hunks = diffLines('one\ntwo\n', 'one\nTWO\n');
		expect(hunks.filter((h) => h.kind === 'remove').map((h) => h.text)).toEqual(['two']);
		expect(hunks.filter((h) => h.kind === 'add').map((h) => h.text)).toEqual(['TWO']);
		expect(hunks.filter((h) => h.kind === 'equal').map((h) => h.text)).toEqual(['one']);
	});
});

describe('assessFidelity', () => {
	it('reports identical for equal sources', () => {
		const report = assessFidelity('# Hi\n', '# Hi\n');
		expect(report.status).toBe('identical');
		expect(report.warn).toBe(false);
	});

	it('reports identical when only trailing newline differs', () => {
		const report = assessFidelity('# Hi', '# Hi\n');
		expect(report.status).toBe('identical');
	});

	it('reports normalized for emphasis style rewrite', () => {
		const report = assessFidelity('Hello __world__\n', 'Hello **world**\n');
		expect(report.status).toBe('normalized');
		expect(report.warn).toBe(false);
	});

	it('reports changed for intentional edits', () => {
		const report = assessFidelity('# A\n\nOne\n', '# A\n\nTwo\n');
		expect(report.status).toBe('changed');
		expect(report.warn).toBe(false);
		expect(report.added + report.removed).toBeGreaterThan(0);
	});

	it('reports lossy when large plain content vanishes', () => {
		const before = [
			'# Report',
			'',
			'This paragraph has substantial unique content that should not vanish.',
			'Another sentence with more words to exceed the loss threshold cleanly.',
			'Third line of material for the skeleton comparison path.',
			''
		].join('\n');
		const after = '# Report\n\nGone.\n';
		const report = assessFidelity(before, after);
		expect(report.status).toBe('lossy');
		expect(report.warn).toBe(true);
	});

	it('reports lossy when many links disappear', () => {
		const before = [
			'See [a](https://a.test), [b](https://b.test), [c](https://c.test), [d](https://d.test).',
			''
		].join('\n');
		const after = 'See a, b, c, d.\n';
		const report = assessFidelity(before, after);
		expect(report.status).toBe('lossy');
		expect(report.summary.toLowerCase()).toMatch(/link/);
	});
});

describe('compactHunks', () => {
	it('keeps context around changes only', () => {
		const hunks = diffLines('a\nb\nc\nd\ne\n', 'a\nb\nC\nd\ne\n');
		const compact = compactHunks(hunks, 1);
		expect(compact.some((h) => h.text === 'C' && h.kind === 'add')).toBe(true);
		expect(compact.some((h) => h.text === 'c' && h.kind === 'remove')).toBe(true);
		// Far equal lines may still appear as context for b/d but not necessarily all.
		expect(compact.length).toBeLessThan(hunks.length + 1);
	});
});

describe('selective Truth restore', () => {
	const before = ['# Title', '', 'alpha', '', 'beta', '', 'gamma', ''].join('\n');
	const after = ['# Title', '', 'ALPHA', '', 'beta', '', 'GAMMA', ''].join('\n');

	it('groups two independent line changes', () => {
		const changes = groupTruthChanges(diffLines(before, after));
		expect(changes.length).toBe(2);
		expect(changes[0].removes).toEqual(['alpha']);
		expect(changes[0].adds).toEqual(['ALPHA']);
		expect(changes[1].removes).toEqual(['gamma']);
		expect(changes[1].adds).toEqual(['GAMMA']);
	});

	it('restores only the first change and keeps the second', () => {
		const next = restoreTruthChange(before, after, 0);
		expect(next).toContain('alpha');
		expect(next).not.toContain('ALPHA');
		expect(next).toContain('GAMMA');
		expect(next).not.toContain('gamma');
		expect(next).toContain('beta');
	});

	it('restores only the second change and keeps the first', () => {
		const next = restoreTruthChange(before, after, 1);
		expect(next).toContain('ALPHA');
		expect(next).toContain('gamma');
		expect(next).not.toContain('GAMMA');
	});

	it('describes changes with visible text, never a vague category alone', () => {
		const changes = groupTruthChanges(diffLines('# Writing Desk\n', '# hriting Desk\n'));
		expect(changes.length).toBe(1);
		const desc = humanChangeDescription(changes[0]);
		expect(desc.toLowerCase()).toMatch(/writing|hriting|w/);
		expect(desc).toMatch(/→/);
		expect(desc).not.toBe('Spacing or punctuation');
		expect(desc).not.toContain('#');
	});

	it('still shows text when only punctuation differs', () => {
		const changes = groupTruthChanges(diffLines('Hello world\n', 'Hello world.\n'));
		expect(changes.length).toBe(1);
		const pair = changeVisualPair(changes[0]);
		// Only the period (or empty vs period), not the whole sentence
		expect(pair.before.length + pair.after.length).toBeLessThan('Hello world.'.length);
		expect(pair.after === '.' || pair.before === '' || pair.after.includes('.')).toBe(true);
	});

	it('minimalEditPair keeps only the differing word', () => {
		const { before, after } = minimalEditPair('Hello world today', 'Hello earth today');
		expect(before.toLowerCase()).toContain('world');
		expect(after.toLowerCase()).toContain('earth');
		expect(before.toLowerCase()).not.toContain('hello');
		expect(after.toLowerCase()).not.toContain('today');
	});
});

describe('round-trip fidelity inventory (render → serialise)', () => {
	const cases: { name: string; source: string; expectStatus: Array<'identical' | 'normalized' | 'changed' | 'lossy'> }[] = [
		{
			name: 'simple paragraph',
			source: 'Hello world.\n',
			expectStatus: ['identical', 'normalized']
		},
		{
			name: 'headings and emphasis',
			source: '# Title\n\nA **bold** and *italic* word.\n',
			expectStatus: ['identical', 'normalized']
		},
		{
			name: 'GFM table',
			source: '| A | B |\n| --- | --- |\n| 1 | 2 |\n',
			expectStatus: ['identical', 'normalized']
		},
		{
			name: 'task list',
			source: '- [x] done\n- [ ] todo\n',
			expectStatus: ['identical', 'normalized', 'changed']
		},
		{
			name: 'fenced code',
			source: '```js\nconst x = 1;\n```\n',
			expectStatus: ['identical', 'normalized']
		},
		{
			name: 'blockquote',
			source: '> A quote\n>\n> with two lines\n',
			expectStatus: ['identical', 'normalized', 'changed']
		},
		{
			name: 'link and image',
			source: 'See [docs](https://commonmark.org) and ![alt](/img.png).\n',
			expectStatus: ['identical', 'normalized']
		},
		{
			name: 'raw HTML stays escaped in source spirit',
			source: 'Text with <not-a-tag> inside.\n',
			expectStatus: ['identical', 'normalized', 'changed']
		}
	];

	for (const c of cases) {
		it(`round-trips: ${c.name}`, () => {
			const after = roundTrip(c.source);
			const report = assessFidelity(c.source, after);
			expect(c.expectStatus, `${c.name}: got ${report.status}\n--- before ---\n${c.source}\n--- after ---\n${after}`).toContain(
				report.status
			);
			// Never classify a pure no-edit round-trip as lossy for these fixtures.
			expect(report.status).not.toBe('lossy');
		});
	}

	it('SAMPLE document round-trips without loss', async () => {
		const { SAMPLE } = await import('./sample');
		const after = roundTrip(SAMPLE);
		const report = assessFidelity(SAMPLE, after);
		expect(report.status).not.toBe('lossy');
		// Skeleton words should largely survive.
		const beforePlain = plainTextSkeleton(SAMPLE);
		const afterPlain = plainTextSkeleton(after);
		expect(afterPlain.length).toBeGreaterThan(beforePlain.length * 0.8);
	});
});
