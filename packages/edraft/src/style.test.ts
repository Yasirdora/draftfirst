import { describe, expect, it } from 'vitest';
import {
	escapeFountainContent,
	normaliseRuns,
	parseEmphasis,
	synthesiseEmphasis
} from './style.js';
import type { StyleRun } from './types.js';
import { parseFountain } from './parse.js';
import { elementToFountain, serialiseFountain } from './serialise.js';
import { paginate } from './layout.js';

/* Offsets below are UTF-16 code units (the ContentIndex space), half-open. */

describe('parseEmphasis — the Fountain spec examples', () => {
	it('parses the four basic forms', () => {
		expect(parseEmphasis('*italics*')).toEqual({
			text: 'italics',
			runs: [{ start: 0, end: 7, styles: ['Italic'] }]
		});
		expect(parseEmphasis('**bold**')).toEqual({
			text: 'bold',
			runs: [{ start: 0, end: 4, styles: ['Bold'] }]
		});
		expect(parseEmphasis('***bold italics***')).toEqual({
			text: 'bold italics',
			runs: [{ start: 0, end: 12, styles: ['Bold', 'Italic'] }]
		});
		expect(parseEmphasis('_underline_')).toEqual({
			text: 'underline',
			runs: [{ start: 0, end: 9, styles: ['Underline'] }]
		});
	});

	it('nests italics inside underline (the spec’s scope example)', () => {
		const { text, runs } = parseEmphasis(
			'_Steel’s face FILLS the *Leupold Mark 4* scope_.'
		);
		expect(text).toBe('Steel’s face FILLS the Leupold Mark 4 scope.');
		expect(runs).toEqual([
			{ start: 0, end: 23, styles: ['Underline'] },
			{ start: 23, end: 37, styles: ['Italic', 'Underline'] },
			{ start: 37, end: 43, styles: ['Underline'] }
		]);
	});

	it('parses escaped asterisks inside bold (the spec keypad example)', () => {
		expect(parseEmphasis('**\\*9765\\***')).toEqual({
			text: '*9765*',
			runs: [{ start: 0, end: 6, styles: ['Bold'] }]
		});
	});

	it('honours whitespace flanking: “*69 and then *23” italicises nothing', () => {
		const source = 'He dialed *69 and then *23, and then hung up.';
		expect(parseEmphasis(source)).toEqual({ text: source, runs: [] });
	});

	it('…but “*69 and then 23*” does italicise', () => {
		expect(parseEmphasis('He dialed *69 and then 23*, and then hung up.')).toEqual({
			text: 'He dialed 69 and then 23, and then hung up.',
			runs: [{ start: 10, end: 24, styles: ['Italic'] }]
		});
	});

	it('lets the writer escape the accidental italics', () => {
		expect(parseEmphasis('He dialed *69 and then 23\\*, and then hung up.')).toEqual({
			text: 'He dialed *69 and then 23*, and then hung up.',
			runs: []
		});
	});

	it('treats an unclosed opener as literal text (no cross-line carry)', () => {
		const source = 'As he rattles off the list, Brick and Steel *share a look.';
		expect(parseEmphasis(source)).toEqual({ text: source, runs: [] });
	});
});

