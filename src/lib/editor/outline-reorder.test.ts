import { describe, expect, it } from 'vitest';
import {
	moveOutlineSection,
	reorderOutlineSections,
	splitOutlineSections
} from './outline-reorder';

const SAMPLE = [
	'Intro line',
	'',
	'# One',
	'Body one',
	'',
	'## Two',
	'Body two',
	'',
	'# Three',
	'Body three',
	''
].join('\n');

describe('splitOutlineSections', () => {
	it('keeps preamble and splits ATX headings', () => {
		const sections = splitOutlineSections(SAMPLE);
		expect(sections[0].level).toBe(0);
		expect(sections[0].body).toContain('Intro line');
		expect(sections.filter((s) => s.level > 0).map((s) => s.title)).toEqual([
			'One',
			'Two',
			'Three'
		]);
	});
});

describe('reorderOutlineSections', () => {
	it('moves a section before another', () => {
		const next = reorderOutlineSections(SAMPLE, 2, 0);
		const titles = splitOutlineSections(next)
			.filter((s) => s.level > 0)
			.map((s) => s.title);
		expect(titles).toEqual(['Three', 'One', 'Two']);
		expect(next).toContain('Intro line');
		expect(next).toContain('Body three');
	});
});

describe('moveOutlineSection', () => {
	it('moves a section down', () => {
		const next = moveOutlineSection(SAMPLE, 0, 1);
		const titles = splitOutlineSections(next)
			.filter((s) => s.level > 0)
			.map((s) => s.title);
		expect(titles[0]).toBe('Two');
		expect(titles[1]).toBe('One');
	});
});
