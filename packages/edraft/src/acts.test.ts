/** The act derivation: ordinals, the canonical spelling, the renumber rule. */
import { describe, expect, it } from 'vitest';
import {
	actOrdinal,
	defaultActCard,
	isCanonicalActCard,
	renumberActs
} from './acts.js';
import type { ScreenplayElement } from './types.js';

function actbreaks(...texts: string[]): ScreenplayElement[] {
	return texts.map((text) => ({ type: 'actbreak', text }));
}

describe('actOrdinal', () => {
	it('spells words through twenty, digits beyond', () => {
		expect(actOrdinal(1)).toBe('ONE');
		expect(actOrdinal(4)).toBe('FOUR');
		expect(actOrdinal(20)).toBe('TWENTY');
		expect(actOrdinal(21)).toBe('21');
		expect(actOrdinal(113)).toBe('113');
	});
});

describe('isCanonicalActCard', () => {
	it('accepts the canonical spelling, words or digits', () => {
		expect(isCanonicalActCard('ACT ONE')).toBe(true);
		expect(isCanonicalActCard('ACT TWENTY')).toBe(true);
		expect(isCanonicalActCard('ACT 21')).toBe(true);
		expect(isCanonicalActCard('ACT 3')).toBe(true);
	});

	it('refuses everything the writer could have meant something by', () => {
		expect(isCanonicalActCard('TEASER')).toBe(false);
		expect(isCanonicalActCard('ACT TWO: THE TURN')).toBe(false);
		expect(isCanonicalActCard('Act One')).toBe(false);
		expect(isCanonicalActCard('ACT TWENTYONE')).toBe(false);
		expect(isCanonicalActCard('ACT ONE ')).toBe(false);
		expect(isCanonicalActCard('ACT  ONE')).toBe(false);
		expect(isCanonicalActCard('ACT')).toBe(false);
		expect(isCanonicalActCard('')).toBe(false);
	});
});

describe('renumberActs', () => {
	it('leaves an already-sequential script untouched, identity included', () => {
		const elements = actbreaks('ACT ONE', 'ACT TWO', 'ACT THREE');
		const renumbered = renumberActs(elements);
		expect(renumbered.map((e) => e.text)).toEqual(['ACT ONE', 'ACT TWO', 'ACT THREE']);
		expect(renumbered.every((e, i) => e === elements[i])).toBe(true);
	});

	it('closes the gap a deleted act leaves', () => {
		const renumbered = renumberActs(actbreaks('ACT ONE', 'ACT THREE', 'ACT FOUR'));
		expect(renumbered.map((e) => e.text)).toEqual(['ACT ONE', 'ACT TWO', 'ACT THREE']);
	});

	it('never rewrites a customised card, but still counts its act', () => {
		const renumbered = renumberActs(actbreaks('ACT ONE', 'TEASER', 'ACT TWO'));
		expect(renumbered.map((e) => e.text)).toEqual(['ACT ONE', 'TEASER', 'ACT THREE']);
	});

	it('renumbers a mid-script insert and what follows it', () => {
		const renumbered = renumberActs(actbreaks('ACT ONE', 'ACT TWO', 'ACT TWO', 'ACT THREE'));
		expect(renumbered.map((e) => e.text)).toEqual(['ACT ONE', 'ACT TWO', 'ACT THREE', 'ACT FOUR']);
	});

	it('crosses from words to digits past twenty', () => {
		const many = actbreaks(...Array.from({ length: 22 }, () => 'ACT ONE'));
		const renumbered = renumberActs(many);
		expect(renumbered[19].text).toBe('ACT TWENTY');
		expect(renumbered[20].text).toBe('ACT 21');
		expect(renumbered[21].text).toBe('ACT 22');
	});

	it('ignores everything that is not an act break', () => {
		const elements: ScreenplayElement[] = [
			{ type: 'scene', text: 'INT. ROOM - DAY' },
			{ type: 'action', text: 'ACT ONE is said aloud, not printed.' },
			{ type: 'actbreak', text: 'ACT SEVEN' }
		];
		const renumbered = renumberActs(elements);
		expect(renumbered[0]).toBe(elements[0]);
		expect(renumbered[1]).toBe(elements[1]);
		expect(renumbered[2].text).toBe('ACT ONE');
	});

	it('is idempotent — the second pass is the empty edit', () => {
		const once = renumberActs(actbreaks('ACT THREE', 'TEASER', 'ACT ONE'));
		const twice = renumberActs(once);
		expect(twice.map((e) => e.text)).toEqual(once.map((e) => e.text));
		expect(twice.every((e, i) => e === once[i])).toBe(true);
	});
});

describe('defaultActCard', () => {
	it('spells the canonical card of its ordinal', () => {
		expect(defaultActCard(2)).toBe('ACT TWO');
		expect(defaultActCard(23)).toBe('ACT 23');
	});
});
