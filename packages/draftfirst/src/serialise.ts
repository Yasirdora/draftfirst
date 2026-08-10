/**
 * Draft First Screenwriting Engine Fountain serializer.
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

/** Render one element as its Fountain source line. */
export function elementToFountain(el: ScreenplayElement): string {
	switch (el.type) {
		case 'scene': {
			const num = el.sceneNumber ? ` #${el.sceneNumber}#` : '';
			/* Force scene headings that the standard detector cannot recognize. */
			const head = SCENE_DETECT.test(el.text) ? el.text : `.${el.text}`;
			return head + num;
		}
		case 'character': {
			/* Force any cue that collides with another Fountain classifier. */
			const cue = el.text + (el.dual ? ' ^' : '');
			return mustForceCharacter(el.text) ? `@${cue}` : cue;
		}
		case 'dialogue':
			/* Fountain's connected blank dialogue line is exactly two spaces. */
			return el.text === '' ? '  ' : el.text;
		case 'parenthetical':
			return el.text;
		case 'transition': {
			return (TRANSITION_DETECT.test(el.text) || FADE_OPENER.test(el.text)) && isUpper(el.text)
				? el.text
				: `> ${escapeForcedTransition(el.text)}`;
		}
		case 'centered':
			return `> ${el.text} <`;
		case 'lyrics':
			return `~ ${el.text}`;
		case 'shot':
			/* Fountain has no shot type. Draft First recognises isolated uppercase
			   shot phrases; keeping `!` exclusively for Action avoids ambiguity. */
			return el.text.replace(/\t/g, '    ');
		case 'general':
		case 'action': {
			const text = el.text.replace(/\t/g, '    ');
			const classified = text.trim();
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
			return `[[${el.text}]]`;
		case 'section': {
			const depth = Math.max(1, el.depth ?? 1);
			return `${'#'.repeat(depth)} ${el.text}`;
		}
		case 'synopsis':
			return `= ${el.text}`;
		case 'pagebreak':
			return '===';
	}
}

export function serialiseFountain(script: Screenplay): string {
	const out: string[] = [];

	if (script.titlePage.length > 0) {
		for (const entry of script.titlePage) {
			if (entry.values.length === 0) {
				out.push(`${entry.key}:`);
			} else {
				out.push(`${entry.key}: ${entry.values[0]}`);
				for (const v of entry.values.slice(1)) out.push(`   ${v}`);
			}
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
