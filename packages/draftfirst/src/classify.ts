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

const SCENE_INTRO = /^(INT\.?\/EXT\.?|INT\/EXT|I\/E|INT|EXT|EST)[.\s]/i;
const FADE_OR_IRIS = /^(FADE (IN|OUT|TO)\b|IRIS (IN|OUT)\b)/i;
const SHOT_INTRO = /^(ANGLE ON|CLOSER? ON|CLOSEUP|INSERT|POV|WIDE( ON| SHOT)?|CRANE SHOT|TRACKING SHOT|AERIAL( SHOT)?|ESTABLISHING SHOT|SHOT)\b/;
const MAX_CUE_CHARACTERS = 42;
const TERMINAL_PUNCT = /[.!?…]$/;
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
function classifyLine(raw: RawLine, text: string, prev: ClassifiedLine | undefined, attached: boolean): ClassifiedLine {
	/* 1. an explicit source style is the strongest evidence there is */
	if (raw.styleName !== undefined) {
		const styled = typeFromStyleName(raw.styleName);
		if (styled !== undefined) return verdict(raw, styled, 'high', `style "${raw.styleName}"`);
	}

	/* 2. scene headings announce themselves */
	if (SCENE_INTRO.test(text)) return verdict(raw, 'scene', 'high', 'opens with INT./EXT.');

	/* 3. transitions: uppercase ending "TO:", or the unambiguous FADE/IRIS family */
	const uppercase = isUppercaseForm(text);
	if ((uppercase && text.endsWith('TO:')) || FADE_OR_IRIS.test(text)) {
		return verdict(raw, 'transition', 'high', 'transition shape');
	}

	/* 4. uppercase camera framing is a shot designation, never a speaker */
	if (uppercase && SHOT_INTRO.test(text)) {
		return verdict(raw, 'shot', 'medium', 'camera framing reads as a shot');
	}

	/* 5. a fully bracketed line reads as a parenthetical */
	if (text.startsWith('(') && text.endsWith(')')) {
		return verdict(raw, 'parenthetical', 'medium', 'a line in brackets reads as a parenthetical');
	}

	/* 6. speech position: after a cue, text is what the character says. A
	   parenthetical only exists inside a speech, so what follows it is
	   speech too — only continuing a finished speech needs true attachment. */
	if (prev?.type === 'character') {
		return verdict(raw, 'dialogue', attached ? 'high' : 'medium', 'follows the character cue');
	}
	if (prev?.type === 'parenthetical') {
		return verdict(raw, 'dialogue', 'medium', 'follows the parenthetical');
	}
	if (attached && prev?.type === 'dialogue') {
		/* pasted streams carry no blank lines, so an uppercase cue-shaped
		   line inside a speech run is a new speaker far more often than a
		   shouted continuation — shouts keep their terminal punctuation */
		if (cueShape(text)) {
			return verdict(raw, 'character', 'medium', 'uppercase cue interrupts the speech above it');
		}
		return verdict(raw, 'dialogue', 'medium', 'continues the speech');
	}

	/* 7. explicit alignment — cues never sit right or centered */
	if (raw.align === 'center') return verdict(raw, 'centered', 'high', 'centered');
	if (raw.align === 'right') return verdict(raw, 'transition', 'medium', 'right-aligned');

	/* 8. far-right layout is transition position */
	const indent = raw.indentInches ?? 0;
	if (indent >= 5) return verdict(raw, 'transition', 'medium', `far-right indent of ${indent}"`);

	/* 9. the uppercase cue shape — layout only decides how sure we are */
	if (cueShape(text)) {
		if (indent >= 1.5) {
			return verdict(raw, 'character', 'high', `uppercase cue at a ${indent}" indent`);
		}
		return verdict(raw, 'character', 'medium', 'uppercase cue shape');
	}

	/* 10. a bare middle indent is speech layout with no other signal — a guess */
	if (indent >= 0.7) return verdict(raw, 'dialogue', 'low', `indented ${indent}" — reads as speech`);

	/* 11. directly under a heading or a shot, prose describes what we see */
	if (prev?.type === 'scene') return verdict(raw, 'action', 'high', 'describes the scene above it');
	if (prev?.type === 'shot') return verdict(raw, 'action', 'high', 'describes what the shot frames');

	/* 12. prose is action */
	return verdict(raw, 'action', 'medium', 'no stronger signal — treated as action');
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
	return classified;
}

/**
 * Classify raw lines into typed elements. Blank lines carry no meaning in
 * the element model and are dropped; attachment between lines is read from
 * `raw.attached`, which the source extractor is responsible for setting.
 */
export function classifyLines(rawLines: readonly RawLine[]): ClassifiedLine[] {
	const classified: ClassifiedLine[] = [];
	for (const raw of rawLines) {
		const text = raw.text.trim();
		if (text === '') continue;
		const prev = classified[classified.length - 1];
		const attached = raw.attached === true && prev !== undefined;
		classified.push(classifyLine(raw, text, prev, attached));
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
		if (line.raw.attached === true && prev !== undefined && prev.type === line.type && MERGEABLE.has(line.type)) {
			prev.text = `${prev.text} ${line.raw.text}`;
			continue;
		}
		elements.push({ type: line.type, text: line.raw.text });
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
