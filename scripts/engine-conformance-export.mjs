#!/usr/bin/env node
/*
 * Engine conformance corpus exporter.
 *
 * Runs the TypeScript engine — the web source of truth — over a curated
 * fixture matrix and writes golden masters to apple/eDraftEngine/Fixtures/.
 * The Swift engine must reproduce every expected value exactly. Regenerating
 * after an engine change produces a diff: that diff IS the behaviour change,
 * and it is reviewed like code.
 *
 * Run: npm run engine:conformance
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseFountain, serialiseFountain } from '../packages/edraft/dist/index.js';
import {
	actOrdinal,
	isActCard,
	isCanonicalActCard,
	isEndActCard,
	parseNumberedSceneHeading,
	renumberActs
} from '../packages/edraft/dist/index.js';
import {
	liveCollapse,
	parseEmphasis,
	propagateRuns,
	styleCovered,
	synthesiseEmphasis,
	toggleStyle
} from '../packages/edraft/dist/style.js';
import { openFdx, parseFdx, writeFdxWithDiagnostics } from '../packages/edraft/dist/fdx.js';
import { estimateRuntime, paginate, printedLineCount } from '../packages/edraft/dist/layout.js';
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
} from '../packages/edraft/dist/editor.js';
import { crc32 } from '../packages/edraft/dist/crc32.js';
import { canonicalCasing } from '../packages/edraft/dist/normalize.js';
import {
	canonicalJson,
	detectDraftFormat,
	draftAnchorContext,
	draftFromScreenplay,
	draftToScreenplay,
	jcs,
	parseDraftJson,
	readDraft,
	writeDraft
} from '../packages/edraft/dist/draft.js';
import { sha256Hex } from '../packages/edraft/dist/sha256.js';
import { readZipEntries } from '../packages/edraft/dist/zip.js';
import { writeZipStored } from '../packages/edraft/dist/zipwrite.js';
import { deflateRawSync } from 'node:zlib';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'apple/eDraftEngine/Fixtures');
mkdirSync(outDir, { recursive: true });

const PRINTING_TYPES = [
	'scene', 'action', 'character', 'dialogue', 'parenthetical',
	'transition', 'shot', 'general', 'centered', 'lyrics', 'actbreak'
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
/* acts.json — the act derivation: ordinals, the canonical spelling,   */
/* and the renumber rule (RFC-ACT-BREAK §4)                            */
/* ------------------------------------------------------------------ */

const actbreak = (text) => ({ type: 'actbreak', text });

const acts = {
	ordinals: [1, 2, 4, 10, 20, 21, 22, 113].map((n) => ({ n, result: actOrdinal(n) })),
	canonical: [
		'ACT ONE', 'ACT TWENTY', 'ACT 21', 'ACT 3', 'TEASER', 'COLD OPEN',
		'ACT TWO: THE TURN', 'Act One', 'ACT TWENTYONE', 'ACT ONE ', 'ACT  ONE',
		'ACT', '', 'END OF ACT ONE'
	].map((text) => ({ text, result: isCanonicalActCard(text) })),
	/* the paste route's two vocabularies (RFC-ACT-BREAK §5): what opens an
	   act, and the closing card the import drops */
	actCards: [
		'ACT ONE', 'ACT TWENTY', 'ACT 21', 'TEASER', 'COLD OPEN',
		'ACT TWO: THE TURN', 'Act One', 'teaser', 'cold open', 'ACT ONE ',
		'ACT', 'END OF ACT ONE', 'END TEASER', ''
	].map((text) => ({ text, result: isActCard(text) })),
	endCards: [
		'END OF ACT ONE', 'END ACT ONE', 'END OF ACT 21', 'END TEASER',
		'END OF ACT TWO: THE TURN', 'END OF ACT ONE ',
		/* the corpus's near-misses — Emilia Pérez's music cues, a plural,
		   a glued suffix, a lowercase spelling, a doubled space */
		'END OF 4M26 MI CAMINO', 'END 1M4 EL ENCUENTRO', 'END 3M19 POR CASUALIDAD',
		'END OF ACTS', 'END ACTA', 'END PILOT.', 'end of act one', 'END  TEASER',
		'END COLD OPEN', ''
	].map((text) => ({ text, result: isEndActCard(text) })),
	renumber: [
		/* already sequential — the empty edit */
		[actbreak('ACT ONE'), actbreak('ACT TWO'), actbreak('ACT THREE')],
		/* the gap a deleted act leaves closes */
		[actbreak('ACT ONE'), actbreak('ACT THREE'), actbreak('ACT FOUR')],
		/* a customised card is never rewritten, but its act still counts */
		[actbreak('ACT ONE'), actbreak('TEASER'), actbreak('ACT TWO')],
		/* a mid-script insert renumbers what follows it */
		[actbreak('ACT ONE'), actbreak('ACT TWO'), actbreak('ACT TWO'), actbreak('ACT THREE')],
		/* digit spellings are canonical too and follow the same rule */
		[actbreak('ACT 1'), actbreak('ACT 2'), actbreak('ACT 5')],
		/* everything that is not an act break is not the rule's business */
		[
			{ type: 'scene', text: 'INT. ROOM - DAY' },
			{ type: 'action', text: 'ACT ONE is said aloud, not printed.' },
			actbreak('ACT SEVEN'),
			{ type: 'action', text: 'After the card.' },
			actbreak('ACT TWO')
		],
		/* words run out at twenty; the count does not */
		Array.from({ length: 22 }, () => actbreak('ACT ONE'))
	].map((elements) => ({
		input: elements,
		result: renumberActs(elements).map((e) => e.text)
	}))
};
writeFixture('acts.json', acts);

/* ------------------------------------------------------------------ */
/* sceneheading.json — the numbered scene heading grammar (routing     */
/* pack, step 1): the flanked production number, the leading number,   */
/* and the OMITTED card — every witness the corpus carries              */
/* ------------------------------------------------------------------ */

const sceneheadings = {
	cases: [
		'15 INT. HOLE.',
		'23 EXT. SIGNAL HILL - THAT MOMENT.',
		'24 INT. BANKSIDE HOME - NIGHT.',
		'2 EXT. NORTH CARTHAGE- MORNING 2',
		'3 EXT. NICK DUNNE’S FRONT YARD- DAWN 3*',
		'4 EXT. BAR PARKING LOT- DAY 4*',
		'2 INT. APARTMENT 4',
		'113 OMITTED.',
		'115 OMITTED',
		'116 OMITTED',
		'OMITTED',
		'OMIT',
		'OMIT.',
		'43 OMIT',
		'139 OMIT- INT. DUNNE BEDROOM- NIGHT 139*',
		'50 OMIT- INT. CAR- DAY 50*',
		'139 OMIT- THE WHOLE BEDROOM SCENE',
		'128A EXT./INT. P~~BW MANSION - DUSK. 128A*',
		'120A INT. SAME. DAWN. 120A',
		'12A INT. APARTMENT - DAY',
		'EXT. ROOF - NIGHT',
		'INT. APARTMENT 4',
		'17.',
		'ACT ONE',
		'WALTER',
		'OMITTED FROM THE DRAFT, HE SAID',
		''
	].map((text) => ({ text, result: parseNumberedSceneHeading(text) ?? null }))
};
writeFixture('sceneheading.json', sceneheadings);


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
const sampleTs = readFileSync(join(root, 'packages/edraft/test/fixtures/sample.ts'), 'utf8');
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

/* Notes that end in `]` or hold `]]` (IL-0038), in the spelling the writer
   used before the fix, the one it uses now, and by hand. Parse and serialise
   only: a note never reaches a page. */
{
	const name = 'note-brackets';
	const source = [
		'INT. KITCHEN - NIGHT',
		'',
		'[[Dana (Director): see [scene 4]]]',
		'',
		'[[[eDraft thread:t4k9qz status:open]]]',
		'',
		'[[Sam (Writer): see [scene 4] ]]',
		'',
		'[[x]]]]',
		'',
		'[[]]]',
		'',
		'[[see [[4] ] later]]',
		'',
		'[[a] ] ]b]]',
		'',
		'Mara waits [[see [4]]] by the door.',
		'',
		'[[Dana (Director): one',
		'Sam (Writer): see [4]]]',
		'',
		'[[a [bracket] inside]]',
		'',
		'The kettle screams.',
		''
	].join('\n');
	const screenplay = parseFountain(source);
	parseFixture.push({ name, source, expected: screenplay });
	serialiseFixture.push({ name, screenplay, expected: serialiseFountain(screenplay) });
}

/* Notes inside a dialogue block (IL-0040), in the inline spelling the
   serialiser now writes: a note on the line after it, never a paragraph of
   its own between a cue and its speech. Parse and serialise only. */
{
	const name = 'asides-in-dialogue';
	const source = [
		'INT. KITCHEN - NIGHT',
		'',
		'BOB',
		'Hello. [[n1]] [[n2]]',
		'',
		'ANN',
		'(beat) [[n3]]',
		'Hi.',
		'Line two [[see [scene 4] ]]',
		'',
		'CARL',
		'Hi.',
		'',
		'DANA ^',
		'Ho. [[n4]]',
		'',
		'[[after the block]]',
		'',
		'The kettle screams.',
		''
	].join('\n');
	const screenplay = parseFountain(source);
	parseFixture.push({ name, source, expected: screenplay });
	serialiseFixture.push({ name, screenplay, expected: serialiseFountain(screenplay) });
}

/* Styled pagination must be identical to the plain twin — the paginator
   measures content, and Courier's fixed advance means style never changes
   geometry. The expected values are computed from the PLAIN twin so the
   corpus itself carries the assertion. */
{
	const styled = parseFountain(
		'INT. LAB - DAY\n\nA **quiet** _room_ for the ages, ~~really~~.\n\nMARA\n*Yes.* She **meant** it.',
		{ emphasis: 'runs' }
	);
	const plainTwin = parseFountain(
		'INT. LAB - DAY\n\nA quiet room for the ages, really.\n\nMARA\nYes. She meant it.'
	);
	const twinPages = paginate(plainTwin);
	paginateFixture.push({
		name: 'styled-equals-plain',
		screenplay: styled,
		expected: {
			pages: twinPages,
			runtime: estimateRuntime(twinPages),
			printedLines: printedLineCount(twinPages)
		}
	});
}

