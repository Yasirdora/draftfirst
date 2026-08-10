/** SmartType extraction and canonical casing at the collection boundary. */
import { describe, it, expect } from 'vitest';
import { collectSmartType, splitSceneHeading, stripCueExtensions, findLocationDrift } from './smarttype.js';
import { predict } from './predict.js';
import type { Screenplay } from './types.js';

const script = (elements: Screenplay['elements']): Screenplay => ({ titlePage: [], elements });

describe('splitSceneHeading', () => {
	it('splits prefix / location / time', () => {
		expect(splitSceneHeading('INT. MOLLY’S DINER - NIGHT')).toEqual({
			prefix: 'INT.',
			location: 'MOLLY’S DINER',
			time: 'NIGHT'
		});
	});

	it('returns canonical uppercase regardless of typed case', () => {
		expect(splitSceneHeading('int. lab - night')).toEqual({
			prefix: 'INT.',
			location: 'LAB',
			time: 'NIGHT'
		});
	});

	it('splits on the LAST spaced dash and tolerates en/em dashes', () => {
		expect(splitSceneHeading('EXT. 54TH ST - UPTOWN - DAY').location).toBe('54TH ST - UPTOWN');
		expect(splitSceneHeading('INT. LAB — NIGHT').time).toBe('NIGHT');
	});

	it('keeps heading modifiers out of both location and time', () => {
		expect(splitSceneHeading('INT. BATHROOM - DAY - ESTABLISHING')).toEqual({
			prefix: 'INT.',
			location: 'BATHROOM',
			time: 'DAY'
		});
	});

	it('a heading without a time reports an empty time', () => {
		expect(splitSceneHeading('INT. LAB').time).toBe('');
	});
});

describe('stripCueExtensions', () => {
	it('strips parenthesised extensions', () => {
		expect(stripCueExtensions('MARA (V.O.)')).toBe('MARA');
		expect(stripCueExtensions("ELIAS (CONT'D)")).toBe('ELIAS');
	});

	it('strips only parenthesised extensions — bare ones are normalizeCue’s job', () => {
		expect(stripCueExtensions('MARA O.S.')).toBe('MARA O.S.');
	});
});

describe('collectSmartType — canonical case contract', () => {
	it('uppercases characters, locations, times and transitions', () => {
		const data = collectSmartType(
			script([
				{ type: 'scene', text: 'int. lab - night' },
				{ type: 'character', text: 'mara' },
				{ type: 'dialogue', text: 'We are out of time.' },
				{ type: 'transition', text: 'cut to:' }
			])
		);
		expect(data.characters).toEqual(['MARA']);
		expect(data.locations).toEqual(['LAB']);
		expect(data.times).toEqual(['NIGHT']);
		expect(data.transitions).toEqual(['CUT TO:']);
	});

	it('never lists the same character twice across case', () => {
		const data = collectSmartType(
			script([
				{ type: 'character', text: 'mara' },
				{ type: 'dialogue', text: 'one' },
				{ type: 'character', text: 'MARA' },
				{ type: 'dialogue', text: 'two' }
			])
		);
		expect(data.characters).toEqual(['MARA']);
	});
});

describe('findLocationDrift', () => {
	it('flags article/punctuation drift between locations', () => {
		const pairs = findLocationDrift(
			script([
				{ type: 'scene', text: 'INT. MOLLY’S DINER - DAY' },
				{ type: 'scene', text: 'INT. THE DINER - NIGHT' }
			])
		);
		expect(pairs.length).toBeGreaterThan(0);
	});

	it('flags locations whose normal forms are exactly equal', () => {
		expect(
			findLocationDrift(
				script([
					{ type: 'scene', text: 'INT. THE DINER - DAY' },
					{ type: 'scene', text: 'INT. DINER - NIGHT' }
				])
			)
		).toEqual([{ a: 'THE DINER', b: 'DINER' }]);
	});

	it('handles a large unique vocabulary without changing deterministic order', () => {
		const locations = Array.from({ length: 2_000 }, (_, index) => ({
			type: 'scene' as const,
			text: `INT. LOCATION ${index} - DAY`
		}));
		locations.push({ type: 'scene', text: 'INT. THE LOCATION 1999 - NIGHT' });

		expect(findLocationDrift(script(locations))).toEqual([
			{ a: 'LOCATION 1999', b: 'THE LOCATION 1999' }
		]);
	});
});

describe('prediction survives raw-case leaks (regression)', () => {
	const leaky = script([
		{ type: 'scene', text: 'INT. LAB - NIGHT' },
		{ type: 'character', text: 'mara' },
		{ type: 'dialogue', text: 'We are out of time.' },
		{ type: 'character', text: 'ELIAS' },
		{ type: 'dialogue', text: 'Then we run.' }
	]);

	it('typing MAR still whispers the name', () => {
		const out = predict(leaky, { type: 'character', text: 'MAR', index: 5 });
		expect(out.map((p) => p.text)).toContain('MARA');
	});

	it('the empty-cue list never offers semantic duplicates', () => {
		const out = predict(leaky, { type: 'character', text: '', index: 5 });
		const upper = out.map((p) => p.text.toUpperCase().replace(/\s*\(CONT'D\)$/, ''));
		expect(new Set(upper).size).toBe(upper.length);
	});

	it('a lowercase heading still feeds location memory', () => {
		const s = script([{ type: 'scene', text: 'int. lab - night' }]);
		const out = predict(s, { type: 'scene', text: 'INT. L', index: 1 });
		expect(out.map((p) => p.text)).toContain('LAB');
	});
});
