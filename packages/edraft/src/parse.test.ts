/** Fountain parsing, serialization, classification, and round-trip behavior. */
import { describe, expect, it } from 'vitest';
import {
	FountainParseError,
	parseFountain,
	SCENE_DETECT,
	TRANSITION_DETECT
} from './parse.js';
import { serialiseFountain } from './serialise.js';
import { SAMPLE_FOUNTAIN, SAMPLE_TITLE_KEYS } from '../test/fixtures/sample.js';
import type { Screenplay } from './types.js';

const types = (s: Screenplay) => s.elements.map((e) => e.type);

describe('Fountain input boundary', () => {
	it('rejects source beyond the configured resource limit', () => {
		expect(() => parseFountain('1234', { maxSourceCharacters: 3 })).toThrow(FountainParseError);
	});

	it('rejects malformed resource-limit options', () => {
		expect(() => parseFountain('', { maxSourceCharacters: Number.NaN })).toThrow(RangeError);
	});
});

describe('line classifiers · shared with the page surface', () => {
	/* Public classifiers must use the same vocabulary as the parser. */
	it('SCENE_DETECT judges prefixes and partial slugs', () => {
		expect(SCENE_DETECT.test('INT.')).toBe(true);
		expect(SCENE_DETECT.test('EXT. ROOFTOP - DAWN')).toBe(true);
		expect(SCENE_DETECT.test('int./ext. car - moving')).toBe(true);
		expect(SCENE_DETECT.test('In the distance')).toBe(false);
		expect(SCENE_DETECT.test('INTERESTING')).toBe(false);
	});

	it('TRANSITION_DETECT judges trimmed uppercase lines', () => {
		expect(TRANSITION_DETECT.test('CUT TO:')).toBe(true);
		expect(TRANSITION_DETECT.test('SMASH CUT TO:')).toBe(true);
		expect(TRANSITION_DETECT.test('FADE OUT.')).toBe(false);
		expect(TRANSITION_DETECT.test('cut to:')).toBe(false);
	});
});

describe('parseFountain · title page', () => {
	it('reads keyed entries and stops at the first blank line', () => {
		const s = parseFountain(SAMPLE_FOUNTAIN);
		expect(s.titlePage.map((e) => e.key)).toEqual(SAMPLE_TITLE_KEYS);
		expect(s.titlePage[0].values).toEqual(['The Empty Cinema']);
		expect(s.titlePage[2].values).toEqual(['A. Projectionist']);
	});

	it('supports multi-line values via indented continuation', () => {
		const s = parseFountain('Title: The Long\n   Winding Title\n\nINT. A - DAY\n');
		expect(s.titlePage[0].values).toEqual(['The Long', 'Winding Title']);
	});

	it('accepts custom title-page keys emitted by the serializer', () => {
		const s = parseFountain('Project Code: DRAFT-FIRST-7\nTitle: Custom metadata\n\n');
		expect(s.titlePage).toEqual([
			{ key: 'Project Code', values: ['DRAFT-FIRST-7'] },
			{ key: 'Title', values: ['Custom metadata'] }
		]);
	});

	it('ignores a document with no title page', () => {
		const s = parseFountain('INT. KITCHEN - DAY\n\nAction.\n');
		expect(s.titlePage).toEqual([]);
	});

	it('never eats a FADE IN: opener as a title-page key', () => {
		const s = parseFountain('FADE IN:\n\nINT. KITCHEN - DAY\n\nAction.\n');
		expect(s.titlePage).toEqual([]);
		expect(s.elements[0]).toEqual({ type: 'transition', text: 'FADE IN:' });
	});

	it('treats a single unknown key line as body text, not metadata', () => {
		const s = parseFountain('FLASHBACK:\n\nINT. KITCHEN - DAY\n');
		expect(s.titlePage).toEqual([]);
	});

	it('still opens a title page on a single known key', () => {
		const s = parseFountain('Title: Only This\n\nINT. KITCHEN - DAY\n');
		expect(s.titlePage).toEqual([{ key: 'Title', values: ['Only This'] }]);
	});
});

