import { describe, expect, it } from 'vitest';
import { SLASH_COMMANDS } from './slash-commands';
import { filterPaletteCommands, PALETTE_COMMANDS } from './palette-commands';

describe('palette catalogue', () => {
	it('has unique ids and complete entries', () => {
		const ids = PALETTE_COMMANDS.map((c) => c.id);
		expect(new Set(ids).size).toBe(ids.length);
		for (const cmd of PALETTE_COMMANDS) {
			expect(cmd.label.length).toBeGreaterThan(0);
			expect(cmd.keywords.length).toBeGreaterThan(0);
		}
	});

	it('mirrors the slash catalogue in the Insert group', () => {
		const inserts = PALETTE_COMMANDS.filter((c) => c.group === 'Insert');
		expect(inserts.length).toBe(SLASH_COMMANDS.length);
		expect(inserts.map((c) => c.label)).toEqual(SLASH_COMMANDS.map((c) => c.label));
	});
});

describe('filterPaletteCommands', () => {
	it('returns everything in stable order for an empty query', () => {
		const all = filterPaletteCommands('');
		expect(all.length).toBe(PALETTE_COMMANDS.length);
		expect(all[0].group).toBe('Document');
		expect(all[0].id).toBe('new');
	});

	it('matches by label, keywords, and hint', () => {
		expect(filterPaletteCommands('table').map((c) => c.id)).toEqual([
			'insert-table',
			'insert-table3'
		]);
		expect(filterPaletteCommands('pdf')[0].id).toBe('export-print');
		expect(filterPaletteCommands('⌘f')[0].id).toBe('find');
	});

	it('matches every whitespace-separated part', () => {
		const hits = filterPaletteCommands('doc new');
		expect(hits.some((c) => c.id === 'new')).toBe(true);
	});

	it('finds insert entries through the group name', () => {
		const hits = filterPaletteCommands('insert');
		expect(hits.every((c) => c.group === 'Insert')).toBe(true);
		expect(hits.length).toBe(SLASH_COMMANDS.length);
	});

	it('returns nothing for gibberish', () => {
		expect(filterPaletteCommands('xyzzy plugh')).toEqual([]);
	});
});
