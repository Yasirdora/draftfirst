/**
 * eDraft Screenwriting Engine Fountain serializer.
 *
 * Emits standards-compatible Fountain. Forcing syntax (`!`, `.`, `>`, `@`) is
 * used only when plain text would otherwise parse as a different element.
 *
 * Spacing rule: dialogue-flow elements (character → parenthetical → dialogue)
 * stay glued without blank lines; every other block is blank-line separated.
 *
 * Semantic round-trip fidelity: recognised uppercase shot language survives;
 * `general` and unrecognised shot phrasing degrade to action because Fountain
 * has no native lane for either type. Exact arbitrary source whitespace is not
 * represented by the current document model and is therefore canonicalized.
 */

import type { AnyElementType, Screenplay, ScreenplayElement } from './types.js';
import { deriveTitlePage } from './titlepage.js';
import { synthesiseEmphasis } from './style.js';

const SCENE_DETECT = /^(INT|EXT|EST|INT\.\/EXT|INT\/EXT|I\/E)([. ]|\.\/)/i;
const TRANSITION_DETECT = /^[A-Z0-9 '()&.,/-]+ TO:$/;
/* Matches the parser: canonical openers/closers print bare, never forced. */
const FADE_OPENER = /^FADE (IN|OUT|TO BLACK|TO WHITE)[.:]?$/;

const SHOT_LEADS = [
	'ANGLE ON', 'CLOSE ON', 'CLOSEUP ON', 'CLOSEUP', 'POV', 'INSERT',
	'WIDE SHOT', 'TWO SHOT', 'TRACKING SHOT', 'AERIAL SHOT', 'CRANE SHOT',
	'STEADICAM SHOT', 'HANDHELD SHOT'
];

const FLOW: ReadonlySet<AnyElementType> = new Set([
	'character',
	'parenthetical',
	'dialogue'
]);

function hasLower(text: string): boolean {
	return /[a-z]/.test(text);
}

function isUpper(text: string): boolean {
	return /[A-Z]/.test(text) && !hasLower(text);
}

function looksLikeShot(text: string): boolean {
	if (!isUpper(text)) return false;
	const up = text.toUpperCase();
	return SHOT_LEADS.some((lead) => up === lead || up.startsWith(`${lead} `)) || / SHOT$/.test(up);
}

function mustForceCharacter(text: string): boolean {
	return (
		!isUpper(text) ||
		SCENE_DETECT.test(text) ||
		TRANSITION_DETECT.test(text) ||
		looksLikeShot(text) ||
		/^[.@!~>#=([]/.test(text)
	);
}

function escapeForcedTransition(text: string): string {
	/* Without this escape, `> SOME TEXT <` reparses as centered text. */
	return text.endsWith('<') ? `${text.slice(0, -1)}\\<` : text;
}

/**
 * A note's text, spelled so its only `]]` is the close: a space between every
 * two adjacent `]`, and one before the close when the text ends in `]`. The
 * reader trims that space and reads `] ]` back as `]]`. Text with neither is
 * written as it is.
 */
function noteBody(body: string): string {
	const spaced = body.replace(/\](?=\])/g, '] ');
	return spaced.endsWith(']') ? `${spaced} ` : spaced;
}

