/**
 * Tests for element choreography (Tab/Enter contract) and SmartType derivation.
 */
import { describe, expect, it } from 'vitest';
import {
	emptyLineEscape,
	nextElement,
	tabNext,
	tabCycle,
	tabSetFor,
	TAB_RING,
	TAB_SET_FRESH
} from './choreography.js';
import { collectSmartType, findLocationDrift, splitSceneHeading, stripCueExtensions } from './smarttype.js';
import { parseFountain } from './parse.js';

describe('choreography · Enter, the forward flow', () => {
	it('scene → action · action → action · character → dialogue', () => {
		expect(nextElement('scene', 'enter')).toBe('action');
		expect(nextElement('action', 'enter')).toBe('action');
		expect(nextElement('character', 'enter')).toBe('dialogue');
	});

	it('parenthetical → dialogue · dialogue → character (the rally)', () => {
		expect(nextElement('parenthetical', 'enter')).toBe('dialogue');
		expect(nextElement('dialogue', 'enter')).toBe('character');
	});

	it('transition → scene (a cut starts a new scene)', () => {
		expect(nextElement('transition', 'enter')).toBe('scene');
	});

	it('Enter on an empty line changes what the line is, and action reaches a cue', () => {
		// The way out of a speech block, from anywhere inside it.
		expect(nextElement('character', 'enter', '')).toBe('scene');
		expect(nextElement('dialogue', 'enter', '')).toBe('action');
		expect(nextElement('parenthetical', 'enter', '')).toBe('action');
		expect(nextElement('scene', 'enter', '   ')).toBe('action');
		// And out of action: a second Return on the blank line it just made
		// reaches for the person who speaks next.
		expect(nextElement('action', 'enter', '')).toBe('character');
		// So a blank line is a cycle rather than a dead end.
		expect(nextElement(emptyLineEscape('action'), 'enter', '')).toBe('scene');
	});
});

describe('choreography · the Tab ring', () => {
	it('is a true ring: every major element exactly once', () => {
		expect(TAB_RING.length).toBe(6);
		expect(new Set(TAB_RING).size).toBe(6);
		for (const t of ['character', 'dialogue', 'parenthetical', 'transition', 'scene', 'action']) {
			expect(TAB_RING).toContain(t);
		}
	});

	it('honours the professional mandates', () => {
		expect(tabNext('character')).toBe('dialogue');
		expect(tabNext('dialogue')).toBe('parenthetical');
		expect(tabNext('parenthetical')).toBe('transition');
		expect(tabNext('transition')).toBe('scene');
		expect(tabNext('scene')).toBe('action');
		expect(tabNext('action')).toBe('character');
	});

	it('a scene heading never reaches a speech element in one step', () => {
		expect(['parenthetical', 'dialogue', 'character']).not.toContain(tabNext('scene'));
	});

	it('a character cue never reaches a scene heading in one step', () => {
		expect(tabNext('character')).not.toBe('scene');
	});

	it('walks the whole ring in exactly six presses and returns home', () => {
		const walk: string[] = ['character'];
		for (let i = 0; i < 6; i++) walk.push(tabNext(walk[walk.length - 1] as never));
		expect(walk).toEqual([
			'character', 'dialogue', 'parenthetical', 'transition', 'scene', 'action', 'character'
		]);
	});

	it('never repeats the previous element, from any start, forever', () => {
		for (const start of TAB_RING) {
			let cur = start;
			for (let i = 0; i < 24; i++) {
				const next = tabNext(cur);
				expect(next).not.toBe(cur);
				cur = next;
			}
		}
	});

	it('⇧Tab walks the same ring backwards', () => {
		expect(tabNext('dialogue', true)).toBe('character');
		expect(tabNext('character', true)).toBe('action');
		let cur = tabNext('character', true);
		for (let i = 0; i < 5; i++) cur = tabNext(cur, true);
		expect(cur).toBe('character');
	});

	it('off-ring types join at action', () => {
		expect(tabNext('shot')).toBe('character');
		expect(tabNext('general')).toBe('character');
	});

	it('nextElement(tab) is the ring successor', () => {
		expect(nextElement('character', 'tab')).toBe('dialogue');
		expect(nextElement('dialogue', 'tab')).toBe('parenthetical');
		expect(nextElement('action', 'tab')).toBe('character');
	});
});

