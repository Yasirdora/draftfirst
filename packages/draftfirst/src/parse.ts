/**
 * Draft First Screenwriting Engine Fountain parser.
 *
 * Implements the authoring subset of the Fountain spec (fountain.io/syntax):
 * title page, scene headings (detected + forced `.`), action (forced `!`),
 * character cues (ALL CAPS, forced `@`, extensions, dual `^`), dialogue,
 * parentheticals, transitions (`TO:`, the FADE opener/closer family, forced `>`),
 * centered `> <`, lyrics `~`, notes [[ ]], boneyard (omitted), sections #,
 * synopses =, page breaks ===. Title pages open on known keys (`Title:`,
 * `Credit:`…) or on any run of 2+ keys — a lone `FADE IN:` is never metadata.
 * Beyond the spec: isolated known shot language (ANGLE ON, INSERT, … SHOT)
 * parses to the shot element. `!` always retains its standard meaning: Action.
 *
 * Production annotations such as MORE/CONT'D, revision marks, and locked pages
 * belong to pagination or production workflows rather than the authoring text.
 *
 * Model convention: one element per meaningful source line (mirrors FDX
 * Paragraphs). Semantic model round-trips are stable; arbitrary runs of blank
 * Action lines are canonicalized because the current model has no whitespace
 * element or source-location metadata.
 */

import type {
	AnyElementType,
	Screenplay,
	ScreenplayElement,
	TitlePageEntry
} from './types.js';

export interface FountainParseOptions {
	/** Maximum UTF-16 code units accepted from one document. Default: 16 MiB. */
	maxSourceCharacters?: number;
}

export const DEFAULT_MAX_FOUNTAIN_SOURCE_CHARACTERS: number = 16 * 1024 * 1024;

export class FountainParseError extends RangeError {
	readonly code: 'FOUNTAIN_SOURCE_LIMIT_EXCEEDED' = 'FOUNTAIN_SOURCE_LIMIT_EXCEEDED';
	readonly limit: number;
	readonly actual: number;

	constructor(limit: number, actual: number) {
		super(`Fountain source contains ${actual} characters; the configured limit is ${limit}.`);
		this.name = 'FountainParseError';
		this.limit = limit;
		this.actual = actual;
	}
}

function sourceLimit(options: FountainParseOptions): number {
	const value = options.maxSourceCharacters ?? DEFAULT_MAX_FOUNTAIN_SOURCE_CHARACTERS;
	if (!Number.isSafeInteger(value) || value <= 0) {
		throw new RangeError('maxSourceCharacters must be a positive safe integer.');
	}
	return value;
}

/* ---- title page -------------------------------------------------------- */

