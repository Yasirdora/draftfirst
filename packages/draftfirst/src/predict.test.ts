/** Contextual prediction, ranking, promotion, and completion behavior. */
import { describe, expect, it } from 'vitest';
import {
	predict,
	ghostSuffix,
	nextWord,
	ghostTabBehavior,
	sceneCharacters,
	lastSpeakerBefore,
	openStructure,
	bestTimeFor,
	type Prediction
} from './predict.js';
import { parseFountain } from './parse.js';
import type { Screenplay, ScreenplayElement } from './types.js';

const el = (type: ScreenplayElement['type'], text: string): ScreenplayElement => ({ type, text });
const doc = (elements: ScreenplayElement[]): Screenplay => ({ titlePage: [], elements });
const texts = (ps: Prediction[]) => ps.map((p) => p.text);

const TWO_HANDER = doc([
	el('scene', 'INT. KITCHEN - NIGHT'),
	el('action', 'Rain on the window.'),
	el('character', 'ELIAS'),
	el('dialogue', 'You came back.'),
	el('character', 'MARA'),
	el('dialogue', 'You said the reel burns at midnight.'),
	el('character', 'ELIAS'),
	el('dialogue', 'Then we watch it—'),
	el('character', '')
]);

describe('scene memory', () => {
	it('collects speakers of the current scene in first-appearance order', () => {
		expect(sceneCharacters(TWO_HANDER.elements, 8)).toEqual(['ELIAS', 'MARA']);
	});

	it('resets at scene boundaries', () => {
		const script = doc([
			el('scene', 'INT. A - DAY'), el('character', 'SAM'), el('dialogue', 'x'),
			el('scene', 'EXT. B - DAY'), el('character', 'JO'), el('dialogue', 'y'),
			el('character', '')
		]);
		expect(sceneCharacters(script.elements, 5)).toEqual(['JO']);
	});

	it('knows who spoke last', () => {
		expect(lastSpeakerBefore(TWO_HANDER.elements, 8)).toBe('ELIAS');
	});

	it('clamps non-finite and out-of-range consumer indices', () => {
		expect(sceneCharacters(TWO_HANDER.elements, Number.NaN)).toEqual([]);
		expect(lastSpeakerBefore(TWO_HANDER.elements, Number.POSITIVE_INFINITY)).toBe('ELIAS');
		expect(sceneCharacters(TWO_HANDER.elements, 999)).toEqual(['ELIAS', 'MARA']);
	});
});

describe('predict · empty character block (the ping-pong rule)', () => {
	it('suggests the dialogue partner first, never the last speaker', () => {
		const out = texts(predict(TWO_HANDER, { type: 'character', text: '', index: 8 }));
		expect(out[0]).toBe('MARA');
		expect(out.slice(0, 1)).not.toContain('ELIAS');
	});

	it('explains itself', () => {
		const out = predict(TWO_HANDER, { type: 'character', text: '', index: 8 });
		expect(out[0].why).toBe('the other half of the conversation');
	});

	it('one voice interrupted by action resumes with (CONT\u2019D)', () => {
		const script = doc([
			el('scene', 'INT. LAB - DAY'),
			el('character', 'MOLLY'),
			el('dialogue', 'I need a moment.'),
			el('action', 'She crosses to the window.'),
			el('character', '')
		]);
		const out = texts(predict(script, { type: 'character', text: '', index: 4 }));
		expect(out[0]).toBe("MOLLY (CONT'D)");
	});

	it('falls back to document characters when no scene partner exists', () => {
		const script = doc([
			el('scene', 'INT. LAB - DAY'),
			el('character', 'MOLLY'),
			el('dialogue', 'Hi.'),
			el('scene', 'EXT. ROOF - DAY'),
			el('action', 'Wind.'),
			el('character', '')
		]);
		expect(texts(predict(script, { type: 'character', text: '', index: 5 }))).toContain('MOLLY');
	});

	it('stays silent when nothing is known', () => {
		expect(predict(doc([]), { type: 'character', text: '', index: 0 })).toEqual([]);
	});
});