describe('choreography · context-narrowed Tab sets (document syntax)', () => {
	it('after a scene heading: action · character · transition — never bare speech, never a new scene', () => {
		const set = tabSetFor('scene');
		expect([...set]).toEqual(['action', 'character', 'transition']);
		expect(set).not.toContain('dialogue');
		expect(set).not.toContain('parenthetical');
		expect(set).not.toContain('scene');
	});

	it('the owner’s walk: from the action under a slug, Tab never offers a speech element', () => {
		let cur: string = 'action';
		const seen: string[] = [];
		for (let i = 0; i < 6; i++) {
			cur = tabCycle(cur as never, 'scene');
			seen.push(cur);
		}
		expect(seen).toEqual(['character', 'transition', 'action', 'character', 'transition', 'action']);
		expect(seen).not.toContain('dialogue');
		expect(seen).not.toContain('parenthetical');
		expect(seen).not.toContain('scene');
	});

	it('after action: a closed action · character · transition loop — no gesture can strand the writer', () => {
		expect([...tabSetFor('action')]).toEqual(['action', 'character', 'transition']);
		// The first stop is unchanged: an action line still enters at character…
		expect(tabCycle('action', 'action')).toBe('character');
		expect(tabCycle('action', 'action', true)).toBe('transition');
		expect(tabCycle('character', 'action')).toBe('transition');
		// …but the loop now comes home: transition wraps to action, and the
		// reverse of the accidental forward swipe (action → character) is
		// character → action.
		expect(tabCycle('transition', 'action')).toBe('action');
		expect(tabCycle('character', 'action', true)).toBe('action');
		expect(tabCycle('transition', 'action', true)).toBe('character');
		// Speech elements stay unreachable, exactly as before.
		let cur: string = 'action';
		for (let i = 0; i < 9; i++) {
			cur = tabCycle(cur as never, 'action');
			expect(['dialogue', 'parenthetical', 'scene']).not.toContain(cur);
		}
	});

	it('after a character cue: dialogue · parenthetical only', () => {
		expect([...tabSetFor('character')]).toEqual(['dialogue', 'parenthetical']);
		expect(tabCycle('dialogue', 'character')).toBe('parenthetical');
		expect(tabCycle('parenthetical', 'character')).toBe('dialogue');
		expect(tabCycle('dialogue', 'character', true)).toBe('parenthetical');
	});

	it('after a parenthetical: a one-element set — the soft park, never a dead key', () => {
		expect([...tabSetFor('parenthetical')]).toEqual(['dialogue']);
		expect(tabCycle('dialogue', 'parenthetical')).toBe('dialogue');
		expect(tabCycle('dialogue', 'parenthetical', true)).toBe('dialogue');
		expect(tabCycle('action', 'parenthetical')).toBe('dialogue');
	});

	it('after dialogue: keep speaking, cut away, open, describe, cue — and back', () => {
		expect([...tabSetFor('dialogue')]).toEqual([
			'dialogue', 'transition', 'scene', 'action', 'character'
		]);
		// Enter from a speech lands on a cue. One Tab forward from there
		// wraps to dialogue, so a writer who meant to keep talking gets
		// there in a single gesture.
		expect(tabCycle('character', 'dialogue')).toBe('dialogue');
		expect(tabCycle('dialogue', 'dialogue')).toBe('transition');
		expect(tabCycle('transition', 'dialogue')).toBe('scene');
		expect(tabCycle('scene', 'dialogue')).toBe('action');
		expect(tabCycle('action', 'dialogue')).toBe('character');
		// Backwards is the same walk in reverse, all the way round.
		expect(tabCycle('character', 'dialogue', true)).toBe('action');
		expect(tabCycle('action', 'dialogue', true)).toBe('scene');
		expect(tabCycle('scene', 'dialogue', true)).toBe('transition');
		expect(tabCycle('transition', 'dialogue', true)).toBe('dialogue');
		expect(tabCycle('dialogue', 'dialogue', true)).toBe('character');
		// A direction belongs under the cue that opens the speech, not
		// between two of its lines.
		expect(tabSetFor('dialogue')).not.toContain('parenthetical');
	});

	it('after a transition: the fresh-line set, scene included', () => {
		expect([...tabSetFor('transition')]).toEqual([...TAB_SET_FRESH]);
		expect(tabCycle('scene', 'transition')).toBe('action');
	});

	it('document start and structural elements open the fresh set', () => {
		expect([...tabSetFor(null)]).toEqual([...TAB_SET_FRESH]);
		expect([...tabSetFor('shot')]).toEqual([...TAB_SET_FRESH]);
		expect([...tabSetFor('general')]).toEqual([...TAB_SET_FRESH]);
		expect([...tabSetFor('centered')]).toEqual([...TAB_SET_FRESH]);
	});

	it('every set is a subset of the ring, non-empty, and cycle-safe forever', () => {
		for (const prev of [null, 'scene', 'action', 'character', 'parenthetical', 'dialogue', 'transition'] as const) {
			const set = tabSetFor(prev as never);
			expect(set.length).toBeGreaterThan(0);
			for (const t of set) expect(TAB_RING).toContain(t);
			let cur = set[0];
			for (let i = 0; i < 12; i++) {
				cur = tabCycle(cur as never, prev as never);
				expect(set).toContain(cur);
			}
		}
	});
});

