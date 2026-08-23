#!/usr/bin/env node
/*
 * Engine conformance corpus exporter.
 *
 * Runs the TypeScript engine — the web source of truth — over a curated
 * fixture matrix and writes golden masters to ios/DraftFirstEngine/Fixtures/.
 * The Swift engine must reproduce every expected value exactly. Regenerating
 * after an engine change produces a diff: that diff IS the behaviour change,
 * and it is reviewed like code.
 *
 * Run: npm run engine:conformance
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseFountain, serialiseFountain } from '../packages/draftfirst/dist/index.js';
import { estimateRuntime, paginate, printedLineCount } from '../packages/draftfirst/dist/layout.js';
import {
	ghostSuffix,
	looksLikeCue,
	nextElement,
	normalizeCue,
	normalizeElementText,
	normalizeParenthetical,
	predict,
	tabCycle,
	tabNext,
	tabSetFor,
	unwrapParenthetical
} from '../packages/draftfirst/dist/editor.js';
import { crc32 } from '../packages/draftfirst/dist/crc32.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'ios/DraftFirstEngine/Fixtures');
mkdirSync(outDir, { recursive: true });

const PRINTING_TYPES = [
	'scene', 'action', 'character', 'dialogue', 'parenthetical',
	'transition', 'shot', 'general', 'centered', 'lyrics'
];
const STRUCTURAL_TYPES = ['note', 'section', 'synopsis', 'pagebreak'];
const ALL_TYPES = [...PRINTING_TYPES, ...STRUCTURAL_TYPES];
const PREVS = [null, ...ALL_TYPES];

function writeFixture(name, payload) {
	const file = join(outDir, name);
	writeFileSync(file, JSON.stringify(payload, null, 2) + '\n');
	console.log(`▸ ${name}`);
}

/* ------------------------------------------------------------------ */
/* choreography.json — the keyboard-flow state machine, exhaustively   */
/* ------------------------------------------------------------------ */

const choreography = {
	tabNext: [],
	tabSetFor: [],
	tabCycle: [],
	nextElement: []
};
for (const current of ALL_TYPES) {
	for (const reverse of [false, true]) {
		choreography.tabNext.push({ current, reverse, result: tabNext(current, reverse) });
	}
}
for (const prev of PREVS) {
	choreography.tabSetFor.push({ prev, result: [...tabSetFor(prev)] });
}
for (const current of ALL_TYPES) {
	for (const prev of PREVS) {
		for (const reverse of [false, true]) {
			choreography.tabCycle.push({ current, prev, reverse, result: tabCycle(current, prev, reverse) });
		}
	}
}
for (const current of ALL_TYPES) {
	for (const key of ['enter', 'tab']) {
		for (const text of ['x', '', '   ', ' ']) {
			choreography.nextElement.push({ current, key, text, result: nextElement(current, key, text) });
		}
	}
}
writeFixture('choreography.json', choreography);

/* ------------------------------------------------------------------ */
/* normalize.json — commit-time parenthetical and cue normalization    */
/* ------------------------------------------------------------------ */

const PARENTHETICAL_INPUTS = [
	'beat', '(beat)', '(beat', 'beat)', '()', '(', ')', '  ( beat )  ',
	'((beat))', 'whispering', '(quietly, to the machine', 'to JOHN)'
];
const CUE_INPUTS = [
	'MARA', 'MARA (V.O.)', 'MARA (V.O', 'MARA (WHISPERING', 'MARA (', 'MARA VO',
	'VO', 'CARLOS', "MARA (CONT'D)", "MARA (cont'd)", 'MARA (CONT’D)',
	'MARA O.S.', 'MARA PRELAP', 'MARA (PRE LAP', 'MARA (PRE-LAP)', 'MARA OC',
	'MARA (SUBTITLE', 'MARA (FILTERED)', 'MARA ()', '(V.O.)', 'MARA  (  V.O.  ',
	'mara vo', 'ELIAS ^', 'DR. ELENA VOSS', 'MARA (INTO PHONE'
];
const LOOKS_LIKE_CUE_INPUTS = [
	'MARA', 'Mara', 'mara', '(to JOHN)', "MARA (CONT'D)", 'A', 'AB', '1234',
	'MARA!', '(SHOUTING)', 'DR. ELENA VOSS', '  ELENA  ', 'ON THE RADIO'
];

