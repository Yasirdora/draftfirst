/** Character renaming: extension preservation, case tolerance, merge safety. */
import { describe, expect, it } from 'vitest';
import { nameDriftGroups } from './continuity.js';
import { normalizeCueName, renameCharacter } from './rename.js';
import type { Screenplay, ScreenplayElement } from './types.js';

function el(type: ScreenplayElement['type'], text: string, extra: Partial<ScreenplayElement> = {}): ScreenplayElement {
	return { type, text, ...extra };
}

function script(elements: ScreenplayElement[]): Screenplay {
	return { titlePage: [], elements };
}

describe('normalizeCueName', () => {
	it('trims, uppercases, and collapses whitespace', () => {
		expect(normalizeCueName('  mara   jane ')).toBe('MARA JANE');
	});
	it('treats anything from an open paren on as an extension', () => {
		expect(normalizeCueName('Mary (O.S.)')).toBe('MARY');
		expect(normalizeCueName("(cont'd)")).toBe('');
	});
	it('returns empty for empty input', () => {
		expect(normalizeCueName('   ')).toBe('');
	});
});

describe('renameCharacter', () => {
	it('renames every cue with the matching base name', () => {
		const s = script([el('character', 'MARA'), el('dialogue', 'You kept it.'), el('character', 'MARA')]);
		const r = renameCharacter(s, 'MARA', 'MARY');
		expect(r.changed).toBe(2);
		expect(r.elements[0].text).toBe('MARY');
		expect(r.elements[2].text).toBe('MARY');
	});

	it('preserves extensions exactly as written', () => {
		const s = script([
			el('character', 'MARA (O.S.)'),
			el('character', "MARA (CONT'D)"),
			el('character', 'MARA (V.O.) (PRE-LAP)')
		]);
		const r = renameCharacter(s, 'MARA', 'MARY');
		expect(r.elements[0].text).toBe('MARY (O.S.)');
		expect(r.elements[1].text).toBe("MARY (CONT'D)");
		expect(r.elements[2].text).toBe('MARY (V.O.) (PRE-LAP)');
	});

	it('matches case-insensitively and writes the canonical uppercase name', () => {
		const s = script([el('character', 'Mara'), el('character', 'mara')]);
		const r = renameCharacter(s, 'mara', 'Mary');
		expect(r.changed).toBe(2);
		expect(r.elements[0].text).toBe('MARY');
	});

	it('never renames a longer name that merely contains the target', () => {
		const s = script([el('character', 'MARIAM'), el('character', 'MARA LANE')]);
		const r = renameCharacter(s, 'MARA', 'MARY');
		expect(r.changed).toBe(0);
		expect(r.elements).toBe(s.elements);
	});

	it('never touches prose — action, dialogue, scene, or transition', () => {
		const s = script([
			el('scene', "INT. MARA'S FLAT - NIGHT"),
			el('action', 'MARA enters, breathless.'),
			el('character', 'ELIAS'),
			el('dialogue', 'MARA! Wait—'),
			el('transition', 'CUT TO:')
		]);
		const r = renameCharacter(s, 'MARA', 'MARY');
		expect(r.changed).toBe(0);
		expect(r.elements).toBe(s.elements);
	});

	it('keeps the dual-dialogue flag with the renamed cue', () => {
		const s = script([el('character', 'MARA', { dual: true })]);
		const r = renameCharacter(s, 'MARA', 'MARY');
		expect(r.elements[0]).toEqual({ type: 'character', text: 'MARY', dual: true });
	});

	it('renaming into an existing name merges the two casts', () => {
		const s = script([el('character', 'MARA'), el('character', 'MARY'), el('character', 'MARA')]);
		const r = renameCharacter(s, 'MARA', 'MARY');
		expect(r.changed).toBe(2);
		expect(r.elements.map((e) => e.text)).toEqual(['MARY', 'MARY', 'MARY']);
	});

	it('is pure: the input stream is never mutated and identity is kept for untouched elements', () => {
		const action = el('action', 'Dust hangs in the beam.');
		const cue = el('character', 'MARA');
		const s = script([cue, action]);
		const r = renameCharacter(s, 'MARA', 'MARY');
		expect(cue.text).toBe('MARA');
		expect(r.elements).not.toBe(s.elements);
		expect(r.elements[1]).toBe(action);
	});

	it('no-ops cleanly: same name, empty name, or an unknown name', () => {
		const s = script([el('character', 'MARA')]);
		expect(renameCharacter(s, 'MARA', 'mara').changed).toBe(0);
		expect(renameCharacter(s, 'MARA', '  ').changed).toBe(0);
		expect(renameCharacter(s, 'NOBODY', 'MARY').changed).toBe(0);
		expect(renameCharacter(s, 'MARA', 'MARA').elements).toBe(s.elements);
	});
});

describe('nameDriftGroups', () => {
	it('groups near-miss typos and leaves distinct names alone', () => {
		const groups = nameDriftGroups(['MARA', 'MARIA', 'ELIAS', 'JOSS']);
		expect(groups).toEqual([['MARA', 'MARIA']]);
	});
	it('chains transitivity: MARA / MARIA / MARIE union into one group', () => {
		const groups = nameDriftGroups(['MARA', 'MARIA', 'MARIE']);
		expect(groups).toEqual([['MARA', 'MARIA', 'MARIE']]);
	});
	it('returns nothing for a clean cast or an empty one', () => {
		expect(nameDriftGroups(['MARA', 'ELIAS'])).toEqual([]);
		expect(nameDriftGroups([])).toEqual([]);
	});
	it('does not flag deliberate lookalikes beyond the edit-distance limit', () => {
		expect(nameDriftGroups(['JOSS', 'JAKE'])).toEqual([]);
	});
});
