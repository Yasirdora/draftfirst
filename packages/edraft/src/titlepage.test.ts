/** The title-page line model: the migration template (D8), the derivation
    that answers by key (D3/D7), and the fixed points between them. */

import { describe, expect, it } from 'vitest';
import {
	deriveTitlePage,
	TITLE_CONTACT_LAST_LINE,
	TITLE_STACK_LEADING_BLANKS,
	titlePageLinesFromEntries,
	titlePageValues
} from './titlepage.js';
import type { TitlePageLine } from './types.js';

const blanks = (count: number): TitlePageLine[] =>
	Array.from({ length: count }, () => ({ text: '' }));

describe('titlePageLinesFromEntries · the classic template', () => {
	it('writes the stack at the grid positions the keyed renderer computed', () => {
		const lines = titlePageLinesFromEntries([
			{ key: 'Title', values: ['The Empty Cinema'] },
			{ key: 'Credit', values: ['written by'] },
			{ key: 'Author', values: ['A. Projectionist'] },
			{ key: 'Draft date', values: ['8/8/2026'] },
			{ key: 'Contact', values: ['booth@example.com', '42 Reel Lane'] }
		]);

		/* Fifteen blanks: line 15 is 72 + 15 × 12 = 252pt down — the classic
		   anchor was 0.32 × 792 = 253.44, so the stack settles 1.44pt onto
		   the grid here and never moves again. */
		expect(lines.slice(0, TITLE_STACK_LEADING_BLANKS)).toEqual(blanks(TITLE_STACK_LEADING_BLANKS));

		/* The renderer uppercased the title; the line stores that form, so
		   nothing has to transform it at render time ever again. */
		expect(lines[15]).toEqual({ text: 'THE EMPTY CINEMA', key: 'Title' });
		expect(lines[16]).toEqual({ text: '' });
		expect(lines[17]).toEqual({ text: 'written by', key: 'Credit' });
		expect(lines[18]).toEqual({ text: '' });
		expect(lines[19]).toEqual({ text: 'A. Projectionist', key: 'Author' });

		/* An extra key prints its label first, exactly as the keyed renderer
		   did — Source was and remains the exception. */
		expect(lines[20]).toEqual({ text: '' });
		expect(lines[21]).toEqual({ text: 'Draft date', key: 'Draft date' });
		expect(lines[22]).toEqual({ text: '8/8/2026', key: 'Draft date' });

		/* Contact lands with its LAST line on line 54 — 72 + 54 × 12 = 720 =
		   page height − 72, the classic anchor, which is grid-exact. */
		expect(lines[lines.length - 2]).toEqual({
			text: 'booth@example.com',
			alignment: 'left',
			key: 'Contact'
		});
		expect(lines[lines.length - 1]).toEqual({
			text: '42 Reel Lane',
			alignment: 'left',
			key: 'Contact'
		});
		expect(lines.length - 1).toBe(TITLE_CONTACT_LAST_LINE);
	});

	it('prints no label line for Source, matching the keyed renderer', () => {
		const lines = titlePageLinesFromEntries([
			{ key: 'Title', values: ['A Film'] },
			{ key: 'Source', values: ['the novel by John Smith'] }
		]);
		/* 15 blanks, the title, and the two unconditional group separators —
		   the keyed renderer advanced past empty groups the same way. */
		expect(lines[16]).toEqual({ text: '' });
		expect(lines[18]).toEqual({ text: '' });
		expect(lines[19]).toEqual({ text: 'the novel by John Smith', key: 'Source' });
	});

	it('keeps every value of a multi-line field contiguous', () => {
		const lines = titlePageLinesFromEntries([
			{ key: 'Title', values: ['The Long', 'Winding Title'] }
		]);
		expect(lines[15]).toEqual({ text: 'THE LONG', key: 'Title' });
		expect(lines[16]).toEqual({ text: 'WINDING TITLE', key: 'Title' });
	});

	it('migrates nothing for entries that rendered nothing', () => {
		expect(titlePageLinesFromEntries([])).toEqual([]);
		expect(titlePageLinesFromEntries([{ key: 'Title', values: [] }])).toEqual([]);
		expect(titlePageLinesFromEntries([{ key: 'Title', values: ['', '  '] }])).toEqual([]);
	});

	it('lets an overflowing stack push contact past its anchor rather than lose it', () => {
		const values = Array.from({ length: 50 }, (_, i) => `Extra ${i}`);
		const lines = titlePageLinesFromEntries([
			{ key: 'Author', values },
			{ key: 'Contact', values: ['home@example.com'] }
		]);
		/* The classic renderer would have overlapped the blocks; the template
		   cannot represent overlap, so contact follows immediately — the one
		   place the settle is documented rather than pixel-exact. */
		expect(lines[lines.length - 1]).toEqual({
			text: 'home@example.com',
			alignment: 'left',
			key: 'Contact'
		});
	});
});