const normalize = {
	parenthetical: PARENTHETICAL_INPUTS.map((input) => ({ input, result: normalizeParenthetical(input) })),
	unwrapParenthetical: PARENTHETICAL_INPUTS.map((input) => ({ input, result: unwrapParenthetical(input) })),
	cue: CUE_INPUTS.map((input) => ({ input, result: normalizeCue(input) })),
	looksLikeCue: LOOKS_LIKE_CUE_INPUTS.map((input) => ({ input, result: looksLikeCue(input) })),
	elementText: []
};
for (const type of PRINTING_TYPES) {
	for (const input of ['beat', '(beat', "MARA (CONT'D)", 'INT. LAB - DAY', 'Some action.']) {
		normalize.elementText.push({ type, input, result: normalizeElementText(type, input) });
	}
}
writeFixture('normalize.json', normalize);

/* ------------------------------------------------------------------ */
/* crc32.json — ZIP integrity, including the canonical check value     */
/* ------------------------------------------------------------------ */

function hexOf(text) {
	return Buffer.from(text, 'utf8').toString('hex');
}
const crcInputs = [
	'',
	'a',
	'abc',
	'The quick brown fox jumps over the lazy dog',
	'MARA (CONT’D) — unicode ✓'
];
const crc32Fixture = {
	cases: crcInputs.map((text) => ({ hex: hexOf(text), result: crc32(Buffer.from(text, 'utf8')) }))
};
crc32Fixture.cases.push({
	hex: Buffer.from(Array.from({ length: 256 }, (_, i) => i)).toString('hex'),
	result: crc32(Buffer.from(Array.from({ length: 256 }, (_, i) => i)))
});
writeFixture('crc32.json', crc32Fixture);

/* ------------------------------------------------------------------ */
/* Script corpus — parse, serialise, paginate, predict                  */
/* ------------------------------------------------------------------ */

/* The shared sample document, lifted verbatim from the package's own test
   fixture so web tests and iOS conformance share one source. */
const sampleTs = readFileSync(join(root, 'packages/draftfirst/test/fixtures/sample.ts'), 'utf8');
const sampleMatch = sampleTs.match(/SAMPLE_FOUNTAIN = `([\s\S]*?)`;/);
if (!sampleMatch) throw new Error('could not extract SAMPLE_FOUNTAIN from test fixture');
const SAMPLE_FOUNTAIN = sampleMatch[1];

/* The 120-scene feature, byte-identical to the in-engine benchmark builder
   (scripts/ios-bridge-entry.js), so app benchmarks and conformance agree. */
function buildFeature(sceneCount) {
	const parts = ['FADE IN:'];
	for (let i = 1; i <= sceneCount; i++) {
		parts.push('');
		parts.push('INT. LOCATION ' + i + ' - ' + (i % 2 === 0 ? 'NIGHT' : 'DAY'));
		parts.push('');
		parts.push('Action line for scene ' + i + '. Something happens that matters to the story and pushes it forward.');
		parts.push('');
		parts.push('MARA');
		parts.push('(whispering)');
		parts.push('Dialogue for scene ' + i + ', beat one. We have to keep moving before they notice.');
		parts.push('');
		parts.push('DAVID');
		parts.push('Reply in scene ' + i + '. I hear you, and I agree completely.');
		if (i % 4 === 0) {
			parts.push('');
			parts.push('CUT TO:');
		}
	}
	return parts.join('\n');
}