describe('parseEmphasis — delimiter-run rules beyond the spec', () => {
	it('treats four or more stars as literal', () => {
		expect(parseEmphasis('****')).toEqual({ text: '****', runs: [] });
	});

	it('treats double underscores as literal (underline never means bold)', () => {
		expect(parseEmphasis('__x__')).toEqual({ text: '__x__', runs: [] });
	});

	it('parses ~~ as strikeout, the format-bar extension', () => {
		expect(parseEmphasis('~~gone~~')).toEqual({
			text: 'gone',
			runs: [{ start: 0, end: 4, styles: ['Strikeout'] }]
		});
	});

	it('treats a single tilde as literal text', () => {
		expect(parseEmphasis('a ~ b')).toEqual({ text: 'a ~ b', runs: [] });
	});

	it('closes-then-opens a mid-line run (Markdown convention)', () => {
		/* *a**b* — the middle run closes “a” then opens “b”; canonical
		   normalisation merges the two adjacent italic runs into one. */
		expect(parseEmphasis('*a**b*')).toEqual({
			text: 'ab',
			runs: [{ start: 0, end: 2, styles: ['Italic'] }]
		});
	});

	it('pins partial consumption of a run: ***a*b**c***', () => {
		/* The trailing *** finds no opener and is literal; the leading ***
		   splits italic over “a”, bold over “ab”. */
		expect(parseEmphasis('***a*b**c***')).toEqual({
			text: 'abc***',
			runs: [
				{ start: 0, end: 1, styles: ['Bold', 'Italic'] },
				{ start: 1, end: 2, styles: ['Bold'] }
			]
		});
	});

	it('matches Markdown on **_** — a bold literal underscore', () => {
		expect(parseEmphasis('**_**')).toEqual({
			text: '_',
			runs: [{ start: 0, end: 1, styles: ['Bold'] }]
		});
	});

	it('allows intraword asterisks, per Markdown', () => {
		expect(parseEmphasis('a*b*c')).toEqual({
			text: 'abc',
			runs: [{ start: 1, end: 2, styles: ['Italic'] }]
		});
	});

	it('parses multiple spans in one line', () => {
		expect(parseEmphasis('*a* and *b*')).toEqual({
			text: 'a and b',
			runs: [
				{ start: 0, end: 1, styles: ['Italic'] },
				{ start: 6, end: 7, styles: ['Italic'] }
			]
		});
	});

	it('nests mixed kinds: **_x_** is bold and underlined', () => {
		expect(parseEmphasis('**_x_**')).toEqual({
			text: 'x',
			runs: [{ start: 0, end: 1, styles: ['Bold', 'Underline'] }]
		});
	});
});

describe('parseEmphasis — coordinate and whitespace edges', () => {
	it('indexes in UTF-16 code units, not graphemes', () => {
		/* 👩‍🚀 is five UTF-16 units; the run must cover all of them. */
		const { text, runs } = parseEmphasis('**the 👩‍🚀 console**');
		expect(text).toBe('the 👩‍🚀 console');
		expect(runs).toEqual([{ start: 0, end: text.length, styles: ['Bold'] }]);
	});

	it('does not treat U+0085 NEL as whitespace (JS \\s semantics)', () => {
		/* NEL stays word-internal: a closer right after it still closes. */
		expect(parseEmphasis('*a\u0085*')).toEqual({
			text: 'a\u0085',
			runs: [{ start: 0, end: 2, styles: ['Italic'] }]
		});
	});

	it('does treat U+FEFF as whitespace (JS \\s semantics)', () => {
		/* BOM to the left of a closer blocks it — everything stays literal. */
		const source = '*a\uFEFF*';
		expect(parseEmphasis(source)).toEqual({ text: source, runs: [] });
	});

	it('keeps a lone or non-punctuation backslash literal', () => {
		expect(parseEmphasis('a\\nb')).toEqual({ text: 'a\\nb', runs: [] });
		expect(parseEmphasis('ends \\')).toEqual({ text: 'ends \\', runs: [] });
	});
});

describe('normaliseRuns — the canonical form', () => {
	it('clamps to the text and drops empty runs', () => {
		expect(
			normaliseRuns(
				[
					{ start: -3, end: 2, styles: ['Bold'] },
					{ start: 5, end: 5, styles: ['Italic'] },
					{ start: 8, end: 99, styles: ['Underline'] }
				],
				10
			)
		).toEqual([
			{ start: 0, end: 2, styles: ['Bold'] },
			{ start: 8, end: 10, styles: ['Underline'] }
		]);
	});

	it('splits overlaps into union segments', () => {
		expect(
			normaliseRuns(
				[
					{ start: 0, end: 4, styles: ['Bold'] },
					{ start: 2, end: 6, styles: ['Italic'] }
				],
				10
			)
		).toEqual([
			{ start: 0, end: 2, styles: ['Bold'] },
			{ start: 2, end: 4, styles: ['Bold', 'Italic'] },
			{ start: 4, end: 6, styles: ['Italic'] }
		]);
	});

	it('merges adjacent runs only when every property is equal', () => {
		expect(
			normaliseRuns(
				[
					{ start: 0, end: 2, styles: ['Bold'], revisionID: 1 },
					{ start: 2, end: 4, styles: ['Bold'], revisionID: 1 }
				],
				10
			)
		).toEqual([{ start: 0, end: 4, styles: ['Bold'], revisionID: 1 }]);

		expect(
			normaliseRuns(
				[
					{ start: 0, end: 2, styles: ['Bold'], revisionID: 1 },
					{ start: 2, end: 4, styles: ['Bold'], revisionID: 2 }
				],
				10
			)
		).toEqual([
			{ start: 0, end: 2, styles: ['Bold'], revisionID: 1 },
			{ start: 2, end: 4, styles: ['Bold'], revisionID: 2 }
		]);
	});

	it('unions tagNumbers and lets the earliest run own a revision conflict', () => {
		expect(
			normaliseRuns(
				[
					{ start: 0, end: 4, styles: [], tagNumbers: [3, 1], revisionID: 7 },
					{ start: 2, end: 6, styles: [], tagNumbers: [2], revisionID: 9 }
				],
				10
			)
		).toEqual([
			{ start: 0, end: 2, styles: [], revisionID: 7, tagNumbers: [1, 3] },
			{ start: 2, end: 4, styles: [], revisionID: 7, tagNumbers: [1, 2, 3] },
			{ start: 4, end: 6, styles: [], revisionID: 9, tagNumbers: [2] }
		]);
	});

	it('drops runs carrying no information at all', () => {
		expect(normaliseRuns([{ start: 0, end: 4, styles: [] }], 10)).toEqual([]);
	});
});