describe('deriveTitlePage · the inverse', () => {
	it('round-trips the keyed fields through the template, label lines included', () => {
		const entries = [
			{ key: 'Title', values: ['The Empty Cinema'] },
			{ key: 'Credit', values: ['written by'] },
			{ key: 'Author', values: ['A. Projectionist'] },
			{ key: 'Draft date', values: ['8/8/2026'] },
			{ key: 'Contact', values: ['booth@example.com', '42 Reel Lane'] }
		];
		const derived = deriveTitlePage(titlePageLinesFromEntries(entries));
		expect(derived).toEqual([
			{ key: 'Title', values: ['THE EMPTY CINEMA'] },
			{ key: 'Credit', values: ['written by'] },
			{ key: 'Author', values: ['A. Projectionist'] },
			{ key: 'Draft date', values: ['8/8/2026'] },
			{ key: 'Contact', values: ['booth@example.com', '42 Reel Lane'] }
		]);
	});

	it('does not eat a Source value that happens to equal its key', () => {
		const lines = titlePageLinesFromEntries([
			{ key: 'Source', values: ['Source', 'the novel by John Smith'] }
		]);
		expect(deriveTitlePage(lines)).toEqual([
			{ key: 'Source', values: ['Source', 'the novel by John Smith'] }
		]);
	});

	it('reads a bare foreign page heuristically: title, credit, authors, contact', () => {
		const lines: TitlePageLine[] = [
			...blanks(15),
			{ text: 'GONE GIRL' },
			{ text: '' },
			{ text: 'written by' },
			{ text: 'Gillian Flynn' },
			...blanks(20),
			{ text: 'Flynn, Gillian', alignment: 'left' },
			{ text: 'gillian@example.com', alignment: 'left' }
		];
		expect(deriveTitlePage(lines)).toEqual([
			{ key: 'Title', values: ['GONE GIRL'] },
			{ key: 'Credit', values: ['written by'] },
			{ key: 'Author', values: ['Gillian Flynn'] },
			{ key: 'Contact', values: ['Flynn, Gillian', 'gillian@example.com'] }
		]);
	});

	it('folds an unclaimed line into the entry above it rather than losing it', () => {
		const lines: TitlePageLine[] = [
			{ text: 'MY FILM', key: 'Title' },
			{ text: '' },
			{ text: 'a story in five reels' }
		];
		expect(deriveTitlePage(lines)).toEqual([
			{ key: 'Title', values: ['MY FILM', 'a story in five reels'] }
		]);
	});

	it('answers by name for the guided surfaces', () => {
		const lines = titlePageLinesFromEntries([
			{ key: 'Title', values: ['A Film'] },
			{ key: 'Author', values: ['Elena Voss', 'June Park'] }
		]);
		expect(titlePageValues(lines, 'author')).toEqual(['Elena Voss', 'June Park']);
		expect(titlePageValues(lines, 'Contact')).toEqual([]);
	});
});
