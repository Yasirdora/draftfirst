import { describe, expect, it } from 'vitest';
import { emptyEnterOutcome, newSummonState, resetSummon, slashSummons } from './summon.js';

describe('emptyEnterOutcome', () => {
	it('advances on the first two empty Enters, summons on the third', () => {
		const s = newSummonState();
		expect(emptyEnterOutcome(s, true)).toBe('advance');
		expect(emptyEnterOutcome(s, true)).toBe('advance');
		expect(emptyEnterOutcome(s, true)).toBe('menu');
	});

	it('starts the cycle fresh after a summon (Esc then Enter advances again)', () => {
		const s = newSummonState();
		emptyEnterOutcome(s, true);
		emptyEnterOutcome(s, true);
		expect(emptyEnterOutcome(s, true)).toBe('menu');
		expect(emptyEnterOutcome(s, true)).toBe('advance');
	});

	it('an Enter with text commits and resets the run', () => {
		const s = newSummonState();
		emptyEnterOutcome(s, true);
		emptyEnterOutcome(s, true);
		expect(emptyEnterOutcome(s, false)).toBe('advance');
		expect(emptyEnterOutcome(s, true)).toBe('advance');
	});

	it('never summons on a line with text, however long the run before it', () => {
		const s = newSummonState();
		emptyEnterOutcome(s, true);
		emptyEnterOutcome(s, true);
		emptyEnterOutcome(s, true);
		expect(emptyEnterOutcome(s, false)).toBe('advance');
	});

	it('resetSummon breaks the run', () => {
		const s = newSummonState();
		emptyEnterOutcome(s, true);
		emptyEnterOutcome(s, true);
		resetSummon(s);
		expect(emptyEnterOutcome(s, true)).toBe('advance');
	});
});

describe('slashSummons', () => {
	it('summons on an empty or whitespace-only line', () => {
		expect(slashSummons('')).toBe(true);
		expect(slashSummons('   ')).toBe(true);
	});

	it('is ordinary text on a line with content', () => {
		expect(slashSummons('APARTMENT 4')).toBe(false);
		expect(slashSummons('a')).toBe(false);
	});
});