describe('synthesiseEmphasis — canonical marker emission', () => {
	it('escapes literal markers and backslashes in plain content', () => {
		expect(escapeFountainContent('2 * 3 or 4_5 \\ 6')).toBe('2 \\* 3 or 4\\_5 \\\\ 6');
		expect(escapeFountainContent('a ~~ b')).toBe('a \\~\\~ b');
		expect(escapeFountainContent('a ~ b')).toBe('a ~ b');
	});

	it('emits the canonical marker for each style combination', () => {
		const wrap = (styles: StyleRun['styles']) =>
			synthesiseEmphasis('x', [{ start: 0, end: 1, styles }]);
		expect(wrap(['Bold'])).toBe('**x**');
		expect(wrap(['Italic'])).toBe('*x*');
		expect(wrap(['Bold', 'Italic'])).toBe('***x***');
		expect(wrap(['Underline'])).toBe('_x_');
		expect(wrap(['Strikeout'])).toBe('~~x~~');
		expect(wrap(['Bold', 'Underline'])).toBe('**_x_**');
		expect(wrap(['Bold', 'Underline', 'Strikeout'])).toBe('**_~~x~~_**');
	});

	it('has no Fountain spelling for AllCaps or HiddenText — recorded loss', () => {
		expect(synthesiseEmphasis('abc', [{ start: 0, end: 3, styles: ['AllCaps'] }])).toBe('abc');
	});

	it('escapes inside styled segments', () => {
		expect(synthesiseEmphasis('a*b', [{ start: 0, end: 3, styles: ['Bold'] }])).toBe('**a\\*b**');
	});

	it('merges adjacent equal runs into one pair', () => {
		expect(
			synthesiseEmphasis('abcd', [
				{ start: 0, end: 2, styles: ['Bold'] },
				{ start: 2, end: 4, styles: ['Bold'] }
			])
		).toBe('**abcd**');
	});

	it('keeps revision and tag properties out of Fountain source', () => {
		expect(
			synthesiseEmphasis('ab', [{ start: 0, end: 2, styles: ['Bold'], revisionID: 3, tagNumbers: [1] }])
		).toBe('**ab**');
	});
});

