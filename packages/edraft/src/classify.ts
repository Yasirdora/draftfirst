/**
 * Shared import classifier — turns raw lines lifted from a foreign document
 * (plain text, pasted prose, or a .docx extractor) into typed screenplay
 * elements, each with a confidence and a plain-language reason.
 *
 * Doctrine: the engine never guesses silently. Every verdict carries its
 * evidence ("why"), and low-confidence verdicts surface in the ImportReport
 * so the writer reviews exactly the lines we were unsure about — trust
 * through transparency, not magic.
 */

import type { ElementType, Screenplay, ScreenplayElement } from './types.js';
import { isPrinting } from './types.js';
import { stripCueExtensions } from './smarttype.js';
import { isActCard } from './acts.js';
import { parseNumberedSceneHeading } from './sceneheading.js';

/** One physical line lifted from a foreign document. */
export interface RawLine {
	/** Visible text, trimmed. */
	text: string;
	/** Left edge of the text in inches, when the source carries layout. */
	indentInches?: number;
	/** Paragraph alignment, when the source carries it. */
	align?: 'left' | 'right' | 'center';
	/** Source paragraph style name (e.g. a Word style), when present. */
	styleName?: string;
	/** True when no blank line separates this line from the previous content line. */
	attached?: boolean;
	/** True when a hard page break precedes this line. */
	pageBreak?: boolean;
}

export type ImportConfidence = 'high' | 'medium' | 'low';

/** A raw line with the engine's verdict. */
export interface ClassifiedLine {
	raw: RawLine;
	type: ElementType;
	confidence: ImportConfidence;
	/** Plain-language reason for the verdict — shown in the import review. */
	why: string;
}

/** A line the engine is unsure about; lineIndex indexes the classified array. */
export interface FlaggedLine {
	lineIndex: number;
	text: string;
	type: ElementType;
	confidence: ImportConfidence;
	why: string;
}

/** What the import produced, in numbers a writer can sanity-check. */
export interface ImportReport {
	format: string;
	lines: number;
	scenes: number;
	characters: string[];
	flagged: FlaggedLine[];
	warnings: string[];
}

/** The classified screenplay plus its report and the lines behind it. */
export interface ImportResult {
	script: Screenplay;
	report: ImportReport;
	/**
	 * The classified lines the report describes (flagged lineIndex values
	 * point here). Edit a line's type and re-run finalizeImport to apply a
	 * review override.
	 */
	classified: ClassifiedLine[];
}

/* compound forms first: INT./EXT., then the reversed hand six files write —
   EXT/INT. COURTHOUSE (emilia-perez ×5, manchester ×4, no-country ×3,
   whiplash ×3, pasted-26 ×3, episode-101 ×1) */
const SCENE_INTRO = /^(INT\.?\/EXT\.?|INT\/EXT|EXT\.?\/INT\.?|EXT\/INT|I\/E|INT|EXT|EST)[.\s]/i;
const FADE_OR_IRIS = /^(FADE (IN|OUT|TO)\b|IRIS (IN|OUT)\b)/i;
const SHOT_INTRO = /^(ANGLE ON|CLOSER? ON|CLOSEUP|INSERT|POV|WIDE( ON| SHOT)?|CRANE SHOT|TRACKING SHOT|AERIAL( SHOT)?|ESTABLISHING SHOT|SHOT)\b/;
/* The camera's own grammar beyond the prefix forms — the corpus's witness
   list: godfather-2's VIEW idiom (167 lines: VIEW ON X, MED. VIEW, CLOSE
   MOVING VIEW, MICHAEL'S VIEW, VIEW ALTERS), heat's ANGLE/POV cards (ANGLE -
   WAINGRO, CERRITO'S POV: JAMMING, 3/4 REAR SHOT), corpus-6's numbered
   angles (35A ANGLE, MOMENTS LATER. 35A), no-country's POINT-OF-VIEW THROUGH
   WINDSHIELD. Every family fired the cue arm before this rule existed, so
   these lines sat in cast lists and speeches alike; the arm must fire before
   speech position (rule 7) adopts them. */