describe('predict · typed character prefix', () => {
	it('prefix-matches known characters case-insensitively', () => {
		expect(texts(predict(TWO_HANDER, { type: 'character', text: 'ma', index: 8 }))).toEqual(['MARA']);
	});

	it('a complete known name is complete — silence, so Tab jumps onward', () => {
		expect(predict(TWO_HANDER, { type: 'character', text: 'MARA', index: 8 })).toEqual([]);
	});
});

describe('predict · character extensions', () => {
	it('a bare name is just a name — silence until the writer signals intent', () => {
		expect(predict(TWO_HANDER, { type: 'character', text: 'MARA', index: 8 })).toEqual([]);
		expect(predict(TWO_HANDER, { type: 'character', text: 'ELIAS ', index: 8 })).toEqual([]);
	});

	it('typing "(" whispers extensions, closing paren included', () => {
		const out = texts(predict(TWO_HANDER, { type: 'character', text: 'MARA (V', index: 8 }));
		expect(out).toEqual(['(V.O.)']);
	});

	it('an open paren alone offers the full extension list', () => {
		const out = texts(predict(TWO_HANDER, { type: 'character', text: 'MARA (', index: 8 }));
		expect(out).toContain('(V.O.)');
		expect(out).toContain('(O.S.)');
	});

	it('ranks the script’s own used extensions first', () => {
		const script = doc([
			el('scene', 'INT. A - DAY'),
			el('character', 'MOLLY (O.S.)'),
			el('dialogue', 'Hello?'),
			el('character', 'ELIAS'),
			el('dialogue', 'Hi.'),
			el('character', 'MOLLY (')
		]);
		expect(texts(predict(script, { type: 'character', text: 'MOLLY (', index: 4 }))[0]).toBe('(O.S.)');
	});

	it('a brand-new name still gets the conventional extensions', () => {
		const out = texts(predict(TWO_HANDER, { type: 'character', text: 'ZZ TOP (', index: 8 }));
		expect(out).toContain('(V.O.)');
		expect(out).toContain('(O.S.)');
	});

	it('a brand-new name does not inherit the script’s habits', () => {
		const script = doc([
			el('scene', 'INT. A - DAY'),
			el('character', 'MOLLY (O.S.)'),
			el('dialogue', 'Hello?'),
			el('character', 'NEWCOMER (')
		]);
		const out = texts(predict(script, { type: 'character', text: 'NEWCOMER (', index: 3 }));
		expect(out[0]).toBe('(V.O.)');
		expect(out).toContain('(O.S.)');
	});
});