const SCRIPTS = [
	{ name: 'sample', source: SAMPLE_FOUNTAIN },
	{
		name: 'edge-headings',
		source: [
			'INT. LAB - DAY', '', 'EXT. ROOF - NIGHT', '', 'EST. CITY - DAWN', '',
			'INT./EXT. CAR - MOVING - DAY', '', 'I/E. PORCH - DUSK', '',
			'.A FORCED HEADING', '', 'INT. LAB - MORNING', '', 'INT. LAB - AFTERNOON', '',
			'INT. LAB - EVENING', '', 'INT. LAB - SUNRISE', '', 'INT. LAB - SUNSET', '',
			'INT. LAB - MAGIC HOUR', '', 'INT. LAB - MIDNIGHT', '', 'INT. LAB - LATER', '',
			'INT. LAB - CONTINUOUS', '', 'INT. LAB - MOMENTS LATER', '', 'INT. LAB - SAME', '',
			'INT. LAB - SAME TIME', '', 'INT. LAB - THE NEXT DAY', '', 'INT. LAB - DAYS LATER', '',
			'INT. LAB - WEEKS LATER', '', 'INT. LAB - MONTHS LATER', '', 'INT. LAB - YEARS LATER', '',
			'INT. LAB - FLASHBACK', '', 'INT. LAB - PRESENT DAY', '', 'INT. LAB - FUTURE'
		].join('\n')
	},
	{
		name: 'edge-dialogue',
		source: [
			'INT. ROOM - DAY', '', 'MARA', '(whispering)', 'A line.', '',
			'MARA (V.O.)', 'Off-screen.', '', "DAVID (CONT'D)", 'Continued.', '',
			'MARA ^', 'Dual line.', '', 'DAVID ^', 'Dual reply.', ''
		].join('\n')
	},
	{
		name: 'edge-structural',
		source: [
			'# Act One', '', '## Sequence', '', '= A synopsis of the beat.', '',
			'[[A private note]]', '', '/*', 'A boneyard block.', '*/', '',
			'INT. ROOM - DAY', '', 'Some action.', '', '===', '',
			'> THE END <', '', '~Sung like a lyric', ''
		].join('\n')
	},
	{
		name: 'edge-title-page',
		source: [
			'Title: My Script', 'Credit: written by', 'Author: A. Writer',
			'Source: A true story', 'Notes:', '    First note line.', '    Second note line.',
			'Unknown Key: kept as-is', '',
			'INT. ROOM - DAY', '', 'Action.'
		].join('\n')
	},
	{ name: 'empty', source: '' },
	{
		name: 'whitespace-chaos',
		source: ['', '', '   ', 'INT.  LAB   -   DAY', '', '', '\tTabbed action.', '', '', 'MARA', '', 'Hi.', '', '', ''].join('\n')
	},
	/* Torture script — the input shapes real files arrive in, which a clean
	   ASCII/LF/NFC corpus never meets. Every hazard below has taken down (or
	   silently corrupted) an engine port before. Escapes are written out so
	   the hazards stay visible in review and survive editor normalisation:
	     \uFEFF BOM at byte zero; CRLF and lone-CR line endings; a spaced
	     double dash; NFD combining marks in a cue and a location; a curly-
	     apostrophe CONT'D; a ZWJ emoji sequence (several UTF-16 units, one
	     grapheme); U+0085 NEL inside a wrapping action line (JS \s does NOT
	     match it — Unicode White_Space does — so wrap points diverge on
	     sloppy ports); an unclosed boneyard opener (the JS regex needs the
	     closing delimiter to match at all, so the tail stays verbatim). */
	{
		name: 'torture',
		source: (() => {
			const lines = [
				'\uFEFFTitle: Torture Draft',
				'Credit: written by',
				'Author: T. Est',
				'',
				'INT. LAB - - DAY',
				'',
				'The generator hums\u0085\u0085 steadily while MARA recalibrates the \u{1F469}\u200D\u{1F680} console, and the array spools past every rated tolerance tonight.',
				'',
				'CAFE\u0301 OWNER (CONT\u2019D)',
				'(whispering 🎧)',
				'A line of dialogue with an emoji 🔥 and enough words to wrap across two printed lines of the page for good measure.',
				'',
				'EXT. CAFE\u0301 TERRACE - NIGHT',
				'',
				'A lone CR\rinside one logical line.',
				'',
				/* NFD with a LOWERCASE base letter: JS /[a-z]/ scans code units
				   and matches the base `e`, so this is action, not a cue. The
				   CAFÉ cue above cannot discriminate — its base `E` is
				   uppercase, so both engines agree there either way. */
				'RENe\u0301',
				'Where were you?',
				'',
				/* Control: a COMPOSED uppercase accent has no [a-z] match, so
				   this one really is a cue. Guards against "fixing" the
				   detector by disabling it. */
				'REN\u00C9',
				'The control line.',
				'',
				/* ECMAScript /i without /u never folds a non-ASCII code point
				   onto an ASCII one, so U+0131 does NOT open a scene heading.
				   toUpperCase() would map it to I and accept the line. */
				'\u0131nt. house - day',
				'',
				/* `[^#]+` cannot hold a `#`, so this has NO scene number. */
				'INT. HOUSE #1##',
				'',
				/* A blank interior trims to "", which is falsy — the key is
				   absent, and the document stays a round-trip fixed point. */
				'.SCENE #  #',
				'',
				/* `\\s*` backtracks one char so `.+?` can match: capture " ". */
				'>  <',
				'',
				/* A combining mark immediately after a space. JS splits on the
				   space and carries the mark into the next word; a grapheme
				   split sees one cluster, refuses to break, and hard-splits at
				   the column instead — different wrap points. */
				'Sparks arc across ' + 'a'.repeat(50) + ' \u0301' + 'b'.repeat(20) + ' and the lab goes dark.',
				'',
				'/* this boneyard is never closed'
			];
			/* Alternate CRLF and LF separators so both line-ending styles are
			   exercised inside a single document. */
			return lines.reduce((acc, line, i) => acc + (i === 0 ? '' : i % 2 === 1 ? '\r\n' : '\n') + line, '');
		})()
	},
	{ name: 'feature-120', source: buildFeature(120) }
];