const CAMERA_LINE = new RegExp(
	[
		/* ANGLE family: ANGLE, ANGLE - X, ANGLE, X, NEW/CLOSER/ANOTHER ANGLE …,
		   with a scene number's furniture allowed at the edge */
		String.raw`^(?:\d{1,3}[A-Z]?\s+)?(?:NEW |CLOSER |ANOTHER |REVERSE |WIDER )?ANGLE(?:\s+ON\b|\s+-|\s*,|$)`,
		/* the VIEW idiom: VIEW ON X (mid-line too — MOVING VIEW ON THE PRIEST),
		   VIEW THROUGH/BY/FROM/ACROSS X, VIEW ALTERS/MOVES/BEGINS — Godfather
		   II's own dialect */
		String.raw`\bVIEW\s+ON\b`,
		String.raw`^(?:THE )?VIEW\s+(?:THROUGH|BY|UP|FROM|ACROSS|INTO|OVER|ALTERS|MOVES|BEGINS|HOLDS|WIDENS|SHIFTS|TIGHTENS|CHANGES)\b`,
		String.raw`\bPOINT[- ]OF[- ]VIEW\b`,
		/* a possessive's framing: MOSS'S POV, MICHAEL'S VIEW */
		String.raw`\b[A-Z][A-Z.'-]*'S (?:VIEW|POV)\b`,
		String.raw`\bPOV\b`,
		/* the qualified SHOT, mid-line too: REAR SHOT - MAN, CLOSE - TWO SHOT */
		String.raw`\b(?:TWO|REAR|LONG|WIDE|FULL|MASTER|REVERSE|MOVING|TRACKING|CRANE|AERIAL|ESTABLISHING|CLOSE|MEDIUM|MED\.?|OVERHEAD) SHOT\b`,
		/* Godfather II's two remaining idioms: MED. CLOSE (ON X / - X), and the
		   WHAT HE SEES card (its colon twin reads as a label already) */
		String.raw`^(?:MED\.?|MEDIUM)\s+CLOSE(?:\s+ON\b|\s+-|$)`,
		String.raw`^WHAT\s+(?:HE|SHE|THEY)\s+SEES:?$`,
		/* the labelled frame — the framing word wears its colon: ECU: X,
		   CLOSE: HANNA, FRONTAL: HANNA, TIGHTER: CHRIS, VIDEO MONITOR: HANNA,
		   SIDE ANGLE: NEIL, REVERSE: BLACK + WHITE, OVER HANNA'S SHOULDER:
		   CERRITO'S (heat ×14 — they used to land in somebody's speech) */
		String.raw`^(?:ECU|CLOSER?|FRONTAL|TIGHTER|WIDER|HIGH \+ WIDE|VIDEO MONITOR|REVERSE|SIDE ANGLE)\s*:`,
		String.raw`^OVER\s+(?:[A-Z][A-Z']*\s+)?SHOULDERS?\s*:`,
		/* the dash twin of CLOSE ON: CLOSE - DRILL BIT, CLOSER - NEIL */
		String.raw`^CLOSER?\s+-`,
		/* the verb carries the frame without the noun: TRACKING HANNA */
		String.raw`^TRACKING\s+\S`,
		/* ends on the camera noun: MED. VIEW, CLOSE MOVING VIEW, LONG SHOT,
		   TWO SHOT, 3/4 REAR SHOT, REAR SHOTS, DANIEL'S POV, */
		String.raw`\b(?:VIEW|SHOTS?|ANGLE|POV),?$`
	].join('|')
);
/* A scene heading's time-of-day ending — the wrap tell for a heading whose
   source line broke before it. */
const HEADING_TIME_ENDING =
	/ - (DAY|NIGHT|DAWN|DUSK|MORNING|EVENING|LATER|CONTINUOUS|SAME|SAME TIME|MOMENTS LATER)$/;
/* The wrapped tail that carries it: all-caps, ends " - DAY" (godfather-2's
   "CORLEONE - DAY", heat's "PROFILE - DAY" ×5, corpus-1's OCR-spaced
   "- HAVENHURST - DAY" ×5). Never itself a new heading. */
