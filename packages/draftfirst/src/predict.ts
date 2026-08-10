/**
 * Draft First Screenwriting Engine contextual predictions.
 *
 * Ranks deterministic suggestions from scene participants, recent dialogue,
 * document vocabulary, scene transitions, and open screenplay structures.
 */

import type { ElementType, Screenplay, ScreenplayElement } from './types.js';
import {
	collectSmartType,
	SCENE_TIME_VALUES,
	stripCueExtensions,
	splitSceneHeading
} from './smarttype.js';

export interface PredictContext {
	/** Element type of the block being edited. */
	type: ElementType;
	/** Current text of that block. */
	text: string;
	/** Index of the block in the element stream. */
	index: number;
}

export interface Prediction {
	/** The full candidate text (e.g. 'MARA', 'KITCHEN', '(V.O.)'). */
	text: string;
	/** Human-readable explanation for the ranking. */
	why: string;
	/** Accepting this converts the block to a different element type. */
	becomes?: ElementType;
	/** A shape hint teaches the form of an element; it is never committed. */
	hint?: boolean;
}

const SCENE_PREFIXES = ['INT. ', 'EXT. ', 'INT./EXT. ', 'EST. ', 'I/E '];

const TIMES = SCENE_TIME_VALUES;

/** Heading modifiers accepted after a scene time. */
const SLUG_MODIFIERS = ['ESTABLISHING', 'STOCK', 'AERIAL', 'ARCHIVE'];

const COMMON_TRANSITIONS = [
	'CUT TO:', 'HARD CUT TO:', 'SMASH CUT TO:', 'MATCH CUT TO:', 'JUMP CUT TO:', 'FLIP CUT TO:',
	'DISSOLVE TO:', 'CROSS DISSOLVE TO:',
	'FADE IN:', 'FADE OUT.', 'FADE TO BLACK.', 'FADE TO WHITE.',
	'PRE-LAP', 'SOUND CUT', 'AUDIO DISSOLVE',
	'WIPE TO:', 'IRIS OUT', 'IRIS IN',
	'INTERCUT:', 'INTERCUT WITH:'
];

/**
 * Conventional cue extensions in display order. `(CONT'D)` is derived from
 * scene context and is therefore excluded from this static list.
 */
const COMMON_EXTENSIONS = [
	'(V.O.)', '(O.S.)', '(O.C.)', '(SUBTITLE)', '(PRE-LAP)', '(FILTERED)'
];

/** Default parenthetical suggestions. */
const COMMON_WRYLIES = [
	'(beat)', '(quietly)', '(then)', '(under her breath)', '(to himself)',
	'(whispering)', '(sarcastic)', '(off that)', '(re: the note)'
];

const COMMON_SHOTS = [
	'ANGLE ON', 'CLOSE ON', 'POV', 'INSERT', 'WIDE SHOT', 'TWO SHOT',
	'TRACKING SHOT', 'AERIAL SHOT', 'CRANE SHOT'
];

/** Recognized structure-opening and structure-closing pairs. */
const STRUCTURE_PAIRS: Array<[string, string]> = [
	['MONTAGE', 'END OF MONTAGE'],
	['SERIES OF SHOTS', 'END OF SERIES OF SHOTS'],
	['FLASHBACK', 'END FLASHBACK'],
	['DREAM SEQUENCE', 'END OF DREAM SEQUENCE'],
	['INTERCUT', 'END INTERCUT'],
	['PRELAP', 'END PRELAP']
];

/** Standalone slug/structure lines offered in scene position. */
const SPECIAL_SLUGS = [
	'MONTAGE', 'SERIES OF SHOTS', 'FLASHBACK', 'DREAM SEQUENCE', 'INTERCUT',
	'FADE IN:', 'SUPER:', 'TITLE CARD:', 'SMASH TO BLACK.'
];

