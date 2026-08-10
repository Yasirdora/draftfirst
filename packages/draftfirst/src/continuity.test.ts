/** Continuity diagnostics and false-positive protections. */
import { describe, expect, it } from 'vitest';
import { continuityKey, continuityReport, driftGroups } from './continuity.js';
import type { Screenplay } from './types.js';

function el(type: any, text: string) {
	return { type, text };
}

function script(elements: ReturnType<typeof el>[]): Screenplay {
	return { titlePage: [], elements };
}

describe('continuityKey', () => {
	it('ignores case, punctuation and leading articles', () => {
		expect(continuityKey("Molly's Diner")).toBe(continuityKey('MOLLYS DINER'));
		expect(continuityKey('The Lab')).toBe(continuityKey('LAB'));
		expect(continuityKey('DR. VOSS')).toBe(continuityKey('Dr Voss'));
	});

	it('does not collapse genuinely different names', () => {
		expect(continuityKey('JOHN')).not.toBe(continuityKey('JOAN'));
	});
});

describe('driftGroups', () => {
	it('groups spelling drift, most-used first', () => {
		const counts = new Map([
			['THE DINER', 5],
			['DINER', 12],
			['STREET', 3]
		]);
		const groups = driftGroups(counts);
		expect(groups).toEqual([['DINER', 'THE DINER']]);
	});
});

describe('continuityReport', () => {
	it('flags character cue drift with counts', () => {
		const s = script([
			el('character', 'MOLLY'),
			el('dialogue', 'Hi.'),
			el('character', 'MOLLY.'),
			el('dialogue', 'Typo cue.')
		]);
		const note = continuityReport(s).find((n) => n.kind === 'Character cue spelled two ways');
		expect(note).toBeTruthy();
		expect(note!.detail).toContain('MOLLY');
		expect(note!.detail).toContain('MOLLY.');
		expect(note).toMatchObject({
			code: 'character-spelling-drift',
			severity: 'warning',
			elementIndices: [0, 2]
		});
	});

	it('flags location drift', () => {
		const s = script([
			el('scene', "INT. MOLLY'S DINER - DAY"),
			el('scene', "INT. THE MOLLY'S DINER - NIGHT")
		]);
		const note = continuityReport(s).find((n) => n.kind === 'Location spelled two ways');
		expect(note).toBeTruthy();
	});

	it('flags an unclosed sequence with its expected closer', () => {
		const s = script([
			el('scene', 'INT. ROOM - DAY'),
			el('action', 'FLASHBACK:'),
			el('action', 'The past.')
		]);
		const note = continuityReport(s).find((n) => n.kind === 'Unclosed sequence');
		expect(note).toBeTruthy();
		expect(note!.why).toContain('END FLASHBACK');
	});

	it('does not flag a closed sequence', () => {
		const s = script([
			el('action', 'FLASHBACK:'),
			el('action', 'The past.'),
			el('action', 'END FLASHBACK')
		]);
		expect(continuityReport(s).find((n) => n.kind === 'Unclosed sequence')).toBeUndefined();
	});

	it('flags scene headings missing a time of day', () => {
		const s = script([
			el('scene', 'INT. KITCHEN'),
			el('scene', 'EXT. STREET - NIGHT')
		]);
		const note = continuityReport(s).find((n) => n.kind.includes('no time of day'));
		expect(note).toBeTruthy();
		expect(note!.detail).toContain('INT. KITCHEN');
		expect(note!.detail).not.toContain('EXT. STREET');
	});

	it('flags a once-speaking near-miss of an established speaker', () => {
		const s = script([
			el('character', 'MOLLY'),
			el('dialogue', 'One.'),
			el('character', 'MOLLY'),
			el('dialogue', 'Two.'),
			el('character', 'MOLLY'),
			el('dialogue', 'Three.'),
			el('character', 'MOLLIE'),
			el('dialogue', 'A typo speaks.')
		]);
		const note = continuityReport(s).find((n) => n.kind.includes('almost-familiar'));
		expect(note).toBeTruthy();
		expect(note!.detail).toContain('MOLLIE');
		expect(note!.detail).toContain('MOLLY');
	});

	it('never flags a once-speaker with an unrelated name', () => {
		const s = script([
			el('character', 'MOLLY'),
			el('dialogue', 'One.'),
			el('character', 'MOLLY'),
			el('dialogue', 'Two.'),
			el('character', 'MOLLY'),
			el('dialogue', 'Three.'),
			el('character', 'STRANGER'),
			el('dialogue', 'Just passing through.')
		]);
		expect(continuityReport(s).find((n) => n.kind.includes('almost-familiar'))).toBeUndefined();
	});

	it('flags dialogue with no cue above it', () => {
		const s = script([
			el('scene', 'INT. ROOM - DAY'),
			el('dialogue', 'Who says this?')
		]);
		const note = continuityReport(s).find((n) => n.kind.includes('no speaker'));
		expect(note).toBeTruthy();
		expect(note).toMatchObject({
			code: 'orphan-dialogue-flow',
			severity: 'error',
			elementIndices: [1]
		});
	});

	it('flags cue-less lyrics as orphaned spoken flow', () => {
		const note = continuityReport(script([el('lyrics', 'No one is singing this.')]))[0];
		expect(note).toMatchObject({ code: 'orphan-dialogue-flow', elementIndices: [0] });
	});

	it('accepts dialogue following a cue, parenthetical or more dialogue', () => {
		const s = script([
			el('character', 'MOLLY'),
			el('parenthetical', '(quietly)'),
			el('dialogue', 'All properly attributed.'),
			el('dialogue', 'Still her.')
		]);
		expect(continuityReport(s).find((n) => n.kind.includes('no speaker'))).toBeUndefined();
	});

	it('returns nothing for a clean script', () => {
		const s = script([
			el('scene', 'INT. KITCHEN - DAY'),
			el('action', 'A kettle screams.'),
			el('character', 'MOLLY'),
			el('dialogue', 'I heard it first.'),
			el('character', 'JOAN'),
			el('dialogue', 'Impossible.'),
			el('character', 'MOLLY'),
			el('dialogue', 'Listen.')
		]);
		expect(continuityReport(s)).toEqual([]);
	});

	it('ignores extension suffixes when counting speakers', () => {
		const s = script([
			el('character', 'MOLLY (V.O.)'),
			el('dialogue', 'Voice.'),
			el('character', "MOLLY (CONT'D)"),
			el('dialogue', 'More.')
		]);
		expect(continuityReport(s).find((n) => n.kind.includes('speaks only once'))).toBeUndefined();
	});
});
