/** Fountain parsing, serialization, classification, and round-trip behavior. */
import { describe, expect, it } from 'vitest';
import {
	FountainParseError,
	parseFountain,
	SCENE_DETECT,
	TRANSITION_DETECT
} from './parse.js';
import { serialiseFountain } from './serialise.js';
import { deriveTitlePage, titlePageValues } from './titlepage.js';
import { SAMPLE_FOUNTAIN, SAMPLE_TITLE_KEYS } from '../test/fixtures/sample.js';
import type { Screenplay, ScreenplayElement } from './types.js';

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
		/* The keyed fields land as template lines (RFC-TITLE-PAGE D8); the
		   derivation gives them back by name — the title in the uppercase
		   the page always rendered. */
		const entries = deriveTitlePage(s.titlePage);
		expect(entries.map((e) => e.key)).toEqual(SAMPLE_TITLE_KEYS);
		expect(entries[0].values).toEqual(['THE EMPTY CINEMA']);
		expect(entries[2].values).toEqual(['A. Projectionist']);
	});

	it('supports multi-line values via indented continuation', () => {
		const s = parseFountain('Title: The Long\n   Winding Title\n\nINT. A - DAY\n');
		expect(titlePageValues(s.titlePage, 'Title')).toEqual(['THE LONG', 'WINDING TITLE']);
	});

	it('accepts custom title-page keys emitted by the serializer', () => {
		const s = parseFountain('Project Code: EDRAFT-7\nTitle: Custom metadata\n\n');
		/* The template normalises order — the stack first, extras after —
		   and the printed label line is never read back as a value. */
		expect(deriveTitlePage(s.titlePage)).toEqual([
			{ key: 'Title', values: ['CUSTOM METADATA'] },
			{ key: 'Project Code', values: ['EDRAFT-7'] }
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
		expect(deriveTitlePage(s.titlePage)).toEqual([{ key: 'Title', values: ['ONLY THIS'] }]);
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

describe('notes that end in ] or hold ]] (IL-0038)', () => {
	/* The writer used to write "[[" + text + "]]": a note ending in `]` went to
	   disk as `]]]`, the reader closed at the first `]]`, and the next open
	   cut the note short and printed a stray `]` into the script. */
	const around = (note: string) => `INT. KITCHEN - NIGHT\n\n${note}\n\nThe kettle screams.\n`;
	const scene = (text: string): Screenplay => ({
		titlePage: [],
		elements: [
			{ type: 'scene', text: 'INT. KITCHEN - NIGHT' },
			{ type: 'note', text },
			{ type: 'action', text: 'The kettle screams.' }
		]
	});
	const written = (text: string) => serialiseFountain({ titlePage: [], elements: [{ type: 'note', text }] });

	it('reads a note the old writer ended in `]]]` whole, and prints nothing', () => {
		expect(parseFountain(around('[[Dana: see [scene 4]]]')).elements).toEqual(scene('Dana: see [scene 4]').elements);
	});

	it('reads a header-only note whole', () => {
		expect(parseFountain(around('[[[eDraft thread:t4k9qz status:open]]]')).elements).toEqual(
			scene('[eDraft thread:t4k9qz status:open]').elements
		);
	});

	it('closes a note at the end of a run of `]`: the rest are its text', () => {
		expect(parseFountain(around('[[x]]]]')).elements).toEqual(scene('x]]').elements);
	});

	it('reads an inline note ending in `]` whole, leaving the line without a stray `]`', () => {
		const s = parseFountain('Mara waits [[see [4]]] by the door.\n');
		expect(s.elements.map((e) => [e.type, e.text])).toEqual([
			['note', 'see [4]'],
			['action', 'Mara waits  by the door.']
		]);
	});

	it.each([
		['ending in ]', 'Dana: see [scene 4]'],
		['a header alone', '[eDraft thread:t4k9qz status:open]'],
		['ending in ]]', 'x]]'],
		['only ]', ']'],
		[']] inside', 'see [[4]] later'],
		[']]] inside', 'a]]]b'],
		['over two lines, the last ending in ]', 'Dana (Director): one\nSam (Writer): see [4]']
	])('a note %s survives save and reopen', (_, text) => {
		expect(parseFountain(serialiseFountain(scene(text))).elements).toEqual(scene(text).elements);
	});

	it.each(['Dana: see [scene 4]', '[eDraft thread:t4k9qz status:open]', 'x]]', ']', 'see [[4]] later', 'a]]]b'])(
		'the only `]]` the writer writes in a note is its close, so an older reader reads it whole: %s',
		(text) => {
			const note = written(text);
			expect(note.startsWith('[[')).toBe(true);
			expect(note.indexOf(']]', 2)).toBe(note.length - 2);
		}
	);

	it('writes a note with no `]` at its end and no `]]` inside exactly as before', () => {
		for (const text of ['rewrite this beat', 'a [bracket] inside', 'Dir: [beat]. Then go.']) {
			expect(written(text)).toBe(`[[${text}]]`);
		}
	});

	it('the chosen asymmetry (RFC §13): a note typed `a] ]b` returns as `a]]b`', () => {
		expect(written('a] ]b')).toBe('[[a] ]b]]');
		expect(parseFountain(around(written('a] ]b'))).elements).toEqual(scene('a]]b').elements);
	});
});

describe('asides inside a dialogue block (IL-0040)', () => {
	/* The editor puts a note in front of the line it is about. Inside a
	   dialogue block, the serialiser wrote it as its own paragraph between
	   blank lines, which ended the block: on the next open the cue and the
	   speech read as Action. */
	const HEADING: ScreenplayElement = { type: 'scene', text: 'INT. KITCHEN - NIGHT' };
	const reopened = (elements: ScreenplayElement[]) =>
		parseFountain(serialiseFountain({ titlePage: [], elements: [HEADING, ...elements] }), { emphasis: 'runs' }).elements.slice(1);
	const cue = (text: string, dual?: boolean): ScreenplayElement => (dual ? { type: 'character', text, dual } : { type: 'character', text });
	const speech = (text: string): ScreenplayElement => ({ type: 'dialogue', text });
	const paren = (text: string): ScreenplayElement => ({ type: 'parenthetical', text });
	const note = (text: string): ScreenplayElement => ({ type: 'note', text });

	it.each<[string, ScreenplayElement[]]>([
		['between the cue and the speech', [cue('BOB'), note('n1'), speech('Hello.')]],
		['two of them there', [cue('BOB'), note('n1'), note('n2'), speech('Hello.')]],
		['before a parenthetical', [cue('BOB'), note('n1'), paren('(beat)'), speech('Hello.')]],
		['after a parenthetical', [cue('BOB'), paren('(beat)'), note('n1'), speech('Hello.')]],
		['in the middle of a speech', [cue('BOB'), speech('Hello.'), note('n1'), paren('(beat)'), speech('Again.')]],
		['between two lines of one speech', [cue('BOB'), speech('Line one'), note('n1'), speech('Line two')]],
		['inside a dual second speech', [cue('BOB'), speech('Hi.'), cue('ANN', true), note('n1'), speech('Ho.')]],
		['ending in ] (IL-0038)', [cue('BOB'), note('see [scene 4]'), speech('Hello.')]]
	])('a one-line note %s stays exactly where it was', (_, elements) => {
		expect(reopened(elements)).toEqual(elements);
	});

	it('a note before an emphasised speech keeps the emphasis', () => {
		const elements: ScreenplayElement[] = [
			cue('BOB'),
			note('n1'),
			{ type: 'dialogue', text: 'Hello there.', runs: [{ start: 0, end: 5, styles: ['Bold'] }] }
		];
		expect(reopened(elements)).toEqual(elements);
	});

	it.each<[string, ScreenplayElement]>([
		['a note of two lines', note('first\nsecond')],
		['a synopsis', { type: 'synopsis', text: 'The kettle wins.' }],
		['a section', { type: 'section', text: 'Beat', depth: 3 }]
	])('%s inside a block moves in front of the cue, and the block survives', (_, aside) => {
		expect(reopened([cue('BOB'), paren('(beat)'), aside, speech('Hello.')])).toEqual([
			aside,
			cue('BOB'),
			paren('(beat)'),
			speech('Hello.')
		]);
	});

	it('a run holding anything that cannot go inline moves whole, in order', () => {
		const synopsis: ScreenplayElement = { type: 'synopsis', text: 'The kettle wins.' };
		expect(reopened([cue('BOB'), note('n1'), synopsis, note('n2'), speech('Hello.')])).toEqual([
			note('n1'),
			synopsis,
			note('n2'),
			cue('BOB'),
			speech('Hello.')
		]);
	});

	it('writes a one-line note inside a block inline on the line after it', () => {
		expect(serialiseFountain({ titlePage: [], elements: [cue('BOB'), note('n1'), note('n2'), speech('Hello.')] })).toBe(
			'BOB\nHello. [[n1]] [[n2]]'
		);
	});

	it('writes a note before a dual second speaker as before, and the pair survives', () => {
		const elements = [cue('BOB'), speech('Hi.'), note('n1'), cue('ANN', true), speech('Ho.')];
		expect(serialiseFountain({ titlePage: [], elements })).toBe('BOB\nHi.\n\n[[n1]]\n\nANN ^\nHo.');
		expect(reopened(elements)).toEqual(elements);
	});

	it('writes an aside outside a dialogue block exactly as before', () => {
		const elements: ScreenplayElement[] = [
			note('before the cue'),
			cue('BOB'),
			speech('Hello.'),
			note('after the block'),
			{ type: 'action', text: 'The kettle screams.' }
		];
		expect(serialiseFountain({ titlePage: [], elements })).toBe(
			'[[before the cue]]\n\nBOB\nHello.\n\n[[after the block]]\n\nThe kettle screams.'
		);
		expect(reopened(elements)).toEqual(elements);
	});
});

describe('act breaks at the Fountain boundary (RFC-ACT-BREAK §3)', () => {
	it('serialises an act break as the centred card', () => {
		expect(
			serialiseFountain({ titlePage: [], elements: [{ type: 'actbreak', text: 'ACT TWO' }] })
		).toContain('> ACT TWO <');
	});

	it('parses an act card back as the act break it was', () => {
		for (const card of ['ACT TWO', 'ACT 12', 'TEASER', 'COLD OPEN']) {
			expect(parseFountain(`> ${card} <`).elements[0]).toMatchObject({ type: 'actbreak', text: card });
		}
		expect(parseFountain('>ACT TWO<').elements[0]).toMatchObject({ type: 'actbreak', text: 'ACT TWO' });
	});

	it('round-trips an act card through Fountain unchanged', () => {
		const script = { titlePage: [], elements: [{ type: 'actbreak' as const, text: 'ACT ONE' }] };
		expect(parseFountain(serialiseFountain(script)).elements).toMatchObject([{ type: 'actbreak', text: 'ACT ONE' }]);
	});

	it('keeps any other centred text centred — a custom card flattens, ink survives', () => {
		for (const text of ['ACT TWO: THE TURN', 'act one', 'END OF ACT ONE', 'THE END']) {
			expect(parseFountain(`> ${text} <`).elements[0]).toMatchObject({ type: 'centered', text });
		}
	});
});