describe('smarttype · cue extensions', () => {
	it('strips (V.O.), (O.S.), (O.C.), (CONT\u2019D)', () => {
		expect(stripCueExtensions('MOLLY (V.O.)')).toBe('MOLLY');
		expect(stripCueExtensions('MOLLY (O.S.)')).toBe('MOLLY');
		expect(stripCueExtensions("MOLLY (CONT'D)")).toBe('MOLLY');
		expect(stripCueExtensions('MOLLY (V.O.) (CONT\u2019D)')).toBe('MOLLY');
	});
});

describe('smarttype · scene heading splitting', () => {
	it('splits prefix / location / time', () => {
		expect(splitSceneHeading('INT. POLICE STATION - NIGHT')).toEqual({
			prefix: 'INT.',
			location: 'POLICE STATION',
			time: 'NIGHT'
		});
	});

	it('handles missing time and forced headings', () => {
		const parts = splitSceneHeading("MOLLY'S DINER");
		expect(parts.location).toBe("MOLLY'S DINER");
		expect(parts.time).toBe('');
	});

	it('keeps multi-word locations with commas intact', () => {
		const parts = splitSceneHeading('INT. BATHROOM, KEVIN\u2019S HOUSE - MORNING');
		expect(parts.location).toBe('BATHROOM, KEVIN\u2019S HOUSE');
		expect(parts.time).toBe('MORNING');
	});
});

describe('smarttype · document vocabulary', () => {
	it('collects characters, locations, times, transitions in order', () => {
		const s = parseFountain(
			[
				'INT. LAB - DAY',
				'',
				'MOLLY (V.O.)',
				'Hello.',
				'',
				'ELIAS',
				'Hi.',
				'',
				'MOLLY',
				'Again.',
				'',
				'CUT TO:',
				'',
				'EXT. ROOF - NIGHT',
				''
			].join('\n')
		);
		const data = collectSmartType(s);
		expect(data.characters).toEqual(['MOLLY', 'ELIAS']);
		expect(data.locations).toEqual(['LAB', 'ROOF']);
		expect(data.times).toEqual(['DAY', 'NIGHT']);
		expect(data.transitions).toEqual(['CUT TO:']);
	});
});

describe('smarttype · location drift lint', () => {
	it('flags MOLLY\u2019S DINER vs THE DINER style drift', () => {
		const s = parseFountain("INT. MOLLY'S DINER - DAY\n\nINT. THE DINER - NIGHT\n");
		const pairs = findLocationDrift(s);
		expect(pairs).toEqual([{ a: "MOLLY'S DINER", b: 'THE DINER' }]);
	});

	it('stays quiet for distinct locations', () => {
		const s = parseFountain('INT. LAB - DAY\n\nEXT. ROOF - NIGHT\n');
		expect(findLocationDrift(s)).toEqual([]);
	});
});