describe('parseFountain · scene headings', () => {
	it('detects INT./EXT. and uppercases', () => {
		const s = parseFountain('int. kitchen - day\n\next. rooftop - night\n');
		expect(types(s)).toEqual(['scene', 'scene']);
		expect(s.elements[0].text).toBe('INT. KITCHEN - DAY');
		expect(s.elements[1].text).toBe('EXT. ROOFTOP - NIGHT');
	});

	it('detects EST, INT./EXT and I/E variants', () => {
		expect(types(parseFountain('EST. CITY - DAWN\n'))).toEqual(['scene']);
		expect(types(parseFountain('INT./EXT. CAR - MOVING - DAY\n'))).toEqual(['scene']);
		expect(types(parseFountain('I/E. PHONE BOOTH - NIGHT\n'))).toEqual(['scene']);
	});

	it('forces a scene heading with a leading dot', () => {
		const s = parseFountain(".MOLLY'S DINER - LATER\n");
		expect(s.elements[0]).toMatchObject({ type: 'scene', text: "MOLLY'S DINER - LATER" });
	});

	it('does not mistake an ellipsis for a forced scene heading', () => {
		const s = parseFountain('...where the road disappears.\n');
		expect(s.elements[0]).toEqual({ type: 'action', text: '...where the road disappears.' });
	});

	it('requires blank-line context for an unforced scene heading', () => {
		const s = parseFountain('Action runs into\nINT. WORDS THAT ARE ACTION\nwithout a break.\n');
		expect(types(s)).toEqual(['action', 'action', 'action']);
	});

	it('extracts a trailing scene number #7#', () => {
		const s = parseFountain('INT. LAB - DAY #7#\n');
		expect(s.elements[0]).toMatchObject({ type: 'scene', sceneNumber: '7' });
		expect(s.elements[0].text).toBe('INT. LAB - DAY');
	});
});

describe('parseFountain · dialogue flow', () => {
	it('groups character, parenthetical and dialogue', () => {
		const s = parseFountain('MOLLY\n(beat)\nWe need to talk.\n');
		expect(types(s)).toEqual(['character', 'parenthetical', 'dialogue']);
		expect(s.elements[0].text).toBe('MOLLY');
	});

	it('keeps cue extensions like (V.O.) and (O.S.)', () => {
		const s = parseFountain('MOLLY (V.O.)\nI was never there.\n');
		expect(s.elements[0].text).toBe('MOLLY (V.O.)');
	});

	it('marks dual dialogue with a caret', () => {
		const s = parseFountain('MOLLY ^\nTogether.\n');
		expect(s.elements[0]).toMatchObject({ type: 'character', dual: true, text: 'MOLLY' });
	});

	it('forces mixed-case names with @', () => {
		const s = parseFountain('@McCready\nAye.\n');
		expect(s.elements[0]).toMatchObject({ type: 'character', text: 'McCready' });
	});

	it('treats an ALL-CAPS line with no follower as action', () => {
		const s = parseFountain('MOLLY\n');
		expect(s.elements[0].type).toBe('action');
	});

	it('treats an ALL-CAPS line followed by a blank line as action', () => {
		const s = parseFountain('THE END?\n\nMore action.\n');
		expect(s.elements[0].type).toBe('action');
	});

	it('requires a blank line before an unforced character cue', () => {
		const s = parseFountain('Action continues.\nMOLLY\nThis is still action.\n');
		expect(types(s)).toEqual(['action', 'action', 'action']);
	});

	it('keeps a shot-like name as a character when dialogue follows', () => {
		const s = parseFountain('POV\nI have a perfectly valid name.\n');
		expect(s.elements).toEqual([
			{ type: 'character', text: 'POV' },
			{ type: 'dialogue', text: 'I have a perfectly valid name.' }
		]);
	});

	it('preserves an intentional blank line inside dialogue', () => {
		const source = 'MOLLY\nFirst thought.\n  \nSecond thought.\n';
		const once = parseFountain(source);
		expect(once.elements).toEqual([
			{ type: 'character', text: 'MOLLY' },
			{ type: 'dialogue', text: 'First thought.' },
			{ type: 'dialogue', text: '' },
			{ type: 'dialogue', text: 'Second thought.' }
		]);
		expect(parseFountain(serialiseFountain(once)).elements).toEqual(once.elements);
	});

	it('accepts an intentional blank as the first line of dialogue', () => {
		const s = parseFountain('MOLLY\n  \nEventually, I answer.\n');
		expect(s.elements).toEqual([
			{ type: 'character', text: 'MOLLY' },
			{ type: 'dialogue', text: '' },
			{ type: 'dialogue', text: 'Eventually, I answer.' }
		]);
	});

	it('does not create an orphan cue before an explicitly forced block', () => {
		const s = parseFountain('MOLLY\n.NEW SCENE\n');
		expect(s.elements).toEqual([
			{ type: 'action', text: 'MOLLY' },
			{ type: 'scene', text: 'NEW SCENE' }
		]);
	});
});