describe('the fixed point', () => {
	const cases: [string, StyleRun[]][] = [
		['plain text', []],
		['bold words', [{ start: 0, end: 4, styles: ['Bold'] }]],
		[
			' Steel FILLS the Leupold scope ',
			[
				{ start: 1, end: 12, styles: ['Underline'] },
				{ start: 17, end: 24, styles: ['Italic', 'Underline'] }
			]
		],
		['literal * stars _ here', []],
		['a*b', [{ start: 0, end: 3, styles: ['Bold'] }]],
		['x', [{ start: 0, end: 1, styles: ['Bold', 'Italic', 'Underline', 'Strikeout'] }]],
		['two  spans', [{ start: 0, end: 3, styles: ['Italic'] }, { start: 5, end: 10, styles: ['Bold'] }]]
	];

	it('parseEmphasis ∘ synthesiseEmphasis is the identity', () => {
		for (const [text, runs] of cases) {
			const round = parseEmphasis(synthesiseEmphasis(text, runs));
			expect(round).toEqual({ text, runs: normaliseRuns(runs, text.length) });
		}
	});

	it('synthesise ∘ parse ∘ synthesise is byte-stable', () => {
		const sources = [
			'*italics*',
			'**bold** and _under_ with ~~strike~~',
			'_Steel FILLS the *Leupold* scope_',
			'He dialed *69 and then *23, hung up.',
			'**\\*9765\\***'
		];
		for (const source of sources) {
			const first = parseEmphasis(source);
			const once = synthesiseEmphasis(first.text, first.runs);
			const second = parseEmphasis(once);
			const twice = synthesiseEmphasis(second.text, second.runs);
			expect(twice).toBe(once);
		}
	});

	it('reproduces the spec example’s natural spelling exactly', () => {
		/* Minimal markers are canonical: the shared underline never closes. */
		const source = '_Steel FILLS the *Leupold* scope_';
		const { text, runs } = parseEmphasis(source);
		expect(synthesiseEmphasis(text, runs)).toBe(source);
	});

	it('tightens marker coverage past boundary whitespace (Fountain cannot flank it)', () => {
		expect(synthesiseEmphasis(' bold ', [{ start: 0, end: 5, styles: ['Bold'] }])).toBe(
			' **bold** '
		);
		/* …and the model-level fixed point is defined on tightened runs. */
		expect(parseEmphasis(' **bold** ')).toEqual({
			text: ' bold ',
			runs: [{ start: 1, end: 5, styles: ['Bold'] }]
		});
	});
});

describe('engine integration (option-gated)', () => {
	it('defaults to preserving markers, untouched', () => {
		const script = parseFountain('INT. LAB - DAY\n\nA **quiet** room.');
		expect(script.elements[1]).toEqual({ type: 'action', text: 'A **quiet** room.' });
	});

	it('parses emphasis into runs when asked', () => {
		const script = parseFountain('INT. LAB - DAY\n\nA **quiet** room.\n\nMARA\n_Yes._', {
			emphasis: 'runs'
		});
		expect(script.elements[1]).toEqual({
			type: 'action',
			text: 'A quiet room.',
			runs: [{ start: 2, end: 7, styles: ['Bold'] }]
		});
		expect(script.elements[3]).toEqual({
			type: 'dialogue',
			text: 'Yes.',
			runs: [{ start: 0, end: 4, styles: ['Underline'] }]
		});
	});

	it('uppercases scene headings before runs are indexed', () => {
		const script = parseFountain('int. *lab* - day #7#', { emphasis: 'runs' });
		expect(script.elements[0]).toEqual({
			type: 'scene',
			text: 'INT. LAB - DAY',
			sceneNumber: '7',
			runs: [{ start: 5, end: 8, styles: ['Italic'] }]
		});
	});

	it('serialises runs back to markers, per element type', () => {
		expect(
			elementToFountain({
				type: 'character',
				text: 'MARA',
				runs: [{ start: 0, end: 4, styles: ['Bold'] }]
			})
		).toBe('**MARA**');
		expect(
			elementToFountain({
				type: 'centered',
				text: 'THE END',
				runs: [{ start: 4, end: 7, styles: ['Italic'] }]
			})
		).toBe('> THE *END* <');
	});

	it('round-trips a styled script through Fountain unchanged', () => {
		const source = 'INT. LAB - DAY\n\nA **quiet** _room_, ~~really~~.\n\nMARA\n*Yes.*';
		const once = serialiseFountain(parseFountain(source, { emphasis: 'runs' }));
		const twice = serialiseFountain(parseFountain(once, { emphasis: 'runs' }));
		expect(twice).toBe(once);
	});

	it('paginates a styled script exactly like its plain twin', () => {
		const styled = parseFountain('INT. LAB - DAY\n\nA **quiet** _room_ for the ages.\n\nMARA\n*Yes.*', {
			emphasis: 'runs'
		});
		const plain = parseFountain('INT. LAB - DAY\n\nA quiet room for the ages.\n\nMARA\nYes.');
		expect(paginate(styled)).toEqual(paginate(plain));
	});
});