describe('predict · (CONT’D) is a fact, not a habit', () => {
	/* A same-scene action interruption should produce `(CONT'D)`. */
	it('leads with (CONT’D) when the same voice resumes after action', () => {
		const script = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('character', 'MARA'),
			el('dialogue', 'Hello.'),
			el('action', 'The machine hums.'),
			el('character', 'MARA (')
		]);
		const out = predict(script, { type: 'character', text: 'MARA (', index: 4 });
		expect(out[0].text).toBe("(CONT'D)");
		expect(out[0].why).toContain('resuming');
	});

	it('a typed prefix still narrows it: (C keeps it, (V does not', () => {
		const script = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('character', 'MARA'),
			el('dialogue', 'Hello.'),
			el('action', 'The machine hums.'),
			el('character', 'MARA (')
		]);
		expect(texts(predict(script, { type: 'character', text: 'MARA (C', index: 4 }))).toEqual(["(CONT'D)"]);
		expect(texts(predict(script, { type: 'character', text: 'MARA (V', index: 4 }))).toEqual(['(V.O.)']);
	});

	it('is not offered when another voice intervened — that is a reply, not a continuation', () => {
		const script = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('character', 'MARA'),
			el('dialogue', 'Hello.'),
			el('character', 'ELIAS'),
			el('dialogue', 'Hi.'),
			el('action', 'The machine hums.'),
			el('character', 'MARA (')
		]);
		const out = texts(predict(script, { type: 'character', text: 'MARA (', index: 6 }));
		expect(out).not.toContain("(CONT'D)");
		expect(out).toContain('(V.O.)');
	});

	it('is not offered across a scene boundary', () => {
		const script = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('character', 'MARA'),
			el('dialogue', 'Hello.'),
			el('action', 'The machine hums.'),
			el('scene', 'EXT. ROOF - DAWN'),
			el('character', 'MARA (')
		]);
		expect(texts(predict(script, { type: 'character', text: 'MARA (', index: 5 }))).not.toContain("(CONT'D)");
	});

	it('is not offered at a first entrance', () => {
		const script = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('action', 'The machine hums.'),
			el('character', 'MARA (')
		]);
		expect(texts(predict(script, { type: 'character', text: 'MARA (', index: 2 }))).not.toContain("(CONT'D)");
	});

	it('is not offered without intervening action — unbroken speech is just speech', () => {
		const script = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('character', 'MARA'),
			el('dialogue', 'Hello.'),
			el('character', 'MARA (')
		]);
		expect(texts(predict(script, { type: 'character', text: 'MARA (', index: 3 }))).not.toContain("(CONT'D)");
	});

	it('is not offered across transitions, general lines, or lyrics', () => {
		for (const interruption of [
			el('transition', 'CUT TO:'),
			el('general', 'A SPECIAL BEAT'),
			el('lyrics', 'La la la')
		]) {
			const script = doc([
				el('scene', 'INT. LAB - NIGHT'),
				el('character', 'MARA'),
				el('dialogue', 'Hello.'),
				el('action', 'The machine hums.'),
				interruption,
				el('character', 'MARA (')
			]);
			expect(texts(predict(script, { type: 'character', text: 'MARA (', index: 5 }))).not.toContain(
				"(CONT'D)"
			);
		}
	});

	it('house style cannot smuggle it back: a used (CONT’D) still needs the context', () => {
		const script = doc([
			el('scene', 'INT. A - DAY'),
			el('character', "JO (CONT'D)"),
			el('dialogue', 'We go on.'),
			el('scene', 'EXT. B - NIGHT'),
			el('action', 'Rain.'),
			el('character', 'SAM (')
		]);
		expect(texts(predict(script, { type: 'character', text: 'SAM (', index: 5 }))).not.toContain("(CONT'D)");
	});
});

describe('predict · the space gesture — name + space whispers the fact', () => {
	const RESUMING = () => doc([
		el('scene', 'INT. LAB - NIGHT'),
		el('character', 'MARA'),
		el('dialogue', 'Hello.'),
		el('action', 'The machine hums.'),
		el('character', 'MARA ')
	]);

	it('a space after the name whispers (CONT’D) when it is true', () => {
		const out = predict(RESUMING(), { type: 'character', text: 'MARA ', index: 4 });
		expect(out).toEqual([{ text: "(CONT'D)", why: 'same voice resuming after action' }]);
	});

	it('the suffix attaches cleanly to the trailing space', () => {
		expect(ghostSuffix("(CONT'D)", 'MARA ')).toBe("(CONT'D)");
	});

	it('a bare name without the space stays silent — the name is not intent', () => {
		expect(predict(RESUMING(), { type: 'character', text: 'MARA', index: 4 })).toEqual([]);
	});

	it('space whispers nothing when (CONT’D) would be false', () => {
		const firstEntrance = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('action', 'The machine hums.'),
			el('character', 'MARA ')
		]);
		expect(predict(firstEntrance, { type: 'character', text: 'MARA ', index: 2 })).toEqual([]);

		const replied = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('character', 'MARA'),
			el('dialogue', 'Hello.'),
			el('character', 'ELIAS'),
			el('dialogue', 'Hi.'),
			el('action', 'The machine hums.'),
			el('character', 'MARA ')
		]);
		expect(predict(replied, { type: 'character', text: 'MARA ', index: 6 })).toEqual([]);
	});

	it('does not invent (CONT’D) when the earlier cue never spoke', () => {
		const silentCue = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('character', 'MARA'),
			el('action', 'The machine hums.'),
			el('character', 'MARA ')
		]);

		expect(predict(silentCue, { type: 'character', text: 'MARA ', index: 3 })).toEqual([]);
	});

	it('an already-extended cue gets silence after the space', () => {
		const script = doc([
			el('scene', 'INT. LAB - NIGHT'),
			el('character', 'MARA'),
			el('dialogue', 'Hello.'),
			el('action', 'The machine hums.'),
			el('character', 'MARA (O.S.) ')
		]);
		expect(predict(script, { type: 'character', text: 'MARA (O.S.) ', index: 4 })).toEqual([]);
	});
});