describe('parseFountain · transitions, centered, lyrics', () => {
	it('detects ALL-CAPS lines ending in TO:', () => {
		expect(types(parseFountain('CUT TO:\n'))).toEqual(['transition']);
		expect(types(parseFountain('DISSOLVE TO:\n'))).toEqual(['transition']);
	});

	it('requires blank-line context for an unforced transition', () => {
		const s = parseFountain('Action continues.\nCUT TO:\nwithout a break.\n');
		expect(types(s)).toEqual(['action', 'action', 'action']);
	});

	it('forces transitions with >', () => {
		const s = parseFountain('> SMASH CUT TO BLACK.\n');
		expect(s.elements[0]).toMatchObject({ type: 'transition', text: 'SMASH CUT TO BLACK.' });
	});

	it('parses > centered < lines', () => {
		const s = parseFountain('> THE END <\n');
		expect(s.elements[0]).toMatchObject({ type: 'centered', text: 'THE END' });
	});

	it('parses ~ lyrics', () => {
		const s = parseFountain('~Happy birthday to you\n');
		expect(s.elements[0]).toMatchObject({ type: 'lyrics', text: 'Happy birthday to you' });
	});
});

describe('parseFountain · structural + misc', () => {
	it('parses sections with depth and synopses', () => {
		const s = parseFountain('# Act One\n\n## Sequence\n\n= Elias threads the reel.\n');
		expect(s.elements[0]).toMatchObject({ type: 'section', depth: 1, text: 'Act One' });
		expect(s.elements[1]).toMatchObject({ type: 'section', depth: 2, text: 'Sequence' });
		expect(s.elements[2]).toMatchObject({ type: 'synopsis', text: 'Elias threads the reel.' });
	});

	it('parses === as a page break', () => {
		expect(types(parseFountain('===\n'))).toEqual(['pagebreak']);
	});

	it('captures standalone [[notes]]', () => {
		const s = parseFountain('[[rewrite this beat]]\n\nAction.\n');
		expect(s.elements[0]).toMatchObject({ type: 'note', text: 'rewrite this beat' });
	});

	it('preserves an unmatched note opener instead of swallowing the screenplay', () => {
		const s = parseFountain(
			'Action before [[unfinished note\nstill visible\n\nINT. ROOM - DAY\n\nAction after.\n'
		);
		expect(s.elements.map((element) => element.text)).toEqual([
			'Action before [[unfinished note',
			'still visible',
			'INT. ROOM - DAY',
			'Action after.'
		]);
		expect(types(s)).toEqual(['action', 'action', 'scene', 'action']);
	});

	it('does not match a note closer beyond a paragraph break', () => {
		const s = parseFountain('Keep [[this literal\n\nAnd this]] visible.\n');
		expect(s.elements.map((element) => element.text)).toEqual([
			'Keep [[this literal',
			'And this]] visible.'
		]);
		expect(s.elements.every((element) => element.type === 'action')).toBe(true);
	});

	it('still supports a closed multi-line note within one paragraph', () => {
		const s = parseFountain('Before [[first line\nsecond line]] after.\n');
		expect(s.elements.find((element) => element.type === 'note')?.text).toBe(
			'first line\nsecond line'
		);
	});

	it('lifts inline [[notes]] out of surrounding text', () => {
		const s = parseFountain('A line with [[fix later]] text.\n');
		const action = s.elements.find((e) => e.type === 'action');
		const note = s.elements.find((e) => e.type === 'note');
		expect(action?.text).not.toContain('[[');
		expect(note?.text).toBe('fix later');
	});

	it('omits boneyard /* … */ content entirely', () => {
		const s = parseFountain('Keep this.\n\n/* cut this\nand this */\n\nAnd this.\n');
		const texts = s.elements.map((e) => e.text).join(' ');
		expect(texts).toContain('Keep this.');
		expect(texts).toContain('And this.');
		expect(texts).not.toContain('cut this');
	});

	it('forces action with ! even for scene-like lines', () => {
		const s = parseFountain('!INT. NOT A SCENE\n');
		expect(s.elements[0]).toMatchObject({ type: 'action', text: 'INT. NOT A SCENE' });
	});

	it('retains Action indentation and normalizes tabs to four spaces', () => {
		const s = parseFountain('    Indented card line.\n\tTabbed card line.\n');
		expect(s.elements.map((element) => element.text)).toEqual([
			'    Indented card line.',
			'    Tabbed card line.'
		]);
		expect(parseFountain(serialiseFountain(s)).elements).toEqual(s.elements);
	});
});