const SCENE_HEAD_RE = /^\s*(INT|EXT|EST|INT\.?\/EXT|INT\/EXT|I\/E)[\.\s]/i;
const EXT_RE = /\s*\(((?:V\.?O\.?|O\.?S\.?|O\.?C\.?|CONT['’]?D|SUBTITLE|PRE-?LAP|FILTERED))\)\s*$/i;

function pushUnique(list: string[], value: string): void {
	if (value !== '' && !list.includes(value)) list.push(value);
}

/** Clamp an external block index to the element stream. */
function clampIndex(elements: ScreenplayElement[], beforeIndex: number): number {
	if (beforeIndex === Number.POSITIVE_INFINITY) return elements.length;
	if (!Number.isFinite(beforeIndex)) return 0;
	return Math.max(0, Math.min(Math.trunc(beforeIndex), elements.length));
}

function prefixHits(pool: readonly string[], prefix: string, cap = 8): string[] {
	if (prefix === '') return [];
	return pool.filter((x) => x.startsWith(prefix) && x !== prefix).slice(0, cap);
}

/* ---- scene memory ------------------------------------------------------- */

/**
 * Characters who have spoken in the scene containing `beforeIndex`
 * (everything since the most recent scene heading), first-appearance order,
 * extensions stripped: [ELIAS, MARA].
 */
export function sceneCharacters(elements: ScreenplayElement[], beforeIndex: number): string[] {
	const n = clampIndex(elements, beforeIndex);
	let start = 0;
	for (let i = n - 1; i >= 0; i--) {
		if (elements[i].type === 'scene') {
			start = i;
			break;
		}
	}
	const out: string[] = [];
	for (let i = start; i < n; i++) {
		const el = elements[i];
		if (el.type === 'character') pushUnique(out, stripCueExtensions(el.text).toUpperCase());
	}
	return out;
}

/**
 * Characters in the current scene ranked by *recency of last speech*
 * (most recent first) — the raw material of the ping-pong rule.
 */
export function scenePartnersByRecency(elements: ScreenplayElement[], beforeIndex: number): string[] {
	const n = clampIndex(elements, beforeIndex);
	let start = 0;
	for (let i = n - 1; i >= 0; i--) {
		if (elements[i].type === 'scene') {
			start = i;
			break;
		}
	}
	const out: string[] = [];
	for (let i = n - 1; i >= start; i--) {
		const el = elements[i];
		if (el.type === 'character') pushUnique(out, stripCueExtensions(el.text).toUpperCase());
	}
	return out;
}

/** The character who spoke most recently before `beforeIndex`, or null. */
export function lastSpeakerBefore(elements: ScreenplayElement[], beforeIndex: number): string | null {
	const n = clampIndex(elements, beforeIndex);
	for (let i = n - 1; i >= 0; i--) {
		const el = elements[i];
		if (el.type === 'character') {
			const name = stripCueExtensions(el.text).trim().toUpperCase();
			if (name !== '') return name;
		}
		if (el.type === 'scene') return null;
	}
	return null;
}

/**
 * The (CONT'D) condition. True only when `name` spoke earlier in THIS scene
 * and nothing but action or shots separates that speech from this block.
 */
function resumingAfterAction(elements: ScreenplayElement[], beforeIndex: number, name: string): boolean {
	let i = clampIndex(elements, beforeIndex) - 1;
	let interrupted = false;
	let spoke = false;
	for (; i >= 0; i--) {
		const t = elements[i].type;
		if (t === 'scene') return false;
		if (t === 'character') {
			return interrupted && spoke && stripCueExtensions(elements[i].text).trim().toUpperCase() === name;
		}
		if (t === 'action' || t === 'shot') interrupted = true;
		else if (t === 'note' || t === 'section' || t === 'synopsis' || t === 'pagebreak') continue;
		else if (t === 'dialogue' || t === 'parenthetical') {
			/* Dialogue seen before an interruption belongs to an unbroken speech;
			   after an interruption it leads us back to the cue being resumed. */
			if (!interrupted) return false;
			if (t === 'dialogue' && elements[i].text.trim() !== '') spoke = true;
		} else {
			/* A transition, general/centered line, or lyric is a semantic break.
			   Ignoring it would manufacture a false continuation. */
			return false;
		}
	}
	return false;
}

/**
 * The Final Draft continuation. True when the most recent voice in THIS
 * scene is `name` and that speech actually happened (non-empty dialogue).
 * Action, shots, and parentheticals between the speeches do not break a
 * continuation; another speaker, a scene boundary, or a semantic break
 * (transition, general line, lyric) does.
 *
 * This is looser than `resumingAfterAction` on purpose: an empty-block guess
 * needs the action beat to be confident, but an explicit extension gesture —
 * typing `(`, or the name plus a trailing space — only needs the fact that
 * the same voice continues. Final Draft marks both.
 */
function continuingSameVoice(elements: ScreenplayElement[], beforeIndex: number, name: string): boolean {
	let spoke = false;
	for (let i = clampIndex(elements, beforeIndex) - 1; i >= 0; i--) {
		const t = elements[i].type;
		if (t === 'scene') return false;
		if (t === 'character') {
			return spoke && stripCueExtensions(elements[i].text).trim().toUpperCase() === name;
		}
		if (t === 'dialogue' || t === 'parenthetical') {
			if (t === 'dialogue' && elements[i].text.trim() !== '') spoke = true;
			continue;
		}
		if (t === 'action' || t === 'shot' || t === 'note' || t === 'section' || t === 'synopsis' || t === 'pagebreak') {
			continue;
		}
		return false;
	}
	return false;
}

/* ---- structure memory ---------------------------------------------------- */

/** The most recently opened structure that has not been closed yet. */
export function openStructure(elements: ScreenplayElement[], beforeIndex: number): { open: string; close: string } | null {
	const stack: string[] = [];
	const n = clampIndex(elements, beforeIndex);
	for (let i = 0; i < n; i++) {
		const el = elements[i];
		if (el.type !== 'scene' && el.type !== 'shot' && el.type !== 'general' && el.type !== 'action') continue;
		const line = el.text.trim().toUpperCase();
		for (const [open, close] of STRUCTURE_PAIRS) {
			if (line === close || line.startsWith(close)) {
				const at = stack.lastIndexOf(open);
				if (at >= 0) stack.splice(at, 1);
			} else if (line === open || line.startsWith(open + ' ') || line.startsWith(open + ' - ') || line.startsWith(open + ':')) {
				stack.push(open);
			}
		}
	}
	if (stack.length === 0) return null;
	const open = stack[stack.length - 1];
	const pair = STRUCTURE_PAIRS.find((p) => p[0] === open);
	return pair ? { open, close: pair[1] } : null;
}

/* ---- time-of-day reasoning -------------------------------------------------- */

/** How many content lines the scene starting at `sceneIdx` holds. */
function sceneBodyLength(elements: ScreenplayElement[], sceneIdx: number, beforeIndex: number): number {
	let n = 0;
	for (let i = sceneIdx + 1; i < beforeIndex; i++) {
		if (elements[i].type === 'scene') break;
		if (elements[i].text.trim() !== '') n++;
	}
	return n;
}

/**
 * Infer the next scene time from the location's history, the preceding scene,
 * and whether the preceding scene was short enough to imply continuity.
 */
export function bestTimeFor(location: string, elements: ScreenplayElement[], beforeIndex: number): string | null {
	const n = clampIndex(elements, beforeIndex);
	/* per-location habit */
	const locTimes = new Map<string, number>();
	for (let i = 0; i < n; i++) {
		const el = elements[i];
		if (el.type !== 'scene') continue;
		const p = splitSceneHeading(el.text);
		if (p.location === location && p.time) locTimes.set(p.time, (locTimes.get(p.time) ?? 0) + 1);
	}

	/* the previous real scene */
	let prevTime = '';
	let prevLoc = '';
	let prevSceneIdx = -1;
	for (let i = n - 1; i >= 0; i--) {
		if (elements[i].type === 'scene') {
			const p = splitSceneHeading(elements[i].text);
			prevTime = p.time;
			prevLoc = p.location;
			prevSceneIdx = i;
			break;
		}
	}

	if (prevTime && locTimes.get(prevTime)) return prevTime;
	if (locTimes.size > 0) return [...locTimes.entries()].sort((a, b) => b[1] - a[1])[0][0];
	if (
		prevSceneIdx >= 0 &&
		prevLoc &&
		prevLoc !== location &&
		sceneBodyLength(elements, prevSceneIdx, n) <= 3
	) {
		return 'CONTINUOUS';
	}
	if (prevTime) return prevTime;
	return null;
}

/* ---- document vocabularies -------------------------------------------------- */

/** Extensions this script already uses, first-seen order — house style. */
export function usedExtensions(elements: ScreenplayElement[]): string[] {
	const out: string[] = [];
	for (const el of elements) {
		if (el.type !== 'character') continue;
		const m = EXT_RE.exec(el.text.trim());
		if (m) pushUnique(out, `(${m[1].toUpperCase().replace('’', "'")})`);
	}
	return out;
}

/** Parentheticals this script already uses. */
export function usedWrylies(elements: ScreenplayElement[]): string[] {
	const out: string[] = [];
	for (const el of elements) {
		if (el.type === 'parenthetical') pushUnique(out, el.text.trim().toLowerCase());
	}
	return out;
}

/** Shots this script already uses. */
export function usedShots(elements: ScreenplayElement[]): string[] {
	const out: string[] = [];
	for (const el of elements) {
		if (el.type === 'shot') pushUnique(out, el.text.trim().toUpperCase());
	}
	return out;
}

/** Where scenes tend to go next: previous location → following locations. */
function nextLocationCounts(elements: ScreenplayElement[], beforeIndex: number): Map<string, string[]> {
	const seq: string[] = [];
	const n = clampIndex(elements, beforeIndex);
	for (let i = 0; i < n; i++) {
		const el = elements[i];
		if (el.type !== 'scene') continue;
		const p = splitSceneHeading(el.text);
		if (p.location) seq.push(p.location);
	}
	const next = new Map<string, Map<string, number>>();
	for (let i = 1; i < seq.length; i++) {
		const from = seq[i - 1];
		if (!next.has(from)) next.set(from, new Map());
		const m = next.get(from)!;
		m.set(seq[i], (m.get(seq[i]) ?? 0) + 1);
	}
	const out = new Map<string, string[]>();
	next.forEach((m, k) => out.set(k, [...m.entries()].sort((a, b) => b[1] - a[1]).map(([l]) => l)));
	return out;
}

/* ---- intro/location coherence ---------------------------------------------
   After EXT. STREET - DAWN, typing INT. must not offer STREET back. */

type IntroKind = 'interior' | 'exterior' | 'both' | 'unknown';

function kindOfIntro(intro: string): IntroKind {
	const up = intro.toUpperCase();
	if (up.includes('/')) return 'both';
	if (up.startsWith('EXT')) return 'exterior';
	if (up.startsWith('INT')) return 'interior';
	return 'unknown';
}

/** Each location's observed intro kinds — a place knows which one it is. */
function locationKinds(elements: ScreenplayElement[]): Map<string, IntroKind> {
	const out = new Map<string, IntroKind>();
	for (const el of elements) {
		if (el.type !== 'scene') continue;
		const p = splitSceneHeading(el.text);
		if (!p.location) continue;
		const kind = kindOfIntro(p.prefix.replace('.', ''));
		if (kind === 'unknown') continue;
		const prev = out.get(p.location);
		out.set(p.location, prev && prev !== kind ? 'both' : kind);
	}
	return out;
}

/* ---- candidate generators ------------------------------------------------ */

/**
 * Empty character block, ranked by certainty:
 *   1. two-character scene → the other participant
 *   2. one voice plus intervening action → the same voice with (CONT'D)
 *   3. ensemble scene → participants by recency
 */
function emptyCharacterCandidates(script: Screenplay, index: number): Prediction[] {
	const elements = script.elements;
	const smart = collectSmartType(script);
	const recency = scenePartnersByRecency(elements, index);
	const last = recency.length > 0 ? recency[0] : null;
	const sceneCast = sceneCharacters(elements, index);

	const ranked: Prediction[] = [];

	if (sceneCast.length === 2 && last) {
		const other = sceneCast.find((n) => n !== last);
		if (other) ranked.push({ text: other, why: 'the other half of the conversation' });
	} else if (sceneCast.length === 1 && last && resumingAfterAction(elements, index, last)) {
		ranked.push({ text: `${last} (CONT'D)`, why: 'same speaker resuming after action' });
	}

	for (const partner of recency.slice(1)) {
		pushUniqueStrings(ranked, { text: partner, why: 'scene participant' });
	}
	for (const c of smart.characters) {
		if (c !== last) pushUniqueStrings(ranked, { text: c, why: 'character in this script' });
	}
	return ranked.slice(0, 8);
}

function pushUniqueStrings(list: Prediction[], p: Prediction): void {
	if (p.text !== '' && !list.some((x) => x.text === p.text)) list.push(p);
}

/** Partial cue typed: case-insensitive prefix match over known characters. */
function typedCharacterCandidates(script: Screenplay, text: string): Prediction[] {
	const prefix = stripCueExtensions(text).trim().toUpperCase();
	if (prefix === '') return [];
	return prefixHits(collectSmartType(script).characters, prefix).map((t) => ({
		text: t,
		why: 'character in this script'
	}));
}

/**
 * Offer cue extensions only after explicit extension input. Document-specific
 * extensions rank before defaults. `(CONT'D)` is included when the same voice
 * continues in the current scene — resuming after action, or simply speaking
 * again; both are continuations, and Final Draft marks both.
 */
function extensionCandidates(script: Screenplay, text: string, index: number): Prediction[] {
	const openParen = /^(.*?)\(([^)]*)$/.exec(text);
	if (!openParen) return [];
	const name = openParen[1].trim().toUpperCase();
	if (name === '') return [];
	const known = collectSmartType(script).characters.includes(name);

	const typed = openParen[2].toUpperCase();
	const pool: string[] = [];
	const resuming = continuingSameVoice(script.elements, index, name);
	if (resuming) pushUnique(pool, "(CONT'D)");
	if (known) {
		for (const e of usedExtensions(script.elements)) {
			if (e === "(CONT'D)") continue; /* facts outrank habits — context decides */
			pushUnique(pool, e);
		}
	}
	for (const e of COMMON_EXTENSIONS) pushUnique(pool, e);

	return pool
		.filter((e) => e.slice(1, -1).startsWith(typed) && e.slice(1, -1) !== typed)
		.slice(0, 6)
		.map((t) => ({ text: t, why: t === "(CONT'D)" ? 'same voice continuing' : 'cue extension' }));
}

/** Scene-heading assembly: intro → location → time, each stage story-aware. */
function sceneCandidates(script: Screenplay, text: string, index: number): Prediction[] {
	const up = text.toUpperCase();

	/* Require two characters before completing a scene prefix to avoid matching
	   ordinary action text. Prefix completion runs before heading detection so
	   compound prefixes such as `INT./EXT.` can be completed. */
	const typed = up.trim();
	if (typed.length < 2) return [];
	const introHit = SCENE_PREFIXES.find((p) => p.startsWith(typed) && p !== typed);
	if (introHit && introHit.slice(typed.length).trim() !== '') {
		return [{ text: introHit, why: 'scene intro' }];
	}

	if (!SCENE_HEAD_RE.test(up)) {
		/* An open structure's closing line takes precedence over generic slugs. */
		const open = openStructure(script.elements, index);
		if (open && open.close.startsWith(typed) && open.close !== typed) {
			return [{ text: open.close, why: `closes the ${open.open.toLowerCase()}` }];
		}

		const slugPool: string[] = [];
		for (const el of script.elements) {
			if ((el.type === 'scene' || el.type === 'general') && !SCENE_HEAD_RE.test(el.text)) {
				pushUnique(slugPool, el.text.trim().toUpperCase());
			}
		}
		for (const s of SPECIAL_SLUGS) pushUnique(slugPool, s);
		return prefixHits(slugPool, typed).map((t) => ({ text: t, why: 'sequence heading' }));
	}

	/* Complete a scene time or a modifier following an existing scene time. */
	const timeMatch = up.match(/\s-\s*([A-Z ]*)$/);
	if (timeMatch) {
		const prefix = timeMatch[1].trimStart();
		const beforeDash = up.replace(/\s-\s*[A-Z ]*$/, '');
		/* Text after a second dash is a heading modifier, not another scene time. */
		if (TIMES.includes(splitSceneHeading(beforeDash).time)) {
			if (prefix === '') return SLUG_MODIFIERS.map((t) => ({ text: t, why: 'heading modifier' }));
			return prefixHits(SLUG_MODIFIERS, prefix, 6).map((t) => ({ text: t, why: 'heading modifier' }));
		}
		/* Do not replace a complete, recognized scene time. */
		if (TIMES.includes(prefix)) return [];
		const loc = splitSceneHeading(beforeDash).location;
		const best = loc ? bestTimeFor(loc, script.elements, index) : null;
		const out: Prediction[] = [];
		if (best && best.startsWith(prefix) && best !== prefix) {
			out.push({ text: best, why: 'the day has not turned over' });
		}
		/* A bare separator requests the default scene-time candidates. */
		if (prefix === '') {
			for (const t of TIMES) pushUniqueStrings(out, { text: t, why: 'time of day' });
			return out.slice(0, 6);
		}
		for (const t of prefixHits(TIMES, prefix, 6)) {
			pushUniqueStrings(out, { text: t, why: 'time of day' });
		}
		return out.slice(0, 6);
	}

	/* With no location text, return a shape hint rather than a specific location. */
	const locMatch = up.match(/^\s*(?:INT\.?\/EXT\.?|INT\/EXT|I\/E|INT|EXT|EST)[\.\s]+(.*)$/);
	const prefix = locMatch ? locMatch[1].trimStart() : '';
	if (prefix === '') {
		return [{ text: 'LOCATION - TIME', why: 'the shape of a scene heading', hint: true }];
	}

	/* Filter locations by their observed interior/exterior usage. */
	const introRaw = (up.match(/^\s*(INT\.?\/EXT\.?|INT\/EXT|I\/E|INT|EXT|EST)/) ?? [null, 'INT'])[1] ?? 'INT';
	const want = kindOfIntro(introRaw.replace('.', ''));
	const kinds = locationKinds(script.elements);
	const fits = (loc: string): boolean => {
		const k = kinds.get(loc);
		return !k || k === 'both' || want === 'both' || k === want;
	};

	const smart = collectSmartType(script);
	/* Do not replace a complete, recognized location. */
	if (smart.locations.includes(prefix)) return [];
	const nextMap = nextLocationCounts(script.elements, index);
	let previousHeading = '';
	for (let i = clampIndex(script.elements, index) - 1; i >= 0; i--) {
		if (script.elements[i].type === 'scene') {
			previousHeading = script.elements[i].text;
			break;
		}
	}
	const prev = splitSceneHeading(previousHeading).location;
	const out: Prediction[] = [];
	if (prev) {
		for (const loc of nextMap.get(prev) ?? []) {
			if (loc.startsWith(prefix) && loc !== prefix && fits(loc)) {
				pushUniqueStrings(out, { text: loc, why: `where ${prev.toLowerCase()} scenes go next` });
			}
		}
	}
	for (const loc of prefixHits(smart.locations.filter(fits), prefix)) {
		pushUniqueStrings(out, { text: loc, why: 'location in this script' });
	}
	return out.slice(0, 8);
}

/** Return document-specific transitions before defaults. */
function transitionCandidates(script: Screenplay, text: string): Prediction[] {
	const prefix = text.trim().toUpperCase();
	const pool: string[] = [];
	for (const t of collectSmartType(script).transitions) pushUnique(pool, t);
	for (const t of COMMON_TRANSITIONS) pushUnique(pool, t);
	return prefixHits(pool, prefix, 6).map((t) => ({ text: t, why: 'transition' }));
}

/** Return document-specific parentheticals before defaults. */
function wrylyCandidates(script: Screenplay, text: string): Prediction[] {
	if (!text.startsWith('(')) return [];
	const pool: string[] = [];
	for (const w of usedWrylies(script.elements)) pushUnique(pool, w);
	for (const w of COMMON_WRYLIES) pushUnique(pool, w);
	return prefixHits(pool, text.toLowerCase(), 6).map((t) => ({ text: t, why: 'wryly' }));
}

/** Return document-specific shots before defaults. */
function shotCandidates(script: Screenplay, text: string): Prediction[] {
	const prefix = text.trim().toUpperCase();
	const pool: string[] = [];
	for (const s of usedShots(script.elements)) pushUnique(pool, s);
	for (const s of COMMON_SHOTS) pushUnique(pool, s);
	return prefixHits(pool, prefix, 6).map((t) => ({ text: t, why: 'shot' }));
}

/* ---- main entry ----------------------------------------------------------- */

/** Return ranked predictions for the block being edited, best first. */
export function predict(script: Screenplay, ctx: PredictContext): Prediction[] {
	const index = clampIndex(script.elements, ctx.index);
	switch (ctx.type) {
		case 'character': {
			if (ctx.text.trim() === '') return emptyCharacterCandidates(script, index);
			/* Extension candidates require explicit extension input. */
			const ext = extensionCandidates(script, ctx.text, index);
			if (ext.length > 0) return ext;
			/* A trailing space may offer `(CONT'D)` when scene context supports it. */
			const spaced = /^(.*?)\s+$/.exec(ctx.text);
			if (spaced) {
				if (EXT_RE.test(spaced[1])) return []; /* already extended */
				const name = stripCueExtensions(spaced[1]).trim().toUpperCase();
				if (name !== '' && continuingSameVoice(script.elements, index, name)) {
					return [{ text: "(CONT'D)", why: 'same voice continuing' }];
				}
				return [];
			}
			return typedCharacterCandidates(script, ctx.text);
		}
		case 'scene':
			return sceneCandidates(script, ctx.text, index);
		case 'transition':
			return transitionCandidates(script, ctx.text);
		case 'parenthetical':
			return wrylyCandidates(script, ctx.text);
		case 'shot':
			return shotCandidates(script, ctx.text);
		case 'action': {
			/* Promote an action block when its text clearly begins a scene heading. */
			const typed = ctx.text.trim();
			if (typed.length < 2) return [];
			const up = typed.toUpperCase();
			const couldBeSlug = SCENE_PREFIXES.some((p) => p.startsWith(up)) || SCENE_HEAD_RE.test(ctx.text);
			if (!couldBeSlug) return [];
			return sceneCandidates(script, ctx.text, index).map((p) => ({ ...p, becomes: 'scene' }));
		}
		default:
			return [];
	}
}

/**
 * The suffix to render as ghost text for a candidate.
 * Full candidate when the block is empty (or the candidate completes a
 * structured line like a scene heading), otherwise the unmatched tail.
 */
export function ghostSuffix(candidate: string, blockText: string, hint = false): string {
	/* shape hints append whole, spaced, and are never committed */
	if (hint) {
		if (blockText === '') return candidate;
		return (blockText.endsWith(' ') ? '' : ' ') + candidate;
	}

	const trimmed = blockText.trim();
	if (trimmed === '') return candidate;

	/* extensions attach to the name: 'MARA' → ' (V.O.)', 'MARA ' → '(V.O.)'
	   (but a wryly block already inside parens completes as a wryly) */
	if (candidate.startsWith('(') && !blockText.trimStart().startsWith('(')) {
		/* unclosed paren mid-cue: 'MARA (V' + '(V.O.)' → '.O.)' */
		const openAt = blockText.indexOf('(');
		if (openAt >= 0) {
			const typed = blockText.slice(openAt).toUpperCase();
			if (candidate.startsWith(typed) && candidate.length > typed.length) {
				return candidate.slice(typed.length);
			}
			return '';
		}
		return (blockText.endsWith(' ') ? '' : ' ') + candidate;
	}

	/* scene headings complete structurally: match against the raw upper text */
	const up = blockText.toUpperCase();
	if (candidate.startsWith(up)) return candidate.slice(up.length);

	/* location stage: block "INT. KIT", candidate "KITCHEN" — offer the tail */
	const locMatch = up.match(/^\s*(?:INT\.?\/EXT\.?|INT\/EXT|I\/E|INT|EXT|EST)[\.\s]+(.*)$/);
	if (locMatch && locMatch[1] && candidate.startsWith(locMatch[1].trimStart().toUpperCase())) {
		return candidate.slice(locMatch[1].trimStart().length);
	}

	/* time stage: block "INT. LAB - NI", candidate "NIGHT".
	   The ' - ' separator belongs to the heading, not to the writer:
	   '-' alone whispers ' NIGHT'; '- ' whispers 'NIGHT'; '- NI' whispers
	   'GHT'; but '-NI' jammed against the dash no suffix can repair — silence */
	const timeMatch = up.match(/\s-\s*([A-Z ]*)$/);
	if (timeMatch) {
		const typed = timeMatch[1];
		if (typed === '') {
			if (up.endsWith(' ')) return candidate;
			return candidate === '' ? '' : ' ' + candidate;
		}
		if (!/\s-\s+[A-Z ]*$/.test(up)) return '';
		if (candidate.startsWith(typed)) return candidate.slice(typed.length);
		return '';
	}

	/* character prefixes: block "MAR", candidate "MARA" */
	const prefix = stripCueExtensions(blockText).trim().toUpperCase();
	if (prefix !== '' && candidate.startsWith(prefix)) return candidate.slice(prefix.length);

	/* wrylies: block "(qu", candidate "(quietly)" */
	if (blockText.startsWith('(') && candidate.startsWith(blockText.toLowerCase())) {
		return candidate.slice(blockText.length);
	}

	return '';
}

/** The next word of a suggestion (with trailing space) — partial accept. */
export function nextWord(text: string): string {
	const m = /^\s*\S+\s*/.exec(text);
	return m ? m[0] : text;
}

/** Accept a prediction with Tab only after the user has entered text. */
export function ghostTabBehavior(blockText: string): 'accept' | 'jump' {
	return blockText.trim() === '' ? 'jump' : 'accept';
}