/* Act breaks (RFC-ACT-BREAK): the card opens a fresh page, centred at its
   top; a document opening on ACT ONE gets no blank first page; a writer's
   pagebreak beside the card collapses into one break. The model elements are
   literal — Fountain's own spelling for the card parses as centered, the
   named degradation, so no Fountain source can build this document. */
{
	const withActs = {
		titlePage: [],
		elements: [
			{ type: 'action', text: 'The teaser plays out.' },
			{ type: 'actbreak', text: 'ACT ONE' },
			{ type: 'scene', text: 'INT. WHITE HOUSE - NIGHT' },
			{ type: 'action', text: 'No president ever slept here.' },
			{ type: 'pagebreak', text: '' },
			{ type: 'actbreak', text: 'ACT TWO' },
			{ type: 'action', text: 'The middle.' }
		]
	};
	const actPages = paginate(withActs);
	paginateFixture.push({
		name: 'act-breaks',
		screenplay: withActs,
		expected: {
			pages: actPages,
			runtime: estimateRuntime(actPages),
			printedLines: printedLineCount(actPages)
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
/* emphasis.json / emphasis-synthesise.json — runs-in-model (RFC v2.1) */
/* ------------------------------------------------------------------ */

/* Parse: the Fountain spec's Emphasis section verbatim (flanking, escapes,
   nesting), plus the engine's pinned rules beyond the spec — delimiter-run
   lengths, the ~~ strikeout extension, UTF-16 coordinates, JS \s flanking. */
const EMPHASIS_PARSE_INPUTS = [
	'*italics*',
	'**bold**',
	'***bold italics***',
	'_underline_',
	'~~strikeout~~',
	'_Steel’s face FILLS the *Leupold Mark 4* scope_.',
	'**\\*9765\\***',
	'He dialed *69 and then *23, and then hung up.',
	'He dialed *69 and then 23*, and then hung up.',
	'He dialed *69 and then 23\\*, and then hung up.',
	'As he rattles off the list, Brick and Steel *share a look.',
	'****',
	'__x__',
	'a ~ b',
	'*a**b*',
	'***a*b**c***',
	'**_**',
	'a*b*c',
	'*a* and *b*',
	'**_x_**',
	'**the \u{1F469}\u200D\u{1F680} console**',
	'*a\u0085*',
	'*a\uFEFF*',
	'a\\nb',
	'ends \\',
	'_**BRICK & STEEL**_',
	'A *little* **strongly** ~~struck~~ _**nested**_ mix.',
	' bold ',
	'* spaced * opener',
	'closers *spaced * too'
];
writeFixture(
	'emphasis.json',
	EMPHASIS_PARSE_INPUTS.map((input) => ({ input, expected: parseEmphasis(input) }))
);

/* Synthesise: canonical emission, escapes, merging, whitespace tightening,
   the Fountain-less styles (AllCaps/HiddenText) dropping, and the recorded
   loss for crossing (non-laminar) coverage. roundTrip entries pin the full
   parse → synthesise → parse path, including the fixed point. */
const EMPHASIS_SYNTH_CASES = [
	{ text: 'plain text', runs: [] },
	{ text: 'bold words', runs: [{ start: 0, end: 4, styles: ['Bold'] }] },
	{
		text: 'x',
		runs: [{ start: 0, end: 1, styles: ['Bold', 'Italic', 'Underline', 'Strikeout'] }]
	},
	{ text: 'abc', runs: [{ start: 0, end: 3, styles: ['AllCaps'] }] },
	{ text: 'abc', runs: [{ start: 0, end: 3, styles: ['HiddenText'] }] },
	{ text: 'a*b', runs: [{ start: 0, end: 3, styles: ['Bold'] }] },
	{
		text: 'abcd',
		runs: [
			{ start: 0, end: 2, styles: ['Bold'] },
			{ start: 2, end: 4, styles: ['Bold'] }
		]
	},
	{ text: ' bold ', runs: [{ start: 0, end: 5, styles: ['Bold'] }] },
	{ text: '  ', runs: [{ start: 0, end: 2, styles: ['Bold'] }] },
	{ text: '2 * 3 or 4_5 \\ 6', runs: [] },
	{ text: 'a ~~ b', runs: [] },
	{
		text: 'two  spans',
		runs: [
			{ start: 0, end: 3, styles: ['Italic'] },
			{ start: 5, end: 10, styles: ['Bold'] }
		]
	},
	{
		text: 'Steel FILLS the Leupold scope',
		runs: [
			{ start: 0, end: 16, styles: ['Underline'] },
			{ start: 16, end: 23, styles: ['Italic', 'Underline'] },
			{ start: 23, end: 29, styles: ['Underline'] }
		]
	},
	{
		text: 'ab',
		runs: [{ start: 0, end: 2, styles: ['Bold'], revisionID: 3, tagNumbers: [1] }]
	},
	/* Crossing (non-laminar) coverage cannot be expressed with properly
	   nested markers: the emitter degrades deterministically instead of
	   corrupting — the expected string pins exactly what is lost. */
	{
		text: 'abcdef',
		runs: [
			{ start: 0, end: 4, styles: ['Bold'] },
			{ start: 2, end: 6, styles: ['Italic'] }
		]
	}
];
writeFixture(
	'emphasis-synthesise.json',
	EMPHASIS_SYNTH_CASES.map(({ text, runs }) => ({
		input: { text, runs },
		expected: synthesiseEmphasis(text, runs)
	}))
);

/* Round-trip gates: foreign/natural spellings in, canonical runs out, and
   back. `synthesised` is the canonical re-emission; `fixedPoint` is the
   second pass — for a clean canonical spelling it equals `synthesised`. */
const EMPHASIS_ROUND_TRIP_SOURCES = [
	'*italics*',
	'**bold** and _under_ with ~~strike~~',
	'_Steel FILLS the *Leupold* scope_',
	'He dialed *69 and then *23, hung up.',
	'**\\*9765\\***',
	'_**BRICK & STEEL**_'
];
const roundTripFixture = EMPHASIS_ROUND_TRIP_SOURCES.map((source) => {
	const first = parseEmphasis(source);
	const synthesised = synthesiseEmphasis(first.text, first.runs);
	const second = parseEmphasis(synthesised);
	return {
		source,
		expected: { text: first.text, runs: first.runs, synthesised, fixedPoint: second }
	};
});
writeFixture('emphasis-roundtrip.json', roundTripFixture);

/* ------------------------------------------------------------------ */
/* style-edits.json — runs under editing (RFC v2.1 §4, Phase A)         */
/* ------------------------------------------------------------------ */

/* propagateRuns: the donor rule (preceding character; following at content
   position 0), trailing-edge extension, deletion shrink, donor heal across
   a replaced selection. `textLength` is the PRE-edit length; the expected
   runs index the post-edit text. */
const PROPAGATE_CASES = [
	{
		name: 'shift-after-untouched-before',
		runs: [
			{ start: 0, end: 2, styles: ['Bold'] },
			{ start: 6, end: 8, styles: ['Bold'] }
		],
		replace: { start: 3, end: 3 },
		insert: 1,
		textLength: 8
	},
	{
		name: 'interior-insertion-extends',
		runs: [{ start: 1, end: 5, styles: ['Bold'] }],
		replace: { start: 3, end: 3 },
		insert: 2,
		textLength: 6
	},
	{
		name: 'trailing-edge-extends',
		runs: [{ start: 0, end: 4, styles: ['Bold'] }],
		replace: { start: 4, end: 4 },
		insert: 1,
		textLength: 4
	},
	{
		name: 'leading-edge-does-not-extend',
		runs: [{ start: 2, end: 6, styles: ['Bold'] }],
		replace: { start: 2, end: 2 },
		insert: 1,
		textLength: 6
	},
	{
		name: 'position-zero-inherits-following',
		runs: [{ start: 0, end: 4, styles: ['Bold'] }],
		replace: { start: 0, end: 0 },
		insert: 2,
		textLength: 4
	},
	{
		name: 'between-runs-inherits-preceding',
		runs: [
			{ start: 0, end: 2, styles: ['Bold'] },
			{ start: 2, end: 4, styles: ['Italic'] }
		],
		replace: { start: 2, end: 2 },
		insert: 1,
		textLength: 4
	},
	{
		name: 'deletion-shrinks',
		runs: [{ start: 0, end: 5, styles: ['Bold'] }],
		replace: { start: 1, end: 4 },
		insert: 0,
		textLength: 5
	},
	{
		name: 'deletion-drops-fully-covered',
		runs: [{ start: 1, end: 4, styles: ['Bold'] }],
		replace: { start: 1, end: 4 },
		insert: 0,
		textLength: 5
	},
	{
		name: 'replacement-heals-from-donor',
		runs: [{ start: 0, end: 5, styles: ['Bold'] }],
		replace: { start: 2, end: 4 },
		insert: 3,
		textLength: 5
	},
	{
		name: 'insert-carries-revision-and-tags',
		runs: [{ start: 0, end: 4, styles: ['Bold'], revisionID: 2, tagNumbers: [7] }],
		replace: { start: 4, end: 4 },
		insert: 1,
		textLength: 4
	},
	{
		name: 'whole-text-replacement-styles-nothing',
		runs: [{ start: 0, end: 4, styles: ['Bold'] }],
		replace: { start: 0, end: 4 },
		insert: 3,
		textLength: 4
	}
];

/* toggleStyle: the coverage rule (fully covered → off, otherwise on),
   union on add, split on remove, revision-carrying runs surviving a style
   removal, and merge-back. */
const TOGGLE_CASES = [
	{
		name: 'add-unions-with-styled-middle',
		runs: [{ start: 2, end: 4, styles: ['Italic'] }],
		start: 0,
		end: 6,
		style: 'Bold',
		textLength: 6
	},
	{
		name: 'remove-splits-at-edges',
		runs: [{ start: 0, end: 6, styles: ['Bold'] }],
		start: 2,
		end: 4,
		style: 'Bold',
		textLength: 6
	},
	{
		name: 'remove-keeps-revision-carrying-run',
		runs: [{ start: 0, end: 4, styles: ['Bold'], revisionID: 9 }],
		start: 0,
		end: 4,
		style: 'Bold',
		textLength: 4
	},
	{
		name: 'remove-merges-identical-neighbours',
		runs: [
			{ start: 0, end: 2, styles: ['Bold'] },
			{ start: 2, end: 4, styles: ['Bold', 'Italic'] },
			{ start: 4, end: 6, styles: ['Bold'] }
		],
		start: 2,
		end: 4,
		style: 'Italic',
		textLength: 6
	},
	{
		name: 'covered-requires-every-offset',
		runs: [{ start: 0, end: 4, styles: ['Bold'] }],
		start: 0,
		end: 5,
		style: 'Bold',
		textLength: 5
	}
];

/* liveCollapse: collapse on the closing delimiter, every spelling, the
   sole-consumer restriction, the whole-delimiter rule (a half-consumed `**`
   waits — typing `**word**` must end bold, not italic), undisturbed
   leftovers, and the null cases (nothing closes / typed char not the
   consumed closer). */
const COLLAPSE_CASES = [
	{ name: 'bold', text: '**world**', at: 8 },
	{ name: 'italic', text: '*x*', at: 2 },
	{ name: 'bold-italic', text: '***x***', at: 6 },
	{ name: 'underline', text: '_x_', at: 2 },
	{ name: 'strikeout-second-tilde', text: '~~x~~', at: 4 },
	{ name: 'nothing-to-close', text: 'a *b', at: 2 },
	{ name: 'flanked-out', text: '2 * 3', at: 2 },
	{ name: 'closer-without-opener', text: 'x*', at: 1 },
	{ name: 'lone-tilde-literal', text: 'y ~', at: 2 },
	{ name: 'typed-char-beyond-consumed', text: '*a**', at: 3 },
	{ name: 'delimiter-soup-refused', text: '*a**b*', at: 5 },
	{ name: 'literal-middle-refused', text: '**a*', at: 3 },
	{ name: 'double-star-waits-for-its-closer', text: '**world*', at: 7 },
	{ name: 'unclosed-leftover-undisturbed', text: '*keep **this**', at: 13 },
	{ name: 'empty-pair-never-collapses', text: '****', at: 3 }
];

writeFixture('style-edits.json', {
	propagate: PROPAGATE_CASES.map(({ name, runs, replace, insert, textLength }) => ({
		name,
		runs,
		replace,
		insert,
		textLength,
		expected: propagateRuns(
			runs,
			replace,
			insert,
			textLength - (replace.end - replace.start) + insert
		)
	})),
	toggle: TOGGLE_CASES.map(({ name, runs, start, end, style, textLength }) => ({
		name,
		runs,
		start,
		end,
		style,
		textLength,
		covered: styleCovered(runs, start, end, style),
		expected: toggleStyle(runs, start, end, style, textLength)
	})),
	collapse: COLLAPSE_CASES.map(({ name, text, at }) => ({
		name,
		text,
		at,
		expected: liveCollapse(text, at)
	}))
});


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

/* ------------------------------------------------------------------ */
/* fdx.json — Final Draft interchange: bounded import, lossy-aware     */
/* export, and the diagnostics both sides must reproduce exactly       */
/* ------------------------------------------------------------------ */

/* The canonical foreign file from the engine's own FDX tests: entity-
   encoded text, a scene number, a centered-via-alignment paragraph, a
   self-closing SceneProperties run, and a positional title page. */
const FOREIGN_FDX = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft DocumentType="Script" Version="3">
  <Content>
    <Paragraph Type="Scene Heading" Number="1">
      <SceneProperties Length="2/8" Page="1"/>
      <Text>INT. FISH &amp; CHIP SHOP - DAY</Text>
    </Paragraph>
    <Paragraph Type="Action"><Text>A &quot;quiet&quot; room &lt;somehow&gt;.</Text></Paragraph>
    <Paragraph Type="Character"><Text>MOLLY (V.O.)</Text></Paragraph>
    <Paragraph Type="Parenthetical"><Text>(beat)</Text></Paragraph>
    <Paragraph Type="Dialogue"><Text>We&apos;re closed.</Text></Paragraph>
    <Paragraph Type="Dialogue"><Text>Come back tomorrow.</Text></Paragraph>
    <Paragraph Type="Transition"><Text>CUT TO:</Text></Paragraph>
    <Paragraph Alignment="Center" Type="General"><Text>THE END</Text></Paragraph>
  </Content>
  <TitlePage>
    <Content>
      <Paragraph Alignment="Center" Type="General"><Text>Chips</Text></Paragraph>
      <Paragraph Alignment="Center" Type="General"><Text>written by</Text></Paragraph>
      <Paragraph Alignment="Center" Type="General"><Text>A. Writer</Text></Paragraph>
    </Content>
  </TitlePage>
</FinalDraft>`;

/* The writer's notes as ScriptNotes (IL-0039, IL-0042): everything new each
   time — a note's RefId, paragraph ids, date — is pinned, so both engines
   write the same bytes. */
const NOTE_WRITING = {
	writer: 'Dana Reyes (Director)',
	now: '20260918T120000',
	ids: Array.from({ length: 24 }, (_, index) => `00000000-0000-4000-8000-${(index + 1).toString(16).padStart(12, '0')}`)
};
function noteWriting(spec) {
	let id = 0;
	return {
		...(spec.writer ? { writer: spec.writer } : {}),
		now: spec.now,
		newId: () => spec.ids[id++]
	};
}

const fdxImport = [];
const fdxExport = [];
function addFdxImport(name, source, options = {}) {
	const result = parseFdx(source, options);
	fdxImport.push({ name, source, options, expected: { script: result.script, diagnostics: result.diagnostics } });
}
function addFdxExport(name, screenplay) {
	const notes = screenplay.elements.some((element) => element.type === 'note') ? NOTE_WRITING : undefined;
	const result = writeFdxWithDiagnostics(screenplay, notes ? { notes: noteWriting(notes) } : {});
	fdxExport.push({ name, screenplay, ...(notes ? { notes } : {}), expected: { xml: result.xml, diagnostics: result.diagnostics } });
}

/* Real-world and adversarial imports. Each malformed shape pins the exact
   diagnostic the TypeScript reader emits for it. */
addFdxImport('foreign', FOREIGN_FDX);
addFdxImport(
	'title-first',
	`<FinalDraft><TitlePage><Content><Paragraph Type="General"><Text>A TITLE</Text></Paragraph></Content></TitlePage><Content><Paragraph Type="Scene Heading"><Text>INT. LAB - DAY</Text></Paragraph><Paragraph Type="Action"><Text>Hum.</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport(
	'single-quoted-attrs',
	`<FinalDraft><Content><Paragraph DataType="Action" Type = 'Scene Heading' Number = 'A>7'><Text>INT. LAB - DAY</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport(
	'comments-cdata',
	`<FinalDraft><Content><!-- <Paragraph Type="Action">bad</Paragraph> --><Paragraph Type="Action"><Text><![CDATA[A < B & C]]></Text></Paragraph></Content></FinalDraft>`
);
addFdxImport(
	'unknown-type',
	`<FinalDraft><Content><Paragraph Type="Cast List"><Text>MOLLY</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport('no-root', `<Content><Paragraph Type="Action"><Text>x</Text></Paragraph></Content>`);
addFdxImport('not-xml', 'not xml at all');
addFdxImport('empty', '');
addFdxImport('unterminated-comment', `<FinalDraft><Content><!-- never closed`);
addFdxImport('unterminated-cdata', `<FinalDraft><Content><Paragraph Type="Action"><Text><![CDATA[rest of file`);
addFdxImport('unterminated-pi', `<?xml version="1.0"`);
addFdxImport(
	'doctype-ignored',
	`<!DOCTYPE FinalDraft SYSTEM "fdx.dtd"><FinalDraft><Content><Paragraph Type="Action"><Text>x</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport('unterminated-declaration', `<!DOCTYPE FinalDraft [ <!ENTITY x "y">`);
addFdxImport('unterminated-tag', `<FinalDraft><Content><Paragraph Type="Action"`);
addFdxImport(
	'unquoted-attribute',
	`<FinalDraft><Content><Paragraph Type=Action><Text>x</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport(
	'malformed-attribute',
	`<FinalDraft><Content><Paragraph Type="Action" Broken><Text>x</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport(
	'nested-paragraph',
	`<FinalDraft><Content><Paragraph Type="Action"><Paragraph Type="Character"><Text>MARA</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport('unterminated-paragraph', `<FinalDraft><Content><Paragraph Type="Action"><Text>open`);
addFdxImport(
	'dual-and-number',
	`<FinalDraft><Content><Paragraph Type="Character" Dual="Yes"><Text>MARA</Text></Paragraph><Paragraph Type="Action" Number="9"><Text>Number on action is ignored.</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport(
	'edraft-markers',
	`<FinalDraft><Content><Paragraph Type="General" EDraft:ElementType="lyrics"><Text>La la</Text></Paragraph><Paragraph Type="General" Alignment="Center"><Text>THE END</Text></Paragraph></Content></FinalDraft>`
);
/* Files exported by the keyed model carry TitleEntry indices beside the
   keys. The line model keeps the key as the line's annotation and ignores
   the index — there is nothing left to conflict. */
addFdxImport(
	'legacy-keyed-title-page',
	`<FinalDraft><Content/><TitlePage><Content><Paragraph Type="General" EDraft:TitleKey="Title" EDraft:TitleEntry="0"><Text>A</Text></Paragraph><Paragraph Type="General" EDraft:TitleKey="Author" EDraft:TitleEntry="0"><Text>B</Text></Paragraph></Content></TitlePage></FinalDraft>`
);
/* Real Final Draft title pages run long — title, credit, multiple writers,
   source, copyright, address. Eight positional paragraphs exceed the five
   fallback keys, the exact shape that trapped the Swift port's
   out-of-bounds subscript (JavaScript's undefined ?? 'Contact'). */
addFdxImport(
	'long-title-page',
	`<FinalDraft><Content><Paragraph Type="Action"><Text>x</Text></Paragraph></Content><TitlePage><Content>${[
		'THE BIG SCRIPT', 'written by', 'First Writer', 'Second Writer',
		'Based on a true story', 'Copyright 2026', '123 Writer Lane', 'Hollywood, CA 90028'
	].map((t) => `<Paragraph Alignment="Center" Type="General"><Text>${t}</Text></Paragraph>`).join('')}</Content></TitlePage></FinalDraft>`
);
addFdxImport(
	'numeric-entities',
	`<FinalDraft><Content><Paragraph Type="Action"><Text>&#65;&#x42; &#x110000; &#55296;</Text></Paragraph></Content></FinalDraft>`
);
/* Final Draft's Note element: a line in the script that does not print,
   which is what Fountain's [[ ]] is. The <ParagraphSpec Type="Note"> in
   <ElementSettings> is the *style* for that element, not an instance of it,
   and reading it as one would put the stylesheet on the page. */
addFdxImport(
	'note',
	`<FinalDraft><ElementSettings Type="Note"><ParagraphSpec Type="Note"/></ElementSettings><Content><Paragraph Type="Scene Heading"><Text>INT. LAB - DAY</Text></Paragraph><Paragraph Type="Note" id="n1"><Text>Is this the same lab as scene 4?</Text></Paragraph><Paragraph Type="Action"><Text>Hum.</Text></Paragraph></Content></FinalDraft>`
);
/* Final Draft's outline: `Outline 1..N` are the writer's act, sequence and
   scene structure, and `Summary` is the prose under one. Read as General they
   printed on the page and paginated — four pages of outline counted as script
   on one of the two real features. The levels can be renamed, so the number
   rules and the name in brackets is ignored. */
addFdxImport(
	'outline',
	`<FinalDraft><Content><Paragraph Type="Outline 1"><Text>Act One</Text></Paragraph><Paragraph Type="Outline 2 (Sequences)"><Text>Meet Tangle</Text></Paragraph><Paragraph Type="Outline 3"><Text>Set up Gold Key</Text></Paragraph><Paragraph Type="Summary"><Text>Tangle questions Uncle.</Text></Paragraph><Paragraph Alignment="Center" Type="End of Act"><Text>The end</Text></Paragraph></Content></FinalDraft>`
);
/* Act breaks (RFC-ACT-BREAK §3): New Act imports as the actbreak element,
   End of Act is absorbed — a fact the model derives, never stores. */
addFdxImport(
	'act-breaks',
	`<FinalDraft><Content><Paragraph Type="Action"><Text>The teaser plays out.</Text></Paragraph><Paragraph Type="End of Act" Alignment="Center"><Text>END OF TEASER</Text></Paragraph><Paragraph Type="New Act" Alignment="Center"><Text>ACT ONE</Text></Paragraph><Paragraph Type="Action"><Text>No president ever slept here.</Text></Paragraph></Content></FinalDraft>`
);
addFdxImport('limits-source', `<FinalDraft><Content/></FinalDraft>`, { maxSourceCharacters: 10 });
addFdxImport(
	'limits-warnings',
	`<FinalDraft><Content>${Array.from({ length: 8 }, (_, i) => `<Paragraph Type="Unknown ${i}"><Text>x</Text></Paragraph>`).join('')}</Content></FinalDraft>`,
	{ maxWarnings: 2 }
);
addFdxImport(
	'limits-paragraphs',
	`<FinalDraft><Content><Paragraph Type="Action"><Text>a</Text></Paragraph><Paragraph Type="Action"><Text>b</Text></Paragraph></Content></FinalDraft>`,
	{ maxParagraphs: 1 }
);
/* Every corpus screenplay, exported. The torture script drags NFD marks,
   a NEL, emoji, and an unclosed boneyard through the XML writer; the
   feature pins the export at production length. */
for (const { name, source } of SCRIPTS) {
	addFdxExport(name, parseFountain(source));
}
addFdxExport('special-fields', {
	titlePage: [
		{ text: 'A & B', key: 'Title' },
		/* The keyed model's empty value list exported as one empty line
		   (`[]` → `[""]`); the line model stores that line directly. */
		{ text: '', key: 'Custom' }
	],
	elements: [
		{ type: 'scene', text: 'INT. A & B - DAY', sceneNumber: 'A7' },
		{ type: 'character', text: 'MARA', dual: true },
		{ type: 'dialogue', text: `It's <fine> "really".` },
		{ type: 'centered', text: 'THE END' },
		{ type: 'lyrics', text: 'La la' }
	]
});
/* Only a page break has no FDX paragraph type left, so it is the only thing
   an export drops. Notes, outline levels and summaries all go out as
   themselves — see `fdxTypeOf`. */
addFdxExport('structural-omissions', {
	titlePage: [],
	elements: [
		{ type: 'section', text: 'Act One', depth: 1 },
		{ type: 'section', text: 'Set up Gold Key', depth: 3 },
		{ type: 'note', text: 'Kept: Final Draft has a Note element.' },
		{ type: 'synopsis', text: 'Tangle questions Uncle.' },
		{ type: 'pagebreak', text: '' },
		{ type: 'action', text: 'Visible.' }
	]
});
addFdxExport('illegal-characters', {
	titlePage: [],
	elements: [{ type: 'action', text: 'A\u0000B' }]
});

/* Act breaks (RFC-ACT-BREAK §3): each actbreak exports as New Act with
   Alignment="Center", and the End of Act cards a Final Draft reader expects
   are generated from the derived boundary — never stored in the model. The
   generated card names the act the way the act names itself: a canonical
   card ends END OF ACT <its ordinal>; a writer's own card is mirrored —
   TEASER closes as END TEASER, Breaking Bad's own spelling. The fixture is
   renumber-stable: TEASER is custom and keeps its name, so ACT TWO is the
   second act's canonical card. */
addFdxExport('act-breaks', {
	titlePage: [],
	elements: [
		{ type: 'action', text: 'Cold pasture.' },
		{ type: 'actbreak', text: 'TEASER' },
		{ type: 'action', text: 'Middle.' },
		{ type: 'actbreak', text: 'ACT TWO' },
		{ type: 'action', text: 'Later.' },
		{ type: 'actbreak', text: 'ACT TWO: THE TURN' },
		{ type: 'action', text: 'Nearly.' },
		{ type: 'actbreak', text: 'ACT THREE' },
		{ type: 'action', text: 'End.' }
	]
});

/* ScriptNotes: the comments Final Draft keeps beside the script, in a
   top-level <ScriptNotes> container, pointing back with a character Range.
   Kept in their own section so every case above keeps its expected output
   exactly. The synthetic cases pin each rule of where a Range lands; the
   file case pins the whole reading of a real feature's eleven notes. */
const fdxScriptNotes = [];
function addScriptNotes(name, input, options = {}, { withScript = true } = {}) {
	const source = input.file ? readFileSync(join(outDir, input.file), 'utf8') : input.source;
	const result = parseFdx(source, options);
	const expected = { diagnostics: result.diagnostics, scriptNotes: result.scriptNotes };
	if (withScript) expected.script = result.script;
	fdxScriptNotes.push({
		name,
		...(input.file ? { sourceFile: input.file } : { source }),
		options,
		expected
	});
}

/* Offsets count every script paragraph, one unit per paragraph break, the
   absorbed End of Act included. Paragraphs start at 0, 15, 20, 35, 43, 48;
   the script ends at 51. */
addScriptNotes('script-notes-anchoring', {
	source: `<FinalDraft><Content><Paragraph Type="Scene Heading"><Text>INT. LAB - DAY</Text></Paragraph><Paragraph Type="Action"><Text>Hum.</Text></Paragraph><Paragraph Type="End of Act" Alignment="Center"><Text>END OF ACT ONE</Text></Paragraph><Paragraph Type="New Act"><Text>ACT TWO</Text></Paragraph><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Go.</Text></Paragraph></Content><ScriptNotes>${[
		['1', '15,19', 'one paragraph, exactly'],
		['2', '14,14', 'a paragraph break belongs to the paragraph before it'],
		['3', '22,22', 'inside the absorbed End of Act: the next element'],
		['4', '43,51', 'across elements, to the end of the script'],
		['5', '60,70', 'starts past the script: range kept, no anchor'],
		['6', '48,99', 'ends past the script: held to its end'],
		['7', '19,15', 'reversed: the same span'],
		['8', 'abc', 'unreadable: no range'],
		['9', '1,2,3', 'three numbers: no range']
	]
		.map(
			([id, range, body]) =>
				`<ScriptNote Id="${id}" Range="${range}" WriterName="Writer A"><Paragraph><Text>${body}</Text></Paragraph></ScriptNote>`
		)
		.join('')}</ScriptNotes></FinalDraft>`
});
/* An End of Act with nothing after it: the end of the last element. */
addScriptNotes('script-notes-trailing-end-of-act', {
	source: `<FinalDraft><Content><Paragraph Type="Action"><Text>Last.</Text></Paragraph><Paragraph Type="End of Act" Alignment="Center"><Text>THE END</Text></Paragraph></Content><ScriptNotes><ScriptNote Id="1" Range="8,8" WriterName="Writer A"><Paragraph><Text>After the end.</Text></Paragraph></ScriptNote></ScriptNotes></FinalDraft>`
});
/* The attributes, verbatim or absent — never inferred. WriterName is decoded
   and trimmed; WriterID is not read; an all-zero Color is unset. The body is
   each direct-child paragraph's direct-child Text, AllCaps shouted, a
   self-closing paragraph a blank line, nested metadata skipped. A ScriptNote
   that is not directly inside <ScriptNotes> is not one. */
addScriptNotes('script-notes-attributes', {
	source: `<FinalDraft><Content><Paragraph Type="Action"><ScriptNote WriterName="Nobody"><Paragraph><Text>not a note</Text></Paragraph></ScriptNote><Text>Hum.</Text></Paragraph></Content><ScriptNotes><TableColumnSettings><Column>Order</Column></TableColumnSettings><ScriptNote Color="#000000000000" DateModified="20201214T005236" DateTime="20201214T005118" Id="143" Name="Re: Re: Xxxx" Range="0,4" RefId="2f18438e-60f5-4514-9ebf-5ab2a3e17bb5" Type="Alt Scenes" WriterID="b63f73e5-f9f4-4d1e-bd09-5539fa3e726b" WriterName="  Ren&#233;e &amp; Co  "><Paragraph Type="Transition"><Text Style="AllCaps">cut to:</Text></Paragraph><Paragraph/><Paragraph><SceneProperties><Paragraph><Text>hidden</Text></Paragraph></SceneProperties><Text>seen</Text><Text><![CDATA[ & kept]]></Text></Paragraph></ScriptNote><ScriptNote Color="#FEEACC8166BA" Name="" Type="" WriterName="   "><Paragraph><Text>No author, no title.</Text></Paragraph></ScriptNote><ScriptNote/></ScriptNotes></FinalDraft>`
});
addScriptNotes('script-notes-none', { source: FOREIGN_FDX });
addScriptNotes('script-notes-unterminated', {
	source: `<FinalDraft><Content><Paragraph Type="Action"><Text>x</Text></Paragraph></Content><ScriptNotes><ScriptNote Id="1" WriterName="Writer A"><Paragraph><Text>open`
});
addScriptNotes(
	'script-notes-limit',
	{
		source: `<FinalDraft><Content><Paragraph Type="Action"><Text>x</Text></Paragraph></Content><ScriptNotes><ScriptNote Id="1"><Paragraph><Text>kept</Text></Paragraph></ScriptNote><ScriptNote Id="2"><Paragraph><Text>past the limit</Text></Paragraph></ScriptNote></ScriptNotes></FinalDraft>`
	},
	{ maxParagraphs: 2 }
);
/* A real feature's eleven notes, anonymised: every letter is x or X, so each
   paragraph keeps its length and every Range lands where it did. The script
   itself is pinned elsewhere; this case pins the notes. */
addScriptNotes('sample0-2', { file: 'sample0-2.fdx' }, {}, { withScript: false });
/* Files Final Draft itself wrote, anonymised, their notes' Ranges measured on
   exactly these paragraphs: every note lands on whole words, or is empty. */
addScriptNotes('finaldraft-sample02', { file: 'finaldraft-sample02.fdx' }, {}, { withScript: false });
addScriptNotes('finaldraft-sample01', { file: 'finaldraft-sample01.fdx' }, {}, { withScript: false });
/* A block Final Draft embeds in a paragraph counts two units where it sits,
   its own paragraphs' text nothing. Paragraphs start at 0, 5 (a dual dialogue:
   units 5-6), 8 ("Omitted", then its omitted scene: units 15-16) and 18; the
   script ends at 21. */
addScriptNotes('script-notes-embedded-blocks', {
	source: `<FinalDraft><Content><Paragraph Type="Action"><Text>Hum.</Text></Paragraph><Paragraph Type="General"><DualDialogue><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Yes.</Text></Paragraph><Paragraph Type="Character"><Text>JON</Text></Paragraph><Paragraph Type="Dialogue"><Text>No.</Text></Paragraph></DualDialogue></Paragraph><Paragraph Type="Scene Heading"><Text>Omitted</Text><OmittedScene><Paragraph Type="Scene Heading"><Text>EXT. YARD - DAY</Text></Paragraph></OmittedScene></Paragraph><Paragraph Type="Action"><Text>Go.</Text></Paragraph></Content><ScriptNotes>${[
		['1', '0,4', 'the line before'],
		['2', '5,7', 'on the dual dialogue and its break'],
		['3', '8,15', 'the text before an omitted scene'],
		['4', '15,16', 'on the omitted scene'],
		['5', '17,18', 'from the break after it to the next line'],
		['6', '18,21', 'the line after both blocks']
	]
		.map(([id, range, text]) => `<ScriptNote Id="${id}" Range="${range}"><Paragraph><Text>${text}</Text></Paragraph></ScriptNote>`)
		.join('')}</ScriptNotes></FinalDraft>`
});

/* The preserving save: a file edited, not rebuilt. Each case is the file,
   the screenplay the save is handed, and the bytes it must write. Pinned
   around End of Act, which the import absorbs, so no element stands for it:
   left to the alignment it was deleted by every save and — typed General
   without an Alignment — given the writer's next edit. The save now keeps
   each card verbatim in front of the next paragraph it keeps, or after the
   last element when none is left. */
const fdxRewrite = [];
function addRewrite(name, source, edit = (elements) => elements) {
	const document = openFdx(source);
	const screenplay = { ...document.script, elements: edit(document.script.elements) };
	fdxRewrite.push({ name, source, screenplay, expected: { xml: document.rewrite(screenplay).xml } });
}
/* Two acts, each closed by a card; `card` is the card's attributes before Type. */
const twoActs = (card) => `<FinalDraft><Content>
  <Paragraph Type="New Act"><Text>ACT ONE</Text></Paragraph>
  <Paragraph Type="Action" id="a1"><Text>Hum.</Text></Paragraph>
  <Paragraph${card} Type="End of Act"><Text>END OF ACT ONE</Text></Paragraph>
  <Paragraph Type="New Act"><Text>ACT TWO</Text></Paragraph>
  <Paragraph Type="Action" id="a2"><Text>Buzz.</Text></Paragraph>
  <Paragraph${card} Type="End of Act"><Text>END OF ACT TWO</Text></Paragraph>
</Content></FinalDraft>`;
const centred = twoActs(' Alignment="Center"');
const bare = twoActs('');
const retext = (from, to) => (elements) =>
	elements.map((element) => (element.text === from ? { ...element, text: to } : element));

addRewrite('end-of-act-no-edit', centred);
addRewrite('end-of-act-bare-no-edit', bare);
/* The measured hijack: the edit lands in its own Action paragraph. */
addRewrite('end-of-act-bare-edit-after-card', bare, retext('Buzz.', 'Buzz, buzz.'));
/* Lines added at the end of act one land before END OF ACT ONE. */
addRewrite('end-of-act-lines-added-at-end-of-act', centred, (elements) => [
	...elements.slice(0, 2),
	{ type: 'action', text: 'A new last line.' },
	...elements.slice(2)
]);
/* The act break a card closes is deleted: the card is kept. */
addRewrite('end-of-act-act-break-deleted', centred, (elements) =>
	elements.filter((element) => element.text !== 'ACT TWO')
);
/* Nothing after the cards survives: both go after the last element. */
addRewrite('end-of-act-everything-after-deleted', centred, (elements) => elements.slice(0, 2));
addRewrite('end-of-act-script-emptied', bare, () => []);
addRewrite(
	'end-of-act-first-in-body',
	`<FinalDraft><Content>\n<Paragraph Type="End of Act"><Text>END OF TEASER</Text></Paragraph>\n<Paragraph Type="New Act"><Text>ACT ONE</Text></Paragraph>\n<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>\n</Content></FinalDraft>`,
	(elements) => [{ type: 'action', text: 'Cold open.' }, ...elements]
);
addRewrite(
	'end-of-act-two-in-a-row',
	`<FinalDraft><Content>\n<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>\n<Paragraph Type="End of Act"><Text>END OF TEASER</Text></Paragraph>\n<Paragraph Alignment="Center" Type="End of Act"><Text>END OF ACT ONE</Text></Paragraph>\n<Paragraph Type="New Act"><Text>ACT TWO</Text></Paragraph>\n</Content></FinalDraft>`,
	retext('ACT TWO', 'ACT TWO: THE TURN')
);

/* A paragraph the writer did not edit is written as its original bytes —
   through the engine, and through Fountain when the caller passes its own
   unedited reading. Fountain carries bold, italic, underline and strikeout
   and nothing else: no production tags, no revision marks, an emphasised
   heading read as Action, a paragraph split at its line breaks, a trailing
   space trimmed. Before this, each of those made an untouched paragraph look
   edited, and the save rewrote it. */
function fountainSource(source) {
	const imported = parseFdx(source).script;
	return serialiseFountain({
		...imported,
		elements: imported.elements.map((element) => ({
			...element,
			text: canonicalCasing(element.type, element.text)
		}))
	});
}
function fountainReading(source) {
	return parseFountain(fountainSource(source), { emphasis: 'runs' });
}
/* Files Final Draft itself wrote, anonymised, still carrying their tags:
   a save with no edit must return them — `identical` pins that both engines
   agree it does. `through: 'fountain'` is the app's path. */
function addFileRewrite(name, file, through) {
	const source = readFileSync(join(outDir, file), 'utf8');
	const document = openFdx(source);
	const reading = through === 'fountain' ? fountainReading(source) : undefined;
	const xml = reading
		? document.rewrite(reading, { unedited: reading }).xml
		: document.rewrite(document.script).xml;
	fdxRewrite.push({ name, sourceFile: file, ...(through ? { through } : {}), expected: { identical: xml === source } });
}
addFileRewrite('finaldraft-sample02-no-edit', 'finaldraft-sample02.fdx');
addFileRewrite('finaldraft-sample02-no-edit-through-fountain', 'finaldraft-sample02.fdx', 'fountain');
addFileRewrite('finaldraft-sample01-no-edit', 'finaldraft-sample01.fdx');
addFileRewrite('finaldraft-sample01-no-edit-through-fountain', 'finaldraft-sample01.fdx', 'fountain');

/* Each rule, small: the screenplay being saved and the unedited reading are
   pinned as data, so Swift is judged without its own Fountain in the way. */
function addUneditedRewrite(name, source, { reading = fountainReading(source), edit = (elements) => elements } = {}) {
	const screenplay = { ...reading, elements: edit(reading.elements) };
	fdxRewrite.push({
		name,
		source,
		screenplay,
		unedited: reading,
		expected: { xml: openFdx(source).rewrite(screenplay, { unedited: reading }).xml }
	});
}
const lab = (paragraphs) => `<FinalDraft><Content>\n${paragraphs.join('\n')}\n</Content></FinalDraft>`;
/* Final Draft splits runs the model merges; compared raw, this read as edited. */
addRewrite(
	'engine-split-runs-no-edit',
	lab([
		'<Paragraph Type="Scene Heading"><Text TagNumber="597">INT. </Text><Text TagNumber="823">HOME LIBRARY, </Text><Text AdornmentStyle="-1" TagNumber="823">CASALINDA</Text><Text TagNumber="599"> - DAY</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>'
	])
);
const tagged = lab([
	'<Paragraph Type="Scene Heading"><Text TagNumber="1">INT. LAB - DAY</Text></Paragraph>',
	'<Paragraph Type="Action"><Text RevisionID="2">She </Text><Text TagNumber="7">waits</Text><Text>.</Text></Paragraph>',
	'<Paragraph Type="Action"><Text>He leaves.</Text></Paragraph>'
]);
addUneditedRewrite('unedited-tags-kept-no-edit', tagged);
addUneditedRewrite('unedited-tags-kept-beside-an-edit', tagged, {
	edit: (elements) => elements.map((element) => (element.text === 'He leaves.' ? { ...element, text: 'He runs.' } : element))
});
const split = lab([
	'<Paragraph Type="Action"><Text TagNumber="3">Lands her point:\nThey must work together.</Text></Paragraph>',
	'<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>'
]);
addUneditedRewrite('unedited-split-paragraph-no-edit', split);
addUneditedRewrite('unedited-split-paragraph-one-line-edited', split, {
	edit: (elements) => elements.map((element) => (element.text === 'They must work together.' ? { ...element, text: 'They agree.' } : element))
});
addUneditedRewrite(
	'unedited-reread-heading-no-edit',
	lab([
		'<Paragraph Number="2" Type="Scene Heading"><Text Style="Bold+Italic" TagNumber="601">INT. </Text><Text Style="Bold+Italic" TagNumber="824">KITCHEN - NIGHT</Text><Text> </Text><Text Style="Bold+Italic">(N1)</Text></Paragraph>',
		'<Paragraph Type="Character"><Text>MAID</Text></Paragraph>',
		'<Paragraph Type="Dialogue"><Text>Not horrible.</Text></Paragraph>',
		'<Paragraph Type="Parenthetical"><Text Style="Italic">(beat)</Text></Paragraph>',
		'<Paragraph Type="Dialogue"><Text>Me too. But... </Text></Paragraph>'
	])
);
addUneditedRewrite('unedited-unaligned-falls-back', tagged, {
	reading: parseFountain('EXT. SOMEWHERE ELSE - NIGHT\n\nNothing like the file.\n', { emphasis: 'runs' })
});

/* An edited paragraph is merged, not rewritten: the writer's change is placed
   onto the file's own paragraph, so its Type, tags, revision marks, AllCaps,
   casing, line breaks and trailing space stand wherever the writer did not
   type. Each case is an edit made the app's way — `edit.find`, which occurs
   once in the Fountain source, becomes `edit.replace` — and saved through
   Fountain, by each engine for itself. An inline file is pinned whole; a
   Final Draft-written one by the one change its save makes: at UTF-16 `at`,
   `removed` became `inserted`. */
/* A file's ScriptNote Range values, in note order, and the file with each one
   emptied — so a pinned change to the script is read apart from the Ranges a
   save moves to keep every note on its words. */
const NOTE_RANGE = /(<ScriptNote\b[^>]*?\sRange=")([^"]*)(")/g;
const scriptNoteRangesOf = (xml) => [...xml.matchAll(NOTE_RANGE)].map((match) => match[2]);
const withoutNoteRanges = (xml) => xml.replace(NOTE_RANGE, '$1$3');
function addMergedRewrite(name, { source, file }, find, replace, notes) {
	const original = source ?? readFileSync(join(outDir, file), 'utf8');
	const text = fountainSource(original);
	if (text.split(find).length !== 2) throw new Error(`${name}: ${JSON.stringify(find)} must occur once`);
	const edited = parseFountain(text.replace(find, () => replace), { emphasis: 'runs' });
	const written = openFdx(original).rewrite(edited, {
		unedited: parseFountain(text, { emphasis: 'runs' }),
		...(notes ? { notes: noteWriting(notes) } : {})
	}).xml;
	const scriptNoteRanges = file ? scriptNoteRangesOf(written) : [];
	const xml = scriptNoteRanges.length > 0 ? withoutNoteRanges(original) : original;
	const saved = scriptNoteRanges.length > 0 ? withoutNoteRanges(written) : written;
	let at = 0;
	while (at < xml.length && xml[at] === saved[at]) at++;
	let tail = 0;
	while (tail < xml.length - at && tail < saved.length - at && xml.at(-1 - tail) === saved.at(-1 - tail)) tail++;
	// Never between the halves of a character outside the BMP.
	if (at > 0 && /[\uD800-\uDBFF]/.test(xml[at - 1])) at--;
	if (tail > 0 && /[\uDC00-\uDFFF]/.test(xml.at(-tail))) tail--;
	const changed = { at, removed: xml.slice(at, xml.length - tail), inserted: saved.slice(at, saved.length - tail) };
	fdxRewrite.push({
		name,
		...(file ? { sourceFile: file } : { source }),
		through: 'fountain',
		edit: { find, replace },
		...(notes ? { notes } : {}),
		expected: file
			? { changed, ...(scriptNoteRanges.length > 0 ? { scriptNoteRanges } : {}) }
			: { xml: saved }
	});
}
const sample02 = { file: 'finaldraft-sample02.fdx' };
const sample01 = { file: 'finaldraft-sample01.fdx' };
addMergedRewrite('merged-tagged-action-typo', sample02, 'Xxxx XXXXXX, 12,', 'Xyxx XXXXXX, 12,');
addMergedRewrite('merged-emphasised-numbered-heading', sample02, '***(X1)*** #2#', '***(X2)*** #2#');
addMergedRewrite('merged-italic-parenthetical', sample02, '(*xx. xxxxx, xxx*)', '(*xx. xxxxx, xxx, xxxxx*)');
addMergedRewrite('merged-beat-read-as-dialogue', sample02, '*...Xxx xxxxxxxx.*\n*(beat)*', '*...Xxx xxxxxxxx.*\n*(beat, xxxxx)*');
addMergedRewrite('merged-summary-second-line', sample01, '\nX & X xxxx xxxx xxxxxxxx.\n', '\nX & X yxxx xxxx xxxxxxxx.\n');
addMergedRewrite('merged-trailing-space-kept', sample01, 'Xx xxx. Xxx... ', 'Yx xxx. Xxx... ');
addMergedRewrite('merged-beside-allcaps-word', sample02, 'XXXXXX xxxxx xxx xxxxx xxx xxxxxxx xxxxxx.', 'XXXXXX yxxxx xxx xxxxx xxx xxxxxxx xxxxxx.');
addMergedRewrite('merged-plain-heading-stored-casing', sample02, '(D2) #4#', '(D3) #4#');
addMergedRewrite(
	'merged-typed-text-inherits-all-but-revision',
	{ source: lab(['<Paragraph Type="Action"><Text AdornmentStyle="-1" Font="Courier Prime" RevisionID="3" Style="AllCaps" TagNumber="12">she waits</Text><Text>.</Text></Paragraph>']) },
	'SHE WAITS.',
	'SHE STILL WAITS.'
);
addMergedRewrite('merged-typed-at-the-start', { source: tagged }, 'She waits.', 'Now she waits.');
addMergedRewrite('merged-two-edits-one-paragraph', { source: tagged }, 'She waits.', 'Then she waits!');
addMergedRewrite('merged-tagged-word-deleted', { source: tagged }, 'She waits.', 'She .');
addMergedRewrite('merged-line-retyped', { source: tagged }, 'She waits.', 'Rain falls.');
const plainTagged = lab(['<Paragraph Type="Action"><Text TagNumber="7">He runs home.</Text></Paragraph>']);
addMergedRewrite('merged-emphasis-added', { source: plainTagged }, 'He runs home.', 'He *runs* home.');
addMergedRewrite(
	'merged-emphasis-removed',
	{ source: lab(['<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>', '<Paragraph Type="Parenthetical"><Text Style="Italic" TagNumber="8">(beat)</Text></Paragraph>']) },
	'*(beat)*',
	'(beat)'
);
addMergedRewrite(
	'merged-kind-changed-retyped',
	{ source: lab(['<Paragraph Type="Scene Heading"><Text TagNumber="1">INT. LAB - DAY</Text></Paragraph>', '<Paragraph Alignment="Left" Type="Action"><Text TagNumber="2">SHE WAITS</Text></Paragraph>']) },
	'!SHE WAITS',
	'> SHE WAITS'
);
addMergedRewrite(
	'merged-astral-character-retyped-whole',
	{ source: lab(['<Paragraph Type="Action"><Text RevisionID="1">Key 🔑.</Text></Paragraph>']) },
	'Key 🔑.',
	'Key 🔒.'
);
/* Final Draft's dual dialogue: a paragraph with no text of its own holding a
   <DualDialogue>, whose paragraphs are the two speeches. Each line is a
   paragraph to the save; the block is kept around the lines kept as a dual
   pair, lines added inside the pair go inside it, and a pair the writer
   undid is dissolved in place and reported. */
const dualPair = '\nXXXXX\nXxx?\n\nXXXXXX ^\nXxx.\n';
addMergedRewrite('dual-dialogue-line-typo', sample02, dualPair, '\nXXXXX\nXxx?\n\nXXXXXX ^\nQxx.\n');
addMergedRewrite('dual-dialogue-cue-typo', sample02, dualPair, '\nQXXXX\nXxx?\n\nXXXXXX ^\nXxx.\n');
addMergedRewrite('dual-dialogue-line-added', sample02, dualPair, '\nXXXXX\nXxx?\n\nXXXXXX ^\nXxx.\n(xxxxx)\nXxx xxx.\n');
addMergedRewrite('dual-dialogue-deleted', sample02, dualPair, '\n');
addMergedRewrite('dual-dialogue-caret-removed', sample02, dualPair, '\nXXXXX\nXxx?\n\nXXXXXX\nXxx.\n');
const dualLab = lab([
	'<Paragraph Type="General"><DualDialogue><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Yes.</Text></Paragraph><Paragraph Type="Character"><Text TagNumber="4">JON</Text></Paragraph><Paragraph Type="Parenthetical"><Text>(beat)</Text></Paragraph><Paragraph Type="Dialogue"><Text>No.</Text></Paragraph></DualDialogue></Paragraph>',
	'<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>'
]);
addUneditedRewrite('dual-dialogue-first-in-body-no-edit', dualLab);
addMergedRewrite('dual-dialogue-first-speaker-line-added', { source: dualLab }, 'MARA\nYes.\n', 'MARA\nYes.\n(softly)\nAgain.\n');
addMergedRewrite('dual-dialogue-first-speaker-removed', { source: dualLab }, 'MARA\nYes.\n\n', '');

/* A save keeps every ScriptNote on its words: each Range value whose words
   moved is rewritten to where they now are, counted as Final Draft counts; a
   note whose words are all gone closes to zero length where they stood. On
   the files Final Draft wrote the change to the script is pinned apart from
   the Range values, which are pinned in note order. */
addMergedRewrite('note-ranges-words-typed-early', sample02, 'Xxxx XXXXXX, 12,', 'Xxxx QZQZ XXXXXX, 12,');
addMergedRewrite('note-ranges-line-added-early', sample02, 'Xxx xxxxxxxx XXXXX, 40x,', 'A new line.\n\nXxx xxxxxxxx XXXXX, 40x,');
addMergedRewrite(
	'note-ranges-line-deleted-early',
	sample02,
	'Xxx xxxxxxxx XXXXX, 40x, xxxxxx xxxxxxxx xxxxxxxxx xxxxxxx, xxxxx xxxx xxxxxxx xxxx xxxxxx xxxxxx x xxxxx xxxxx.\n\n',
	''
);
addMergedRewrite('note-ranges-a-notes-words-deleted', sample02, 'X xxxxx xxxxxxx. Xxxx:\n\nXXXXX\nXxxxxxx.\n', 'X xxxxx xxxxxxx. Xxxx:\n');
/* Paragraphs start at 0, 9 and 21; the script ends at 30. */
const notedLab = `<FinalDraft><Content>\n<Paragraph Type="Action"><Text>One two.</Text></Paragraph>\n<Paragraph Type="Action"><Text>Three four.</Text></Paragraph>\n<Paragraph Type="Action"><Text>Five six.</Text></Paragraph>\n</Content><ScriptNotes>${[
	['1', '0,3', 'One'],
	['2', '9,14', 'Three'],
	['3', '19,15', 'four, written end first'],
	['4', '30,30', 'at the end'],
	['5', '99,120', 'already past the end']
]
	.map(([id, range, text]) => `<ScriptNote Id="${id}" Range="${range}"><Paragraph><Text>${text}</Text></Paragraph></ScriptNote>`)
	.join('')}</ScriptNotes></FinalDraft>`;
/* Typed at a note's edge: not joined. Typed inside its words: joined. */
addMergedRewrite('note-ranges-edges-and-inside', { source: notedLab }, 'One two.\n\nThree four.', 'One and two.\n\nThrxee four.');
/* A note's words all deleted: zero length where they stood, reversed or not. */
addMergedRewrite('note-ranges-words-all-deleted', { source: notedLab }, 'Three four.\n\n', '');

/* A line of another kind with other words in its place replaced the paragraph:
   written as before, none of the old paragraph's attributes carried over. */
addMergedRewrite('merged-replaced-by-another-kind', { source: tagged }, 'She waits.', '> CUT TO BLACK.');
/* An edit only to what Fountain added cannot be placed: that paragraph takes
   the old path (and TypeScript reports FDX_REWRITE_EDIT_UNPLACED). */
addMergedRewrite(
	'merged-unplaced-takes-the-old-path',
	{ source: lab(['<Paragraph Number="2" Type="Scene Heading"><Text Style="Bold+Italic" TagNumber="601">INT. KITCHEN - NIGHT</Text></Paragraph>', '<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>']) },
	'#2#',
	'#3#'
);

/* The writer's notes, written as Final Draft ScriptNotes and read back as the
   writer's own (IL-0039). The screenplay saved and the unedited reading are
   pinned as data, so Swift is judged without its own Fountain in the way. */
const NOTES_LAB = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft DocumentType="Script" Template="No" Version="5">

  <Content>
    <Paragraph Type="Scene Heading">
      <Text>INT. KITCHEN - NIGHT</Text>
    </Paragraph>
    <Paragraph Type="Action">
      <Text>The kettle screams.</Text>
    </Paragraph>
    <Paragraph Type="Note">
      <Text>A note the file already has.</Text>
    </Paragraph>
    <Paragraph Type="Character">
      <Text>MARA</Text>
    </Paragraph>
    <Paragraph Type="Dialogue">
      <Text>It's the same lab.</Text>
    </Paragraph>
  </Content>

  <Characters>
    <Character>MARA</Character>
  </Characters>

  <Navigator/>
</FinalDraft>
`;
const throughFountain = (script) => parseFountain(serialiseFountain(script), { emphasis: 'runs' });
function addNoteRewrite(name, source, edit, notes = NOTE_WRITING) {
	const unedited = fountainReading(source);
	const screenplay = throughFountain({ ...unedited, elements: edit(unedited.elements) });
	const xml = openFdx(source).rewrite(screenplay, { unedited, notes: noteWriting(notes) }).xml;
	fdxRewrite.push({ name, source, screenplay, unedited, notes, expected: { xml } });
	return xml;
}
const noteBefore = (text, line) => (elements) => {
	const at = elements.findIndex((element) => element.text === line);
	if (at === -1) throw new Error(`no line ${JSON.stringify(line)}`);
	return [...elements.slice(0, at), { type: 'note', text }, ...elements.slice(at)];
};
const withOwnNote = addNoteRewrite('script-notes-new-note', NOTES_LAB, noteBefore('Dana Reyes (Director): Too flat?', "It's the same lab."));
addNoteRewrite('script-notes-unsigned-note-takes-the-writer', NOTES_LAB, noteBefore('Too flat?', 'The kettle screams.'));
addNoteRewrite('script-notes-trailing-note', NOTES_LAB, (elements) => [...elements, { type: 'note', text: 'The end?' }]);
addNoteRewrite('script-notes-lines', NOTES_LAB, noteBefore('First thought.\nSecond thought.', 'The kettle screams.'));
addNoteRewrite('script-notes-no-writer', NOTES_LAB, noteBefore('Too flat?', 'The kettle screams.'), { ...NOTE_WRITING, writer: undefined });
addNoteRewrite('script-notes-body-note-edited-stays', NOTES_LAB, (elements) =>
	noteBefore('Tighter?', 'MARA')(elements.map((element) => (element.text === 'A note the file already has.' ? { ...element, text: 'A note the file has, edited.' } : element)))
);
addNoteRewrite('script-notes-body-note-deleted', NOTES_LAB, (elements) => elements.filter((element) => element.text !== 'A note the file already has.'));
addNoteRewrite(
	'script-notes-dual-dialogue-kept',
	`<FinalDraft DocumentType="Script" Template="No" Version="5">
  <Content>
    <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
    <Paragraph><DualDialogue><Paragraph Type="Character"><Text>BOB</Text></Paragraph><Paragraph Type="Dialogue"><Text>Hi.</Text></Paragraph><Paragraph Type="Character"><Text>ANN</Text></Paragraph><Paragraph Type="Dialogue"><Text>Ho.</Text></Paragraph></DualDialogue></Paragraph>
  </Content>
</FinalDraft>`,
	noteBefore('Overlap?', 'Ho.')
);
addNoteRewrite(
	'script-notes-self-closing-container',
	lab(['<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>']).replace('</Content>', '</Content><ScriptNotes/>'),
	noteBefore('Why?', 'Hum.')
);
addNoteRewrite('script-notes-no-container-no-characters', lab(['<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>']), noteBefore('Why?', 'Hum.'));
/* Reopened: the file this save wrote. */
addRewrite('script-notes-reopened-no-edit', withOwnNote);
{
	const reading = fountainReading(withOwnNote);
	const xml = openFdx(withOwnNote).rewrite(reading, { unedited: reading, notes: noteWriting(NOTE_WRITING) }).xml;
	fdxRewrite.push({ name: 'script-notes-reopened-no-edit-through-fountain', source: withOwnNote, through: 'fountain', notes: NOTE_WRITING, expected: { identical: xml === withOwnNote } });
}
addNoteRewrite('script-notes-reopened-line-above-edited', withOwnNote, (elements) =>
	elements.map((element) => (element.text === 'The kettle screams.' ? { ...element, text: 'The old kettle screams.' } : element))
);
addNoteRewrite('script-notes-reopened-deleted', withOwnNote, (elements) => elements.filter((element) => !element.text.endsWith('Too flat?')));
addNoteRewrite('script-notes-reopened-changed', withOwnNote, (elements) =>
	elements.map((element) => (element.text.endsWith('Too flat?') ? { ...element, text: 'Dana Reyes (Director): Much too flat.' } : element))
);
/* Added to Final Draft's own notes, in a file Final Draft wrote. */
addMergedRewrite('script-notes-added-to-final-draft-notes', sample02, 'Xxxx XXXXXX, 12,', 'Xxxx XXXXXX, 12, [[Tighter?]]', NOTE_WRITING);
/* And read: eDraft's notes back as the writer's own, Final Draft's as they were. */
addScriptNotes('script-notes-owned-read-back', { source: withOwnNote });
addScriptNotes('script-notes-owned-beside-final-draft', {
	source: withOwnNote.replace(
		'  <ScriptNotes>\n',
		'  <ScriptNotes>\n    <ScriptNote Id="7" Range="0,20" Type="Producer" WriterName="Sam Okafor"><Paragraph><Text>No [eDraft] mark: Final Draft\'s.</Text></Paragraph></ScriptNote>\n'
	)
});

writeFixture('fdx.json', {
	import: fdxImport,
	export: fdxExport,
	scriptNotes: fdxScriptNotes,
	rewrite: fdxRewrite
});

/* ------------------------------------------------------------------ */
/* draft.json — the .draft 1.0 file (docs/RFC-DRAFT-FORMAT.md)         */
/* ------------------------------------------------------------------ */

const draftHex = (bytes) => Buffer.from(bytes).toString('hex');
const draftUtf8 = (text) => new TextEncoder().encode(text);
const draftText = (bytes) => new TextDecoder().decode(bytes);
const draftChar = (...codes) => String.fromCharCode(...codes);
const DRAFT_WRITER = { name: 'eDraft', version: '1.0 (conformance)' };

/** A document as the fixture carries it: trees as canonical JSON text, so
	member order is pinned exactly; parts in the order the reader made. */
function draftDocJson(document) {
	const out = {};
	if (document.title !== undefined) out.title = document.title;
	out.script = canonicalJson(document.script);
	if (document.notes !== undefined) out.notes = canonicalJson(document.notes);
	if (document.manifestExtra !== undefined) out.manifestExtra = canonicalJson(document.manifestExtra);
	out.parts = document.parts.map((part) => ({ path: part.path, hex: draftHex(part.data), damaged: part.damaged === true }));
	return out;
}

/** Invented script text only — the repository is public. */
const DRAFT_SAMPLE = [
	'Title: The Kettle',
	'Author: Sam Okafor',
	'',
	'INT. KITCHEN - NIGHT',
	'',
	'[[Too still? She should flinch.]]',
	'',
	'The kettle **screams**. Mara doesn’t move.',
	'',
	'MARA ^',
	'(quietly)',
	'Not yet.',
	'',
	'# ACT ONE',
	'',
	'= The kettle, again.',
	'',
	'CUT TO:',
	'',
	'[[A last thought.]]',
	''
].join('\n');

const draftSample = () => draftFromScreenplay(parseFountain(DRAFT_SAMPLE, { emphasis: 'runs' }), { title: 'The Kettle' });

function draftWithEverything() {
	const document = draftSample();
	const elements = document.script.get('elements');
	const line = elements[1].get('text');
	const words = 'Mara doesn’t move';
	const start = line.indexOf(words);
	const { prefix, suffix } = draftAnchorContext(line, start, start + words.length);
	const thread = document.notes.get('threads')[0];
	thread.set('anchor', new Map([['element', '2'], ['start', start], ['end', start + words.length], ['quote', words], ['prefix', prefix], ['suffix', suffix]]));
	thread.set('messages', [
		new Map([['id', '2'], ['by', 'Dana Reyes'], ['role', 'Director'], ['at', '2026-09-18T10:02:00Z'], ['text', 'Too still? She should flinch.'], ['source', new Map([['fdx', '12']])]]),
		new Map([['id', '5'], ['by', 'Sam Okafor'], ['at', '2026-09-18T10:05:00Z'], ['text', 'She’s frozen — that’s the beat.\nOn purpose.']])
	]);
	thread.set('status', [new Map([['state', 'resolved'], ['by', 'Dana Reyes'], ['at', '2026-09-18T11:00:00Z']])]);
	document.notes.set('nextId', '6');
	return document;
}

function draftMustPreserve() {
	const document = draftSample();
	document.script.set('x-future', new Map([['2', 1], ['a', [null, true, -7, 'q"\\' + draftChar(1, 0x2028)]]]));
	document.script.get('elements')[1].set('com.example.tag', 'kept');
	document.script.get('elements')[1].get('runs')[0].set('com.example.weight', 3);
	document.notes.get('threads')[0].set('com.example.colour', 'teal');
	document.notes.get('threads')[0].get('messages')[0].set('mood', 'wry');
	document.manifestExtra = new Map([['generator', 'another tool'], ['z', new Map()]]);
	document.parts = [
		{ path: 'ext/com.example/data.bin', data: new Uint8Array([0, 1, 2, 255]) },
		{ path: 'history/2026-09-01.json', data: draftUtf8('{"kept": true}') }
	];
	return document;
}

function draftWithParts() {
	const document = draftFromScreenplay(parseFountain('INT. HALL - DAY\n\nQuiet.\n', { emphasis: 'runs' }));
	document.parts = [
		{ path: 'ext/com.example/b.json', data: draftUtf8('{}') },
		{ path: 'revisions.json', data: draftUtf8('{"sets": []}') },
		{ path: 'origin/source.fountain', data: draftUtf8('INT. HALL - DAY\n\nQuiet.\n') },
		{ path: 'ext/com.example/été.txt', data: draftUtf8('x') },
		{ path: 'origin/source.fdx', data: draftUtf8('<?xml version="1.0"?><FinalDraft/>') }
	];
	return document;
}

function draftDamagedCarried() {
	const document = draftFromScreenplay(parseFountain('INT. HALL - DAY\n\nQuiet.\n', { emphasis: 'runs' }));
	document.parts = [
		{ path: 'notes.json', data: draftUtf8('{"threads": [ oops'), damaged: true },
		{ path: 'mimetype', data: draftUtf8('application/zip'), damaged: true },
		{ path: 'script.json', data: draftUtf8('not json'), damaged: true }
	];
	return document;
}

const draftWrites = [
	['sample', draftSample()],
	['no-notes-no-title', draftFromScreenplay(parseFountain('INT. HALL - DAY\n\nQuiet.\n', { emphasis: 'runs' }))],
	['everything', draftWithEverything()],
	['must-preserve', draftMustPreserve()],
	['parts', draftWithParts()],
	['damaged-carried', draftDamagedCarried()],
	['empty', draftFromScreenplay({ titlePage: [], elements: [] })]
].map(([name, document]) => ({ name, document: draftDocJson(document), bytes: draftHex(writeDraft(document, { writer: DRAFT_WRITER })) }));

async function draftEntries(bytes) {
	return new Map((await readZipEntries(bytes)).map((entry) => [entry.name, entry.data]));
}
const draftRezip = (entries) => writeZipStored([...entries].map(([name, data]) => ({ name, data })), { dosDate: 0x0021 });
const draftBytesOf = (name) => Buffer.from(draftWrites.find((w) => w.name === name).bytes, 'hex');

/** One more entry, deflated, as another tool would add it. */
function draftAppendDeflated(archive, name, packed, rawSize, crc = 0) {
	const view = new DataView(archive.buffer, archive.byteOffset, archive.byteLength);
	const eocd = archive.length - 22;
	const count = view.getUint16(eocd + 10, true);
	const centralSize = view.getUint32(eocd + 12, true);
	const centralOffset = view.getUint32(eocd + 16, true);
	const nameBytes = draftUtf8(name);
	const local = new Uint8Array(30 + nameBytes.length);
	const lv = new DataView(local.buffer);
	lv.setUint32(0, 0x04034b50, true);
	lv.setUint16(4, 20, true);
	lv.setUint16(8, 8, true);
	lv.setUint32(14, crc, true);
	lv.setUint32(18, packed.length, true);
	lv.setUint32(22, rawSize, true);
	lv.setUint16(26, nameBytes.length, true);
	local.set(nameBytes, 30);
	const record = new Uint8Array(46 + nameBytes.length);
	const rv = new DataView(record.buffer);
	rv.setUint32(0, 0x02014b50, true);
	rv.setUint16(4, 20, true);
	rv.setUint16(6, 20, true);
	rv.setUint16(10, 8, true);
	rv.setUint32(16, crc, true);
	rv.setUint32(20, packed.length, true);
	rv.setUint32(24, rawSize, true);
	rv.setUint16(28, nameBytes.length, true);
	rv.setUint32(42, centralOffset, true);
	record.set(nameBytes, 46);
	const end = new Uint8Array(22);
	const ev = new DataView(end.buffer);
	ev.setUint32(0, 0x06054b50, true);
	ev.setUint16(8, count + 1, true);
	ev.setUint16(10, count + 1, true);
	ev.setUint32(12, centralSize + record.length, true);
	ev.setUint32(16, centralOffset + local.length + packed.length, true);
	return Buffer.concat([archive.subarray(0, centralOffset), local, packed, archive.subarray(centralOffset, centralOffset + centralSize), record, end]);
}

async function draftEdited(name, edit) {
	const entries = await draftEntries(draftBytesOf(name));
	await edit(entries);
	return draftRezip(entries);
}
const draftScriptEdit = (name, change) =>
	draftEdited(name, (entries) => {
		const script = parseDraftJson(draftText(entries.get('script.json')));
		change(script);
		entries.set('script.json', draftUtf8(canonicalJson(script)));
	});
const draftManifestEdit = (change) =>
	draftEdited('sample', (entries) => {
		const manifest = parseDraftJson(draftText(entries.get('manifest.json')));
		change(manifest);
		entries.set('manifest.json', draftUtf8(canonicalJson(manifest)));
	});

const draftReadInputs = [
	...draftWrites.map((w) => [w.name, Buffer.from(w.bytes, 'hex')]),
	['outside-edit', await draftScriptEdit('sample', (script) => script.get('elements')[0].set('text', 'INT. KITCHEN - DAY'))],
	['damaged-notes', await draftEdited('sample', (entries) => entries.set('notes.json', draftUtf8('{"threads": [ oops')))],
	['damaged-script', await draftEdited('sample', (entries) => entries.set('script.json', draftUtf8('not json')))],
	['damaged-script-and-notes', await draftEdited('sample', (entries) => {
		entries.set('script.json', draftUtf8('{}'));
		entries.set('notes.json', draftUtf8('[]'));
	})],
	['no-script', await draftEdited('sample', (entries) => {
		entries.set('script.json', draftUtf8('x'));
		entries.set('script.fountain', new Uint8Array([0xff, 0xfe]));
	})],
	['crc-damaged-notes', (() => {
		const bytes = draftBytesOf('sample');
		const at = bytes.indexOf(Buffer.from('"threads"')) + 1;
		const out = Buffer.from(bytes);
		out[at] ^= 0x20;
		return out;
	})()],
	['truncated', (() => {
		const bytes = draftBytesOf('sample');
		const centralAt = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(bytes.length - 6, true);
		return bytes.subarray(0, centralAt);
	})()],
	['newer-minor', await draftManifestEdit((manifest) => {
		manifest.set('version', '1.4');
		manifest.set('minReader', '1.4');
	})],
	['newer-major', await draftManifestEdit((manifest) => {
		manifest.set('version', '2.0');
		manifest.set('minReader', '2.0');
	})],
	['manifest-damaged', await draftEdited('sample', (entries) => entries.set('manifest.json', draftUtf8('{"format": "draft"')))],
	['mimetype-wrong', await draftEdited('sample', (entries) => entries.set('mimetype', draftUtf8('application/zip')))],
	['mimetype-missing', await draftEdited('sample', (entries) => entries.delete('mimetype'))],
	['unlisted-and-missing', await draftEdited('parts', (entries) => {
		entries.delete('revisions.json');
		entries.set('ext/com.example/new.txt', draftUtf8('added elsewhere'));
	})],
	['duplicate-and-invalid-names', draftRezip(new Map([
		...(await draftEntries(draftBytesOf('sample'))),
		['Script.JSON', draftUtf8('{}')],
		['../escape.txt', draftUtf8('outside')],
		['ext/a//b', draftUtf8('empty segment')]
	]))],
	['bomb', draftAppendDeflated(draftBytesOf('sample'), 'ext/x/bomb', deflateRawSync(new Uint8Array(1_000_000)), 1_000_000)],
	['deflated-part', (() => {
		const raw = draftUtf8('read through inflate '.repeat(20));
		return draftAppendDeflated(draftBytesOf('sample'), 'ext/x/deflated.txt', deflateRawSync(raw), raw.length, crc32(raw));
	})()],
	['anchor-moved-within', await draftScriptEdit('everything', (script) => script.get('elements')[1].set('text', 'Steam. The kettle screams. Mara doesn’t move.'))],
	['anchor-words-changed', await draftScriptEdit('everything', (script) => script.get('elements')[1].set('text', 'The kettle screams. Mara runs.'))],
	['anchor-moved-elsewhere', await draftScriptEdit('everything', (script) => {
		const elements = script.get('elements');
		elements.splice(1, 1);
		elements.push(new Map([['id', 'z9'], ['type', 'action'], ['text', 'Later. The kettle screams. Mara doesn’t move.']]));
	})],
	['anchor-detached', await draftScriptEdit('everything', (script) => script.get('elements').splice(1, 1))],
	['not-a-draft', writeZipStored([{ name: 'word/document.xml', data: draftUtf8('<w/>') }])],
	['not-a-zip', draftUtf8('INT. HALL - DAY\n')]
	/* The 512-entry limit is pinned by each port's own tests, not here: an
       archive over it is 100 KB of fixture for one refusal. */
];

const draftReads = [];
for (const [name, bytes] of draftReadInputs) {
	try {
		const result = await readDraft(new Uint8Array(bytes));
		draftReads.push({ name, bytes: draftHex(bytes), document: draftDocJson(result.document), diagnostics: result.diagnostics, readOnly: result.readOnly });
	} catch (error) {
		draftReads.push({ name, bytes: draftHex(bytes), refused: error.code });
	}
}

const draftBackslash = draftChar(92);
const draftJsonInputs = [
	'{"b": 1, "a": [true, false, null, "x"], "2": -3, "": {}}',
	'{"' + draftBackslash + 'u20ac": 1, "' + draftBackslash + 'ud83d' + draftBackslash + 'ude00": 2, "a": {"z": 0, "b": []}, "' +
		draftBackslash + 'u0080": 3, "' + draftBackslash + 'u007f": 4}',
	'["q' + ['"', draftBackslash, '/', 'b', 'f', 'n', 'r', 't', 'u0001', 'u001f', 'u2028'].map((e) => draftBackslash + e).join('') +
		' é 🎬", 9007199254740991, -9007199254740991, 0, -0]',
	'  {\n\t"nested": [[[[]]]], "empty": {} , "s": "" }  '
];
const draftJsonInvalid = [
	'{"a": 1, "a": 2}',
	'{"a": 1.5}',
	'{"a": 1e3}',
	'{"a": 9007199254740992}',
	'"' + draftBackslash + 'ud800"',
	'"' + draftBackslash + 'udc00x"',
	draftChar(0xfeff) + '{}',
	'{} x',
	'"a' + draftChar(1) + 'b"',
	'['.repeat(65) + ']'.repeat(65),
	'{"a" 1}',
	'[1,]',
	'{,}',
	'tru',
	"'a'",
	'01',
	'-',
	'"' + draftBackslash + 'x"',
	''
];

for (const input of draftJsonInvalid) {
	let parsed = true;
	try {
		parseDraftJson(input);
	} catch {
		parsed = false;
	}
	if (parsed) throw new Error(`draft.json: an invalid JSON case parsed: ${JSON.stringify(input)}`);
}

const draftDetect = [
	['draft', draftBytesOf('sample')],
	['pdf', draftUtf8('%PDF-1.7\n')],
	['fdx', draftUtf8('<?xml version="1.0"?><FinalDraft/>')],
	['fdx-bom', draftUtf8(draftChar(0xfeff) + '\n<FinalDraft/>')],
	['text', draftUtf8(DRAFT_SAMPLE)],
	['empty', new Uint8Array(0)],
	['not-utf8', new Uint8Array([0xc3, 0x28])],
	['overlong', new Uint8Array([0xc0, 0xaf])],
	['surrogate', new Uint8Array([0xed, 0xa0, 0x80])],
	['cut-sequence', new Uint8Array([0x61, 0xe2, 0x82])],
	['four-byte', draftUtf8('🎬')],
	['other-zip', writeZipStored([{ name: 'word/document.xml', data: draftUtf8('<w/>') }])]
].map(([name, bytes]) => ({ name, hex: draftHex(bytes), format: detectDraftFormat(new Uint8Array(bytes)) }));

/* Small cases carry their outputs whole; the parse corpus's cases name
   their source in parse.json and pin their outputs by SHA-256. */
const draftBridgeSources = [
	['sample', DRAFT_SAMPLE],
	['trailing-note', '[[First]]\n\nA line.\n\n[[Last]]\n'],
	['only-notes', '[[One]]\n\n[[Two]]\n']
];
const draftBridge = (source) => {
	const document = draftFromScreenplay(parseFountain(source, { emphasis: 'runs' }));
	const back = draftToScreenplay(document);
	return { document, back: serialiseFountain(back.screenplay), diagnostics: back.diagnostics };
};
const draftBridges = [
	...draftBridgeSources.map(([name, source]) => {
		const { document, back, diagnostics } = draftBridge(source);
		return { name, source, document: draftDocJson(document), back, diagnostics };
	}),
	...parseFixture.map((c) => {
		const { document, back, diagnostics } = draftBridge(c.source);
		const digest = (text) => sha256Hex(draftUtf8(text));
		return {
			name: `corpus-${c.name}`,
			corpus: c.name,
			scriptSha256: digest(canonicalJson(document.script)),
			notesSha256: document.notes === undefined ? null : digest(canonicalJson(document.notes)),
			backSha256: digest(back),
			diagnostics
		};
	})
];

const draftSha = [
	...Array.from({ length: 131 }, (_, n) => new Uint8Array(n).map((_, i) => (i * 31 + n) & 0xff)),
	draftUtf8('abc'),
	new Uint8Array(1000).fill(0x61)
].map((bytes) => ({ hex: draftHex(bytes), sha256: sha256Hex(bytes) }));

const draftContexts = [
	['The kettle screams. Mara doesn’t move.', 20, 37],
	['The quick brown foxes jump over it', 22, 26],
	['Unbroken', 2, 4],
	['A', 0, 1],
	['Tabs\tand\nlines around the words here', 14, 19]
].map(([text, start, end]) => ({ text, start, end, ...draftAnchorContext(text, start, end) }));

writeFixture('draft.json', {
	writer: DRAFT_WRITER,
	sha256: draftSha,
	json: {
		valid: draftJsonInputs.map((input) => {
			const tree = parseDraftJson(input);
			return { input, canonical: canonicalJson(tree), jcs: jcs(tree) };
		}),
		invalid: draftJsonInvalid
	},
	contexts: draftContexts,
	detect: draftDetect,
	bridges: draftBridges,
	write: draftWrites,
	read: draftReads
});

console.log('✓ conformance corpus written to apple/eDraftEngine/Fixtures/');