const TITLE_KEY = /^([A-Za-z][A-Za-z0-9 '&./_-]*):[ \t]*(.*)$/;
const TITLE_TRANSITION = /^[A-Z0-9 '()&.,/-]+ TO:$/;

/* Keys that unambiguously open a title page on their own. A single leading
   `Key: value` line is only a title page when its key is a known one —
   otherwise beloved openers like `FADE IN:` would be eaten as metadata
   (the classic Fountain gotcha). Two or more consecutive key lines are
   always a title page, whatever keys they carry. */
const KNOWN_TITLE_KEYS: ReadonlySet<string> = new Set([
	'title',
	'credit',
	'author',
	'authors',
	'written by',
	'source',
	'contact',
	'address',
	'draft',
	'draft date',
	'date',
	'revision',
	'copyright'
]);

function parseTitlePage(lines: string[]): { entries: TitlePageEntry[]; consumed: number } {
	const entries: TitlePageEntry[] = [];
	let i = 0;
	/* skip leading blank lines */
	while (i < lines.length && lines[i].trim() === '') i++;
	if (i >= lines.length) return { entries, consumed: i };

	const first = TITLE_KEY.exec(lines[i]);
	if (!first || TITLE_TRANSITION.test(lines[i].trim())) {
		return { entries: [], consumed: 0 };
	}

	while (i < lines.length) {
		const line = lines[i];
		if (line.trim() === '') {
			i++;
			break;
		}
		const m = TITLE_KEY.exec(line);
		if (m && !/^\s/.test(line)) {
			entries.push({ key: m[1].trim(), values: m[2].trim() === '' ? [] : [m[2].trim()] });
			i++;
			continue;
		}
		/* continuation: indented line extends the previous entry's values */
		if (/^\s+\S/.test(line) && entries.length > 0) {
			entries[entries.length - 1].values.push(line.trim());
			i++;
			continue;
		}
		break;
	}

	/* one key alone is metadata only when the key is a known one */
	if (entries.length === 1 && !KNOWN_TITLE_KEYS.has(entries[0].key.toLowerCase())) {
		return { entries: [], consumed: 0 };
	}
	return { entries, consumed: i };
}

/* ---- boneyard + notes (multi-line aware pre-pass) ---------------------- */

/** Remove boneyard /* … *​/ blocks entirely; they never print and never persist. */
function stripBoneyard(text: string): string {
	return text.replace(/\/\*[\s\S]*?\*\//g, '');
}

interface LogicalLine {
	text: string;
	notes: string[];
}

/**
 * Fountain deliberately fails safe: an unclosed inline construct must not
 * consume subsequent paragraphs. A note may cross a normal line ending, but
 * not a genuinely empty line (two spaces are Fountain's explicit connected
 * blank line syntax).
 */
function hasNoteCloseBeforeParagraphBreak(
	lines: readonly string[],
	startLine: number,
	startColumn: number
): boolean {
	for (let lineIndex = startLine; lineIndex < lines.length; lineIndex++) {
		const line = lines[lineIndex];
		const from = lineIndex === startLine ? startColumn : 0;
		if (line.indexOf(']]', from) !== -1) return true;
		const connectedBlankWidth = line.replace(/\t/g, '    ').length;
		if (lineIndex > startLine && line.trim() === '' && connectedBlankWidth < 2) return false;
	}
	return false;
}

/**
 * Split into lines, extracting [[ notes ]] (which may span lines).
 * Standalone notes become their own note lines; inline notes are lifted out
 * of the surrounding text.
 */
function logicalLines(raw: string): LogicalLine[] {
	const out: LogicalLine[] = [];
	let inNote = false;
	let noteBuf = '';
	const lines = raw.split('\n').map((line) => line.replace(/\r$/, ''));

	for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
		let line = lines[lineIndex];
		const notes: string[] = [];
		let rebuilt = '';

		for (let i = 0; i < line.length; i++) {
			if (inNote) {
				if (line[i] === ']' && line[i + 1] === ']') {
					notes.push(noteBuf.trim());
					noteBuf = '';
					inNote = false;
					i++;
				} else {
					noteBuf += line[i];
				}
				continue;
			}
			if (
				line[i] === '[' &&
				line[i + 1] === '[' &&
				hasNoteCloseBeforeParagraphBreak(lines, lineIndex, i + 2)
			) {
				inNote = true;
				noteBuf = '';
				i++;
				continue;
			}
			rebuilt += line[i];
		}
		if (inNote) noteBuf += '\n';
		line = rebuilt;

		out.push({ text: line, notes });
	}
	return out;
}

/* ---- element classifiers ----------------------------------------------- */

export const SCENE_DETECT: RegExp = /^(INT|EXT|EST|INT\.\/EXT|INT\/EXT|I\/E)([. ]|\.\/)/i;
const SCENE_NUMBER = /#([^#]+)#\s*$/;
export const TRANSITION_DETECT: RegExp = /^[A-Z0-9 '()&.,/-]+ TO:$/;
/* Beloved openers/closers that carry no `TO:` — recognised as transitions on
   import so a foreign script's `FADE IN:` never degrades to prose. */
const FADE_OPENER: RegExp = /^FADE (IN|OUT|TO BLACK|TO WHITE)[.:]?$/;
const FORCED_TRANSITION = /^>\s*(.+)$/;
const CENTERED = /^>\s*(.+?)\s*<$/;
const UPPERCASE_LINE = /[A-Z]/;

function hasLower(text: string): boolean {
	return /[a-z]/.test(text);
}

function isUpperCue(text: string): boolean {
	return UPPERCASE_LINE.test(text) && !hasLower(text);
}

/**
 * Fountain has no shot syntax — a shot serialises as (forced) action.
 * On the way back in, known shot language comes home to its own element,
 * so our native .draft round-trips without degradation. Conservative by
 * design: ALL-CAPS lines only, named leads or a terminal SHOT — ordinary
 * shouted action ("THE ROOM SPINS") is never hijacked.
 */
const SHOT_LEADS = [
	'ANGLE ON', 'CLOSE ON', 'CLOSEUP ON', 'CLOSEUP', 'POV', 'INSERT',
	'WIDE SHOT', 'TWO SHOT', 'TRACKING SHOT', 'AERIAL SHOT', 'CRANE SHOT',
	'STEADICAM SHOT', 'HANDHELD SHOT'
];

function looksLikeShot(text: string): boolean {
	if (!isUpperCue(text)) return false;
	const up = text.toUpperCase();
	return (
		SHOT_LEADS.some((lead) => up === lead || up.startsWith(lead + ' ')) ||
		/ SHOT$/.test(up)
	);
}

function centeredMatch(text: string): RegExpExecArray | null {
	/* `\<` is the serializer's unambiguous escape for a forced transition
	   whose literal text ends in `<`. */
	if (/\\<$/.test(text)) return null;
	return CENTERED.exec(text);
}

function unescapeForcedTransition(text: string): string {
	return /\\<$/.test(text) ? `${text.slice(0, -2)}<` : text;
}

function expandActionTabs(text: string): string {
	return text.replace(/\t/g, '    ');
}

function isIntentionalDialogueBlank(raw: string, inDialogue: boolean): boolean {
	if (!inDialogue || !/^[ \t]+$/.test(raw)) return false;
	return expandActionTabs(raw).length >= 2;
}

/** Strip a trailing scene number (#12#) and report it. */
function splitSceneNumber(text: string): { text: string; sceneNumber?: string } {
	const m = SCENE_NUMBER.exec(text);
	if (!m) return { text: text.trim() };
	return { text: text.slice(0, m.index).trim(), sceneNumber: m[1].trim() };
}

/** True when the cue carries a dual-dialogue caret; strips it in place. */
function splitDual(text: string): { text: string; dual: boolean } {
	if (text.endsWith('^')) return { text: text.slice(0, -1).trim(), dual: true };
	return { text, dual: false };
}

/* ---- main parse -------------------------------------------------------- */

export function parseFountain(source: string, options: FountainParseOptions = {}): Screenplay {
	const rawSource = String(source ?? '');
	const limit = sourceLimit(options);
	if (rawSource.length > limit) throw new FountainParseError(limit, rawSource.length);
	const cleaned = stripBoneyard(rawSource);
	const ll = logicalLines(cleaned);
	const rawLines = ll.map((l) => l.text);
	const { entries, consumed } = parseTitlePage(rawLines);

	const elements: ScreenplayElement[] = [];

	const push = (type: AnyElementType, text: string, extra?: Partial<ScreenplayElement>) => {
		elements.push({ type, text, ...extra });
	};

	/* attach standalone notes captured during line splitting */
	const noteQueue = ll.slice(consumed).map((l) => l.notes);

	let prev: AnyElementType | null = null; // previous *printing/flow* element
	let i = consumed;

	/** A character cue is only a cue when dialogue-capable content follows directly. */
	const directDialogueFollower = (from: number): string | null => {
		if (from >= rawLines.length) return null;
		const raw = rawLines[from];
		const text = raw.trim();
		if (text === '') return expandActionTabs(raw).length >= 2 ? raw : null;
		if (
			/^={3,}$/.test(text) ||
			text.startsWith('#') ||
			text.startsWith('=') ||
			text.startsWith('>') ||
			text.startsWith('~') ||
			text.startsWith('!') ||
			text.startsWith('@') ||
			/^\.[\p{L}\p{N}]/u.test(text)
		) {
			return null;
		}
		return text;
	};

	for (; i < rawLines.length; i++) {
		const notes = noteQueue[i - consumed] ?? [];
		for (const n of notes) push('note', n);

		const raw = rawLines[i];
		const line = raw.trim();
		const inDialogue =
			prev === 'character' || prev === 'parenthetical' || prev === 'dialogue';
		const blankBefore = i === consumed || rawLines[i - 1].trim() === '';
		const blankAfter = i === rawLines.length - 1 || rawLines[i + 1].trim() === '';

		/* Two spaces on an otherwise empty line intentionally continue Dialogue. */
		if (isIntentionalDialogueBlank(raw, inDialogue)) {
			push('dialogue', '');
			prev = 'dialogue';
			continue;
		}

		if (line === '') {
			prev = null;
			continue;
		}

		/* page break */
		if (/^={3,}\s*$/.test(line)) {
			push('pagebreak', '');
			prev = null;
			continue;
		}

		/* section */
		if (line.startsWith('#')) {
			const depth = line.match(/^#+/)![0].length;
			push('section', line.slice(depth).trim(), { depth });
			prev = null;
			continue;
		}

		/* synopsis (but not a page break, handled above) */
		if (line.startsWith('=')) {
			push('synopsis', line.replace(/^=+\s*/, ''));
			prev = null;
			continue;
		}

		/* centered  > THE END < */
		const c = centeredMatch(line);
		if (c) {
			push('centered', c[1]);
			prev = 'centered';
			continue;
		}

		/* forced transition  > SMASH CUT TO BLACK. */
		const ft = FORCED_TRANSITION.exec(line);
		if (ft) {
			push('transition', unescapeForcedTransition(ft[1].trim()));
			prev = 'transition';
			continue;
		}

		/* lyrics  ~la la la */
		if (line.startsWith('~')) {
			push('lyrics', line.slice(1).trim());
			prev = 'lyrics';
			continue;
		}

		/* forced action  !Molly's Diner */
		if (line.startsWith('!')) {
			const t = expandActionTabs(raw.trimStart().slice(1));
			push('action', t);
			prev = 'action';
			continue;
		}

		/* forced character  @McCready */
		if (line.startsWith('@')) {
			const { text, dual } = splitDual(line.slice(1).trim());
			push('character', text, dual ? { dual } : undefined);
			prev = 'character';
			continue;
		}

		/* Only one dot followed by an alphanumeric forces a scene. Ellipses stay text. */
		if (/^\.[\p{L}\p{N}]/u.test(line)) {
			const { text, sceneNumber } = splitSceneNumber(line.slice(1));
			push('scene', text.toUpperCase(), sceneNumber ? { sceneNumber } : undefined);
			prev = 'scene';
			continue;
		}

		/* inside a dialogue block? parenthetical attaches to cue/dialogue */
		if (inDialogue && line.startsWith('(')) {
			push('parenthetical', line);
			prev = 'parenthetical';
			continue;
		}
		if (inDialogue) {
			push('dialogue', line);
			prev = 'dialogue';
			continue;
		}

		/* Unforced block types require their Fountain blank-line context. */
		if (blankBefore && blankAfter && SCENE_DETECT.test(line)) {
			const { text, sceneNumber } = splitSceneNumber(line);
			push('scene', text.toUpperCase(), sceneNumber ? { sceneNumber } : undefined);
			prev = 'scene';
			continue;
		}

		/* detected transition  CUT TO: / DISSOLVE TO: / FADE IN: */
		if (blankBefore && blankAfter && (TRANSITION_DETECT.test(line) || FADE_OPENER.test(line)) && isUpperCue(line)) {
			push('transition', line);
			prev = 'transition';
			continue;
		}

		/* Character context wins over the native shot extension: POV followed
		   directly by speech is a valid Fountain character cue. */
		const follower = directDialogueFollower(i + 1);
		if (
			blankBefore &&
			isUpperCue(line) &&
			follower !== null
		) {
			const { text, dual } = splitDual(line);
			push('character', text, dual ? { dual } : undefined);
			prev = 'character';
			continue;
		}

		/* Known shot language is a Draft First extension. Unforced names still
		   obey standard Fountain cue context when dialogue follows directly. */
		if (looksLikeShot(line)) {
			push('shot', line);
			prev = 'shot';
			continue;
		}

		push('action', expandActionTabs(raw));
		prev = 'action';
	}

	return { titlePage: entries, elements };
}