describe('round-trip · parse → serialise → parse', () => {
	it('is model-stable for the sample document', () => {
		const once = parseFountain(SAMPLE_FOUNTAIN);
		const twice = parseFountain(serialiseFountain(once));
		expect(twice.elements).toEqual(once.elements);
		expect(twice.titlePage).toEqual(once.titlePage);
	});

	it('is model-stable across every core element type', () => {
		const src = [
			'# Act One',
			'',
			'= Setup',
			'',
			'INT. LAB - DAY #2#',
			'',
			'Machines hum.',
			'',
			'.A STRANGE PLACE - LATER',
			'',
			'@McCready',
			'(softly)',
			'Aye.',
			'More words.',
			'',
			'~la la la',
			'',
			'CUT TO:',
			'',
			'> TIME CUT TO:',
			'',
			'> THE END <',
			'',
			'[[a note]]',
			'',
			'==='
		].join('\n');
		const once = parseFountain(src);
		const twice = parseFountain(serialiseFountain(once));
		expect(twice.elements).toEqual(once.elements);
	});

	it('forces risky action lines so they survive reparse', () => {
		const once = parseFountain('INT. REAL SCENE - DAY\n\n!INT. JUST TEXT\n');
		const twice = parseFountain(serialiseFountain(once));
		expect(twice.elements).toEqual(once.elements);
	});

	it('shots come home: isolated known shot language parses back to the shot element', () => {
		const s = parseFountain('INT. LAB - DAY\n\nANGLE ON THE SAFE\n\nINSERT - THE KEY\n\nESTABLISHING SHOT\n');
		expect(s.elements[1]).toEqual({ type: 'shot', text: 'ANGLE ON THE SAFE' });
		expect(s.elements[2]).toEqual({ type: 'shot', text: 'INSERT - THE KEY' });
		expect(s.elements[3]).toEqual({ type: 'shot', text: 'ESTABLISHING SHOT' });
	});

	it('a shot block round-trips as a shot — the .draft fidelity promise', () => {
		const once = parseFountain('INT. LAB - DAY\n\nMachines hum.\n');
		once.elements.push({ type: 'shot', text: 'ANGLE ON THE CENTRIFUGE' });
		const twice = parseFountain(serialiseFountain(once));
		expect(twice.elements).toEqual(once.elements);
	});

	it('shouted action is never hijacked as a shot', () => {
		const s = parseFountain('INT. LAB - DAY\n\n!THE ROOM SPINS\n');
		expect(s.elements[1]).toEqual({ type: 'action', text: 'THE ROOM SPINS' });
		const t = parseFountain('INT. LAB - DAY\n\nAngle on the safe, slowly.\n');
		expect(t.elements[1].type).toBe('action');
	});

	it('honors forced Action even when its text resembles a known shot', () => {
		const model: Screenplay = {
			titlePage: [],
			elements: [{ type: 'action', text: 'POV' }]
		};
		const fountain = serialiseFountain(model);
		expect(fountain).toBe('!POV');
		expect(parseFountain(fountain).elements).toEqual(model.elements);
	});

	it('forces shot-like and classifier-like character names on serialization', () => {
		const model: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'character', text: 'POV' },
				{ type: 'dialogue', text: 'I see it.' },
				{ type: 'character', text: 'CUT TO:' },
				{ type: 'dialogue', text: 'That is my name.' }
			]
		};
		const fountain = serialiseFountain(model);
		expect(fountain).toContain('@POV');
		expect(fountain).toContain('@CUT TO:');
		expect(parseFountain(fountain).elements).toEqual(model.elements);
	});

	it('escapes a forced transition ending in < so it cannot become centered', () => {
		const model: Screenplay = {
			titlePage: [],
			elements: [{ type: 'transition', text: 'WIPE TO <' }]
		};
		const fountain = serialiseFountain(model);
		expect(fountain).toContain('WIPE TO \\<');
		expect(parseFountain(fountain).elements).toEqual(model.elements);
	});

	it('round-trips a forced transition beginning with <', () => {
		const model: Screenplay = {
			titlePage: [],
			elements: [{ type: 'transition', text: '<MATCH CUT' }]
		};
		expect(parseFountain(serialiseFountain(model)).elements).toEqual(model.elements);
	});
});