const parseFixture = [];
const serialiseFixture = [];
const paginateFixture = [];
const predictFixture = [];

for (const { name, source } of SCRIPTS) {
	const screenplay = parseFountain(source);
	parseFixture.push({ name, source, expected: screenplay });
	serialiseFixture.push({ name, screenplay, expected: serialiseFountain(screenplay) });
	const pages = paginate(screenplay);
	paginateFixture.push({
		name,
		screenplay,
		expected: {
			pages,
			runtime: estimateRuntime(pages),
			printedLines: printedLineCount(pages)
		}
	});
}

/* Prediction contexts against the sample document, the feature, and the
   torture script — the shapes a writer actually meets: a fresh scene, a
   deep document, and hostile real-world text. */
const screenplaysByName = Object.fromEntries(parseFixture.map((f) => [f.name, f.expected]));
const PREDICT_CONTEXTS = [
	{ script: 'sample', type: 'scene', text: 'IN' },
	{ script: 'sample', type: 'scene', text: 'INT. ' },
	{ script: 'sample', type: 'character', text: '' },
	{ script: 'sample', type: 'character', text: 'MA' },
	{ script: 'sample', type: 'character', text: 'MARA (' },
	{ script: 'sample', type: 'transition', text: 'CUT' },
	{ script: 'sample', type: 'transition', text: '' },
	{ script: 'sample', type: 'dialogue', text: '' },
	{ script: 'sample', type: 'action', text: '' },
	{ script: 'feature-120', type: 'character', text: 'MA' },
	{ script: 'feature-120', type: 'character', text: 'DAVID (' },
	/* First-scene contexts: the torture script's location chain includes a
	   spaced double dash and NFD combining marks — the exact states that
	   trapped the Swift port. */
	{ script: 'torture', type: 'scene', text: 'INT. LAB ' },
	{ script: 'torture', type: 'scene', text: 'INT. CAFE\u0301 ' },
	{ script: 'torture', type: 'character', text: 'CAFE\u0301 OWNER (' },
	{ script: 'torture', type: 'character', text: '' }
];
for (const ctx of PREDICT_CONTEXTS) {
	const screenplay = screenplaysByName[ctx.script];
	if (!screenplay) throw new Error(`unknown predict fixture script: ${ctx.script}`);
	const context = { type: ctx.type, text: ctx.text, index: screenplay.elements.length };
	predictFixture.push({
		name: `${ctx.script}:${ctx.type}:${JSON.stringify(ctx.text)}`,
		screenplay,
		context,
		expected: predict(screenplay, context)
	});
}
writeFixture('parse.json', parseFixture);
writeFixture('serialise.json', serialiseFixture);
writeFixture('paginate.json', paginateFixture);
writeFixture('predict.json', predictFixture);

/* ------------------------------------------------------------------ */
/* ghostSuffix.json — the completion math behind every ghost           */
/* ------------------------------------------------------------------ */

const ghostSuffixFixture = [];
const GHOST_CANDIDATES = ['INT.', 'EXT.', 'DAY', 'NIGHT', "CONT'D", 'CUT TO:', 'ELIAS', '(whispering)'];
const GHOST_TEXTS = ['', 'I', 'IN', 'INT', 'DA', 'MARA ', 'ELI'];
for (const candidate of GHOST_CANDIDATES) {
	for (const text of GHOST_TEXTS) {
		for (const hint of [false, true]) {
			ghostSuffixFixture.push({ candidate, text, hint, expected: ghostSuffix(candidate, text, hint) });
		}
	}
}
writeFixture('ghostSuffix.json', ghostSuffixFixture);

console.log('✓ conformance corpus written to ios/DraftFirstEngine/Fixtures/');