const HEADING_TIME_TAIL =
	/^[A-Z0-9 .,'&()\-]+? - (DAY|NIGHT|DAWN|DUSK|MORNING|EVENING|LATER|CONTINUOUS|SAME|SAME TIME|MOMENTS LATER)$/;
const MAX_CUE_CHARACTERS = 42;
const TERMINAL_PUNCT = /[.!?…]$/;
/* a speech's last line closes a sentence — punctuation first, then any
   closing quotes or brackets riding its tail */
const TERMINAL_SENTENCE = /[.!?…]['"”’)]*$/;
const TRAILING_PARENS = /(\s*\([^()]*\)\s*)+$/;

/** Types whose wrapped continuation lines merge back into one element. */
const MERGEABLE: ReadonlySet<ElementType> = new Set(['action', 'dialogue', 'parenthetical']);

function isUppercaseForm(text: string): boolean {
	return /[A-Z]/.test(text) && !/[a-z]/.test(text);
}

/**
 * The shape of a character cue: uppercase, short, and no sentence-ending
 * punctuation once cue extensions like (V.O.) are stripped.
 */
function cueShape(text: string): boolean {
	if (!isUppercaseForm(text)) return false;
	const core = text.replace(TRAILING_PARENS, '').trim();
	if (core.length === 0 || core.length > MAX_CUE_CHARACTERS) return false;
	/* a speaker's name never carries a colon — colon lines are labels
	   ("SYNOPSIS: …", "SECTION HEADING: …"), not people */
	if (core.includes(':')) return false;
	return !TERMINAL_PUNCT.test(core);
}

/** Map a source paragraph style name to an element type, or undefined. */
function typeFromStyleName(styleName: string): ElementType | undefined {
	const key = styleName.toLowerCase().replace(/[^a-z]/g, '');
	if (key === '') return undefined;
	if (/scene|slug/.test(key)) return 'scene';
	if (/character|cue/.test(key)) return 'character';
	if (/parenthetical|paren|wryly/.test(key)) return 'parenthetical';
	if (/dialog/.test(key)) return 'dialogue';
	if (/transition/.test(key)) return 'transition';
	if (/shot/.test(key)) return 'shot';
	if (/action|description|narrative/.test(key)) return 'action';
	if (/center/.test(key)) return 'centered';
	if (/lyrics?/.test(key)) return 'lyrics';
	if (/general/.test(key)) return 'general';
	return undefined;
}

function verdict(raw: RawLine, type: ElementType, confidence: ImportConfidence, why: string): ClassifiedLine {
	return { raw, type, confidence, why };
}

/**
 * Classify one line. `prev` is the previous classified line when this one is
 * structurally near it; a cue is always followed by its speech, so the
 * character rule consults `prev` even across a blank line, while speech
 * continuation requires true attachment (no blank line between).
 */
function classifyLine(
	raw: RawLine,
	text: string,
	prev: ClassifiedLine | undefined,
	attached: boolean,
	speechEdge: number
): ClassifiedLine {
	/* 1. an explicit source style is the strongest evidence there is */
	if (raw.styleName !== undefined) {
		const styled = typeFromStyleName(raw.styleName);
		if (styled !== undefined) return verdict(raw, styled, 'high', `style "${raw.styleName}"`);
	}

	/* 2. scene headings announce themselves — bare, or carrying the scene
	   number a production draft prints at their left edge */
	if (SCENE_INTRO.test(text)) return verdict(raw, 'scene', 'high', 'opens with INT./EXT.');
	if (parseNumberedSceneHeading(text) !== undefined) {
		return verdict(raw, 'scene', 'high', 'numbered scene heading');
	}

	/* 2½. a wrapped heading's tail: the heading above never reached its
	   time-of-day and this attached line carries it. The fold happens at
	   assembly (toScreenplay); here the line answers to the heading, not to
	   the cue shape it wears. */
	if (
		attached &&
		prev?.type === 'scene' &&
		!HEADING_TIME_ENDING.test(prev.raw.text) &&
		isUppercaseForm(text) &&
		HEADING_TIME_TAIL.test(text)
	) {
		return verdict(raw, 'scene', 'high', "a wrapped heading's time-of-day tail");
	}

	/* 3. an act card announces itself — the canonical spelling or one of
	   television's unnumbered openers (RFC-ACT-BREAK §5). Without this arm
	   the cue shape below adopts ACT ONE as a speaker. */
	if (isActCard(text)) return verdict(raw, 'actbreak', 'high', 'act card');

	/* 4. transitions: uppercase ending "TO:", or the unambiguous FADE/IRIS family */
	const uppercase = isUppercaseForm(text);
	if ((uppercase && text.endsWith('TO:')) || FADE_OR_IRIS.test(text)) {
		return verdict(raw, 'transition', 'high', 'transition shape');
	}

	/* 5. uppercase camera framing is a shot designation, never a speaker */
	if (uppercase && (SHOT_INTRO.test(text) || CAMERA_LINE.test(text))) {
		return verdict(raw, 'shot', 'medium', 'camera framing reads as a shot');
	}

	/* 6. a fully bracketed line reads as a parenthetical */
	if (text.startsWith('(') && text.endsWith(')')) {
		return verdict(raw, 'parenthetical', 'medium', 'a line in brackets reads as a parenthetical');
	}

	/* 7. speech position: after a cue, text is what the character says. A
	   parenthetical only exists inside a speech, so what follows it is
	   speech too — only continuing a finished speech needs true attachment.
	   An explicitly centered line answers to its alignment, never to speech
	   position: a title card under a cue is a card, not a dangling speech. */
	if (raw.align !== 'center' && prev?.type === 'character') {
		return verdict(raw, 'dialogue', attached ? 'high' : 'medium', 'follows the character cue');
	}
	if (raw.align !== 'center' && prev?.type === 'parenthetical') {
		return verdict(raw, 'dialogue', 'medium', 'follows the parenthetical');
	}
	if (attached && prev?.type === 'dialogue' && raw.align !== 'center') {
		/* pasted streams carry no blank lines, so an uppercase cue-shaped
		   line inside a speech run is a new speaker far more often than a
		   shouted continuation — shouts keep their terminal punctuation */
		if (cueShape(text)) {
			return verdict(raw, 'character', 'medium', 'uppercase cue interrupts the speech above it');
		}
		/* The edge tell (lalaland ×3 pinned below; the user saw it in other
		   scripts too). A hard-wrapped source preserves two print columns:
		   dialogue wraps narrow (every corpus file's dialogue column is
		   ≤ 43 once cue-shaped furniture is excluded) and action wide
		   (54–66). A line that runs past both the narrow-column ceiling and
		   the speech's own running edge is action rejoining the left margin,
		   not more speech. The 46 floor protects a short-opened speech
		   ("Shit." then a ≤46 continuation); the +6 absorbs the jitter of
		   proportional words in a fixed column. Three guards keep the tell
		   honest where geometry alone lies:
		   — a speech boundary falls at a sentence boundary: the speech's
		     last line must close with terminal punctuation;
		   — a parenthetical-led line is speech furniture, however wide
		     (emilia-perez's "(yelling) Hey guys…" ×13);
		   — a lowercase or inverted-mark opening continues a sentence, so
		     it belongs with the line above, whichever column that was.
		   The residue this cannot see: translation-paired dialogue that
		   wraps past the dialogue column (emilia-perez's pleas, 50–57) is
		   geometrically identical to action, and stays fused. */
		if (text.length <= 46 || text.length <= speechEdge + 6) {
			return verdict(raw, 'dialogue', 'medium', 'continues the speech');
		}
		if (!TERMINAL_SENTENCE.test(prev.raw.text) || /^[a-z¿¡(]/.test(text)) {
			return verdict(raw, 'dialogue', 'medium', 'continues the speech');
		}
		/* falls through: wider than the speech above it ever ran */
	}

	/* 8. explicit alignment — cues never sit right or centered */
	if (raw.align === 'center') return verdict(raw, 'centered', 'high', 'centered');
	if (raw.align === 'right') return verdict(raw, 'transition', 'medium', 'right-aligned');

	/* 9. far-right layout is transition position */
	const indent = raw.indentInches ?? 0;
	if (indent >= 5) return verdict(raw, 'transition', 'medium', `far-right indent of ${indent}"`);

	/* 10. the uppercase cue shape — layout only decides how sure we are */
	if (cueShape(text)) {
		if (indent >= 1.5) {
			return verdict(raw, 'character', 'high', `uppercase cue at a ${indent}" indent`);
		}
		return verdict(raw, 'character', 'medium', 'uppercase cue shape');
	}

	/* 11. a bare middle indent is speech layout with no other signal — a guess */
	if (indent >= 0.7) return verdict(raw, 'dialogue', 'low', `indented ${indent}" — reads as speech`);

	/* 12. directly under a heading or a shot, prose describes what we see */
	if (prev?.type === 'scene') return verdict(raw, 'action', 'high', 'describes the scene above it');
	if (prev?.type === 'shot') return verdict(raw, 'action', 'high', 'describes what the shot frames');

	/* 13. prose is action */
	return verdict(raw, 'action', 'medium', 'no stronger signal — treated as action');
}

/* Cue confirmation: what ends a cue's candidacy outright. A cue directly
   above one of these was never introducing speech — the line below it has a
   structure of its own. */
const CUE_ENDING_FOLLOWER: ReadonlySet<ElementType> = new Set(['scene', 'transition', 'actbreak', 'centered', 'shot']);

/* The widest a wrapped dialogue column is witnessed to run (the edge tell's
   constant, rule 7): past it, a "speech" line is prose. */
const SPEECH_COLUMN_CEILING = 46;

/**
 * Cue confirmation. A pasted cue keeps its character only when speech
 * follows it. The cue shape is cheap to fake — every season card ("WINTER",
 * lalaland ×2), time card ("SEVEN YEARS AGO --", manchester ×29), subject
 * slug ("ON STAGE", whiplash ×4; "MOSS" mid-action, no-country ×5), and
 * title-page line is uppercase and short — so shape alone is an application,
 * and the speech beneath it is the interview. Two failures rescind it:
 *
 *   structural — the next line is a heading, transition, act card, centered
 *     card or shot, or nothing at all ("THE END" at the document's end). A
 *     cue introduces speech; these are not speech.
 *
 *   wide block — a "speech" follows, but it runs prose-wide: its first line
 *     outruns the dialogue column without ending a sentence or opening as a
 *     sentence's continuation, and either its second line runs just as wide
 *     (two prose lines — WINTER's "We settle on a new car…" 54/61) or the
 *     block ends and a structural line or the document's end cuts it off
 *     (WINTER's other card, "A palm tree…" 60/14 before EXT. STUDIO LOT; a
 *     single wide line is also cut off by the next cue — cast-table rows
 *     with wide description text, episode-101's MAID).
 *
 * The escapes are where geometry alone lies, each corpus-witnessed: a wide
 * line that closes its sentence is a complete utterance (breaking-bad's
 * HANK, 51 wide, ends "."); a wide line opening lowercase, bracketed,
 * inverted-marked or with an ellipsis continues a sentence from above
 * (corpus-6's ELI, 52 wide, opens "…"); a fused scan line with a narrow
 * second line is one long breath, not prose (whiplash's STUDIO CORE MEMBER
 * #3, 75 then 19). What the rule cannot see stays and is named: a card whose
 * follower wraps short ("FALL" over "Silence." — one narrow word is a real
 * speech's exact shape) and the title page's own name ("LA LA LAND" over
 * "by" — a title page is the deferred RFC's ground, not this rule's). A
 * cast table's name rows answer to the same speech test as everything
 * else: a second cue-shaped line directly under a cue classifies as its
 * speech (rule 7 answers to position first), so a bare row over a narrow
 * name survives (TRAVIS MARTINEZ over CODY, episode-101) and a row over a
 * wide dotted-leader description does not (MAID) — both are the table's
 * own residue, kept honest rather than hidden.
 *
 * Demotion converts the cue and its whole attached block — parentheticals
 * and dialogue lines — to action: the words all survive, only the false
 * speaker leaves the cast. A cue an explicit source style named (the DOCX
 * route) is flagged by the confidence rules above, never retyped here.
 */
function confirmCues(classified: ClassifiedLine[]): void {
	for (let i = 0; i < classified.length; i++) {
		const cue = classified[i];
		if (cue === undefined || cue.type !== 'character' || cue.raw.styleName !== undefined) continue;
		const next = classified[i + 1];

		let why: string | undefined;
		let block: ClassifiedLine[] = [];
		if (next === undefined) {
			why = 'the document ends under it — a card, not a speaker';
		} else if (CUE_ENDING_FOLLOWER.has(next.type)) {
			why = `no speech beneath it — a ${next.type} follows`;
		} else {
			/* a cue-shaped line directly under a cue classified as its speech
			   (rule 7 answers to position first), so the block scan below also
			   covers the cast table's name rows */
			for (let j = i + 1; j < classified.length; j++) {
				const member = classified[j];
				if (member === undefined || (member.type !== 'dialogue' && member.type !== 'parenthetical')) break;
				block.push(member);
			}
			const speech = block.filter((member) => member.type === 'dialogue');
			if (speech.length === 0) continue; /* brackets and no words — no corpus witness; left flagged */
			const first = speech[0]?.raw.text ?? '';
			const wide =
				first.length > SPEECH_COLUMN_CEILING &&
				!TERMINAL_SENTENCE.test(first) &&
				!/^[.…a-z¿¡(]/.test(first);
			if (!wide) continue;
			const after = classified[i + 1 + block.length];
			const cutOff = after === undefined || CUE_ENDING_FOLLOWER.has(after.type);
			const secondWide = (speech[1]?.raw.text.length ?? 0) > SPEECH_COLUMN_CEILING;
			if (secondWide) {
				why = `the speech under it runs prose-wide (${first.length}/${speech[1]?.raw.text.length}) — a card or a slug, not a speaker`;
			} else if (cutOff || (speech.length === 1 && after?.type === 'character')) {
				why = `one wide line under it (${first.length}), then the thought is cut — a card or a slug, not a speaker`;
			} else {
				continue;
			}
		}

		cue.type = 'action';
		cue.confidence = 'low';
		cue.why = `uppercase cue shape, but ${why} — treated as action`;
		for (const member of block) {
			member.type = 'action';
			member.confidence = 'low';
			member.why = `the cue above it was no speaker — treated as action`;
		}
	}
}

/**
 * Context repair pass. Classification is per-line; this pass checks each
 * verdict against its neighbours and downgrades (never upgrades past the
 * evidence) the structurally impossible ones.
 */
function repairContext(classified: ClassifiedLine[]): ClassifiedLine[] {
	for (let i = 0; i < classified.length; i++) {
		const line = classified[i];
		const prev = i > 0 ? classified[i - 1] : undefined;
		const next = i + 1 < classified.length ? classified[i + 1] : undefined;

		if (line === undefined) continue;

		/* a transition directly followed by a scene is nearly always right */
		if (line.type === 'transition' && next?.type === 'scene' && line.confidence !== 'high') {
			line.confidence = 'high';
			line.why += ' — a scene follows it';
		}

		/* a parenthetical only exists inside a speech */
		if (
			line.type === 'parenthetical' &&
			(prev === undefined || (prev.type !== 'character' && prev.type !== 'parenthetical' && prev.type !== 'dialogue'))
		) {
			if (line.raw.styleName !== undefined) {
				line.confidence = 'low';
				line.why = `style "${line.raw.styleName}" says parenthetical, but no speech sits above it`;
			} else {
				line.type = 'action';
				line.confidence = 'low';
				line.why = 'brackets outside a speech — treated as action';
			}
		}

		/* speech with no speaker above it */
		if (line.type === 'dialogue' && prev?.type === 'scene') {
			line.confidence = 'low';
			line.why = 'speech with no speaker above it';
		}

		/* a cue with no speech beneath it */
		if (
			line.type === 'character' &&
			(next === undefined || (next.type !== 'parenthetical' && next.type !== 'dialogue'))
		) {
			line.confidence = 'low';
			line.why = 'cue with no speech beneath it';
		}
	}
	confirmCues(classified);
	return classified;
}

/**
 * Classify raw lines into typed elements. Blank lines carry no meaning in
 * the element model and are dropped; attachment between lines is read from
 * `raw.attached`, which the source extractor is responsible for setting.
 */
export function classifyLines(rawLines: readonly RawLine[]): ClassifiedLine[] {
	const classified: ClassifiedLine[] = [];
	/* the running right edge of the speech in progress — the edge tell in
	   rule 7 measures a rejoining action line against it */
	let speechEdge = 0;
	for (const raw of rawLines) {
		const text = raw.text.trim();
		if (text === '') continue;
		const prev = classified[classified.length - 1];
		const attached = raw.attached === true && prev !== undefined;
		const line = classifyLine(raw, text, prev, attached, speechEdge);
		classified.push(line);
		if (line.type === 'dialogue') {
			speechEdge =
				prev?.type === 'character' || prev?.type === 'parenthetical'
					? text.length
					: Math.max(speechEdge, text.length);
		} else {
			speechEdge = 0;
		}
	}
	return repairContext(classified);
}

/**
 * Build the screenplay from classified lines. Wrapped continuation lines
 * (attached, same mergeable type) fold back into one element; hard page
 * breaks become structural pagebreak elements.
 */
export function toScreenplay(classified: readonly ClassifiedLine[]): Screenplay {
	const elements: ScreenplayElement[] = [];
	for (const line of classified) {
		if (line.raw.pageBreak === true) elements.push({ type: 'pagebreak', text: '' });
		const prev = elements[elements.length - 1];
		/* a wrapped heading's tail folds into the heading it completes: the
		   heading never reached its time-of-day and this attached line
		   carries it — one scene element, whatever column the tail sat at
		   (the classify arm types it scene; only the fold needs the same
		   evidence again so a bare back-to-back heading never merges) */
		if (
			line.raw.attached === true &&
			prev !== undefined &&
			prev.type === 'scene' &&
			line.type === 'scene' &&
			!SCENE_INTRO.test(line.raw.text) &&
			!HEADING_TIME_ENDING.test(prev.text) &&
			HEADING_TIME_TAIL.test(line.raw.text)
		) {
			prev.text = `${prev.text} ${line.raw.text}`;
			continue;
		}
		if (line.raw.attached === true && prev !== undefined && prev.type === line.type && MERGEABLE.has(line.type)) {
			prev.text = `${prev.text} ${line.raw.text}`;
			continue;
		}
		const element: ScreenplayElement = { type: line.type, text: line.raw.text };
		if (line.type === 'scene') {
			/* the number a production draft prints at the edge is furniture
			   with a home — sceneNumber — not part of the writer's heading */
			const numbered = parseNumberedSceneHeading(element.text);
			if (numbered !== undefined) {
				element.text = numbered.text;
				if (numbered.number !== undefined) element.sceneNumber = numbered.number;
			}
		}
		elements.push(element);
	}
	return { titlePage: [], elements };
}

/**
 * Package a classified import for the review sheet: the screenplay plus a
 * report of counts, the character list, warnings, and the low-confidence
 * lines a writer should glance at before committing.
 */
export function finalizeImport(
	classified: readonly ClassifiedLine[],
	format: string,
	warnings: readonly string[]
): ImportResult {
	const script = toScreenplay(classified);
	const characters: string[] = [];
	const seen = new Set<string>();
	let scenes = 0;
	let lines = 0;
	for (const element of script.elements) {
		if (!isPrinting(element.type)) continue;
		lines++;
		if (element.type === 'scene') scenes++;
		if (element.type === 'character') {
			const name = stripCueExtensions(element.text).toUpperCase();
			if (name !== '' && !seen.has(name)) {
				seen.add(name);
				characters.push(name);
			}
		}
	}
	const flagged: FlaggedLine[] = [];
	classified.forEach((line, lineIndex) => {
		if (line.confidence === 'low') {
			flagged.push({
				lineIndex,
				text: line.raw.text,
				type: line.type,
				confidence: line.confidence,
				why: line.why
			});
		}
	});
	return {
		script,
		report: { format, lines, scenes, characters, flagged, warnings: [...warnings] },
		classified: [...classified]
	};
}