describe('predict · scene heading assembly', () => {
	const script = parseFountain('INT. KITCHEN - NIGHT\n\nAction.\n\nEXT. ROOFTOP - DAWN\n');

	it('stage 1: completes INT./EXT. prefixes', () => {
		expect(texts(predict(script, { type: 'scene', text: 'in', index: 4 }))).toContain('INT. ');
	});

	it('stage 1: never hijacks a one-letter start', () => {
		expect(predict(script, { type: 'scene', text: 'i', index: 4 })).toEqual([]);
	});

	it('stage 2: offers learned locations by prefix', () => {
		expect(texts(predict(script, { type: 'scene', text: 'INT. KIT', index: 4 }))).toContain('KITCHEN');
	});

	it('stage 2 with nothing committed: teach the shape, never invent a place', () => {
		const out = predict(script, { type: 'scene', text: 'INT. ', index: 4 });
		expect(out).toEqual([{ text: 'LOCATION - TIME', why: 'the shape of a scene heading', hint: true }]);
	});

	it('coherence: EXT. STREET is never offered after INT.', () => {
		const s = doc([
			el('scene', 'EXT. STREET - DAY'),
			el('action', 'Traffic.'),
			el('scene', 'INT. KITCHEN - DAY'),
			el('action', 'Quiet.'),
			el('scene', '')
		]);
		const out = texts(predict(s, { type: 'scene', text: 'INT. S', index: 4 }));
		expect(out).not.toContain('STREET');
	});

	it('coherence: both-kind locations (INT./EXT.) fit either intro', () => {
		const s = doc([
			el('scene', 'INT./EXT. CAR - DAY'),
			el('action', 'Engine.'),
			el('scene', '')
		]);
		const out = texts(predict(s, { type: 'scene', text: 'EXT. C', index: 2 }));
		expect(out).toContain('CAR');
	});

	it('treats EST. locations as neutral rather than interior-only', () => {
		const s = doc([el('scene', 'EST. CITY - DAY'), el('scene', '')]);
		expect(texts(predict(s, { type: 'scene', text: 'EXT. C', index: 1 }))).toContain('CITY');
	});

	it('stage 3: offers times of day after the dash', () => {
		const out = texts(predict(script, { type: 'scene', text: 'EXT. ROOFTOP - D', index: 4 }));
		expect(out).toContain('DAWN');
		expect(out).toContain('DAY');
	});

	it('stage 3: a bare dash still offers the day — the ghost adds the space', () => {
		const out = predict(script, { type: 'scene', text: 'INT. KITCHEN -', index: 4 });
		expect(out.length).toBeGreaterThan(0);
		expect(out[0].text).toBe('NIGHT');
	});

	it('stage 1: covers I/E alongside INT./EXT.', () => {
		expect(texts(predict(script, { type: 'scene', text: 'I/', index: 4 }))).toEqual(['I/E ']);
	});

	it('stage 1: a half-typed compound intro completes (INT./ → INT./EXT.)', () => {
		expect(texts(predict(script, { type: 'scene', text: 'INT./', index: 4 }))).toEqual(['INT./EXT. ']);
	});

	it('stage 3: a bare dash offers the working day even with no habits yet', () => {
		const fresh = parseFountain('');
		const out = texts(predict(fresh, { type: 'scene', text: 'EXT. PIER -', index: 0 }));
		expect(out[0]).toBe('DAY');
		expect(out).toContain('NIGHT');
	});

	it('stage 3b: a second dash never offers the time twice — it offers modifiers', () => {
		const out = texts(predict(script, { type: 'scene', text: 'INT./EXT. BATHROOM - DAY -', index: 4 }));
		expect(out).not.toContain('DAY');
		expect(out).not.toContain('NIGHT');
		expect(out).toContain('ESTABLISHING');
	});

	it('stage 3b: a typed modifier prefix narrows; a complete one is silence', () => {
		expect(texts(predict(script, { type: 'scene', text: 'EXT. PIER - NIGHT - E', index: 4 }))).toEqual([
			'ESTABLISHING'
		]);
		expect(predict(script, { type: 'scene', text: 'EXT. PIER - NIGHT - ESTABLISHING', index: 4 })).toEqual([]);
	});

	it('stage 3: a complete known time is complete — silence, so Tab stays a commit', () => {
		expect(predict(script, { type: 'scene', text: 'INT. ATTIC - DAY', index: 4 })).toEqual([]);
		expect(predict(script, { type: 'scene', text: 'EXT. PIER - NIGHT', index: 4 })).toEqual([]);
		expect(texts(predict(script, { type: 'scene', text: 'INT. ATTIC - DAYS', index: 4 }))).toEqual([
			'DAYS LATER'
		]);
	});

	it('stage 2: a complete known location is complete — the same silence', () => {
		expect(predict(script, { type: 'scene', text: 'INT. KITCHEN', index: 4 })).toEqual([]);
		expect(texts(predict(script, { type: 'scene', text: 'INT. KIT', index: 4 }))).toContain('KITCHEN');
	});

	it('stage 3: covers the full professional time vocabulary', () => {
		expect(texts(predict(script, { type: 'scene', text: 'EXT. PIER - SUN', index: 4 }))).toEqual(['SUNRISE', 'SUNSET']);
		expect(texts(predict(script, { type: 'scene', text: 'EXT. DESERT - M', index: 4 }))).toEqual(
			expect.arrayContaining(['MAGIC HOUR', 'MIDNIGHT'])
		);
		expect(texts(predict(script, { type: 'scene', text: 'INT. BUNKER - SAME T', index: 4 }))).toEqual(['SAME TIME']);
		expect(texts(predict(script, { type: 'scene', text: 'INT. HOUSE - THE N', index: 4 }))).toEqual(['THE NEXT DAY']);
		expect(texts(predict(script, { type: 'scene', text: 'EXT. FARM - Y', index: 4 }))).toEqual(['YEARS LATER']);
		expect(texts(predict(script, { type: 'scene', text: 'INT. OFFICE - WEE', index: 4 }))).toEqual(['WEEKS LATER']);
		expect(texts(predict(script, { type: 'scene', text: 'INT. ATTIC - FL', index: 4 }))).toEqual(['FLASHBACK']);
		expect(texts(predict(script, { type: 'scene', text: 'INT. ATTIC - PRE', index: 4 }))).toEqual(['PRESENT DAY']);
		expect(texts(predict(script, { type: 'scene', text: 'EXT. CITY - FU', index: 4 }))).toEqual(['FUTURE']);
	});

	it('stage 3: time reasoning prefers the location’s own habit', () => {
		const s = doc([
			el('scene', 'INT. KITCHEN - NIGHT'),
			el('action', 'x'),
			el('scene', 'INT. BEDROOM - DAY'),
			el('action', 'y'),
			el('scene', 'INT. KITCHEN - ')
		]);
		expect(texts(predict(s, { type: 'scene', text: 'INT. KITCHEN - ', index: 4 }))[0]).toBe('NIGHT');
	});

	it('stage 3: a short threshold-crossing scene suggests CONTINUOUS', () => {
		const s = doc([
			el('scene', 'INT. HALLWAY - DAY'),
			el('action', 'He walks.'),
			el('scene', 'INT. STUDY - ')
		]);
		expect(bestTimeFor('STUDY', s.elements, 2)).toBe('CONTINUOUS');
	});
});

