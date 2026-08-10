import { describe, expect, it } from 'vitest';
import { looksLikeCue, normalizeCue, normalizeElementText, normalizeParenthetical } from './normalize.js';

describe('normalizeParenthetical', () => {
	it('wraps bare text', () => {
		expect(normalizeParenthetical('beat')).toBe('(beat)');
	});

	it('closes an unclosed opening bracket', () => {
		expect(normalizeParenthetical('(beat')).toBe('(beat)');
	});

	it('supplies a missing opening bracket', () => {
		expect(normalizeParenthetical('beat)')).toBe('(beat)');
	});

	it('is idempotent on correct text', () => {
		expect(normalizeParenthetical('(beat)')).toBe('(beat)');
	});

	it('treats bracket-only residue as empty', () => {
		expect(normalizeParenthetical('')).toBe('');
		expect(normalizeParenthetical('(')).toBe('');
		expect(normalizeParenthetical('()')).toBe('');
		expect(normalizeParenthetical(')')).toBe('');
		expect(normalizeParenthetical('  (  ')).toBe('');
	});

	it('closes a second unclosed group inside', () => {
		expect(normalizeParenthetical('(beat) (sotto')).toBe('(beat) (sotto)');
	});

	it('trims stray whitespace inside the brackets', () => {
		expect(normalizeParenthetical('(  beat  )')).toBe('(beat)');
	});
});

describe('normalizeCue', () => {
	it('closes and canonicalizes a partial known extension', () => {
		expect(normalizeCue('MARA (V.O')).toBe('MARA (V.O.)');
		expect(normalizeCue("MARA (CONT'D")).toBe("MARA (CONT'D)");
	});

	it('closes an ambiguous partial extension without guessing', () => {
		expect(normalizeCue('MARA (V')).toBe('MARA (V)');
	});

	it('closes an unclosed custom extension', () => {
		expect(normalizeCue('MARA (WHISPERING')).toBe('MARA (WHISPERING)');
	});

	it('drops a dangling empty bracket', () => {
		expect(normalizeCue('MARA (')).toBe('MARA');
	});

	it('brackets a bare known extension', () => {
		expect(normalizeCue('MARA VO')).toBe('MARA (V.O.)');
		expect(normalizeCue('MARA V.O')).toBe('MARA (V.O.)');
		expect(normalizeCue('MARA O.S')).toBe('MARA (O.S.)');
		expect(normalizeCue("MARA CONT'D")).toBe("MARA (CONT'D)");
		expect(normalizeCue('MARA PRE-LAP')).toBe('MARA (PRE-LAP)');
	});

	it('lowercases bare extensions are canonicalized', () => {
		expect(normalizeCue('Mara vo')).toBe('Mara (V.O.)');
	});

	it('leaves already-closed cues untouched', () => {
		expect(normalizeCue('MARA (V.O.)')).toBe('MARA (V.O.)');
		expect(normalizeCue('MARA (O.S.)')).toBe('MARA (O.S.)');
	});

	it('never treats a lone extension as a cue', () => {
		expect(normalizeCue('VO')).toBe('VO');
		expect(normalizeCue('os')).toBe('os');
	});

	it('never mangles names that merely end in extension letters', () => {
		expect(normalizeCue('CARLOS')).toBe('CARLOS');
		expect(normalizeCue('MARA')).toBe('MARA');
	});

	it('handles empty input', () => {
		expect(normalizeCue('')).toBe('');
		expect(normalizeCue('   ')).toBe('');
	});
});

describe('looksLikeCue', () => {
	it('recognizes cue-shaped names', () => {
		expect(looksLikeCue('JOHN')).toBe(true);
		expect(looksLikeCue('DETECTIVE ROSA')).toBe(true);
		expect(looksLikeCue("O'MALLEY")).toBe(true);
		expect(looksLikeCue('AGENT 47')).toBe(true);
		expect(looksLikeCue('MARA VO')).toBe(true);
	});

	it('never hijacks a genuine wryly', () => {
		expect(looksLikeCue('beat')).toBe(false);
		expect(looksLikeCue('(beat')).toBe(false);
		expect(looksLikeCue('under her breath')).toBe(false);
		expect(looksLikeCue('to JOHN')).toBe(false);
	});

	it('rejects non-names', () => {
		expect(looksLikeCue('')).toBe(false);
		expect(looksLikeCue('J')).toBe(false);
		expect(looksLikeCue('47')).toBe(false);
		expect(looksLikeCue('John')).toBe(false);
	});
});

describe('normalizeElementText', () => {
	it('dispatches parentheticals and cues', () => {
		expect(normalizeElementText('parenthetical', 'beat')).toBe('(beat)');
		expect(normalizeElementText('character', 'MARA VO')).toBe('MARA (V.O.)');
	});

	it('returns other element types untouched', () => {
		expect(normalizeElementText('action', 'she (walks')).toBe('she (walks');
		expect(normalizeElementText('dialogue', 'wait...')).toBe('wait...');
		expect(normalizeElementText('scene', 'INT. LAB - DAY')).toBe('INT. LAB - DAY');
		expect(normalizeElementText('transition', 'CUT TO:')).toBe('CUT TO:');
	});
});