/** Render one element as its Fountain source line. */
export function elementToFountain(el: ScreenplayElement): string {
	/* Classification reads el.text — marker-free content — so markers can
	   never hijack an element type; emission uses body, content with its
	   style runs synthesised back into boundary markers. Known limit: a
	   scene that needs the forcing `.` AND starts with a styled character
	   cannot round-trip (Fountain requires an alphanumeric after the dot) —
	   recorded as an accepted Fountain-boundary loss. */
	const body = el.runs && el.runs.length > 0 ? synthesiseEmphasis(el.text, el.runs) : el.text;
	switch (el.type) {
		case 'scene': {
			const num = el.sceneNumber ? ` #${el.sceneNumber}#` : '';
			/* Force scene headings that the standard detector cannot recognize. */
			const head = SCENE_DETECT.test(el.text) ? body : `.${body}`;
			return head + num;
		}
		case 'character': {
			/* Force any cue that collides with another Fountain classifier. */
			const cue = body + (el.dual ? ' ^' : '');
			return mustForceCharacter(el.text) ? `@${cue}` : cue;
		}
		case 'dialogue':
			/* Fountain's connected blank dialogue line is exactly two spaces. */
			return el.text === '' ? '  ' : body;
		case 'parenthetical':
			return body;
		case 'transition': {
			return (TRANSITION_DETECT.test(el.text) || FADE_OPENER.test(el.text)) && isUpper(el.text)
				? body
				: `> ${escapeForcedTransition(body)}`;
		}
		case 'centered':
			return `> ${body} <`;
		case 'actbreak':
			/* Fountain has no act spelling; the centred card prints correctly
			   everywhere and re-imports as centered — the named degradation,
			   RFC-ACT-BREAK §3. The paste route is smarter than the format. */
			return `> ${body} <`;
		case 'lyrics':
			return `~ ${body}`;
		case 'shot':
			/* Fountain has no shot type. eDraft recognises isolated uppercase
			   shot phrases; keeping `!` exclusively for Action avoids ambiguity. */
			return body.replace(/\t/g, '    ');
		case 'general':
		case 'action': {
			const text = body.replace(/\t/g, '    ');
			const classified = el.text.trim();
			/* Force action when the plain line would parse as another element. */
			const risky =
				SCENE_DETECT.test(classified) ||
				isUpper(classified) ||
				/^[.@!~>#=([]/.test(classified) ||
				classified === '' ||
				/^={3,}$/.test(classified);
			return risky ? `!${text}` : text;
		}
		case 'note':
			return `[[${noteBody(body)}]]`;
		case 'section': {
			const depth = Math.max(1, el.depth ?? 1);
			return `${'#'.repeat(depth)} ${body}`;
		}
		case 'synopsis':
			return `= ${body}`;
		case 'pagebreak':
			return '===';
	}
}

export function serialiseFountain(script: Screenplay): string {
	const out: string[] = [];

	/* Fountain's title page is Key: value lines, so the line model derives
	   its keys (RFC-TITLE-PAGE D7); derivation's fold rule means no line is
	   ever dropped here. Emission follows the page's own order — the stack,
	   extras in appearance order, contact last — so serialise → parse is a
	   fixed point in key order as well as in content. */
	const derived = deriveTitlePage(script.titlePage);
	const pick = (key: string): typeof derived =>
		derived.filter((entry) => entry.key.toLowerCase() === key);
	const special = new Set(['title', 'credit', 'author', 'contact']);
	const titleEntries = [
		...pick('title'),
		...pick('credit'),
		...pick('author'),
		...derived.filter((entry) => !special.has(entry.key.toLowerCase())),
		...pick('contact')
	];
	if (titleEntries.length > 0) {
		for (const entry of titleEntries) {
			out.push(`${entry.key}: ${entry.values[0] ?? ''}`);
			for (const v of entry.values.slice(1)) out.push(`   ${v}`);
		}
		out.push('');
	}

	let prev: AnyElementType | null = null;
	for (const el of script.elements) {
		/*
		 * Glue only WITHIN one speech block (cue → parenthetical → dialogue).
		 * A new character cue must always be blank-line separated: glued to the
		 * previous dialogue it would reparse as dialogue text (Fountain spec).
		 */
		const glued =
			FLOW.has(el.type) &&
			el.type !== 'character' &&
			prev !== null &&
			FLOW.has(prev);
		if (!glued && out.length > 0 && out[out.length - 1] !== '') out.push('');
		out.push(elementToFountain(el));
		prev = el.type;
	}

	return out.join('\n').replace(/\n+$/, '\n');
}