describe('predict · sequence structures', () => {
	it('an unclosed MONTAGE offers END OF MONTAGE', () => {
		const s = doc([
			el('scene', 'INT. GYM - DAY'),
			el('general', 'MONTAGE'),
			el('action', 'He trains.'),
			el('scene', 'END')
		]);
		const open = openStructure(s.elements, 3);
		expect(open).toEqual({ open: 'MONTAGE', close: 'END OF MONTAGE' });
		const out = texts(predict(s, { type: 'scene', text: 'END', index: 3 }));
		expect(out[0]).toBe('END OF MONTAGE');
	});

	it('offers special slugs by prefix', () => {
		const out = texts(predict(doc([]), { type: 'scene', text: 'MON', index: 0 }));
		expect(out).toContain('MONTAGE');
	});
});

describe('predict · transitions, wrylies, shots', () => {
	it('suggests transitions by prefix', () => {
		expect(texts(predict(doc([]), { type: 'transition', text: 'SM', index: 0 }))).toEqual(['SMASH CUT TO:']);
	});

	it('covers the full professional transition vocabulary', () => {
		const t = (text: string) => texts(predict(doc([]), { type: 'transition', text, index: 0 }));
		expect(t('H')).toEqual(['HARD CUT TO:']);
		expect(t('F')).toContain('FLIP CUT TO:');
		expect(t('FL')).toEqual(['FLIP CUT TO:']);
		expect(t('C')).toContain('CROSS DISSOLVE TO:');
		expect(t('CR')).toEqual(['CROSS DISSOLVE TO:']);
		expect(t('FADE TO W')).toEqual(['FADE TO WHITE.']);
		expect(t('FADE TO B')).toEqual(['FADE TO BLACK.']);
		expect(t('P')).toEqual(['PRE-LAP']);
		expect(t('SO')).toEqual(['SOUND CUT']);
		expect(t('AU')).toEqual(['AUDIO DISSOLVE']);
		expect(t('IRIS O')).toEqual(['IRIS OUT']);
		expect(t('IRIS I')).toEqual(['IRIS IN']);
		expect(t('INTERCUT W')).toEqual(['INTERCUT WITH:']);
		expect(predict(doc([]), { type: 'transition', text: 'CUT TO:', index: 0 })).toEqual([]);
	});

	it('ranks the writer’s own transitions first', () => {
		const script = doc([el('transition', 'BACK TO:')]);
		expect(texts(predict(script, { type: 'transition', text: 'B', index: 1 }))[0]).toBe('BACK TO:');
	});

	it('suggests parentheticals by prefix', () => {
		expect(texts(predict(doc([]), { type: 'parenthetical', text: '(qu', index: 0 }))).toEqual(['(quietly)']);
	});

	it('ranks the script’s own wrylies first', () => {
		const script = doc([el('parenthetical', '(dead inside)')]);
		expect(texts(predict(script, { type: 'parenthetical', text: '(de', index: 1 }))[0]).toBe('(dead inside)');
	});

	it('suggests shots by prefix', () => {
		expect(texts(predict(doc([]), { type: 'shot', text: 'AN', index: 0 }))).toEqual(['ANGLE ON']);
	});

	it('covers the working shot vocabulary', () => {
		const s = (text: string) => texts(predict(doc([]), { type: 'shot', text, index: 0 }));
		expect(s('W')).toEqual(['WIDE SHOT']);
		expect(s('TW')).toEqual(['TWO SHOT']);
		expect(s('CR')).toEqual(['CRANE SHOT']);
		expect(s('A')).toEqual(['ANGLE ON', 'AERIAL SHOT']);
	});

	it('covers the full cue-extension set', () => {
		const x = (text: string) => texts(predict(doc([]), { type: 'character', text, index: 0 }));
		expect(x('MARA (P')).toEqual(['(PRE-LAP)']);
		expect(x('MARA (F')).toEqual(['(FILTERED)']);
	});
});

describe('predict · action-line promotion (becomes)', () => {
	it('an action line starting a slugline predicts AND promises promotion', () => {
		const script = parseFountain('INT. KITCHEN - NIGHT\n\nAction.\n');
		const out = predict(script, { type: 'action', text: 'EXT', index: 3 });
		expect(out.length).toBeGreaterThan(0);
		expect(out[0].becomes).toBe('scene');
		expect(out[0].text).toBe('EXT. ');
	});

	it('ordinary prose gets silence', () => {
		expect(predict(doc([]), { type: 'action', text: 'The rain', index: 0 })).toEqual([]);
	});
});

describe('ghostSuffix', () => {
	it('empty block: offers the whole candidate', () => {
		expect(ghostSuffix('MARA', '')).toBe('MARA');
	});

	it('character prefix: offers only the tail', () => {
		expect(ghostSuffix('MARA', 'mar')).toBe('A');
	});

	it('scene prefix stage: offers the rest of INT. ', () => {
		expect(ghostSuffix('INT. ', 'in')).toBe('T. ');
	});

	it('location stage: offers the location tail', () => {
		expect(ghostSuffix('KITCHEN', 'INT. KIT')).toBe('CHEN');
	});

	it('time stage: offers the time tail', () => {
		expect(ghostSuffix('NIGHT', 'INT. LAB - NI')).toBe('GHT');
	});

	it('wrylies complete lowercase', () => {
		expect(ghostSuffix('(quietly)', '(qu')).toBe('ietly)');
	});

	it('shape hints append whole and spaced', () => {
		expect(ghostSuffix('LOCATION - TIME', 'INT.', true)).toBe(' LOCATION - TIME');
		expect(ghostSuffix('LOCATION - TIME', 'INT. ', true)).toBe('LOCATION - TIME');
	});

	it('extensions attach with correct spacing', () => {
		expect(ghostSuffix('(V.O.)', 'MARA')).toBe(' (V.O.)');
		expect(ghostSuffix('(V.O.)', 'MARA ')).toBe('(V.O.)');
	});

	it('the heading owns the dash spacing, not the writer', () => {
		expect(ghostSuffix('NIGHT', 'INT. LAB -')).toBe(' NIGHT');
		expect(ghostSuffix('NIGHT', 'INT. LAB - ')).toBe('NIGHT');
		expect(ghostSuffix('NIGHT', 'INT. LAB - N')).toBe('IGHT');
		expect(ghostSuffix('NIGHT', 'INT. LAB - DAY')).toBe('');
		expect(ghostSuffix('NIGHT', 'INT. LAB -N')).toBe('');
	});

	it('unclosed paren mid-cue completes the extension with its closer', () => {
		expect(ghostSuffix('(V.O.)', 'MARA (V')).toBe('.O.)');
		expect(ghostSuffix('(O.S.)', 'MARA (')).toBe('O.S.)');
	});

	it('returns empty when nothing aligns', () => {
		expect(ghostSuffix('MARA', 'xy')).toBe('');
	});
});

describe('nextWord (partial accept)', () => {
	it('takes the first word with trailing space', () => {
		expect(nextWord('KITCHEN - NIGHT')).toBe('KITCHEN ');
	});

	it('handles leading spaces and single words', () => {
		expect(nextWord(' (V.O.)')).toBe(' (V.O.)');
		expect(nextWord('MARA')).toBe('MARA');
	});
});

describe('ghostTabBehavior (Tab etiquette)', () => {
	it('an empty block means the writer is navigating — Tab jumps the element', () => {
		expect(ghostTabBehavior('')).toBe('jump');
		expect(ghostTabBehavior('   ')).toBe('jump');
	});

	it('committed letters mean Tab completes them', () => {
		expect(ghostTabBehavior('MAR')).toBe('accept');
	});
});
