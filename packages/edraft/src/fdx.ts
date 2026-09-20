/**
 * eDraft Screenwriting Engine FDX interoperability.
 *
 * This is deliberately a small, non-validating XML reader. It understands the
 * FDX paragraph/text subset, ignores comments and processing instructions, and
 * never resolves external entities. Import is bounded and best-effort: malformed
 * input produces structured diagnostics instead of escaping as an exception.
 *
 * FDX cannot represent every element in the eDraft document model. Detailed export
 * therefore reports every lossy conversion, and the compatibility `writeFdx`
 * helper embeds an XML warning when non-printing structure must be omitted.
 */

import { actOrdinal, isCanonicalActCard } from './acts.js';
import { canonicalCasing } from './normalize.js';
import { normaliseRuns, STYLE_ORDER } from './style.js';
import { isPrinting } from './types.js';
import { anchorFor, quoteAnchorWords, resolveAnchor } from './noteanchor.js';
import type {
	AnyElementType,
	ElementType,
	Screenplay,
	ScreenplayElement,
	TitlePageLine, StyleRun, StyleToken, NoteAnchor, Omission } from './types.js';

/* ---- diagnostics and limits -------------------------------------------- */

/** `info` reports what a save did on the writer's behalf; it is never a warning. */
export type FdxDiagnosticSeverity = 'info' | 'warning' | 'error';

export interface FdxDiagnostic {
	code: string;
	severity: FdxDiagnosticSeverity;
	message: string;
	offset?: number;
	paragraphIndex?: number;
	elementIndex?: number;
	count?: number;
}

export interface FdxImportOptions {
	/** Maximum UTF-16 code units accepted from one document. Default: 16 MiB. */
	maxSourceCharacters?: number;
	/** Maximum paragraphs collected from one document. Default: 100,000. */
	maxParagraphs?: number;
	/** Maximum Text runs processed from one document. Default: 500,000. */
	maxTextRuns?: number;
	/** Maximum diagnostics returned. Default: 100. */
	maxWarnings?: number;
}

export interface FdxExportOptions {
	/** Maximum diagnostics returned. Default: 100. */
	maxWarnings?: number;
	/** How the writer's notes are written into <ScriptNotes>. */
	notes?: FdxNoteWriting;
}

/**
 * How a save writes the notes the writer left in eDraft: each one a Final
 * Draft ScriptNote (RFC-NOTES-SYSTEM §4.2), never a paragraph of the script.
 * Every value that is new each time is the caller's to give, so a test can
 * pin every byte; left out, each is made fresh.
 */
export interface FdxNoteWriting {
	/** The writer's name for notes: `Name (Role)`, or `Name` (D4). A note that
	    does not name its author is written with it (D3). Never read from the
	    system: without it, such a note names nobody. */
	writer?: string;
	/** `yyyyMMddTHHmmss`, local time, as Final Draft writes DateTime. */
	now?: string;
	/** A fresh lowercase UUID, for a note's RefId and each paragraph's id. */
	newId?: () => string;
}

export interface FdxImportResult {
	script: Screenplay;
	/** Backward-compatible messages. Prefer `diagnostics` for programmatic use. */
	warnings: string[];
	diagnostics: FdxDiagnostic[];
	/** The file's ScriptNotes, in file order. See `FdxScriptNote`. */
	scriptNotes: FdxScriptNote[];
}

/** A place in the imported screenplay: an index into `script.elements` and a
    ContentIndex into that element's text. */
export interface FdxScriptNotePosition {
	element: number;
	offset: number;
}

/**
 * A Final Draft ScriptNote — a comment the file keeps beside the script.
 *
 * Final Draft does not put these in the script's <Content>. They live in a
 * top-level <ScriptNotes> container and point back into the script with a
 * character Range, so they are read here as what they are: a reading of the
 * file, not part of the screenplay. A screenplay field would evaporate the
 * moment the app turns the file into Fountain, and a `note` element cannot
 * hold one — measured on a real feature, a note of nine paragraphs, four of
 * them blank, came back from Fountain as five printed Action lines. Nothing
 * here is ever written: the preserving save copies <ScriptNotes> byte for
 * byte, because it lies outside the paragraphs a save rewrites.
 *
 * Every field is the file's own, verbatim, and absent when the file leaves it
 * empty. What the file does not say is not inferred:
 *
 * - `author` is `WriterName`. `WriterID` is not read — all eleven notes in
 *   the measured file shared one WriterID across two different writers.
 * - `category` is `Type`, and it is free text, not a role: one writer's notes
 *   were typed both "Writer" and "Alt Scenes".
 * - `color` is `#RRRRGGGGBBBB`, sixteen bits a channel, no alpha; the all-zero
 *   value means unset and reads as absent. It says what kind of note this is,
 *   never who wrote it — one writer's eight notes came in four colours.
 * - `range` is the file's Range. `anchor` is where it lands (see
 *   `anchorOf`), and is absent when the Range starts past the script — a
 *   stale Range is kept rather than guessed at.
 * - `text` is the body's paragraphs joined with "\n", blank paragraphs kept.
 */
export interface FdxScriptNote {
	id?: string;
	author?: string;
	title?: string;
	category?: string;
	color?: string;
	created?: string;
	modified?: string;
	range?: { start: number; end: number };
	anchor?: { start: FdxScriptNotePosition; end: FdxScriptNotePosition };
	text: string;
}

/** The title a note eDraft wrote carries (RFC-NOTES-SYSTEM §4.3). */
const EDRAFT_TITLE = '[eDraft]';

/**
 * A note eDraft wrote: its title, Final Draft's `Name`, is `[eDraft]` (§4.3).
 * Final Draft keeps a note's title when someone edits the note there, so the
 * note stays eDraft's; it re-stamps the author field, so the note is then
 * authored by whoever edited it (D9).
 */
interface OwnedNote {
	/** Its author: Final Draft's `WriterName`. */
	name?: string;
	/** Their role: Final Draft's Type. */
	role?: string;
	message: string;
}

function ownedNoteOf(
	title: string | undefined,
	writerName: string | undefined,
	type: string | undefined,
	paragraphs: string[]
): OwnedNote | null {
	if ((title ?? '').trim() !== EDRAFT_TITLE) return null;
	const name = (writerName ?? '').trim();
	const role = (type ?? '').trim();
	return { ...(name ? { name } : {}), ...(role ? { role } : {}), message: paragraphs.join('\n') };
}

/** How a note of eDraft's signs in the editor: `Name (Role)`, or `Name` (D4). */
function ownedNoteAuthor(note: OwnedNote): string | undefined {
	if (!note.name) return undefined;
	return note.role ? `${note.name} (${note.role})` : note.name;
}

/** A note of eDraft's as the writer reads and edits it: `Name (Role): words`. */
function ownedNoteText(note: OwnedNote): string {
	const author = ownedNoteAuthor(note);
	return author ? `${author}: ${note.message}` : note.message;
}

/** `Name (Role)` into the name and the role; a signature with no role is all name. */
function nameAndRole(signature: string): { name: string; role: string } {
	const at = signature.lastIndexOf(' (');
	if (signature.endsWith(')') && at > 0) {
		const name = signature.slice(0, at).trim();
		if (name) return { name, role: signature.slice(at + 2, -1).trim() };
	}
	return { name: signature.trim(), role: '' };
}

export interface FdxExportResult {
	xml: string;
	warnings: string[];
	diagnostics: FdxDiagnostic[];
}

interface FdxLimits {
	maxSourceCharacters: number;
	maxParagraphs: number;
	maxTextRuns: number;
	maxWarnings: number;
}

const DEFAULT_FDX_LIMITS: FdxLimits = {
	maxSourceCharacters: 16 * 1024 * 1024,
	maxParagraphs: 100_000,
	maxTextRuns: 500_000,
	maxWarnings: 100
};

function positiveInteger(value: number | undefined, fallback: number): number {
	return Number.isSafeInteger(value) && (value ?? 0) > 0 ? (value as number) : fallback;
}

function importLimits(options: FdxImportOptions): FdxLimits {
	return {
		maxSourceCharacters: positiveInteger(
			options.maxSourceCharacters,
			DEFAULT_FDX_LIMITS.maxSourceCharacters
		),
		maxParagraphs: positiveInteger(options.maxParagraphs, DEFAULT_FDX_LIMITS.maxParagraphs),
		maxTextRuns: positiveInteger(options.maxTextRuns, DEFAULT_FDX_LIMITS.maxTextRuns),
		maxWarnings: positiveInteger(options.maxWarnings, DEFAULT_FDX_LIMITS.maxWarnings)
	};
}

class DiagnosticCollector {
	readonly #limit: number;
	readonly #items: FdxDiagnostic[] = [];
	#truncated = false;

	constructor(limit: number) {
		this.#limit = limit;
	}

	add(diagnostic: FdxDiagnostic): void {
		if (this.#items.length < this.#limit) {
			this.#items.push(diagnostic);
			return;
		}
		if (this.#truncated || this.#limit === 0) return;
		this.#truncated = true;
		this.#items[this.#limit - 1] = {
			code: 'FDX_DIAGNOSTICS_TRUNCATED',
			severity: 'warning',
			message: `Additional diagnostics were omitted after the ${this.#limit}-message limit.`
		};
	}

	result(): FdxDiagnostic[] {
		return this.#items.slice();
	}
}

function messagesOf(diagnostics: FdxDiagnostic[]): string[] {
	return diagnostics.filter((diagnostic) => diagnostic.severity !== 'info').map((diagnostic) => diagnostic.message);
}

/* ---- entities ----------------------------------------------------------- */

function isLegalXmlCodePoint(codePoint: number): boolean {
	return (
		codePoint === 0x09 ||
		codePoint === 0x0a ||
		codePoint === 0x0d ||
		(codePoint >= 0x20 && codePoint <= 0xd7ff) ||
		(codePoint >= 0xe000 && codePoint <= 0xfffd) ||
		(codePoint >= 0x10000 && codePoint <= 0x10ffff)
	);
}

function sanitiseXmlCharacters(text: string): { text: string; replacements: number } {
	let clean = '';
	let replacements = 0;
	for (const character of text) {
		const codePoint = character.codePointAt(0) ?? 0;
		if (isLegalXmlCodePoint(codePoint)) clean += character;
		else {
			clean += '\uFFFD';
			replacements++;
		}
	}
	return { text: clean, replacements };
}

/** Decode each entity exactly once. Invalid numeric entities remain unchanged. */
export function decodeXmlEntities(text: string): string {
	return String(text).replace(
		/&(?:#(?:x|X)[0-9a-fA-F]+|#[0-9]+|lt|gt|quot|apos|amp);/g,
		(entity): string => {
			if (entity === '&lt;') return '<';
			if (entity === '&gt;') return '>';
			if (entity === '&quot;') return '"';
			if (entity === '&apos;') return "'";
			if (entity === '&amp;') return '&';

			const hexadecimal = entity[2] === 'x' || entity[2] === 'X';
			const digits = entity.slice(hexadecimal ? 3 : 2, -1);
			const codePoint = Number.parseInt(digits, hexadecimal ? 16 : 10);
			if (!Number.isSafeInteger(codePoint) || !isLegalXmlCodePoint(codePoint)) return entity;
			return String.fromCodePoint(codePoint);
		}
	);
}

export function encodeXmlEntities(text: string): string {
	return sanitiseXmlCharacters(String(text)).text
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

function encodeXmlValue(
	value: string,
	diagnostics: DiagnosticCollector,
	context: string,
	elementIndex?: number
): string {
	const sanitised = sanitiseXmlCharacters(value);
	if (sanitised.replacements > 0) {
		const diagnostic: FdxDiagnostic = {
			code: 'FDX_INVALID_XML_CHARACTER_REPLACED',
			severity: 'warning',
			message: `${sanitised.replacements} illegal XML character(s) in ${context} were replaced with U+FFFD.`,
			count: sanitised.replacements
		};
		if (elementIndex !== undefined) diagnostic.elementIndex = elementIndex;
		diagnostics.add(diagnostic);
	}
	return sanitised.text
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

/* ---- type mapping ------------------------------------------------------- */

const FDX_TO_MODEL: Readonly<Record<string, AnyElementType>> = {
	'scene heading': 'scene',
	action: 'action',
	character: 'character',
	dialogue: 'dialogue',
	parenthetical: 'parenthetical',
	transition: 'transition',
	shot: 'shot',
	general: 'general',
	// A Final Draft "Note" is a line in the script that does not print, which
	// is exactly what Fountain's [[ ]] is. Reading it as General put a
	// writer's notes on the page — ten of them across the two real features
	// this was measured on.
	note: 'note',
	// The card that opens an act prints and is structure: the model's
	// actbreak keeps both (RFC-ACT-BREAK §3). Its Alignment="Center" is a
	// property of the type, so nothing is refined from attributes.
	'new act': 'actbreak'
	/* 'end of act' is deliberately absent: it carries no fact the model
	   lacks — an act ends where the next one begins (D3). The import loop
	   absorbs it below; mapping it here would store a derivable fact. */
};

const MODEL_TO_FDX: Readonly<Partial<Record<AnyElementType, string>>> = {
	scene: 'Scene Heading',
	action: 'Action',
	character: 'Character',
	dialogue: 'Dialogue',
	parenthetical: 'Parenthetical',
	transition: 'Transition',
	shot: 'Shot',
	general: 'General',
	centered: 'General',
	lyrics: 'General',
	actbreak: 'New Act',
	note: 'Note',
	synopsis: 'Summary'
	/* `section` is not here: its level is part of its type — see `fdxTypeOf`. */
};

/* Our own FDX extension namespace: the attributes Final Draft has no field
   for (lyrics, title-page keys). The prefix and URI changed with the eDraft
   rename, so both are READ and only the current one is written — an .fdx
   exported under the old name must keep re-importing losslessly forever. */
const EDRAFT_NAMESPACE = 'https://edraft.xyz/ns/fdx/1';
const EDRAFT_PREFIX = 'EDraft';
const LEGACY_ATTRIBUTE_PREFIXES: readonly string[] = Object.freeze(['draftfirst']);

/* ---- bounded XML tokenisation ------------------------------------------ */

interface ParsedTag {
	name: string;
	attributes: Map<string, string>;
	selfClosing: boolean;
}

interface XmlHandlers {
	start(tag: ParsedTag, offset: number): boolean;
	end(name: string, offset: number): boolean;
	text(value: string, cdata: boolean): boolean;
}

function tagEndOf(source: string, start: number): number {
	let quote = '';
	for (let index = start; index < source.length; index++) {
		const character = source[index];
		if (quote !== '') {
			if (character === quote) quote = '';
		} else if (character === '"' || character === "'") quote = character;
		else if (character === '>') return index;
	}
	return -1;
}

function declarationEndOf(source: string, start: number): number {
	let quote = '';
	let subsetDepth = 0;
	for (let index = start; index < source.length; index++) {
		const character = source[index];
		if (quote !== '') {
			if (character === quote) quote = '';
			continue;
		}
		if (character === '"' || character === "'") quote = character;
		else if (character === '[') subsetDepth++;
		else if (character === ']' && subsetDepth > 0) subsetDepth--;
		else if (character === '>' && subsetDepth === 0) return index;
	}
	return -1;
}

function isWhitespace(character: string | undefined): boolean {
	return character !== undefined && /\s/.test(character);
}

function parseTag(rawTag: string, offset: number, diagnostics: DiagnosticCollector): ParsedTag | null {
	let raw = rawTag.trim();
	const selfClosing = raw.endsWith('/');
	if (selfClosing) raw = raw.slice(0, -1).trimEnd();

	let cursor = 0;
	while (isWhitespace(raw[cursor])) cursor++;
	const nameStart = cursor;
	while (cursor < raw.length && !isWhitespace(raw[cursor]) && raw[cursor] !== '=') cursor++;
	if (cursor === nameStart) {
		diagnostics.add({
			code: 'FDX_MALFORMED_TAG',
			severity: 'warning',
			message: 'An XML tag without a name was ignored.',
			offset
		});
		return null;
	}

	const name = raw.slice(nameStart, cursor).toLowerCase();
	const attributes = new Map<string, string>();
	while (cursor < raw.length) {
		while (isWhitespace(raw[cursor])) cursor++;
		if (cursor >= raw.length) break;

		const attributeStart = cursor;
		while (cursor < raw.length && !isWhitespace(raw[cursor]) && raw[cursor] !== '=') cursor++;
		const attributeName = raw.slice(attributeStart, cursor).toLowerCase();
		while (isWhitespace(raw[cursor])) cursor++;
		if (attributeName === '' || raw[cursor] !== '=') {
			diagnostics.add({
				code: 'FDX_MALFORMED_ATTRIBUTE',
				severity: 'warning',
				message: `A malformed attribute on <${name}> was ignored.`,
				offset
			});
			while (cursor < raw.length && !isWhitespace(raw[cursor])) cursor++;
			continue;
		}

		cursor++;
		while (isWhitespace(raw[cursor])) cursor++;
		const quote = raw[cursor];
		let value = '';
		if (quote === '"' || quote === "'") {
			cursor++;
			const valueStart = cursor;
			while (cursor < raw.length && raw[cursor] !== quote) cursor++;
			value = raw.slice(valueStart, cursor);
			if (cursor < raw.length) cursor++;
			else {
				diagnostics.add({
					code: 'FDX_UNTERMINATED_ATTRIBUTE',
					severity: 'warning',
					message: `An unterminated attribute on <${name}> was imported best-effort.`,
					offset
				});
			}
		} else {
			const valueStart = cursor;
			while (cursor < raw.length && !isWhitespace(raw[cursor])) cursor++;
			value = raw.slice(valueStart, cursor);
			diagnostics.add({
				code: 'FDX_UNQUOTED_ATTRIBUTE',
				severity: 'warning',
				message: `Unquoted attribute "${attributeName}" on <${name}> was accepted best-effort.`,
				offset
			});
		}
		attributes.set(attributeName, decodeXmlEntities(value));
	}

	return { name, attributes, selfClosing };
}

function scanXml(
	source: string,
	handlers: XmlHandlers,
	diagnostics: DiagnosticCollector
): void {
	let cursor = 0;
	while (cursor < source.length) {
		const opening = source.indexOf('<', cursor);
		if (opening === -1) {
			handlers.text(source.slice(cursor), false);
			return;
		}
		if (opening > cursor && !handlers.text(source.slice(cursor, opening), false)) return;

		if (source.startsWith('<!--', opening)) {
			const end = source.indexOf('-->', opening + 4);
			if (end === -1) {
				diagnostics.add({
					code: 'FDX_UNTERMINATED_COMMENT',
					severity: 'warning',
					message: 'An unterminated XML comment ended the import.',
					offset: opening
				});
				return;
			}
			cursor = end + 3;
			continue;
		}

		if (source.startsWith('<![CDATA[', opening)) {
			const end = source.indexOf(']]>', opening + 9);
			if (end === -1) {
				diagnostics.add({
					code: 'FDX_UNTERMINATED_CDATA',
					severity: 'warning',
					message: 'An unterminated CDATA section ended the import.',
					offset: opening
				});
				handlers.text(source.slice(opening + 9), true);
				return;
			}
			if (!handlers.text(source.slice(opening + 9, end), true)) return;
			cursor = end + 3;
			continue;
		}

		if (source.startsWith('<?', opening)) {
			const end = source.indexOf('?>', opening + 2);
			if (end === -1) {
				diagnostics.add({
					code: 'FDX_UNTERMINATED_PROCESSING_INSTRUCTION',
					severity: 'warning',
					message: 'An unterminated XML processing instruction ended the import.',
					offset: opening
				});
				return;
			}
			cursor = end + 2;
			continue;
		}

		if (source.startsWith('<!', opening)) {
			const end = declarationEndOf(source, opening + 2);
			if (end === -1) {
				diagnostics.add({
					code: 'FDX_UNTERMINATED_DECLARATION',
					severity: 'warning',
					message: 'An unterminated XML declaration ended the import.',
					offset: opening
				});
				return;
			}
			diagnostics.add({
				code: 'FDX_DECLARATION_IGNORED',
				severity: 'warning',
				message: 'An XML declaration such as DOCTYPE was ignored; external entities are never resolved.',
				offset: opening
			});
			cursor = end + 1;
			continue;
		}

		const end = tagEndOf(source, opening + 1);
		if (end === -1) {
			diagnostics.add({
				code: 'FDX_UNTERMINATED_TAG',
				severity: 'warning',
				message: 'An unterminated XML tag ended the import.',
				offset: opening
			});
			return;
		}
		const rawTag = source.slice(opening + 1, end);
		if (rawTag.trimStart().startsWith('/')) {
			const name = (rawTag.trimStart().slice(1).trim().split(/\s/, 1)[0] ?? '').toLowerCase();
			if (name !== '' && !handlers.end(name, opening)) return;
		} else {
			const tag = parseTag(rawTag, opening, diagnostics);
			if (tag && !handlers.start(tag, opening)) return;
			if (tag?.selfClosing && !handlers.end(tag.name, opening)) return;
		}
		cursor = end + 1;
	}
}

/**
 * Whether a Text run carries Final Draft's AllCaps style.
 *
 * This is how Final Draft shouts: it stores what the writer typed and marks the
 * run, so `<Text Style="AllCaps">cHroNo-aGEnT vAL</Text>` is displayed as
 * CHRONO-AGENT VAL and has been for the life of the document. Read the text
 * without the style and a script that looked immaculate for years opens as
 * though it were typed with a broken shift key.
 *
 * Styles are a '+'-separated list — 'Bold+Underline+AllCaps' — so this matches
 * a whole entry rather than a substring.
 */
function runIsAllCaps(style: string | undefined): boolean {
	if (!style) return false;
	return style
		.split('+')
		.some((part) => part.trim().toLowerCase() === 'allcaps');
}

interface FdxParagraph {
	attributes: Map<string, string>;
	text: string;
	paragraphIndex: number;
	runs: StyleRun[];
	/** Where each block Final Draft embeds in the paragraph — a <DualDialogue>,
	    an <OmittedScene> — sits among its text, as an offset into `text`. */
	blocks: number[];
	/** Each <DualDialogue> directly inside it, as source offsets. */
	dialogues: { start: number; end: number }[];
	/** Each <OmittedScene> directly inside it, as source offsets (§7.3). */
	omissions: { start: number; end: number }[];
}

interface ParsedParagraphs {
	body: FdxParagraph[];
	title: FdxParagraph[];
	hasFinalDraftRoot: boolean;
}

type MutableFdxParagraph = FdxParagraph & {
	inTitlePage: boolean;
	/** Where the whole <Paragraph> sits in the source, for a preserving write. */
	start: number;
	end: number;
	/** Where its direct-child <Text> runs sit, so only they are replaced. */
	textStart: number;
	textEnd: number;
};

/** Whether two run lists say the same thing, property for property. */
function runsEqual(a: StyleRun[], b: StyleRun[]): boolean {
	if (a.length !== b.length) return false;
	return a.every((run, index) => {
		const other = b[index];
		return (
			run.start === other.start &&
			run.end === other.end &&
			run.styles.join() === other.styles.join() &&
			run.revisionID === other.revisionID &&
			(run.tagNumbers ?? []).join() === (other.tagNumbers ?? []).join() &&
			run.highlight === other.highlight
		);
	});
}

/** One Text element's attributes, read as a model run — nothing when the
    run carries nothing (AllCaps aside, which lives in the text itself). */
function modelRunFromAttributes(
	attributes: Map<string, string>,
	start: number,
	end: number
): StyleRun | null {
	if (end <= start) return null;
	const run: StyleRun = { start, end, styles: [] };
	const style = attributes.get('style');
	if (style) {
		const present = new Set(style.split('+').map((part) => part.trim()));
		/* AllCaps stays in the text — the file's own rule (see runIsAllCaps)
		   — so it never becomes a run token here. */
		run.styles = STYLE_ORDER.filter((token) => token !== 'AllCaps' && present.has(token));
	}
	const revision = Number(attributes.get('revisionid'));
	if (Number.isSafeInteger(revision)) run.revisionID = revision;
	const tags = (attributes.get('tagnumber') ?? '')
		.split(',')
		.filter((part) => part.trim() !== '')
		.map((part) => Number(part.trim()))
		.filter((value) => Number.isSafeInteger(value));
	if (tags.length > 0) run.tagNumbers = tags;
	const highlight = attributes.get('edraft:highlight') ?? attributes.get('draftfirst:highlight');
	if ((highlight ?? '').trim().toLowerCase() === 'yellow') run.highlight = 'yellow';
	if (
		run.styles.length === 0 &&
		run.revisionID === undefined &&
		run.tagNumbers === undefined &&
		run.highlight === undefined
	) {
		return null;
	}
	return run;
}

function paragraphsOf(
	source: string,
	limits: FdxLimits,
	diagnostics: DiagnosticCollector
): ParsedParagraphs {
	const body: FdxParagraph[] = [];
	const title: FdxParagraph[] = [];
	let hasFinalDraftRoot = false;
	let titleDepth = 0;
	let textDepth = 0;
	/**
	 * The elements open above the cursor, so a <Content> can be told from its
	 * parent. Self-closing tags dispatch both start and end, so this balances.
	 */
	const open: string[] = [];
	/**
	 * One entry per open <Content>: whether it is the script's.
	 *
	 * A Final Draft document has many. The screenplay is the one directly
	 * under <FinalDraft>, the title page has its own under <TitlePage>, and a
	 * feature written with the Beat Board carries one per <Outline> section —
	 * fifty-three of them in the files this was measured against. Taking
	 * paragraphs from all of them puts the writer's beats, page goals and cast
	 * list into the script.
	 */
	const contents: boolean[] = [];
	const inScriptContent = (): boolean => contents.some(Boolean);
	/**
	 * How deep inside the current paragraph the cursor is, counting everything
	 * that is not the paragraph's own <Text>.
	 *
	 * A paragraph's text is the <Text> that is its *direct child*. Everything
	 * else inside it is Final Draft's metadata — and in a real file that
	 * includes whole paragraphs: a scene heading carries <SceneProperties>
	 * with a <CharacterArcBeat> for every character in the scene, each holding
	 * its own <Paragraph><Text>. Reading those as script is what emptied every
	 * scene heading in the file and put the arc beats in the body.
	 *
	 * Counting rather than naming the containers is deliberate. FDX is a large
	 * and unstable format; a list of tags to skip is a list to keep up with,
	 * and the rule "a paragraph owns only its direct-child Text" is the format
	 * itself. It is bounded by the paragraph's own closing tag, so a strange
	 * document cannot make it run away.
	 */
	let metadataDepth = 0;
	/// Whether the Text run being read is styled AllCaps by Final Draft.
	let runUppercases = false;
	/** The direct-child Text run being read, so its attributes become a
	    model run: styles, revision, tags, and our own highlight. */
	let openRun: { attributes: Map<string, string>; start: number } | null = null;
	let paragraphCount = 0;
	let textRunCount = 0;
	let limitReached = false;
	let current: MutableFdxParagraph | null = null;
	/** The end of the tag that opened at `offset`, past its '>'. */
	const tagEnd = (offset: number): number => {
		const close = source.indexOf('>', offset);
		return close === -1 ? source.length : close + 1;
	};

	const finishParagraph = (): void => {
		if (!current) return;
		metadataDepth = 0;
		if (current.inTitlePage) title.push(current);
		else body.push(current);
		current = null;
		textDepth = 0;
	};

	scanXml(
		source,
		{
			start(tag, offset): boolean {
				const parent = open[open.length - 1];
				open.push(tag.name);

				if (tag.name === 'finaldraft') hasFinalDraftRoot = true;
				if (tag.name === 'titlepage') titleDepth++;
				if (tag.name === 'content') {
					// The screenplay's, the title page's, and nobody else's.
					contents.push(parent === 'finaldraft' || parent === 'titlepage');
				}

				/* A block Final Draft embeds in the paragraph is still skipped as
				   metadata, but its place is kept: a ScriptNote Range counts it. */
				if (current && metadataDepth === 0 && EMBEDDED_BLOCKS.has(tag.name)) {
					current.blocks.push(current.text.length);
					if (tag.name === 'dualdialogue') current.dialogues.push({ start: offset, end: -1 });
					if (tag.name === 'omittedscene') current.omissions.push({ start: offset, end: -1 });
				}
				// Inside a paragraph, anything that is not its own <Text> is
				// metadata — including nested paragraphs. Skipped whole.
				if (current && (metadataDepth > 0 || (tag.name !== 'text' && tag.name !== 'content'))) {
					metadataDepth++;
					return true;
				}

				if (tag.name === 'paragraph' && inScriptContent()) {
					if (paragraphCount >= limits.maxParagraphs) {
						limitReached = true;
						return false;
					}
					if (current) {
						// Not the nested-metadata case, which is handled above:
						// this is a paragraph that never closed.
						diagnostics.add({
							code: 'FDX_NESTED_PARAGRAPH',
							severity: 'warning',
							message: 'A nested Paragraph closed the preceding paragraph best-effort.',
							offset
						});
						finishParagraph();
					}
					current = {
						attributes: tag.attributes,
						text: '',
						paragraphIndex: paragraphCount,
						inTitlePage: titleDepth > 0,
						start: offset,
						end: offset,
						textStart: -1,
						textEnd: -1,
						runs: [],
						blocks: [],
						dialogues: [],
						omissions: []
					};
					paragraphCount++;
				}

				if (tag.name === 'text' && current) {
					if (textRunCount >= limits.maxTextRuns) {
						limitReached = true;
						return false;
					}
					textRunCount++;
					textDepth++;
					if (current.textStart === -1) current.textStart = offset;
					runUppercases = runIsAllCaps(tag.attributes.get('style'));
					openRun = { attributes: tag.attributes, start: current.text.length };
				}
				return true;
			},
			end(name, offset): boolean {
				if (open[open.length - 1] === name) open.pop();

				if (current && metadataDepth > 0) {
					if (name === 'dualdialogue' && metadataDepth === 1 && current.dialogues.length > 0) {
						current.dialogues[current.dialogues.length - 1].end = tagEnd(offset);
					}
					if (name === 'omittedscene' && metadataDepth === 1 && current.omissions.length > 0) {
						current.omissions[current.omissions.length - 1].end = tagEnd(offset);
					}
					metadataDepth--;
					if (name === 'content') contents.pop();
					return true;
				}

				if (name === 'text' && textDepth > 0) {
					textDepth--;
					runUppercases = false;
					if (current) {
						current.textEnd = tagEnd(offset);
						if (openRun) {
							const span = modelRunFromAttributes(openRun.attributes, openRun.start, current.text.length);
							if (span) current.runs.push(span);
							openRun = null;
						}
					}
				}
				if (name === 'paragraph') {
					if (current) current.end = tagEnd(offset);
					finishParagraph();
				}
				if (name === 'content') contents.pop();
				if (name === 'titlepage' && titleDepth > 0) titleDepth--;
				return true;
			},
			text(value, cdata): boolean {
				if (current && textDepth > 0 && metadataDepth === 0) {
					const decoded = cdata ? value : decodeXmlEntities(value);
					current.text += runUppercases ? decoded.toLocaleUpperCase() : decoded;
				}
				return true;
			}
		},
		diagnostics
	);

	const unterminated = current as MutableFdxParagraph | null;
	if (unterminated) {
		diagnostics.add({
			code: 'FDX_UNTERMINATED_PARAGRAPH',
			severity: 'warning',
			message: 'An unterminated Paragraph was imported best-effort.',
			paragraphIndex: unterminated.paragraphIndex
		});
		finishParagraph();
	}
	if (limitReached) {
		diagnostics.add({
			code: 'FDX_PARSE_LIMIT_REACHED',
			severity: 'error',
			message: `Import stopped at ${limits.maxParagraphs} paragraphs or ${limits.maxTextRuns} Text runs.`,
			count: paragraphCount
		});
	}

	return { body, title, hasFinalDraftRoot };
}

function attributeOf(paragraph: FdxParagraph, name: string): string {
	return paragraph.attributes.get(name.toLowerCase()) ?? '';
}

/**
 * One of our own extension attributes, read under the current prefix or any
 * legacy one. Files exported before the eDraft rename carry `draftfirst:`;
 * they must keep importing losslessly, so every reader tries both.
 */
function extensionAttribute(paragraph: FdxParagraph, name: string): string {
	const current = attributeOf(paragraph, `${EDRAFT_PREFIX}:${name}`);
	if (current !== '') return current;
	for (const legacy of LEGACY_ATTRIBUTE_PREFIXES) {
		const value = attributeOf(paragraph, `${legacy}:${name}`);
		if (value !== '') return value;
	}
	return '';
}

/* ---- import ------------------------------------------------------------- */

/** The title page, verbatim (RFC-TITLE-PAGE D5): every paragraph becomes a
    line — text, alignment, styled runs, blanks and all. Our TitleKey
    extension attribute survives as an annotation when the file carries it;
    nothing is guessed, because guessing was how foreign files lost their
    layout. */
function titlePageLinesOf(paragraphs: FdxParagraph[]): TitlePageLine[] {
	return paragraphs.map((paragraph) => {
		const line: TitlePageLine = { text: paragraph.text };
		const alignment = attributeOf(paragraph, 'alignment').toLowerCase();
		if (alignment === 'left' || alignment === 'right') line.alignment = alignment;
		else if (alignment === 'center') line.alignment = 'center';
		const runs = normaliseRuns(paragraph.runs, paragraph.text.length);
		if (runs.length > 0) line.runs = runs;
		const key = extensionAttribute(paragraph, 'titlekey');
		if (key !== '') line.key = key;
		return line;
	});
}

function emptyImport(diagnostics: DiagnosticCollector): FdxImportResult {
	const items = diagnostics.result();
	return {
		script: { titlePage: [], elements: [] },
		warnings: messagesOf(items),
		diagnostics: items,
		scriptNotes: []
	};
}

export function parseFdx(xml: string, options: FdxImportOptions = {}): FdxImportResult {
	const limits = importLimits(options);
	const diagnostics = new DiagnosticCollector(limits.maxWarnings);
	let source: string;
	try {
		source = String(xml ?? '');
	} catch {
		diagnostics.add({
			code: 'FDX_INPUT_CONVERSION_FAILED',
			severity: 'error',
			message: 'The FDX input could not be converted to text.'
		});
		return emptyImport(diagnostics);
	}

	if (source.length > limits.maxSourceCharacters) {
		diagnostics.add({
			code: 'FDX_INPUT_TOO_LARGE',
			severity: 'error',
			message: `The FDX input exceeds the ${limits.maxSourceCharacters}-character safety limit.`,
			count: source.length
		});
		return emptyImport(diagnostics);
	}

	try {
		const parsed = paragraphsOf(source, limits, diagnostics);
		if (!parsed.hasFinalDraftRoot) {
			diagnostics.add({
				code: 'FDX_ROOT_MISSING',
				severity: 'warning',
				message: 'Missing <FinalDraft> root — attempting best-effort paragraph import.'
			});
		}

		const elements: ScreenplayElement[] = [];
		/* Scenes the production has omitted (§7.3), as spans over `elements`. */
		const omissions: Omission[] = [];
		/* Every body paragraph as a ScriptNote Range counts it — absorbed ones
		   included, because Final Draft's text still holds them. */
		const layout: ParagraphLayout[] = [];
		for (const paragraph of parsed.body) {
			const fdxType = attributeOf(paragraph, 'type');
			const key = fdxType.trim().toLowerCase();
			/* RFC-ACT-BREAK D3: an End of Act carries no fact the model lacks —
			   an act ends where the next one begins, and the export regenerates
			   these. Absorbed without a warning: a diagnostic the reader cannot
			   act on only teaches them to ignore the list. */
			layout.push({
				length: paragraph.text.length + BLOCK_UNITS * paragraph.blocks.length,
				blocks: paragraph.blocks,
				element: key === 'end of act' ? -1 : elements.length
			});
			if (key === 'end of act') continue;
			const kind = fdxElementKind(key);
			if (!kind && fdxType !== '') {
				diagnostics.add({
					code: 'FDX_UNKNOWN_PARAGRAPH_TYPE',
					severity: 'warning',
					message: `Unknown paragraph type "${fdxType}" — imported as General.`,
					paragraphIndex: paragraph.paragraphIndex
				});
			}

			/* Final Draft keeps dual dialogue as a paragraph with no text of its
			   own holding a <DualDialogue>, whose paragraphs are the two
			   speeches. Read as metadata, all of it was invisible: each block
			   arrived as one empty General element. Its lines are the script. */
			const lines = dualDialogueOf(source, paragraph, limits);
			if (lines) {
				let cues = 0;
				for (const line of lines) {
					const element = elementOf(line, fdxElementKind(attributeOf(line, 'type').trim().toLowerCase()));
					// The second speaker's cue is the one Fountain marks `^`.
					if (element.type === 'character' && ++cues === 2) element.dual = true;
					elements.push(element);
				}
				continue;
			}
			if (paragraph.dialogues.length > 0) {
				diagnostics.add({
					code: 'FDX_DUAL_DIALOGUE_NOT_READ',
					severity: 'warning',
					message: 'A paragraph holds dual dialogue in a form not read (text of its own, or more than one block); its speeches are not shown.',
					paragraphIndex: paragraph.paragraphIndex
				});
			}
			/* An omitted scene is nested inside the Scene Heading that shows
			   its OMITTED card (§7.3). The card stays the element it always
			   was — its index, its number, its Range unchanged — and the
			   body follows it, with the omission naming the span. Skipped as
			   metadata before this, the whole scene was lost on any export
			   that did not keep the file's own bytes. */
			elements.push(elementOf(paragraph, kind));
			const omitted = key === 'end of act' ? null : omittedSceneOf(source, paragraph, limits);
			if (omitted) {
				const start = elements.length;
				for (const line of omitted) {
					elements.push(elementOf(line, fdxElementKind(attributeOf(line, 'type').trim().toLowerCase())));
				}
				omissions.push({ start, end: elements.length });
			}
		}

		const places: ScriptNotesPlaces = { notes: [], container: null, afterCharacters: null, rootClose: null };
		const read = scriptNotesOf(source, layout, limits, diagnostics, undefined, places);
		const { elements: withOwn, scriptNotes, movedTo } = withOwnedNotes(elements, read, places.notes.map((note) => note.owned));
		return {
			script: {
				titlePage: titlePageLinesOf(parsed.title),
				elements: withOwn,
				/* Notes read in front of their line shift the elements after
				   them, so a span recorded during the read is moved with them. */
				...(omissions.length > 0 ? { omissions: movedOmissions(omissions, movedTo, withOwn.length) } : {})
			},
			warnings: messagesOf(diagnostics.result()),
			diagnostics: diagnostics.result(),
			scriptNotes
		};
	} catch (error) {
		diagnostics.add({
			code: 'FDX_IMPORT_FAILED',
			severity: 'error',
			message: `FDX import stopped safely: ${error instanceof Error ? error.message : 'unknown parser failure'}.`
		});
		return emptyImport(diagnostics);
	}
}

/**
 * What a paragraph typed "General" actually is.
 *
 * Final Draft has one bucket for anything that is not a script element, and
 * what it means is carried by other attributes: centred by its alignment,
 * lyrics by ours. Shared by the import and the preserving rewrite, because a
 * rewrite has to reach the same answer the import did — deriving it twice was
 * how a centred paragraph came out as an unmatched insert and rewrote the tail
 * of the file.
 */
/**
 * The outline levels, which Final Draft lets a writer rename.
 *
 * Stock they are `Outline 1`, `Outline 2`, `Outline 3`; renamed they arrive as
 * `Outline 1 (Acts)`, `Outline 2 (Sequences)`, `Outline 3 (Scenes)` — both
 * shapes are in the two production drafts this was measured on, from the same
 * writer. Matching the number and ignoring whatever they called it is the only
 * rule that reads both.
 */
const OUTLINE_TYPE = /^outline\s+(\d+)(?:\s*\(.*\))?$/;

/**
 * What a Final Draft paragraph type means to the engine, and how deep it sits.
 *
 * `undefined` for a type we have never heard of — the caller warns and falls
 * back to General, which is what it always did.
 */
function elementOf(paragraph: FdxParagraph, kind: { type: AnyElementType; depth?: number } | undefined): ScreenplayElement {
	const type = refineGeneral(kind?.type ?? 'general', paragraph);
	const element: ScreenplayElement = { type, text: paragraph.text };
	if (paragraph.runs.length > 0) {
		element.runs = normaliseRuns(paragraph.runs, (paragraph.text as string).length);
	}
	if (type === 'section' && kind?.depth !== undefined) element.depth = kind.depth;
	const sceneNumber = attributeOf(paragraph, 'number');
	if (type === 'scene' && sceneNumber !== '') element.sceneNumber = sceneNumber;
	if (type === 'character' && attributeOf(paragraph, 'dual').toLowerCase() === 'yes') {
		element.dual = true;
	}
	return element;
}

/** Both blocks Final Draft embeds in a paragraph are re-read inside this
    minimal frame: the wrapper tag itself is not a paragraph, so the scanner
    walks straight past it to the paragraphs inside. */
const EMBEDDED_BLOCK_FRAME = '<FinalDraft><Content>';

/**
 * The lines of a dual dialogue: the paragraphs of the one <DualDialogue> a
 * paragraph with no text of its own holds, in order, with where they sit —
 * or null for any other paragraph.
 *
 * Measured on files Final Draft wrote, every dual dialogue has this form: a
 * General paragraph, no text, one block of Character, Dialogue, Character,
 * Dialogue. The block is read as a script of its own, so each line is read
 * exactly as a body paragraph is.
 */
function dualDialogueOf(source: string, paragraph: FdxParagraph, limits: FdxLimits): MutableFdxParagraph[] | null {
	if (paragraph.text !== '' || paragraph.dialogues.length !== 1 || paragraph.dialogues[0].end === -1) return null;
	const { start, end } = paragraph.dialogues[0];
	const shift = start - EMBEDDED_BLOCK_FRAME.length;
	const parsed = paragraphsOf(`${EMBEDDED_BLOCK_FRAME}${source.slice(start, end)}</Content></FinalDraft>`, limits, new DiagnosticCollector(1));
	if (parsed.body.length === 0) return null;
	return parsed.body.map((line) => {
		const held = line as MutableFdxParagraph;
		return {
			...held,
			start: held.start + shift,
			end: held.end + shift,
			textStart: held.textStart === -1 ? -1 : held.textStart + shift,
			textEnd: held.textEnd === -1 ? -1 : held.textEnd + shift
		};
	});
}

/**
 * The paragraphs of the <OmittedScene> a paragraph holds, or null when it
 * holds none (RFC-DRAFT-PRODUCTION §7.3).
 *
 * Final Draft nests an omitted scene INSIDE the Scene Heading paragraph that
 * shows the OMITTED card, so unlike a dual dialogue the holding paragraph
 * has text of its own — the card's. Read like a dual dialogue: the block is
 * a script of its own, so each paragraph inside it is read exactly as a body
 * paragraph is, and offsets are shifted back onto the real source.
 */
function omittedSceneOf(source: string, paragraph: FdxParagraph, limits: FdxLimits): MutableFdxParagraph[] | null {
	if (paragraph.omissions.length !== 1 || paragraph.omissions[0].end === -1) return null;
	const { start, end } = paragraph.omissions[0];
	const shift = start - EMBEDDED_BLOCK_FRAME.length;
	const parsed = paragraphsOf(`${EMBEDDED_BLOCK_FRAME}${source.slice(start, end)}</Content></FinalDraft>`, limits, new DiagnosticCollector(1));
	if (parsed.body.length === 0) return null;
	return parsed.body.map((line) => {
		const held = line as MutableFdxParagraph;
		return {
			...held,
			start: held.start + shift,
			end: held.end + shift,
			textStart: held.textStart === -1 ? -1 : held.textStart + shift,
			textEnd: held.textEnd === -1 ? -1 : held.textEnd + shift
		};
	});
}

function fdxElementKind(key: string): { type: AnyElementType; depth?: number } | undefined {
	const known = FDX_TO_MODEL[key];
	if (known) return { type: known };

	/* An outline heading is a section, at the level Final Draft gives it.
	   Read as General these printed on the page as stage directions — 82 of
	   them across the two real features, and they took the page count with
	   them, because a section does not paginate and General does. */
	const outline = OUTLINE_TYPE.exec(key);
	if (outline) return { type: 'section', depth: Math.max(1, Number(outline[1])) };

	/* The prose under an outline heading. Fountain calls it a synopsis and
	   writes it `= like this`; Final Draft calls it a Summary. Same thing:
	   what the scene is for, not a line of it. */
	if (key === 'summary') return { type: 'synopsis' };

	return undefined;
}

/** The Final Draft paragraph type an element goes out as. */
function fdxTypeOf(element: {
	type: AnyElementType;
	depth?: number;
}): string | undefined {
	/* Keyed on the element rather than on its type alone, because a section's
	   level is part of what it is: `# Act One` is `Outline 1` and `### A scene`
	   is `Outline 3`, and a map from type to string cannot say that. */
	if (element.type === 'section') return `Outline ${Math.max(1, element.depth ?? 1)}`;
	return MODEL_TO_FDX[element.type];
}

function refineGeneral(type: AnyElementType, paragraph: FdxParagraph): AnyElementType {
	if (type !== 'general') return type;
	if (extensionAttribute(paragraph, 'elementtype').toLowerCase() === 'lyrics') return 'lyrics';
	if (attributeOf(paragraph, 'alignment').toLowerCase() === 'center') return 'centered';
	return type;
}

/* ---- script notes ------------------------------------------------------- */

/**
 * The blocks Final Draft embeds inside a script paragraph, and what each
 * counts in a ScriptNote Range: two units, wherever it sits, its own
 * paragraphs' text nothing.
 *
 * Measured on files Final Draft wrote. Counted as zero, every position after
 * a block landed two units late for each block before it: in each of two
 * files, two notes began mid-word and one fell past the script's end. Counted
 * as two, every note lands on whole words or is empty.
 */
const EMBEDDED_BLOCKS: ReadonlySet<string> = new Set(['dualdialogue', 'omittedscene']);
const BLOCK_UNITS = 2;

/** One body paragraph as a ScriptNote Range counts it: its text length plus
    two units for each embedded block, where those blocks sit in its text, and
    the element it became — -1 when the import absorbed it. */
interface ParagraphLayout {
	length: number;
	blocks: number[];
	element: number;
}

/** A unit of a paragraph as a Range counts it, as an offset into its text:
    the units of an embedded block are the place it sits. */
function textOffsetIn(paragraph: ParagraphLayout, unit: number): number {
	let passed = 0;
	for (const at of paragraph.blocks) {
		if (unit < at + passed) break;
		if (unit < at + passed + BLOCK_UNITS) return at;
		passed += BLOCK_UNITS;
	}
	return Math.min(unit - passed, paragraph.length - BLOCK_UNITS * paragraph.blocks.length);
}

/** The script's text as a ScriptNote Range counts it. */
interface ScriptText {
	layout: ParagraphLayout[];
	starts: number[];
	/** The position just past the last paragraph's text. */
	end: number;
}

function scriptTextOf(layout: ParagraphLayout[]): ScriptText {
	const starts: number[] = [];
	let cursor = 0;
	for (const paragraph of layout) {
		starts.push(cursor);
		cursor += paragraph.length + 1;
	}
	return { layout, starts, end: cursor - 1 };
}

/**
 * Where a Range position lands in the imported screenplay.
 *
 * Final Draft counts the script paragraph by paragraph, one unit for each
 * paragraph break — measured on a real feature, where one Range began on the
 * first character of the shot it was about and another covered exactly one
 * character cue. A break belongs to the paragraph before it, so every position
 * from 0 to the end of the script lands in exactly one paragraph.
 *
 * A position in a paragraph the import absorbed — an End of Act — moves to the
 * start of the next element, or to the end of the last one when nothing
 * follows. Past the end of the script there is nothing honest to point at.
 */
function positionIn(text: ScriptText, position: number): FdxScriptNotePosition | undefined {
	const { layout, starts } = text;
	if (layout.length === 0 || position < 0 || position > text.end) return undefined;
	let low = 0;
	let high = layout.length - 1;
	while (low < high) {
		const middle = (low + high + 1) >> 1;
		if (starts[middle] <= position) low = middle;
		else high = middle - 1;
	}
	if (layout[low].element !== -1) {
		return { element: layout[low].element, offset: textOffsetIn(layout[low], position - starts[low]) };
	}
	for (let next = low + 1; next < layout.length; next++) {
		if (layout[next].element !== -1) return { element: layout[next].element, offset: 0 };
	}
	for (let previous = low - 1; previous >= 0; previous--) {
		if (layout[previous].element !== -1) {
			return { element: layout[previous].element, offset: textOffsetIn(layout[previous], layout[previous].length) };
		}
	}
	return undefined;
}

/**
 * Where a Range lands. A Range that starts past the script is stale and has
 * no anchor; one that only ends past it is held to the script's end, so the
 * note still marks the text it does cover.
 */
function anchorOf(
	range: { start: number; end: number },
	text: ScriptText
): FdxScriptNote['anchor'] {
	const start = positionIn(text, range.start);
	const end = positionIn(text, Math.min(range.end, text.end));
	return start && end ? { start, end } : undefined;
}

/** Where the file's <ScriptNotes> sit, so a save can take one out or add one. */
interface ScriptNotesPlaces {
	/** Each <ScriptNote>, in file order: from the line break in front of it
	    (when only its indent is between) to the end of its closing tag. */
	notes: { start: number; end: number; id: number; owned: OwnedNote | null }[];
	/** The <ScriptNotes> container: where it opens, and where its closing tag
	    starts — null when it closes itself. */
	container: { open: number; close: number | null; selfClosing: boolean } | null;
	/** Just past the top-level </Characters>, where Final Draft keeps them. */
	afterCharacters: number | null;
	/** Where </FinalDraft> starts. */
	rootClose: number | null;
}

/** Where a ScriptNote's Range value sits in the source, and what it says. */
interface ScriptNoteRangeValue {
	valueStart: number;
	valueEnd: number;
	range: { start: number; end: number };
	/** Written end first. Kept that way when the Range is rewritten. */
	reversed: boolean;
}

/** The Range value of the <ScriptNote> tag opening at `tagStart` — the last
    one, as the tag's attributes read — or null when it has none readable. */
function rangeValueIn(source: string, tagStart: number): ScriptNoteRangeValue | null {
	const tagEnd = tagEndOf(source, tagStart + 1);
	const tag = source.slice(tagStart, tagEnd === -1 ? source.length : tagEnd);
	let found: RegExpExecArray | null = null;
	const pattern = /\srange\s*=\s*(?:"([^"]*)"|'([^']*)')/gi;
	for (let match = pattern.exec(tag); match !== null; match = pattern.exec(tag)) found = match;
	if (found === null) return null;
	const value = found[1] ?? found[2] ?? '';
	const range = rangeOf(decodeXmlEntities(value));
	if (!range) return null;
	const pair = /^\s*(\d+)\s*,\s*(\d+)\s*$/.exec(decodeXmlEntities(value));
	const valueEnd = tagStart + found.index + found[0].length - 1;
	return {
		valueStart: valueEnd - value.length,
		valueEnd,
		range,
		reversed: pair !== null && Number(pair[1]) > Number(pair[2])
	};
}

/** A Range attribute, `start,end` in digits. A reversed pair is the same span. */
function rangeOf(value: string): { start: number; end: number } | undefined {
	const match = /^\s*(\d+)\s*,\s*(\d+)\s*$/.exec(value);
	if (!match) return undefined;
	const first = Number(match[1]);
	const second = Number(match[2]);
	if (!Number.isSafeInteger(first) || !Number.isSafeInteger(second)) return undefined;
	return { start: Math.min(first, second), end: Math.max(first, second) };
}

function scriptNoteOf(
	attributes: Map<string, string>,
	paragraphs: string[],
	text: ScriptText
): FdxScriptNote {
	const verbatim = (name: string): string | undefined => {
		const value = attributes.get(name) ?? '';
		return value.trim() === '' ? undefined : value;
	};
	const note = {} as FdxScriptNote;
	const id = verbatim('id');
	if (id !== undefined) note.id = id;
	const author = (attributes.get('writername') ?? '').trim();
	if (author !== '') note.author = author;
	const title = verbatim('name');
	if (title !== undefined) note.title = title;
	const category = verbatim('type');
	if (category !== undefined) note.category = category;
	const color = verbatim('color');
	if (color !== undefined && !/^#0+$/.test(color)) note.color = color;
	const created = verbatim('datetime');
	if (created !== undefined) note.created = created;
	const modified = verbatim('datemodified');
	if (modified !== undefined) note.modified = modified;
	const range = rangeOf(attributes.get('range') ?? '');
	if (range) {
		note.range = range;
		const anchor = anchorOf(range, text);
		if (anchor) note.anchor = anchor;
	}
	note.text = paragraphs.join('\n');
	return note;
}

/**
 * The file's ScriptNotes.
 *
 * A second, narrow scan, like `bodySpansOf`, so the reader the preserving
 * save depends on is not touched to serve it. A note is a <ScriptNote>
 * directly inside <ScriptNotes>; its body is its direct-child paragraphs'
 * direct-child <Text>, the same rule the script's own paragraphs follow.
 * Notes and their paragraphs are bounded by `maxParagraphs`, their runs by
 * `maxTextRuns`, counted apart from the script's.
 */
function scriptNotesOf(
	source: string,
	layout: ParagraphLayout[],
	limits: FdxLimits,
	diagnostics: DiagnosticCollector,
	rangeValues?: (ScriptNoteRangeValue | null)[],
	places?: ScriptNotesPlaces
): FdxScriptNote[] {
	const text = scriptTextOf(layout);
	const notes: FdxScriptNote[] = [];
	const open: string[] = [];
	let note: { attributes: Map<string, string>; depth: number; paragraphs: string[]; start: number } | null = null;
	let paragraph: { text: string; depth: number } | null = null;
	let run: { uppercases: boolean; depth: number } | null = null;
	let paragraphCount = 0;
	let textRunCount = 0;
	let limitReached = false;

	const finishNote = (closing?: number): void => {
		if (!note) return;
		if (paragraph) note.paragraphs.push(paragraph.text);
		notes.push(scriptNoteOf(note.attributes, note.paragraphs, text));
		if (places) {
			const end = closing === undefined ? source.length : source.indexOf('>', closing) + 1 || source.length;
			const lineStart = source.lastIndexOf('\n', note.start - 1);
			const indentOnly = lineStart !== -1 && /^[ \t]*$/.test(source.slice(lineStart + 1, note.start));
			places.notes.push({
				start: indentOnly ? lineStart : note.start,
				end,
				id: /^\d+$/.test((note.attributes.get('id') ?? '').trim()) ? Number((note.attributes.get('id') ?? '').trim()) : NaN,
				owned: ownedNoteOf(note.attributes.get('name'), note.attributes.get('writername'), note.attributes.get('type'), note.paragraphs)
			});
		}
		note = null;
		paragraph = null;
		run = null;
	};

	scanXml(
		source,
		{
			start(tag, offset): boolean {
				const parent = open[open.length - 1];
				open.push(tag.name);
				const opensNote = tag.name === 'scriptnote' && parent === 'scriptnotes' && !note;
				if (places && open.length === 2 && tag.name === 'scriptnotes' && !places.container) {
					places.container = { open: offset, close: null, selfClosing: tag.selfClosing === true };
				}
				const opensParagraph =
					note !== null && tag.name === 'paragraph' && open.length === note.depth + 1;
				if (opensNote || opensParagraph) {
					if (paragraphCount >= limits.maxParagraphs) {
						limitReached = true;
						return false;
					}
					paragraphCount++;
				}
				if (opensNote) {
					note = { attributes: tag.attributes, depth: open.length, paragraphs: [], start: offset };
					rangeValues?.push(rangeValueIn(source, offset));
				} else if (opensParagraph) {
					paragraph = { text: '', depth: open.length };
				} else if (paragraph && tag.name === 'text' && open.length === paragraph.depth + 1) {
					if (textRunCount >= limits.maxTextRuns) {
						limitReached = true;
						return false;
					}
					textRunCount++;
					run = { uppercases: runIsAllCaps(tag.attributes.get('style')), depth: open.length };
				}
				return true;
			},
			end(name, offset): boolean {
				if (run && name === 'text' && open.length === run.depth) {
					run = null;
				} else if (note && paragraph && name === 'paragraph' && open.length === paragraph.depth) {
					note.paragraphs.push(paragraph.text);
					paragraph = null;
				} else if (note && name === 'scriptnote' && open.length === note.depth) {
					finishNote(offset);
				}
				if (places && open.length === 2 && open[1] === name) {
					if (name === 'scriptnotes' && places.container && !places.container.selfClosing && places.container.close === null) {
						places.container.close = offset;
					}
					if (name === 'characters') places.afterCharacters = source.indexOf('>', offset) + 1 || null;
				}
				if (places && open.length === 1 && name === 'finaldraft') places.rootClose = offset;
				if (open[open.length - 1] === name) open.pop();
				return true;
			},
			text(value, cdata): boolean {
				if (run && paragraph && open.length === run.depth) {
					const decoded = cdata ? value : decodeXmlEntities(value);
					paragraph.text += run.uppercases ? decoded.toLocaleUpperCase() : decoded;
				}
				return true;
			}
		},
		new DiagnosticCollector(1)
	);

	finishNote();
	if (limitReached) {
		diagnostics.add({
			code: 'FDX_SCRIPT_NOTES_LIMIT_REACHED',
			severity: 'warning',
			message: `Script notes stopped at ${limits.maxParagraphs} notes and paragraphs or ${limits.maxTextRuns} Text runs.`,
			count: notes.length
		});
	}
	return notes;
}

/**
 * The notes eDraft wrote, back as the writer's own (RFC-NOTES-SYSTEM §4.3).
 *
 * A ScriptNote titled `[eDraft]` is eDraft's: it becomes a note element in
 * front of the element its Range starts in —
 * where the editor keeps a note — reading `Name (Role): words`, and is no
 * longer one of the file's notes. A note whose Range lands nowhere goes to the
 * end of the script, as an editor note whose line is gone does. Final Draft's
 * notes stay as they are, their anchors moved past the elements put in.
 */
function withOwnedNotes(
	elements: ScreenplayElement[],
	notes: FdxScriptNote[],
	ownership: (OwnedNote | null)[]
): { elements: ScreenplayElement[]; scriptNotes: FdxScriptNote[]; movedTo: number[] | null } {
	const inFront = new Map<number, ScreenplayElement[]>();
	const theirs: FdxScriptNote[] = [];
	notes.forEach((note, index) => {
		const owned = ownership[index];
		if (!owned) {
			theirs.push(note);
			return;
		}
		const at = note.anchor?.start.element ?? elements.length;
		/* The words its Range covers, back as the anchor the editor holds
		   (§5.4). A Range over the whole paragraph carries no anchor. */
		const anchor = note.anchor ? anchorOfRange(elements, note.anchor) : undefined;
		inFront.set(at, [
			...(inFront.get(at) ?? []),
			{ type: 'note', text: ownedNoteText(owned), ...(anchor ? { anchor } : {}) }
		]);
	});
	if (inFront.size === 0) return { elements, scriptNotes: notes, movedTo: null };
	const result: ScreenplayElement[] = [];
	const movedTo: number[] = [];
	elements.forEach((element, index) => {
		result.push(...(inFront.get(index) ?? []));
		movedTo.push(result.length);
		result.push(element);
	});
	result.push(...(inFront.get(elements.length) ?? []));
	const moved = (position: FdxScriptNotePosition): FdxScriptNotePosition => ({
		element: movedTo[position.element],
		offset: position.offset
	});
	return {
		elements: result,
		scriptNotes: theirs.map((note) =>
			note.anchor ? { ...note, anchor: { start: moved(note.anchor.start), end: moved(note.anchor.end) } } : note
		),
		movedTo
	};
}

/** An omission span, after the notes read in front of their lines have
    moved the elements it covers. `movedTo` is null when nothing moved. */
function movedOmissions(omissions: readonly Omission[], movedTo: number[] | null, total: number): Omission[] {
	if (movedTo === null) return omissions.map((omission) => ({ ...omission }));
	return omissions.map(({ start, end }) => ({
		start: movedTo[start],
		/* `end` is exclusive: it is where the element after the span went, or
		   the end of the script when the span runs to it. */
		end: end < movedTo.length ? movedTo[end] : total
	}));
}

/**
 * Where each omitted scene's body sits in the elements being saved.
 *
 * The file says which paragraphs are inside an <OmittedScene> and which
 * Scene Heading holds them; this finds that run in the script the caller is
 * saving, anchored on the card's own words and taken in file order. The run
 * is found by the file's structure rather than by `script.omissions`,
 * because Fountain has no spelling for an omission and the app's own save
 * path goes through Fountain.
 *
 * A body whose words all still match is found exactly. One whose words were
 * edited is still found, by its card and its length — the save keeps the
 * file's version and says so. A card whose words are gone is not guessed at.
 */
function omittedRunsIn(
	elements: readonly ScreenplayElement[],
	spans: readonly OriginParagraph[]
): { start: number; body: string[] }[] {
	const runs: { start: number; body: string[] }[] = [];
	/* Compared without casing: a round trip through Fountain gives a scene
	   heading its canonical capitals, so the card and the body's first line
	   come back in different letters from the ones the file holds. */
	const key = (text: string): string => text.trim().toUpperCase();
	let from = 0;
	for (const span of spans) {
		const body = span.omittedBody;
		if (!body || body.length === 0) continue;
		const scoreAt = (at: number): number => {
			let matched = 0;
			for (let k = 0; k < body.length; k++) {
				if (elements[at + k]?.text === body[k]) matched++;
			}
			return matched;
		};
		/* The card holds the body: its own paragraph is the one the block is
		   nested in, so the run begins at the element after it. */
		let best = -1;
		let score = -1;
		const cardKey = key(span.text);
		for (let at = from; at + body.length <= elements.length; at++) {
			if (key(elements[at].text) !== cardKey) continue;
			const found = scoreAt(at + 1);
			if (found > score) {
				score = found;
				best = at + 1;
				if (found === body.length) break;
			}
		}
		/* A card with nothing of its body left under it is not evidence: the
		   scene may have been edited, or deleted, and taking the elements that
		   follow would swallow live paragraphs. At least one line must stand. */
		if (score < 1) best = -1;
		/* No card to hang it on — its words were changed too. The body itself
		   is then the only evidence, and it has to be unmistakable. */
		if (best === -1) {
			const needed = Math.max(1, Math.ceil(body.length * 0.6));
			score = -1;
			for (let at = from; at + body.length <= elements.length; at++) {
				const found = scoreAt(at);
				if (found >= needed && found > score) {
					score = found;
					best = at;
					if (found === body.length) break;
				}
			}
			if (best === -1) continue;
		}
		runs.push({ start: best, body });
		from = best + body.length;
	}
	return runs;
}

/* ---- preserving round trip ---------------------------------------------- */

/**
 * A Final Draft file, kept whole.
 *
 * Reading an .fdx into a screenplay and writing a new one from that screenplay
 * throws away everything the screenplay cannot hold. Measured on a real
 * production draft: 19 revisions, 171 revised runs, 25 locked pages, 73
 * deleted-text marks, 248 production tags, 6 dual-dialogue blocks, 136
 * emphasis runs and 3 script notes — all gone, from opening the file, changing
 * one word and saving. On a script a crew is shooting from, the revision
 * history and the locked pages *are* the document.
 *
 * So the file is not rebuilt, it is edited. The original stays, and a write
 * replaces only the paragraphs whose text actually changed. Everything else —
 * every attribute, every nested block, and the whole of the document outside
 * the script's own <Content> — is emitted byte for byte as it arrived.
 *
 * The point is that this costs no understanding. eDraft does not have to know
 * what a `<TagDefinition>` or a `<LockedPage>` means in order to keep it, and
 * a future version of Final Draft can invent a dozen more without this needing
 * to be told.
 */
export interface FdxDocument extends FdxImportResult {
	/**
	 * The screenplay written back into the file it came from.
	 *
	 * Unchanged paragraphs keep their bytes. A paragraph whose text changed
	 * keeps its attributes and its nested blocks — a scene heading keeps its
	 * <SceneProperties> and its arc beats — and only its own <Text> is
	 * rewritten. New paragraphs are written the way `writeFdx` writes them.
	 */
	rewrite(script: Screenplay, options?: FdxRewriteOptions): FdxExportResult;
}

export interface FdxRewriteOptions {
	/**
	 * This file as the caller read it before any edit — for an editor that
	 * works in Fountain, the file carried through Fountain and read back.
	 *
	 * A representation that cannot carry everything the file does makes every
	 * paragraph it cannot carry look edited: Fountain has no production tags,
	 * no revision marks, and reads an emphasised heading as Action. Given this
	 * reading, a paragraph whose element comes back exactly as it was read is
	 * written as its original bytes, whatever the representation lost. Without
	 * it, the save judges each paragraph against the file itself.
	 */
	unedited?: Screenplay;
	/** How the writer's notes are written into <ScriptNotes>. */
	notes?: FdxNoteWriting;
}

/** One paragraph as it sits in the original file. */
interface OriginParagraph {
	key: string;
	/** Its words, as the import read them. */
	text: string;
	type: AnyElementType;
	start: number;
	end: number;
	textStart: number;
	textEnd: number;
	/**
	 * The whitespace between the paragraph before it and this one.
	 *
	 * Kept so a save reproduces the file byte for byte. Final Draft indents
	 * its Content; joining paragraphs with a newline would rewrite every line
	 * of a 750KB document, which turns "I fixed a typo" into a diff nobody can
	 * read and makes it impossible to see what actually changed.
	 */
	lead: string;
	/** The runs the file itself declared, in canonical form, for the content
	    gate on a preserving save — a run changed without a character moving
	    still rewrites the paragraph. Canonical because Final Draft splits runs
	    the model merges ("HOME LIBRARY, " and "CASALINDA", one tag): compared
	    raw, every such paragraph read as edited and lost its tags on a save
	    that changed nothing. */
	runs: StyleRun[];
	/**
	 * Whether the import absorbed this paragraph — an End of Act — so that no
	 * element will ever stand for it. The rewrite writes these back itself
	 * and never lets the alignment see them; see `openFdx`.
	 */
	absorbed: boolean;
	/** For the Scene Heading that holds an <OmittedScene> (§7.3): the words of
	    the paragraphs nested inside it, in order. The block's bytes belong to
	    this paragraph, so a preserving save writes them back untouched and the
	    body's elements take no part in the alignment. */
	omittedBody?: string[];
	/** The dual dialogue this paragraph is a line of. */
	block?: DualDialogueBlock;
}

/**
 * A Final Draft dual dialogue as the save sees it: the paragraph that holds
 * the <DualDialogue>, as a frame around its lines. Each line is a paragraph
 * to the save like any other; the frame is written around the lines kept
 * together, verbatim.
 */
interface DualDialogueBlock {
	/** The whitespace before the holding paragraph. */
	lead: string;
	start: number;
	end: number;
	/** The frame: its bytes up to the first line, and after the last line. */
	head: string;
	tail: string;
	lines: OriginParagraph[];
}

/**
 * How a paragraph is recognised across a round trip.
 *
 * Compared with the casing the app applies rather than the letters the file
 * stores, because Final Draft stores what the writer typed and puts the
 * capitals on in the *view* — `ElementSettings Type="Scene Heading"` carries
 * `Style="Bold+AllCaps"`. Opening `Deeper in the woods - cONTINUOUS` therefore
 * gives a screenplay that says DEEPER IN THE WOODS - CONTINUOUS, and comparing
 * the letters would call every heading, cue and transition in the file an
 * edit: measured, that rewrote them all, lost the writer's own casing, and
 * dropped the `<DualDialogue>` wrappers that live between the paragraphs it
 * replaced.
 *
 * So casing is not an edit. The file keeps what the writer typed; the app goes
 * on showing capitals.
 */
function originKey(type: AnyElementType, text: string): string {
	return canonicalCasing(type as ElementType, text);
}

/**
 * Element kinds a Fountain round trip cannot carry.
 *
 * The document eDraft edits is Fountain, and Fountain has no `General` and no
 * `Shot` — both arrive back as action. So a paragraph of either kind looks to
 * a naive comparison as though the writer retyped it, and rewriting it as
 * Action is a loss the writer never asked for. The file's own type is
 * authoritative for these; eDraft cannot prove it changed.
 */
const FOUNTAIN_FLATTENS = new Set<AnyElementType>(['general', 'shot']);

/**
 * Which original paragraphs the new screenplay still contains.
 *
 * A longest-common-subsequence over (type, text): what matches is kept
 * verbatim, what does not is an edit. The pass afterwards is what makes this
 * worth doing — a delete and an insert of the same element type, adjacent, is
 * one paragraph whose text was edited, and pairing them keeps its attributes
 * and its nested blocks instead of discarding them and writing a bare one.
 *
 * Falls back to matching by position when a script is large enough that the
 * table would be extravagant. That is still lossless for an unedited file and
 * still right for an edit in place; it only pairs less cleverly after a large
 * reordering.
 */
function alignParagraphs(
	origin: OriginParagraph[],
	elements: ScreenplayElement[]
): (OriginParagraph | null)[] {
	const paired: (OriginParagraph | null)[] = new Array(elements.length).fill(null);
	const n = origin.length;
	const m = elements.length;
	if (n === 0 || m === 0) return paired;

	if (n * m > 4_000_000) {
		for (let i = 0; i < Math.min(n, m); i++) paired[i] = origin[i];
		return paired;
	}

	const table = new Int32Array((n + 1) * (m + 1));
	const at = (i: number, j: number): number => i * (m + 1) + j;
	for (let i = n - 1; i >= 0; i--) {
		for (let j = m - 1; j >= 0; j--) {
			table[at(i, j)] =
				origin[i].key === originKey(elements[j].type, elements[j].text)
					? table[at(i + 1, j + 1)] + 1
					: Math.max(table[at(i + 1, j)], table[at(i, j + 1)]);
		}
	}

	// Walk the table, recording which original paragraph each element keeps and
	// which originals fell out, so an edit in place can be paired afterwards.
	const dropped: number[] = [];
	const inserted: number[] = [];
	let i = 0;
	let j = 0;
	while (i < n && j < m) {
		if (origin[i].key === originKey(elements[j].type, elements[j].text)) {
			paired[j] = origin[i];
			i++;
			j++;
		} else if (table[at(i + 1, j)] >= table[at(i, j + 1)]) {
			dropped.push(i++);
		} else {
			inserted.push(j++);
		}
	}
	while (i < n) dropped.push(i++);
	while (j < m) inserted.push(j++);

	// An edit in place: one paragraph gone and one arrived, in the same place.
	for (const j2 of inserted) {
		const type = elements[j2].type;
		// Same kind, or a kind Fountain flattened on the way through — a Shot
		// the writer retyped comes back as action and is still that Shot.
		const near = dropped.findIndex(
			(i2) => origin[i2].type === type || FOUNTAIN_FLATTENS.has(origin[i2].type)
		);
		if (near !== -1) {
			paired[j2] = origin[dropped[near]];
			dropped.splice(near, 1);
		}
	}
	return paired;
}

/**
 * The paragraph's opening tag with a new Type, and every other attribute of it
 * left alone — an id, an alignment, a scene number all survive a writer
 * changing what kind of line this is.
 */
function retypedOpenTag(source: string, origin: OriginParagraph, fdxType: string): string {
	const head = source.slice(origin.start, origin.textStart);
	return /\sType="[^"]*"/.test(head)
		? head.replace(/\sType="[^"]*"/, ` Type="${fdxType}"`)
		: head.replace('<Paragraph', `<Paragraph Type="${fdxType}"`);
}

function rewriteParagraph(
	source: string,
	origin: OriginParagraph,
	element: ScreenplayElement,
	diagnostics: DiagnosticCollector,
	index: number
): string {
	const sameText = origin.key === originKey(element.type, element.text);
	/* The text is only half of a paragraph's content: a highlight or a
	   style changed without a character moving must rewrite the run too. */
	const sameRuns = runsEqual(
		origin.runs,
		normaliseRuns(element.runs ?? [], element.text.length)
	);
	const changedKind =
		origin.type !== element.type &&
		!FOUNTAIN_FLATTENS.has(origin.type) &&
		MODEL_TO_FDX[element.type] !== undefined;
	if (sameText && sameRuns && !changedKind) return source.slice(origin.start, origin.end);
	if (origin.textStart === -1 || origin.textEnd <= origin.textStart) {
		return source.slice(origin.start, origin.end);
	}

	// The attributes and every nested block stay; only the paragraph's own
	// text runs are replaced. A scene heading keeps its <SceneProperties>.
	const head = changedKind
		? retypedOpenTag(source, origin, MODEL_TO_FDX[element.type] as string)
		: source.slice(origin.start, origin.textStart);
	if (sameText && sameRuns) return head + source.slice(origin.textStart, origin.end);

	return head + textRunsMarkup(element, diagnostics, index) + source.slice(origin.textEnd, origin.end);
}

/* ---- unedited paragraphs ------------------------------------------------ */

/** How far ahead the correspondence looks to find its footing again. */
const CORRESPONDENCE_REACH = 16;

/** A paragraph's words as the correspondence compares them: casing and the
    whitespace at either end are not what makes two paragraphs different. */
function wordsKey(text: string): string {
	return text.toLocaleUpperCase().trim();
}

/**
 * Which elements of the unedited reading each file paragraph became.
 *
 * The reading may carry a paragraph differently from the file — Fountain
 * reads an emphasised heading as Action, trims a trailing space, and splits a
 * paragraph at its line breaks — so this pairs by words, never by element:
 * one paragraph to one element when their words agree; to the run of
 * consecutive elements its lines became when those agree; and, where the
 * words disagree for as many paragraphs as elements before both sides agree
 * again, by position — a heading Fountain re-read is still that heading. A
 * region that cannot be paired stays unpaired and is judged against the file
 * as before. Each paragraph gets a half-open range of elements, or null.
 */
function correspondence(
	spans: OriginParagraph[],
	reading: ScreenplayElement[]
): ([number, number] | null)[] {
	const ranges: ([number, number] | null)[] = new Array(spans.length).fill(null);
	const file = spans.map((span) => wordsKey(span.text));
	const read = reading.map((element) => wordsKey(element.text));
	let i = 0;
	let k = 0;
	while (i < spans.length && k < reading.length) {
		if (file[i] === read[k]) {
			ranges[i] = [k, k + 1];
			i += 1;
			k += 1;
			continue;
		}
		const lines = spans[i].text.split('\n').length;
		if (
			lines > 1 &&
			k + lines <= reading.length &&
			wordsKey(reading.slice(k, k + lines).map((element) => element.text).join('\n')) === file[i]
		) {
			ranges[i] = [k, k + lines];
			i += 1;
			k += lines;
			continue;
		}
		// Find footing again: the nearest place both sides agree, nearest first.
		let found: [number, number] | null = null;
		for (let reach = 1; reach <= CORRESPONDENCE_REACH && found === null; reach++) {
			for (let skipped = 0; skipped <= reach; skipped++) {
				const di = skipped;
				const dk = reach - skipped;
				if (i + di < spans.length && k + dk < reading.length && file[i + di] === read[k + dk]) {
					found = [di, dk];
					break;
				}
			}
		}
		if (found === null) break;
		const [di, dk] = found;
		if (di === dk) {
			for (let step = 0; step < di; step++) ranges[i + step] = [k + step, k + step + 1];
		}
		i += di;
		k += dk;
	}
	return ranges;
}

/** Whether two elements are the same element, property for property. */
function sameElement(a: ScreenplayElement, b: ScreenplayElement): boolean {
	return (
		a.type === b.type &&
		a.text === b.text &&
		(a.dual ?? false) === (b.dual ?? false) &&
		(a.sceneNumber ?? '') === (b.sceneNumber ?? '') &&
		(a.depth ?? 0) === (b.depth ?? 0) &&
		runsEqual(
			normaliseRuns(a.runs ?? [], a.text.length),
			normaliseRuns(b.runs ?? [], b.text.length)
		)
	);
}

/**
 * For each element being saved, the element of the unedited reading it still
 * is, unchanged — or null.
 *
 * A longest common subsequence over whole elements, run only between the
 * common prefix and suffix, which is where an edit actually is. Past four
 * million cells the middle pairs by position: still exact for an unedited
 * script and for an edit in place.
 */
function unchangedFrom(
	saved: ScreenplayElement[],
	reading: ScreenplayElement[]
): (number | null)[] {
	const matched: (number | null)[] = new Array(saved.length).fill(null);
	let head = 0;
	while (head < saved.length && head < reading.length && sameElement(saved[head], reading[head])) {
		matched[head] = head;
		head += 1;
	}
	let tail = 0;
	while (
		tail < saved.length - head &&
		tail < reading.length - head &&
		sameElement(saved[saved.length - 1 - tail], reading[reading.length - 1 - tail])
	) {
		matched[saved.length - 1 - tail] = reading.length - 1 - tail;
		tail += 1;
	}
	const n = saved.length - head - tail;
	const m = reading.length - head - tail;
	if (n === 0 || m === 0) return matched;

	if (n * m > 4_000_000) {
		for (let d = 0; d < Math.min(n, m); d++) {
			if (sameElement(saved[head + d], reading[head + d])) matched[head + d] = head + d;
		}
		return matched;
	}

	const table = new Int32Array((n + 1) * (m + 1));
	const at = (i: number, j: number): number => i * (m + 1) + j;
	for (let i = n - 1; i >= 0; i--) {
		for (let j = m - 1; j >= 0; j--) {
			table[at(i, j)] = sameElement(saved[head + i], reading[head + j])
				? table[at(i + 1, j + 1)] + 1
				: Math.max(table[at(i + 1, j)], table[at(i, j + 1)]);
		}
	}
	let i = 0;
	let j = 0;
	while (i < n && j < m) {
		if (sameElement(saved[head + i], reading[head + j])) {
			matched[head + i] = head + j;
			i += 1;
			j += 1;
		} else if (table[at(i + 1, j)] >= table[at(i, j + 1)]) {
			i += 1;
		} else {
			j += 1;
		}
	}
	return matched;
}

/* ---- edited paragraphs -------------------------------------------------- */

/** The emphasis a Fountain reading carries. Everything else on a run — tags,
    revision, font, AllCaps, HiddenText — is the file's, and only the file's. */
const CARRIED_STYLES: readonly StyleToken[] = ['Bold', 'Italic', 'Underline', 'Strikeout'];

/** Past this many cells an alignment is not attempted. */
const ALIGNMENT_CELLS = 4_000_000;

/** One direct-child <Text> run of a file paragraph: its bytes and its words. */
interface FileRun {
	/** Where the whitespace before it starts. */
	lead: number;
	start: number;
	end: number;
	/** The opening tag's attributes, in the file's order, values verbatim. */
	attributes: [string, string][];
	text: string;
}

function isWhitespaceUnit(unit: number): boolean {
	return /\s/.test(String.fromCharCode(unit));
}

/** A tag's attributes, strictly `name="value"` separated by whitespace — or null. */
function strictAttributes(raw: string): [string, string][] | null {
	const attributes: [string, string][] = [];
	let cursor = 0;
	while (cursor < raw.length) {
		const at = cursor;
		while (cursor < raw.length && isWhitespaceUnit(raw.charCodeAt(cursor))) cursor += 1;
		if (cursor >= raw.length) break;
		if (cursor === at) return null;
		const nameStart = cursor;
		while (cursor < raw.length && raw[cursor] !== '=' && !isWhitespaceUnit(raw.charCodeAt(cursor))) cursor += 1;
		if (cursor === nameStart || raw[cursor] !== '=' || raw[cursor + 1] !== '"') return null;
		const name = raw.slice(nameStart, cursor);
		const valueStart = cursor + 2;
		const valueEnd = raw.indexOf('"', valueStart);
		if (valueEnd === -1) return null;
		attributes.push([name, raw.slice(valueStart, valueEnd)]);
		cursor = valueEnd + 1;
	}
	return attributes;
}

/**
 * A paragraph's own runs, or null when its text region holds anything but
 * plain `<Text>` runs and the whitespace between them — then nothing is safe
 * to merge into, and the paragraph keeps today's path.
 */
function fileRunsOf(source: string, origin: OriginParagraph): FileRun[] | null {
	if (origin.textStart < 0 || origin.textEnd <= origin.textStart) return null;
	const runs: FileRun[] = [];
	let cursor = origin.textStart;
	while (cursor < origin.textEnd) {
		const lead = cursor;
		while (cursor < origin.textEnd && isWhitespaceUnit(source.charCodeAt(cursor))) cursor += 1;
		if (cursor >= origin.textEnd) break;
		if (!source.startsWith('<Text', cursor)) return null;
		const close = source.indexOf('>', cursor);
		if (close === -1 || close >= origin.textEnd) return null;
		let raw = source.slice(cursor + '<Text'.length, close);
		const selfClosing = raw.endsWith('/');
		if (selfClosing) raw = raw.slice(0, -1);
		if (raw !== '' && !isWhitespaceUnit(raw.charCodeAt(0))) return null;
		const attributes = strictAttributes(raw);
		if (attributes === null) return null;
		if (selfClosing) {
			runs.push({ lead, start: cursor, end: close + 1, attributes, text: '' });
			cursor = close + 1;
			continue;
		}
		const endTag = source.indexOf('</Text>', close + 1);
		if (endTag === -1 || endTag + '</Text>'.length > origin.textEnd) return null;
		const content = source.slice(close + 1, endTag);
		if (content.includes('<')) return null;
		runs.push({ lead, start: cursor, end: endTag + '</Text>'.length, attributes, text: decodeXmlEntities(content) });
		cursor = endTag + '</Text>'.length;
	}
	return runs;
}

/** A text's UTF-16 units, as numbers to align. */
function unitsOf(text: string): Int32Array {
	const units = new Int32Array(text.length);
	for (let u = 0; u < text.length; u++) units[u] = text.charCodeAt(u);
	return units;
}

/**
 * A text's UTF-16 units as numbers that are equal exactly when the units are
 * the same letter, casing aside — a surrogate only ever equal to itself.
 * `spelled` numbers the uppercase forms longer than one unit, across texts.
 */
function letterKeys(text: string, spelled: Map<string, number>): Int32Array {
	const keys = new Int32Array(text.length);
	for (let u = 0; u < text.length; u++) {
		const unit = text.charCodeAt(u);
		if (unit >= 0xd800 && unit <= 0xdfff) {
			keys[u] = 0x20000 + unit;
			continue;
		}
		const upper = String.fromCharCode(unit).toLocaleUpperCase();
		if (upper.length === 1) {
			keys[u] = upper.charCodeAt(0);
			continue;
		}
		let key = spelled.get(upper);
		if (key === undefined) {
			key = 0x30000 + spelled.size;
			spelled.set(upper, key);
		}
		keys[u] = key;
	}
	return keys;
}

/** For each unit of `a`, the unit of `b` a longest common subsequence pairs it
    with, or -1 — null when the alignment would be too large to attempt. */
function alignedUnits(a: Int32Array, b: Int32Array): Int32Array | null {
	const n = a.length;
	const m = b.length;
	const pairs = new Int32Array(n).fill(-1);
	if (n === 0 || m === 0) return pairs;
	if (n * m > ALIGNMENT_CELLS) return null;
	const table = new Int32Array((n + 1) * (m + 1));
	const at = (i: number, j: number): number => i * (m + 1) + j;
	for (let i = n - 1; i >= 0; i--) {
		for (let j = m - 1; j >= 0; j--) {
			table[at(i, j)] = a[i] === b[j]
				? table[at(i + 1, j + 1)] + 1
				: Math.max(table[at(i + 1, j)], table[at(i, j + 1)]);
		}
	}
	let i = 0;
	let j = 0;
	while (i < n && j < m) {
		if (a[i] === b[j]) {
			pairs[i] = j;
			i += 1;
			j += 1;
		} else if (table[at(i + 1, j)] >= table[at(i, j + 1)]) {
			i += 1;
		} else {
			j += 1;
		}
	}
	return pairs;
}


/** A stretch of the unedited reading and the edited text that do not correspond. */
interface Hunk {
	readStart: number;
	readEnd: number;
	nowStart: number;
	nowEnd: number;
}

function changedUnits(hunks: Hunk[]): number {
	return hunks.reduce((sum, hunk) => sum + (hunk.readEnd - hunk.readStart) + (hunk.nowEnd - hunk.nowStart), 0);
}

/**
 * The hunks an alignment of reading to edited text leaves. A line retyped
 * shares a space or a letter here and there with what it replaced; those are
 * coincidences, not text the writer kept, so an unchanged stretch no longer
 * than the changes on both sides of it is folded into them.
 */
function changeHunks(readToNow: Int32Array, readLength: number, nowLength: number): Hunk[] {
	const hunks: Hunk[] = [];
	const push = (hunk: Hunk) => {
		let current = hunk;
		while (hunks.length > 0) {
			const last = hunks[hunks.length - 1];
			const kept = current.readStart - last.readEnd;
			if (kept > changedUnits([last]) || kept > changedUnits([current])) break;
			hunks.pop();
			current = { readStart: last.readStart, readEnd: current.readEnd, nowStart: last.nowStart, nowEnd: current.nowEnd };
		}
		hunks.push(current);
	};
	let lastRead = -1;
	let lastNow = -1;
	const close = (readNext: number, nowNext: number) => {
		if (readNext - lastRead > 1 || nowNext - lastNow > 1) {
			push({ readStart: lastRead + 1, readEnd: readNext, nowStart: lastNow + 1, nowEnd: nowNext });
		}
	};
	for (let r = 0; r < readLength; r++) {
		const n = readToNow[r];
		if (n < 0) continue;
		close(r, n);
		lastRead = r;
		lastNow = n;
	}
	close(readLength, nowLength);
	return hunks;
}

/** The carried emphasis of each unit of a text, as a bit set per unit. */
function carriedStylesPerUnit(text: string, runs: StyleRun[] | undefined): Uint8Array {
	const styles = new Uint8Array(text.length);
	for (const run of normaliseRuns(runs ?? [], text.length)) {
		let bits = 0;
		CARRIED_STYLES.forEach((token, bit) => {
			if (run.styles.includes(token)) bits |= 1 << bit;
		});
		for (let unit = run.start; unit < run.end; unit++) styles[unit] = bits;
	}
	return styles;
}

/** A run's attributes with its Style made of the file's own tokens and the given carried emphasis. */
function attributesWith(attributes: [string, string][], carried: number, dropRevision: boolean): [string, string][] {
	const own = attributes.find(([name]) => name === 'Style')?.[1] ?? '';
	const tokens = new Set(own.split('+').map((token) => token.trim()).filter((token) => token !== ''));
	for (const [bit, token] of CARRIED_STYLES.entries()) {
		if (carried & (1 << bit)) tokens.add(token);
		else tokens.delete(token);
	}
	const known = STYLE_ORDER.filter((token) => tokens.has(token));
	const unknown = [...tokens].filter((token) => !(STYLE_ORDER as readonly string[]).includes(token));
	const style = [...known, ...unknown].join('+');
	const out: [string, string][] = attributes.filter(([name]) => !(dropRevision && name === 'RevisionID'));
	const index = out.findIndex(([name]) => name === 'Style');
	if (index !== -1) {
		if (style === '') out.splice(index, 1);
		else out[index] = ['Style', style];
	} else if (style !== '') {
		const before = out.findIndex(([name]) => name > 'Style');
		out.splice(before === -1 ? out.length : before, 0, ['Style', style]);
	}
	return out;
}

function carriedOf(styleValue: string | undefined): number {
	const tokens = (styleValue ?? '').split('+').map((token) => token.trim());
	let bits = 0;
	CARRIED_STYLES.forEach((token, bit) => {
		if (tokens.includes(token)) bits |= 1 << bit;
	});
	return bits;
}

/**
 * The writer's change to one paragraph, written in the file's own terms — or
 * null when it cannot be placed without guessing.
 *
 * The change is what separates the unedited reading from the edited elements;
 * the reading is aligned with the file's own text, casing aside, so what the
 * reading added (Fountain's `#2#`, a leading `.`) and dropped (a trailing
 * space, the file's casing, a run split) is known and never written. Replaced
 * characters are the file characters matched to the replaced reading
 * characters; a pure insertion deletes nothing only the file has, and sits
 * beside characters the file has. Every run the change does not touch is
 * written as its bytes; a run it touches keeps its opening tag's attributes,
 * with the writer's emphasis applied. Inserted text takes the attributes of
 * the run it is typed into — or the run before, at a boundary — except its
 * RevisionID: a revision mark is the file's record of when text changed.
 * The file's Type stands unless the writer changed the element's kind.
 */
function mergedParagraph(
	source: string,
	origin: OriginParagraph,
	unedited: ScreenplayElement[],
	edited: ScreenplayElement[],
	diagnostics: DiagnosticCollector,
	index: number
): string | null {
	if (unedited.length !== edited.length || unedited.length === 0) return null;
	for (const [at, read] of unedited.entries()) {
		const now = edited[at];
		// A dual dialogue line's `dual` is its block's, not its paragraph's.
		if (!origin.block && (read.dual ?? false) !== (now.dual ?? false)) return null;
		if ((read.sceneNumber ?? '') !== (now.sceneNumber ?? '')) return null;
		if ((read.depth ?? 0) !== (now.depth ?? 0)) return null;
		if (unedited.length > 1 && read.type !== now.type) return null;
	}
	const runs = fileRunsOf(source, origin);
	if (runs === null || runs.length === 0) return null;

	const joinRuns = (elements: ScreenplayElement[]) => {
		let text = '';
		const runsOut: StyleRun[] = [];
		for (const [at, element] of elements.entries()) {
			if (at > 0) text += '\n';
			for (const run of normaliseRuns(element.runs ?? [], element.text.length)) {
				runsOut.push({ ...run, start: run.start + text.length, end: run.end + text.length });
			}
			text += element.text;
		}
		return { text, runs: runsOut };
	};
	const read = joinRuns(unedited);
	const now = joinRuns(edited);
	const fileText = runs.map((run) => run.text).join('');

	const spelled = new Map<string, number>();
	const readToFile = alignedUnits(letterKeys(read.text, spelled), letterKeys(fileText, spelled));
	if (readToFile === null) return null;
	const readStyles = carriedStylesPerUnit(read.text, read.runs);
	const nowStyles = carriedStylesPerUnit(now.text, now.runs);

	// The writer's change: of the two smallest alignments, the one that changes less.
	const readUnits = unitsOf(read.text);
	const nowUnits = unitsOf(now.text);
	const forward = alignedUnits(readUnits, nowUnits);
	const mirrored = alignedUnits(readUnits.slice().reverse(), nowUnits.slice().reverse());
	if (forward === null || mirrored === null) return null;
	const backward = new Int32Array(read.text.length).fill(-1);
	mirrored.forEach((n, r) => {
		if (n >= 0) backward[read.text.length - 1 - r] = now.text.length - 1 - n;
	});
	const forwardHunks = changeHunks(forward, read.text.length, now.text.length);
	const backwardHunks = changeHunks(backward, read.text.length, now.text.length);
	const useBackward = changedUnits(backwardHunks) < changedUnits(forwardHunks);
	const readToNow = useBackward ? backward : forward;
	const hunks = useBackward ? backwardHunks : forwardHunks;

	// Where each hunk lands in the file's text.
	interface Placed { fileStart: number; fileEnd: number; nowStart: number; nowEnd: number }
	const placed: Placed[] = [];
	for (const [h, hunk] of hunks.entries()) {
		if (hunk.readEnd > hunk.readStart) {
			for (let r = hunk.readStart; r < hunk.readEnd; r++) if (readToFile[r] < 0) return null;
			placed.push({
				fileStart: readToFile[hunk.readStart],
				fileEnd: readToFile[hunk.readEnd - 1] + 1,
				nowStart: hunk.nowStart,
				nowEnd: hunk.nowEnd
			});
			continue;
		}
		// A pure insertion may slide over equal characters; it goes where the file has neighbours.
		const floor = h > 0 ? hunks[h - 1].readEnd : 0;
		const ceiling = h + 1 < hunks.length ? hunks[h + 1].readStart : read.text.length;
		const inserted = now.text.slice(hunk.nowStart, hunk.nowEnd);
		const candidates: { position: number; text: string }[] = [{ position: hunk.readStart, text: inserted }];
		for (let position = hunk.readStart, text = inserted; position > floor && read.text[position - 1] === text[text.length - 1];) {
			text = read.text[position - 1] + text.slice(0, -1);
			position -= 1;
			candidates.push({ position, text });
		}
		for (let position = hunk.readStart, text = inserted; position < ceiling && read.text[position] === text[0];) {
			text = text.slice(1) + read.text[position];
			position += 1;
			candidates.push({ position, text });
		}
		const leftHas = (p: number) => p > 0 && readToFile[p - 1] >= 0;
		const rightHas = (p: number) => p < read.text.length && readToFile[p] >= 0;
		const chosen =
			candidates.find((c) => (c.position === 0 || leftHas(c.position)) && (c.position === read.text.length || rightHas(c.position))) ??
			candidates.find((c) => leftHas(c.position)) ??
			candidates.find((c) => c.position === 0 && rightHas(0));
		if (chosen === undefined) return null;
		const fileAt = chosen.position > 0 ? readToFile[chosen.position - 1] + 1 : 0;
		// The inserted text is the edited text at the chosen position.
		const shift = chosen.position - hunk.readStart;
		placed.push({ fileStart: fileAt, fileEnd: fileAt, nowStart: hunk.nowStart + shift, nowEnd: hunk.nowEnd + shift });
	}
	for (let p = 1; p < placed.length; p++) {
		if (placed[p].fileStart < placed[p - 1].fileEnd) return null;
		if (placed[p].fileStart === placed[p - 1].fileEnd && placed[p].fileStart === placed[p].fileEnd && placed[p - 1].fileStart === placed[p - 1].fileEnd) return null;
	}

	// The emphasis the writer changed on characters they did not retype.
	const fileToRead = new Int32Array(fileText.length).fill(-1);
	readToFile.forEach((f, r) => {
		if (f >= 0) fileToRead[f] = r;
	});

	// The merged paragraph, unit by unit: which run each unit comes from and its carried emphasis.
	interface Unit { char: string; run: number; original: boolean; carried: number }
	const runOfFileUnit = new Int32Array(fileText.length);
	{
		let at = 0;
		runs.forEach((run, r) => {
			for (let u = 0; u < run.text.length; u++) runOfFileUnit[at + u] = r;
			at += run.text.length;
		});
	}
	const units: Unit[] = [];
	const ownCarried = runs.map((run) => carriedOf(run.attributes.find(([name]) => name === 'Style')?.[1]));
	let next = 0;
	const keepFileUnits = (until: number) => {
		for (; next < until; next++) {
			const r = fileToRead[next];
			let carried = ownCarried[runOfFileUnit[next]];
			if (r >= 0 && readToNow[r] >= 0 && readStyles[r] !== nowStyles[readToNow[r]]) carried = nowStyles[readToNow[r]];
			units.push({ char: fileText[next], run: runOfFileUnit[next], original: true, carried });
		}
	};
	for (const edit of placed) {
		keepFileUnits(edit.fileStart);
		/* Replaced characters take the run they replace; typed characters
		   continue the run before them — the first run, at the very start. */
		const donor =
			edit.fileEnd > edit.fileStart
				? runOfFileUnit[edit.fileStart]
				: edit.fileStart > 0
					? runOfFileUnit[edit.fileStart - 1]
					: fileText.length > 0
						? runOfFileUnit[0]
						: 0;
		for (let u = edit.nowStart; u < edit.nowEnd; u++) {
			units.push({ char: now.text[u], run: donor, original: false, carried: nowStyles[u] });
		}
		next = edit.fileEnd;
	}
	keepFileUnits(fileText.length);
	if (units.length === 0) return null;
	// A character outside the BMP is one character: half of it retyped retypes both halves.
	for (let at = 0; at + 1 < units.length; at++) {
		const [high, low] = [units[at], units[at + 1]];
		if (!/[\uD800-\uDBFF]/.test(high.char) || !/[\uDC00-\uDFFF]/.test(low.char) || high.original === low.original) continue;
		const typed = high.original ? low : high;
		units[at] = { ...high, run: typed.run, original: false, carried: typed.carried };
		units[at + 1] = { ...low, run: typed.run, original: false, carried: typed.carried };
	}

	// Runs, emitted. Units group by the attributes they will carry; a run whose
	// every unit is present, in place and unchanged is written as its bytes.
	const keyCache = new Map<string, string>();
	const keyOf = (unit: Unit): string => {
		const cacheKey = `${unit.run}:${unit.carried}:${unit.original}`;
		let key = keyCache.get(cacheKey);
		if (key === undefined) {
			key = JSON.stringify(attributesWith(runs[unit.run].attributes, unit.carried, !unit.original));
			keyCache.set(cacheKey, key);
		}
		return key;
	};
	const firstUnitOfRun = new Int32Array(runs.length).fill(-1);
	const unitsInRun = new Int32Array(runs.length);
	units.forEach((unit, at) => {
		if (!unit.original) return;
		if (firstUnitOfRun[unit.run] === -1) firstUnitOfRun[unit.run] = at;
		unitsInRun[unit.run] += 1;
	});
	const whole = runs.map((run, r) => {
		if (run.text.length === 0 || unitsInRun[r] !== run.text.length) return false;
		for (let k = 0; k < run.text.length; k++) {
			const unit = units[firstUnitOfRun[r] + k];
			if (!unit || !unit.original || unit.run !== r || unit.carried !== ownCarried[r]) return false;
		}
		return true;
	});
	// Text typed onto an untouched run with exactly its attributes joins that run.
	for (const unit of units) {
		if (unit.original || !whole[unit.run]) continue;
		if (keyOf(unit) === keyOf({ ...unit, original: true, carried: ownCarried[unit.run] })) whole[unit.run] = false;
	}

	let out = '';
	let emptyNext = 0;
	const written = new Uint8Array(runs.length);
	const emitEmptyBefore = (limit: number) => {
		for (; emptyNext < limit; emptyNext++) {
			if (runs[emptyNext].text === '' && !written[emptyNext]) out += source.slice(runs[emptyNext].lead, runs[emptyNext].end);
		}
	};
	let u = 0;
	while (u < units.length) {
		const r = units[u].run;
		emitEmptyBefore(r);
		if (units[u].original && whole[r] && firstUnitOfRun[r] === u) {
			out += source.slice(runs[r].lead, runs[r].end);
			u += runs[r].text.length;
			continue;
		}
		// Each run written is laid out as the file lays out the run it comes from.
		const key = keyOf(units[u]);
		const lead = source.slice(runs[r].lead, runs[r].start);
		written[r] = 1;
		let text = '';
		while (u < units.length && keyOf(units[u]) === key && !(units[u].original && whole[units[u].run])) {
			text += units[u].char;
			u += 1;
		}
		const attributes = JSON.parse(key) as [string, string][];
		out += `${lead}<Text${attributes.map(([name, value]) => ` ${name}="${value}"`).join('')}>${encodeXmlValue(text, diagnostics, 'paragraph text', index)}</Text>`;
	}
	emitEmptyBefore(runs.length);

	const retyped = unedited.length === 1 && unedited[0].type !== edited[0].type && MODEL_TO_FDX[edited[0].type] !== undefined;
	const head = retyped
		? retypedOpenTag(source, origin, MODEL_TO_FDX[edited[0].type] as string)
		: source.slice(origin.start, origin.textStart);
	return head + out + source.slice(origin.textEnd, origin.end);
}

/** Each reading element paired with the saved element it became: unchanged, or edited in place — where a stretch between two unchanged pairs holds as many saved elements as reading ones. */
function pairedInPlace(matches: (number | null)[], readingLength: number): Map<number, number> {
	const pairs = new Map<number, number>();
	let lastSaved = -1;
	let lastRead = -1;
	const fill = (savedNext: number, readNext: number) => {
		const gap = savedNext - lastSaved - 1;
		if (gap > 0 && gap === readNext - lastRead - 1) {
			for (let d = 1; d <= gap; d++) pairs.set(lastRead + d, lastSaved + d);
		}
	};
	matches.forEach((k, j) => {
		if (k === null) return;
		fill(j, k);
		pairs.set(k, j);
		lastSaved = j;
		lastRead = k;
	});
	fill(matches.length, readingLength);
	return pairs;
}

/**
 * Opens a Final Draft file and keeps it, so it can be written back whole.
 *
 * The screenplay it returns is exactly `parseFdx`'s — same elements, same
 * diagnostics — and `rewrite` is the part that matters: it edits the original
 * rather than rebuilding it. Use this whenever the file may be saved again.
 * `parseFdx` remains right for reading a script you will never write back,
 * such as an import into a new document.
 */
export function openFdx(xml: string, options: FdxImportOptions = {}): FdxDocument {
	const source = String(xml ?? '');
	const imported = parseFdx(source, options);

	// The paragraphs of the script's own <Content>, in order, with where they
	// sit. `parseFdx` has already decided which those are.
	const { spans, paragraphs: topLevel } = bodySpansOf(source, options);
	const topLevelAt = new Map(topLevel.map((paragraph, index) => [paragraph.start, index]));
	/* Where each ScriptNote's Range value sits, so a save can keep it on its words. */
	const rangeValues: (ScriptNoteRangeValue | null)[] = [];
	/* And where each note and their container sit, and which are eDraft's. */
	const places: ScriptNotesPlaces = { notes: [], container: null, afterCharacters: null, rootClose: null };
	scriptNotesOf(source, [], importLimits(options), new DiagnosticCollector(1), rangeValues, places);
	const first = spans.length > 0 ? (spans[0].block?.start ?? spans[0].start) : -1;
	const last = spans.length > 0 ? (spans[spans.length - 1].block?.end ?? spans[spans.length - 1].end) : -1;
	/* Only paragraphs the import turned into elements can be matched to one.
	   An absorbed End of Act left in the alignment was deleted by every save,
	   and — typed General when it has no Alignment — was paired with the
	   writer's next edit and given their text. */
	const aligned = spans.filter((span) => !span.absorbed);

	return {
		...imported,
		rewrite(script: Screenplay, rewriteOptions: FdxRewriteOptions = {}): FdxExportResult {
			// Nothing recognisable to edit: write a whole new file rather than
			// pretend, so a malformed or empty original cannot corrupt a save.
			if (spans.length === 0 || first < 0) {
				return writeFdxWithDiagnostics(script, rewriteOptions.notes ? { notes: rewriteOptions.notes } : {});
			}

			const diagnostics = new DiagnosticCollector(
				positiveInteger(options.maxWarnings, DEFAULT_FDX_LIMITS.maxWarnings)
			);
			let elements = script.elements;

			/* An omitted scene's body is the file's own bytes, inside its
			   card's paragraph (§7.3). Those elements have no paragraph of
			   their own here, so they are taken out of the alignment before
			   anything is paired — otherwise each would be written a second
			   time, as a live paragraph, which is the resurrection this work
			   exists to prevent. Matched against the file rather than against
			   `script.omissions`, because Fountain has no spelling for an
			   omission and the app's own save path goes through it. */
			const omittedRuns = omittedRunsIn(elements, spans);
			let unedited = rewriteOptions.unedited?.elements;
			/* Located in each reading on its own terms: an edit that adds or
			   removes a line moves everything after it, so the same run sits
			   at different indices in the two. */
			const omittedBefore = unedited ? omittedRunsIn(unedited, spans) : null;
			const lost = spans.filter((span) => span.omittedBody && span.omittedBody.length > 0).length - omittedRuns.length;
			if (lost > 0) {
				diagnostics.add({
					code: 'FDX_REWRITE_OMITTED_SCENE_UNPLACED',
					severity: 'warning',
					message: `${lost} omitted scene(s) could not be found in the script being saved; the file's own bytes were kept and nothing was guessed at.`,
					count: lost
				});
			}
			if (omittedRuns.length > 0) {
				/* Judged against the caller's own unedited reading, not against
				   the file: a round trip through Fountain gives a scene heading
				   its canonical casing, and that is the representation's doing,
				   not the writer's. Without a reading to judge by, the file's
				   own words are the best there is. */
				const edited = omittedRuns.filter((run, at) => {
					const was = omittedBefore?.[at];
					return run.body.some((text, k) =>
						was && unedited
							? unedited[was.start + k]?.text !== elements[run.start + k]?.text
							: elements[run.start + k]?.text !== text
					);
				}).length;
				if (edited > 0) {
					diagnostics.add({
						code: 'FDX_REWRITE_OMITTED_SCENE_KEPT',
						severity: 'info',
						message: `${edited} omitted scene(s) were written back as the file had them: an omitted scene's body is kept, not rewritten.`,
						count: edited
					});
				}
				const dropFrom = (runs: { start: number; body: string[] }[]): Set<number> => {
					const drop = new Set<number>();
					for (const { start, body } of runs) {
						for (let k = 0; k < body.length; k++) drop.add(start + k);
					}
					return drop;
				};
				const drop = dropFrom(omittedRuns);
				elements = elements.filter((_, j) => !drop.has(j));
				if (unedited && omittedBefore) {
					const dropped = dropFrom(omittedBefore);
					unedited = unedited.filter((_, j) => !dropped.has(j));
				}
			}

			/* A paragraph the writer did not edit is written as its original
			   bytes. With the caller's unedited reading, "did not edit" is asked
			   in the caller's own terms: the paragraph's element — or the run of
			   elements its lines became — comes back exactly as it was read.
			   Measured without this on a file Final Draft wrote, a save through
			   Fountain that changed nothing lost 400 of 407 production tags. */
			const verbatim = new Map<number, OriginParagraph>();
			const merged = new Map<number, { span: OriginParagraph; bytes: string }>();
			const consumed = new Set<number>();
			const reading = unedited;
			if (reading) {
				const ranges = correspondence(aligned, reading);
				const unpaired = ranges.filter((range) => range === null).length;
				if (unpaired > 0) {
					diagnostics.add({
						code: 'FDX_REWRITE_UNEDITED_UNALIGNED',
						severity: 'warning',
						message: `${unpaired} paragraph(s) could not be paired with the unedited reading and were judged against the file itself.`,
						count: unpaired
					});
				}
				const matches = unchangedFrom(elements, reading);
				const savedAt = new Map<number, number>();
				matches.forEach((k, j) => {
					if (k !== null) savedAt.set(k, j);
				});
				ranges.forEach((range, i) => {
					if (range === null) return;
					const [from, to] = range;
					const at = savedAt.get(from);
					if (at === undefined) return;
					for (let k = from + 1; k < to; k++) {
						if (savedAt.get(k) !== at + (k - from)) return;
					}
					verbatim.set(at, aligned[i]);
					for (let k = from + 1; k < to; k++) consumed.add(at + (k - from));
				});

				/* A paragraph the writer did edit — its elements edited in place —
				   has only the writer's change written into it: its Type, its
				   attributes, its nested blocks, and every tag, revision mark and
				   run split on the words they did not touch stay the file's.
				   Rewritten from the edited element instead, a typo fix lost a
				   line's tags and an emphasised heading became Action with
				   Fountain's `#2#` in its text. */
				const inPlace = pairedInPlace(matches, reading.length);
				let unplaced = 0;
				ranges.forEach((range, i) => {
					if (range === null) return;
					const [from, to] = range;
					const at = inPlace.get(from);
					if (at === undefined || verbatim.has(at) || consumed.has(at)) return;
					/* A line of another kind with other words, in its place, replaced
					   it: that is not this paragraph edited, and is paired as before. */
					if (to - from === 1 && reading[from].type !== elements[at].type && wordsKey(reading[from].text) !== wordsKey(elements[at].text)) return;
					for (let k = from + 1; k < to; k++) {
						const line = inPlace.get(k);
						if (line !== at + (k - from) || verbatim.has(line) || consumed.has(line)) return;
					}
					const bytes = mergedParagraph(
						source,
						aligned[i],
						reading.slice(from, to),
						elements.slice(at, at + (to - from)),
						diagnostics,
						at
					);
					if (bytes === null) {
						unplaced += 1;
						return;
					}
					merged.set(at, { span: aligned[i], bytes });
					for (let k = from + 1; k < to; k++) consumed.add(at + (k - from));
				});
				if (unplaced > 0) {
					diagnostics.add({
						code: 'FDX_REWRITE_EDIT_UNPLACED',
						severity: 'warning',
						message: `${unplaced} edited paragraph(s) could not have the edit placed in the file's own text and were rewritten from the edited element.`,
						count: unplaced
					});
				}
			}

			// Everything else is paired as it always was.
			const writtenAsRead = new Set([...verbatim.values(), ...[...merged.values()].map((entry) => entry.span)]);
			const rest = elements.flatMap((_, j) => (verbatim.has(j) || merged.has(j) || consumed.has(j) ? [] : [j]));
			const restPaired = alignParagraphs(
				aligned.filter((span) => !writtenAsRead.has(span)),
				rest.map((j) => elements[j])
			);
			const paired: (OriginParagraph | null)[] = new Array(elements.length).fill(null);
			rest.forEach((j, r) => {
				paired[j] = restPaired[r];
			});
			verbatim.forEach((span, j) => {
				paired[j] = span;
			});
			merged.forEach((entry, j) => {
				paired[j] = entry.span;
			});

			/* The writer's notes go into <ScriptNotes> (RFC-NOTES-SYSTEM §4.2):
			   every note that is not one of the file's own body Note paragraphs.
			   A body Note paragraph stays a paragraph — kept, edited or deleted
			   as before. Taken out of the script before anything is laid out,
			   so a note never becomes a paragraph and never parts a dual pair;
			   each remembers the element it sits in front of. */
			const outOfBody: { element: ScreenplayElement; before: number }[] = [];
			if (elements.some((element, j) => element.type === 'note' && paired[j]?.type !== 'note')) {
				const keep: number[] = [];
				elements.forEach((element, j) => {
					if (element.type === 'note' && paired[j]?.type !== 'note') outOfBody.push({ element, before: keep.length });
					else keep.push(j);
				});
				const moved = new Map(keep.map((j, k) => [j, k]));
				const remapped = <T>(map: Map<number, T>): [number, T][] =>
					[...map].flatMap(([j, value]) => (moved.has(j) ? [[moved.get(j) as number, value] as [number, T]] : []));
				const verbatimKept = remapped(verbatim);
				const mergedKept = remapped(merged);
				const consumedKept = [...consumed].flatMap((j) => (moved.has(j) ? [moved.get(j) as number] : []));
				verbatim.clear();
				for (const [k, span] of verbatimKept) verbatim.set(k, span);
				merged.clear();
				for (const [k, entry] of mergedKept) merged.set(k, entry);
				consumed.clear();
				for (const k of consumedKept) consumed.add(k);
				paired.splice(0, paired.length, ...keep.map((j) => paired[j]));
				elements = keep.map((j) => elements[j]);
			}

			/* Each absorbed paragraph goes back, verbatim, in front of the first
			   paragraph after it that this save keeps — anchored to what
			   follows, so lines added at the end of an act still land before
			   its End of Act — and after the last element when nothing after
			   it survives. Never dropped: eDraft does not show an End of Act,
			   so no writer can have meant to delete one. Keyed by where each
			   paragraph starts, which is unique. */
			const kept = new Set(paired.flatMap((origin) => (origin ? [origin.start] : [])));
			const absorbedBefore = new Map<number, OriginParagraph[]>();
			let waiting: OriginParagraph[] = [];
			for (const span of spans) {
				if (span.absorbed) {
					waiting.push(span);
				} else if (waiting.length > 0 && kept.has(span.start)) {
					absorbedBefore.set(span.start, waiting);
					waiting = [];
				}
			}

			/* A dual dialogue is kept whole where the writer kept it a dual pair:
			   its frame is written verbatim around its lines, and lines added
			   inside the pair go inside the block. Where the lines kept from it
			   are no longer a dual pair — the second cue no longer dual, or the
			   lines apart — the block is dissolved: its lines are written in its
			   place as ordinary paragraphs, and the frame goes. */
			const keptLines = new Map<DualDialogueBlock, number[]>();
			paired.forEach((origin, index) => {
				if (!origin?.block) return;
				const kept = keptLines.get(origin.block) ?? [];
				kept.push(index);
				keptLines.set(origin.block, kept);
			});
			const pairs = new Map<number, { block: DualDialogueBlock; end: number }>();
			let dissolved = 0;
			for (const [block, kept] of keptLines) {
				const end = dualPairEnd(elements, paired, consumed, block, kept);
				if (end === null) dissolved += 1;
				else pairs.set(kept[0], { block, end });
			}
			if (dissolved > 0) {
				diagnostics.add({
					code: 'FDX_REWRITE_DUAL_DIALOGUE_DISSOLVED',
					severity: 'warning',
					message: `${dissolved} dual dialogue(s) no longer a dual pair were written as ordinary paragraphs, without Final Draft's dual dialogue block.`,
					count: dissolved
				});
			}

			const out: string[] = [];
			/* Which original paragraph each paragraph written came from, in
			   order, so each ScriptNote's Range can follow its words. */
			const written: WrittenParagraph[] = [];
			const writtenFrom = (start: number, kind: WrittenParagraph['kind']): void => {
				written.push({ origin: topLevelAt.get(start) ?? null, kind });
			};
			const dissolvedWritten = new Set<DualDialogueBlock>();
			// A new paragraph is laid out like the one it follows, so an insert
			// does not announce itself as the one differently-indented line in
			// the file.
			let lead = '';
			const restore = (span: OriginParagraph): void => {
				if (out.length > 0) out.push(span.lead === '' ? lead : span.lead);
				if (span.lead !== '') lead = span.lead;
				out.push(source.slice(span.start, span.end));
				writtenFrom(span.start, 'same');
			};
			const keptBytes = (index: number, origin: OriginParagraph): string =>
				verbatim.get(index) === origin
					? source.slice(origin.start, origin.end)
					: merged.get(index)?.span === origin
						? (merged.get(index) as { bytes: string }).bytes
						: rewriteParagraph(source, origin, elements[index], diagnostics, index);
			const freshBytes = (element: ScreenplayElement): string => {
				const fresh = writeFdxWithDiagnostics({ titlePage: [], elements: [element] }, options);
				return fresh.xml.match(/<Paragraph[\s\S]*<\/Paragraph>/)?.[0] ?? '';
			};
			/* The paragraph each element was written into, as `written` counts:
			   a note in front of an element is placed on that paragraph. */
			const paragraphOf: number[] = new Array(elements.length).fill(-1);
			for (let index = 0; index < elements.length; index++) {
				// A line of a paragraph already written whole.
				if (consumed.has(index)) {
					paragraphOf[index] = written.length - 1;
					continue;
				}
				const pair = pairs.get(index);
				if (pair) {
					const { block } = pair;
					for (const line of block.lines) for (const span of absorbedBefore.get(line.start) ?? []) restore(span);
					if (out.length > 0) out.push(block.lead === '' ? lead : block.lead);
					if (block.lead !== '') lead = block.lead;
					out.push(block.head);
					writtenFrom(block.start, 'same');
					let lineLead = block.lines[1]?.lead ?? block.lead;
					for (let line = index; line <= pair.end; line++) {
						const origin = paired[line];
						if (line > index) out.push(origin && origin.lead !== '' ? origin.lead : lineLead);
						if (origin && origin.lead !== '') lineLead = origin.lead;
						// Inside Final Draft's block, a speaker is dual by where it stands.
						const { dual: _dual, ...speech } = elements[line];
						out.push(origin ? keptBytes(line, origin) : freshBytes(speech));
					}
					out.push(block.tail);
					for (let line = index; line <= pair.end; line++) paragraphOf[line] = written.length - 1;
					index = pair.end;
					continue;
				}
				const origin = paired[index];
				if (origin) {
					for (const span of absorbedBefore.get(origin.start) ?? []) restore(span);
					const ownLead = origin.block ? origin.block.lead : origin.lead;
					if (out.length > 0) out.push(ownLead === '' ? lead : ownLead);
					if (ownLead !== '') lead = ownLead;
					out.push(keptBytes(index, origin));
					if (origin.block) {
						// A dissolved dual dialogue: its place is its first line.
						if (dissolvedWritten.has(origin.block)) written.push({ origin: null, kind: 'same' });
						else writtenFrom(origin.block.start, 'first-line');
						dissolvedWritten.add(origin.block);
					} else {
						writtenFrom(origin.start, verbatim.get(index) === origin ? 'same' : 'text');
					}
					paragraphOf[index] = written.length - 1;
					continue;
				}
				if (out.length > 0) out.push(lead === '' ? '\n' : lead);
				out.push(freshBytes(elements[index]));
				written.push({ origin: null, kind: 'same' });
				paragraphOf[index] = written.length - 1;
			}
			for (const span of waiting) restore(span);

			/* Each ScriptNote stays on its words. Final Draft counts a Range
			   over the script as it now stands, so a Range written for the
			   old text points at other words after any edit that moves them —
			   measured, one word typed near the start moved ten of eleven
			   notes. Only the Range values that move are rewritten.

			   Then the writer's notes (RFC-NOTES-SYSTEM §4.2, stage 1). A note
			   of eDraft's the writer left as it was, on the same line, keeps
			   every byte but its Range. One whose note is gone — deleted, or
			   changed, which stage 1 writes as a new note — is taken out. Every
			   note left over is written as a new ScriptNote on the paragraph it
			   sits in front of. Final Draft's own notes are never touched. */
			let prefix = source.slice(0, first);
			let suffix = source.slice(last);
			const body = out.join('');
			const ownedCount = places.notes.filter((note) => note.owned !== null).length;
			if (rangeValues.some((value) => value !== null) || outOfBody.length > 0 || ownedCount > 0) {
				const after = paragraphsOf(prefix + body + suffix, importLimits(options), new DiagnosticCollector(1)).body;
				const matched = after.length === written.length;
				const moved = matched
					? movedScriptNoteRanges(topLevel, written, after, rangeValues)
					: { replacements: [], ranges: rangeValues.map((value) => (value === null ? null : value.range)), deleted: [] };
				if (!matched && rangeValues.some((value) => value !== null)) {
					diagnostics.add({
						code: 'FDX_REWRITE_SCRIPT_NOTE_RANGES_KEPT',
						severity: 'warning',
						message: 'The saved script could not be matched paragraph for paragraph, so script note Ranges were left as they were.'
					});
				}
				const lengths = after.map((paragraph) => paragraph.text.length + BLOCK_UNITS * paragraph.blocks.length);
				const starts: number[] = [];
				lengths.reduce((cursor, length) => {
					starts.push(cursor);
					return cursor + length + 1;
				}, 0);
				const paragraphAt = (position: number): number => {
					let found = -1;
					for (let index = 0; index < starts.length && starts[index] <= position; index++) found = index;
					return found;
				};
				const lastParagraph = written.length - 1;
				const placed = outOfBody.map(({ element, before }) => ({
					element,
					at: matched ? (before < paragraphOf.length ? paragraphOf[before] : lastParagraph) : -1
				}));

				// Stage 1 pairs eDraft's notes by their line and their words.
				const removed = new Set<number>();
				const pairedNote = new Set<number>();
				places.notes.forEach((note, index) => {
					if (!note.owned) return;
					const range = moved.ranges[index];
					// Where the import put it: the paragraph its Range starts in, or the end.
					const at = !matched ? null : range ? paragraphAt(range.start) : lastParagraph;
					const text = ownedNoteText(note.owned);
					const match = placed.findIndex(
						(candidate, k) => !pairedNote.has(k) && (at === null || candidate.at === at) && candidate.element.text === text
					);
					if (match === -1) removed.add(index);
					else pairedNote.add(match);
				});

				const edits: { start: number; end: number; value: string }[] = [];
				for (const replacement of moved.replacements) {
					if (!removed.has(replacement.note)) edits.push(replacement);
				}
				for (const index of removed) edits.push({ start: places.notes[index].start, end: places.notes[index].end, value: '' });
				const fresh = placed.filter((_, k) => !pairedNote.has(k));
				if (fresh.length > 0) {
					const writing = resolvedNoteWriting(rewriteOptions.notes);
					const names = [
						...(writing.writer ? [writing.writer] : []),
						...places.notes.flatMap((note) => {
							const author = note.owned ? ownedNoteAuthor(note.owned) : undefined;
							return author ? [author] : [];
						})
					];
					let id = places.notes.reduce((highest, note) => (Number.isFinite(note.id) ? Math.max(highest, note.id) : highest), 0);
					const lines = fresh.flatMap(({ element, at }) =>
						scriptNoteLines(
							{
							id: ++id,
							...noteAuthorship(element.text, names, writing.writer),
							range: noteRange(paragraphRange(lengths, at), after[at], element.anchor, diagnostics)
						},
							writing,
							diagnostics
						)
					);
					const indented = lines.map((line) => `\n${' '.repeat(4 + 2 * line.depth)}${line.text}`).join('');
					const { container, afterCharacters, rootClose } = places;
					if (container && container.close !== null) {
						const lineStart = source.lastIndexOf('\n', container.close - 1);
						const at = lineStart !== -1 && /^[ \t]*$/.test(source.slice(lineStart + 1, container.close)) ? lineStart : container.close;
						edits.push({ start: at, end: at, value: indented });
					} else if (container) {
						const tagEnd = source.indexOf('>', container.open) + 1;
						edits.push({ start: container.open, end: tagEnd, value: `<ScriptNotes>${indented}\n  </ScriptNotes>` });
					} else {
						const at = afterCharacters ?? rootClose ?? source.length;
						edits.push({ start: at, end: at, value: `\n\n  <ScriptNotes>${indented}\n  </ScriptNotes>` });
					}
					diagnostics.add({
						code: 'FDX_REWRITE_SCRIPT_NOTES_WRITTEN',
						severity: 'info',
						message: `${fresh.length} note(s) were written as Final Draft script notes.`,
						count: fresh.length
					});
					if (!matched) {
						diagnostics.add({
							code: 'FDX_REWRITE_SCRIPT_NOTES_UNPLACED',
							severity: 'warning',
							message: `The saved script could not be matched paragraph for paragraph, so ${fresh.length} note(s) were written at the start of the script.`,
							count: fresh.length
						});
					}
				}
				if (removed.size > 0) {
					diagnostics.add({
						code: 'FDX_REWRITE_SCRIPT_NOTES_REMOVED',
						severity: 'info',
						message: `${removed.size} note(s) eDraft wrote were taken out: deleted, or changed and written again.`,
						count: removed.size
					});
				}
				const kept = moved.replacements.filter((replacement) => !removed.has(replacement.note)).length;
				if (kept > 0) {
					diagnostics.add({
						code: 'FDX_REWRITE_SCRIPT_NOTE_RANGES_MOVED',
						severity: 'info',
						message: `${kept} script note Range(s) were moved to stay on their words.`,
						count: kept
					});
				}
				const deleted = moved.deleted.filter((note) => !removed.has(note)).length;
				if (deleted > 0) {
					diagnostics.add({
						code: 'FDX_REWRITE_SCRIPT_NOTE_WORDS_DELETED',
						severity: 'warning',
						message: `${deleted} script note(s) lost all their words and were closed to zero length where the words stood.`,
						count: deleted
					});
				}
				const apply = (text: string, base: number, limit: number): string => {
					let result = text;
					const inside = edits.filter((edit) => edit.start >= base && edit.end <= limit);
					inside.sort((a, b) => b.start - a.start || b.end - a.end);
					for (const edit of inside) {
						result = result.slice(0, edit.start - base) + edit.value + result.slice(edit.end - base);
					}
					return result;
				};
				prefix = apply(prefix, 0, first);
				suffix = apply(suffix, last, source.length);
			}

			return {
				xml: ensureNamespaceDeclared(prefix + body + suffix),
				warnings: messagesOf(diagnostics.result()),
				diagnostics: diagnostics.result()
			};
		}
	};
}

/**
 * Where the script's body paragraphs sit in the source.
 *
 * Deliberately a second, narrow scan rather than a return value threaded
 * through `parseFdx`: the import's shape is pinned by a conformance corpus
 * shared with the Swift engine, and widening it to carry byte offsets would
 * make every fixture carry them too.
 */
function bodySpansOf(source: string, options: FdxImportOptions): { spans: OriginParagraph[]; paragraphs: MutableFdxParagraph[] } {
	const diagnostics = new DiagnosticCollector(1);
	const limits = importLimits(options);
	const parsed = paragraphsOf(source, limits, diagnostics);
	let previousEnd = -1;
	const spans: OriginParagraph[] = [];
	const spanOf = (paragraph: MutableFdxParagraph, fdxType: string, lead: string): OriginParagraph => {
		/* End of Act is kept as a span, marked absorbed, by the same rule the
		   import absorbs it with (RFC-ACT-BREAK D3). No element ever stands
		   for it, so the rewrite owns its bytes: dropping the span here would
		   lose them, and leaving it unmarked let the alignment delete it. */
		const type = refineGeneral(fdxElementKind(fdxType)?.type ?? 'general', paragraph);
		return {
			key: originKey(type, paragraph.text),
			text: paragraph.text,
			type,
			start: paragraph.start,
			end: paragraph.end,
			textStart: paragraph.textStart,
			textEnd: paragraph.textEnd,
			lead,
			runs: normaliseRuns(paragraph.runs, paragraph.text.length),
			absorbed: fdxType === 'end of act'
		};
	};
	for (const paragraph of parsed.body) {
		const held = paragraph as MutableFdxParagraph;
		const fdxType = attributeOf(paragraph, 'type').trim().toLowerCase();
		const lead = previousEnd === -1 ? '' : source.slice(previousEnd, held.start);
		previousEnd = held.end;
		const lines = fdxType === 'end of act' ? null : dualDialogueOf(source, paragraph, limits);
		if (!lines) {
			const span = spanOf(held, fdxType, lead);
			/* An omitted scene's paragraphs live inside this one, so this
			   paragraph's bytes already carry them: the save writes it whole
			   and the body is preserved exactly (§7.3, "Preserved on
			   splice"). Recorded so the alignment can leave those elements
			   out — they have no paragraph of their own to be written to. */
			const omitted = fdxType === 'end of act' ? null : omittedSceneOf(source, paragraph, limits);
			if (omitted) span.omittedBody = omitted.map((line) => line.text);
			spans.push(span);
			continue;
		}
		const block: DualDialogueBlock = {
			lead,
			start: held.start,
			end: held.end,
			head: source.slice(held.start, lines[0].start),
			tail: source.slice(lines[lines.length - 1].end, held.end),
			lines: []
		};
		lines.forEach((line, at) => {
			const span = spanOf(line, attributeOf(line, 'type').trim().toLowerCase(), at === 0 ? '' : source.slice(lines[at - 1].end, line.start));
			span.block = block;
			block.lines.push(span);
			spans.push(span);
		});
	}
	return { spans, paragraphs: parsed.body as MutableFdxParagraph[] };
}

/* ---- ScriptNote Ranges through a save ------------------------------------ */

/** A paragraph of a written script, as a Range counts it, and what it came
    from: the original top-level paragraph, and how its units relate — its
    own bytes, text that changed, or the first line of a dissolved dual
    dialogue. `null` for a paragraph the writer added. */
interface WrittenParagraph {
	origin: number | null;
	kind: 'same' | 'text' | 'first-line';
}

/** A paragraph's units as a Range counts them: its text, with two for each
    embedded block where it sits (-1, which no text unit equals). */
function rangeUnitsOf(paragraph: FdxParagraph): Int32Array {
	const units = new Int32Array(paragraph.text.length + BLOCK_UNITS * paragraph.blocks.length);
	let at = 0;
	let block = 0;
	for (let unit = 0; unit <= paragraph.text.length; unit++) {
		while (block < paragraph.blocks.length && paragraph.blocks[block] === unit) {
			for (let k = 0; k < BLOCK_UNITS; k++) units[at++] = -1;
			block += 1;
		}
		if (unit < paragraph.text.length) units[at++] = paragraph.text.charCodeAt(unit);
	}
	return units;
}

/** For each old unit, the new unit it is — or -1: the common prefix and suffix,
    and a longest common subsequence between them when small enough. */
function unitCorrespondence(before: Int32Array, after: Int32Array): Int32Array {
	const pairs = new Int32Array(before.length).fill(-1);
	let head = 0;
	while (head < before.length && head < after.length && before[head] === after[head]) {
		pairs[head] = head;
		head += 1;
	}
	let tail = 0;
	while (tail < before.length - head && tail < after.length - head && before[before.length - 1 - tail] === after[after.length - 1 - tail]) {
		pairs[before.length - 1 - tail] = after.length - 1 - tail;
		tail += 1;
	}
	const middle = alignedUnits(before.subarray(head, before.length - tail), after.subarray(head, after.length - tail));
	middle?.forEach((n, r) => {
		if (n >= 0) pairs[head + r] = head + n;
	});
	return pairs;
}

/**
 * The Range values a save must rewrite so each note stays on its words, and
 * how many notes lost all of them.
 *
 * Each end of a Range stays with its character: a start before the first
 * character of the note that survives, an end after the last. Text typed
 * inside a note joins it; text typed at its edges does not. A note whose
 * words are all gone closes to zero length where they stood. A Range already
 * past the script's end when the file was read keeps its bytes, as does every
 * Range that does not move.
 */
function movedScriptNoteRanges(
	before: FdxParagraph[],
	written: WrittenParagraph[],
	after: FdxParagraph[],
	values: (ScriptNoteRangeValue | null)[]
): {
	replacements: { start: number; end: number; value: string; note: number }[];
	/** Each note's Range after the save, as rewritten or as it was. */
	ranges: ({ start: number; end: number } | null)[];
	/** The notes that lost all their words. */
	deleted: number[];
} {
	const layoutOf = (paragraphs: FdxParagraph[]) => {
		const starts: number[] = [];
		const lengths: number[] = [];
		let cursor = 0;
		for (const paragraph of paragraphs) {
			starts.push(cursor);
			const length = paragraph.text.length + BLOCK_UNITS * paragraph.blocks.length;
			lengths.push(length);
			cursor += length + 1;
		}
		return { starts, lengths, end: cursor - 1 };
	};
	const old = layoutOf(before);
	const now = layoutOf(after);
	const writtenAt = new Map<number, number>();
	written.forEach((paragraph, at) => {
		if (paragraph.origin !== null && !writtenAt.has(paragraph.origin)) writtenAt.set(paragraph.origin, at);
	});
	const correspondences = new Map<number, Int32Array>();

	const boundary = (position: number, side: 'start' | 'end'): number => {
		let low = 0;
		let high = before.length - 1;
		while (low < high) {
			const middle = (low + high + 1) >> 1;
			if (old.starts[middle] <= position) low = middle;
			else high = middle - 1;
		}
		const at = writtenAt.get(low);
		if (at === undefined) {
			// Gone: where it stood — the start of what follows the last paragraph kept before it.
			let previous = -1;
			written.forEach((paragraph, index) => {
				if (paragraph.origin !== null && paragraph.origin < low) previous = index;
			});
			return previous === -1 ? 0 : Math.min(now.starts[previous] + now.lengths[previous] + 1, now.end);
		}
		const offset = position - old.starts[low];
		const { kind } = written[at];
		if (kind === 'first-line') return now.starts[at];
		if (kind === 'same') return now.starts[at] + Math.min(offset, now.lengths[at]);
		let pairs = correspondences.get(low);
		if (!pairs) {
			pairs = unitCorrespondence(rangeUnitsOf(before[low]), rangeUnitsOf(after[at]));
			correspondences.set(low, pairs);
		}
		if (side === 'start') {
			for (let unit = offset; unit < pairs.length; unit++) if (pairs[unit] >= 0) return now.starts[at] + pairs[unit];
			return now.starts[at] + now.lengths[at];
		}
		for (let unit = Math.min(offset, pairs.length) - 1; unit >= 0; unit--) if (pairs[unit] >= 0) return now.starts[at] + pairs[unit] + 1;
		return now.starts[at];
	};

	const replacements: { start: number; end: number; value: string; note: number }[] = [];
	const ranges = values.map((value) => (value === null ? null : value.range));
	const deleted: number[] = [];
	if (before.length === 0 || after.length === 0) return { replacements, ranges, deleted };
	values.forEach((value, note) => {
		if (value === null || value.range.end > old.end) return;
		const { start, end } = value.range;
		let movedStart = boundary(start, 'start');
		let movedEnd = start === end ? movedStart : boundary(end, 'end');
		if (start < end && movedEnd <= movedStart) {
			movedStart = Math.min(movedStart, movedEnd);
			movedEnd = movedStart;
			deleted.push(note);
		}
		if (movedStart === start && movedEnd === end) return;
		ranges[note] = { start: movedStart, end: movedEnd };
		replacements.push({
			start: value.valueStart,
			end: value.valueEnd,
			value: value.reversed ? `${movedEnd},${movedStart}` : `${movedStart},${movedEnd}`,
			note
		});
	});
	return { replacements, ranges, deleted };
}

/** The kinds that belong to a speech after its cue. */
const SPEECH_TYPES: ReadonlySet<string> = new Set(['dialogue', 'parenthetical', 'lyrics']);

/**
 * Where a dual dialogue kept by a save ends — the element index of the
 * second speaker's last line — or null when the lines kept from it no longer
 * form a dual pair there.
 *
 * A dual pair is what Fountain reads as one: a cue, its speech, the cue
 * marked dual, its speech. It must open on the first line kept from the
 * block, hold every line kept from it, and hold nothing another paragraph of
 * the file became — only the block's own lines and lines the writer added.
 */
function dualPairEnd(
	elements: ScreenplayElement[],
	paired: (OriginParagraph | null)[],
	consumed: Set<number>,
	block: DualDialogueBlock,
	kept: number[]
): number | null {
	const start = kept[0];
	let at = start;
	if (elements[at]?.type !== 'character' || elements[at].dual) return null;
	at += 1;
	while (at < elements.length && SPEECH_TYPES.has(elements[at].type)) at += 1;
	if (elements[at]?.type !== 'character' || !elements[at].dual) return null;
	at += 1;
	while (at < elements.length && SPEECH_TYPES.has(elements[at].type)) at += 1;
	const end = at - 1;
	if (kept[kept.length - 1] > end) return null;
	for (let index = start; index <= end; index++) {
		if (consumed.has(index)) return null;
		const origin = paired[index];
		if (origin && origin.block !== block) return null;
	}
	return end;
}

/* ---- the writer's notes, as ScriptNotes -------------------------------- */

interface ResolvedNoteWriting {
	writer?: string;
	now: string;
	newId: () => string;
}

/** Final Draft's `20260918T120000`: local time, no zone. */
function noteTimestamp(date: Date): string {
	const two = (value: number): string => String(value).padStart(2, '0');
	return `${date.getFullYear()}${two(date.getMonth() + 1)}${two(date.getDate())}T${two(date.getHours())}${two(date.getMinutes())}${two(date.getSeconds())}`;
}

function randomBytes(count: number): number[] {
	const crypto = (globalThis as { crypto?: { getRandomValues?: (array: Uint8Array) => Uint8Array } }).crypto;
	const bytes = new Uint8Array(count);
	if (crypto?.getRandomValues) crypto.getRandomValues(bytes);
	else for (let index = 0; index < count; index++) bytes[index] = Math.floor(Math.random() * 256);
	return [...bytes];
}

function freshUuid(): string {
	const bytes = randomBytes(16);
	bytes[6] = (bytes[6] & 0x0f) | 0x40;
	bytes[8] = (bytes[8] & 0x3f) | 0x80;
	const hex = bytes.map((byte) => byte.toString(16).padStart(2, '0')).join('');
	return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function resolvedNoteWriting(writing: FdxNoteWriting = {}): ResolvedNoteWriting {
	const writer = writing.writer?.trim();
	return {
		...(writer ? { writer } : {}),
		now: writing.now ?? noteTimestamp(new Date()),
		newId: writing.newId ?? freshUuid
	};
}

/**
 * Who wrote a note and what it says, from the words the editor holds.
 *
 * A `Name: ` prefix names the author when the name is the writer's own or one
 * the file's eDraft notes already carry — the longest that fits. Any other
 * note is the writer's (D3), prefix and all: a colon in a sentence is not a
 * person.
 */
function noteAuthorship(text: string, names: string[], writer?: string): { author?: string; message: string } {
	let author: string | undefined;
	for (const name of names) {
		if (text.startsWith(`${name}: `) && (author === undefined || name.length > author.length)) author = name;
	}
	if (author !== undefined) return { author, message: text.slice(author.length + 2) };
	return { ...(writer ? { author: writer } : {}), message: text };
}

/** Where a paragraph sits as a Range counts it: its first unit, and its last. */
function paragraphRange(lengths: number[], at: number): { start: number; end: number } {
	if (at < 0 || lengths.length === 0) return { start: 0, end: 0 };
	let start = 0;
	for (let index = 0; index < at; index++) start += lengths[index] + 1;
	return { start, end: start + lengths[at] };
}

/**
 * A text offset inside one paragraph, as a ScriptNote Range counts it — the
 * inverse of `textOffsetIn`. An embedded block's two units sit where the
 * block sits, so an offset at a block's own position is the text after it
 * (`inclusive`), while a span ending there stops in front of it.
 */
function unitOffsetIn(blocks: readonly number[], offset: number, inclusive: boolean): number {
	let units = offset;
	for (const at of blocks) {
		if (inclusive ? at <= offset : at < offset) units += BLOCK_UNITS;
	}
	return units;
}

/**
 * The Range one of the writer's notes takes (RFC-NOTES-SYSTEM §5.1):
 * its anchored words when it has an anchor and those words are still in the
 * paragraph, and the whole paragraph otherwise.
 *
 * §5.3 rule 5, said out loud: words that are gone do not move the note to
 * another paragraph and are never guessed at. The note falls back to its
 * paragraph and the save says so.
 */
function noteRange(
	whole: { start: number; end: number },
	paragraph: { text: string; blocks: readonly number[] } | undefined,
	anchor: NoteAnchor | undefined,
	diagnostics: DiagnosticCollector
): { start: number; end: number } {
	if (anchor === undefined || paragraph === undefined) return whole;
	const span = resolveAnchor(paragraph.text, anchor);
	if (span === null) {
		diagnostics.add({
			code: 'FDX_NOTE_ANCHOR_WORDS_CHANGED',
			severity: 'info',
			message: `A note anchored to ${quoteAnchorWords(anchor.on)} was written on its whole paragraph: those words are no longer in it.`
		});
		return whole;
	}
	return {
		start: whole.start + unitOffsetIn(paragraph.blocks, span.start, true),
		end: whole.start + unitOffsetIn(paragraph.blocks, span.end, false)
	};
}

/**
 * The anchor a Range carries, for a note eDraft owns (§5.4).
 *
 * A Range over the whole paragraph is no anchor at all — that is every note
 * written before stage 4. A Range that spans paragraphs anchors to the words
 * it covers in the first (§5.3 rule 6); FDX keeps its full span.
 */
function anchorOfRange(
	elements: readonly ScreenplayElement[],
	anchor: NonNullable<FdxScriptNote['anchor']>
): NoteAnchor | undefined {
	const element = elements[anchor.start.element];
	if (element === undefined) return undefined;
	const end = anchor.end.element === anchor.start.element ? anchor.end.offset : element.text.length;
	return anchorFor(element.text, anchor.start.offset, end) ?? undefined;
}

const NOTE_PARAGRAPH_ATTRIBUTES =
	'Alignment="Left" FirstIndent="0.00" Leading="Regular" LeftIndent="0.00" OutlineLevel="1" RightIndent="1.39" SpaceBefore="0" Spacing="1" StartsNewPage="No"';
const NOTE_TEXT_ATTRIBUTES = 'AdornmentStyle="0" Font="Arial" RevisionID="0" Size="12" Style=""';
/** WriterID carries nothing (IL-0024): one fixed value, never an identity. */
const NOTE_WRITER_ID = '00000000-0000-4000-8000-000000000001';

/**
 * One of the writer's notes as a Final Draft ScriptNote (RFC-NOTES-SYSTEM
 * §4.2), in the shape Final Draft 13.4 opened, showed and kept whole: titled
 * `[eDraft]`, the writer's name as its author, their role as the Type Final
 * Draft shows in the note's dropdown, and one paragraph for each line of the
 * message — the writer's words, once, and nothing else. Its lines, each with
 * its depth under the note.
 */
function scriptNoteLines(
	note: { id: number; author?: string; message: string; range: { start: number; end: number } },
	writing: ResolvedNoteWriting,
	diagnostics: DiagnosticCollector
): { depth: number; text: string }[] {
	const refId = writing.newId();
	const { name, role } = nameAndRole(note.author ?? '');
	const value = (text: string, context: string): string => encodeXmlValue(text, diagnostics, context);
	const lines = [
		{
			depth: 0,
			text:
				`<ScriptNote Color="#000000000000" DateModified="${writing.now}" DateTime="${writing.now}" Id="${note.id}"` +
				` Name="${EDRAFT_TITLE}" Range="${note.range.start},${note.range.end}"` +
				` RefId="${refId}" Type="${value(role, 'note role')}" WriterID="${NOTE_WRITER_ID}"` +
				` WriterName="${value(name, 'note author')}">`
		}
	];
	for (const text of note.message.split('\n')) {
		lines.push(
			{ depth: 1, text: `<Paragraph ${NOTE_PARAGRAPH_ATTRIBUTES} id="${writing.newId()}">` },
			{ depth: 2, text: `<Text ${NOTE_TEXT_ATTRIBUTES}>${value(text, 'note')}</Text>` },
			{ depth: 1, text: '</Paragraph>' }
		);
	}
	lines.push({ depth: 0, text: '</ScriptNote>' });
	return lines;
}

/* ---- export ------------------------------------------------------------- */

const XML_HEADER = '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>';

/**
 * A namespaced attribute means nothing without its declaration. Files
 * written by Final Draft have never heard of our prefix, so the first
 * time eDraft's own metadata is spliced into one — a highlight, a lyrics
 * mark — the root gains the declaration. Files that already declare it
 * (anything eDraft wrote) pass through byte-identical.
 */
function ensureNamespaceDeclared(xml: string): string {
	if (!xml.includes(`${EDRAFT_PREFIX}:`)) return xml;
	if (xml.includes(`xmlns:${EDRAFT_PREFIX}=`)) return xml;
	const root = xml.indexOf('<FinalDraft');
	if (root === -1) return xml;
	return (
		xml.slice(0, root + '<FinalDraft'.length) +
		` xmlns:${EDRAFT_PREFIX}="${EDRAFT_NAMESPACE}"` +
		xml.slice(root + '<FinalDraft'.length)
	);
}

/**
 * A paragraph's text as one or more <Text> runs.
 *
 * The model's runs become the file's runs: styles in FDX's own '+'
 * list, the highlight in our extension namespace, revision and tags
 * carried. A paragraph with no runs writes exactly what it always did —
 * the plain single <Text> — so a runless document's bytes never move.
 */
function textRunsMarkup(
	element: { text: string; runs?: StyleRun[] },
	diagnostics: DiagnosticCollector,
	index: number
): string {
	const runs = element.runs ?? [];
	if (runs.length === 0) {
		return `<Text>${encodeXmlValue(element.text, diagnostics, 'paragraph text', index)}</Text>`;
	}
	const encode = (slice: string) => encodeXmlValue(slice, diagnostics, 'paragraph text', index);
	const text = element.text;
	const out: string[] = [];
	let cursor = 0;
	const ordered = [...runs].sort((a, b) => a.start - b.start);
	for (const run of ordered) {
		const start = Math.max(cursor, Math.min(run.start, text.length));
		const end = Math.max(start, Math.min(run.end, text.length));
		if (start > cursor) out.push(`<Text>${encode(text.slice(cursor, start))}</Text>`);
		if (end > start) {
			const attrs: string[] = [];
			const styles = STYLE_ORDER.filter((token) => run.styles.includes(token));
			if (styles.length > 0) attrs.push(`Style="${styles.join('+')}"`);
			if (run.revisionID !== undefined) attrs.push(`RevisionID="${run.revisionID}"`);
			if (run.tagNumbers !== undefined && run.tagNumbers.length > 0) {
				attrs.push(`TagNumber="${run.tagNumbers.join(',')}"`);
			}
			if (run.highlight !== undefined) attrs.push(`${EDRAFT_PREFIX}:Highlight="Yellow"`);
			const attributeText = attrs.length > 0 ? ` ${attrs.join(' ')}` : '';
			out.push(`<Text${attributeText}>${encode(text.slice(start, end))}</Text>`);
		}
		cursor = end;
	}
	if (cursor < text.length) out.push(`<Text>${encode(text.slice(cursor))}</Text>`);
	return out.join('');
}

export function writeFdxWithDiagnostics(
	script: Screenplay,
	options: FdxExportOptions = {}
): FdxExportResult {
	const diagnostics = new DiagnosticCollector(
		positiveInteger(options.maxWarnings, DEFAULT_FDX_LIMITS.maxWarnings)
	);
	const body: string[] = [];
	/* Each paragraph's length as a ScriptNote Range counts it. */
	const lengths: number[] = [];
	/* And its words, so a note anchored to some of them finds them (§5.1).
	   A fresh write has no embedded blocks: dual dialogue is written as
	   Dual="Yes" on the cue, never as a <DualDialogue> block. */
	const paragraphTexts: { text: string; blocks: readonly number[] }[] = [];
	/* The writer's notes, and the paragraph each sits in front of. */
	const notes: { element: ScreenplayElement; at: number }[] = [];

	/* Omitted scenes (§7.3): the card each one hangs under, and every element
	   inside a span — written inside its card, never on its own. */
	const omissionAfter = new Map<number, Omission>();
	const omittedBody = new Set<number>();
	for (const omission of script.omissions ?? []) {
		if (omission.start <= 0 || omission.end <= omission.start) continue;
		omissionAfter.set(omission.start - 1, omission);
		for (let at = omission.start; at < omission.end; at++) omittedBody.add(at);
	}
	const paragraphAttributes = (element: ScreenplayElement, fdxType: string, index: number): string[] => {
		const attributes: string[] = [`Type="${fdxType}"`];
		if (element.type === 'centered' || element.type === 'actbreak') attributes.push('Alignment="Center"');
		if (element.type === 'lyrics') attributes.push(`${EDRAFT_PREFIX}:ElementType="lyrics"`);
		if (element.type === 'character' && element.dual) attributes.push('Dual="Yes"');
		if (element.type === 'scene' && element.sceneNumber) {
			attributes.push(`Number="${encodeXmlValue(element.sceneNumber, diagnostics, 'scene number', index)}"`);
		}
		return attributes;
	};
	/** One element of an omitted body, as the paragraph it was. */
	const paragraphMarkup = (element: ScreenplayElement, index: number): string => {
		const fdxType = fdxTypeOf(element) ?? 'Action';
		return `<Paragraph ${paragraphAttributes(element, fdxType, index).join(' ')}>${textRunsMarkup(element, diagnostics, index)}</Paragraph>`;
	};
	let waiting: ScreenplayElement[] = [];
	let omittedStructural = 0;
	let omittedUnknown = 0;
	let actCount = 0;
	/* the card the previous act break carries, so the generated End of Act
	   can name the act the way the act names itself */
	let previousActCard: string | undefined;

	for (const [index, element] of script.elements.entries()) {
		/* Inside an omitted scene: written with its card, not here. */
		if (omittedBody.has(index)) continue;
		/* A note is a ScriptNote (RFC-NOTES-SYSTEM §4.2), never a paragraph:
		   Final Draft shows a body Note paragraph as a line of the script. */
		if (element.type === 'note') {
			waiting.push(element);
			continue;
		}
		const fdxType = fdxTypeOf(element);
		if (!fdxType) {
			/* A non-printing element FDX has no paragraph type for — a
			   section, a synopsis, a page break. Notes are not among them:
			   Final Draft's Note element means what Fountain's [[ ]] means,
			   so it is in MODEL_TO_FDX and never reaches here. */
			if (isPrinting(element.type)) omittedUnknown++;
			else omittedStructural++;
			continue;
		}

		if (element.type === 'actbreak') {
			/* D3, written out loud: the act that just ended is a derivable
			   fact, so its card is generated here rather than stored in the
			   model. Final Draft readers see the file their software would
			   have written; eDraft never stores it. The card names the act
			   the way the act names itself: a canonical card ends "END OF
			   ACT ONE", a writer's own card is mirrored — TEASER closes as
			   END TEASER, which is Breaking Bad's own spelling. */
			actCount++;
			if (actCount > 1 && previousActCard !== undefined) {
				const endText = isCanonicalActCard(previousActCard)
					? `END OF ACT ${actOrdinal(actCount - 1)}`
					: `END ${previousActCard}`;
				body.push(
					`<Paragraph Type="End of Act" Alignment="Center"><Text>${encodeXmlValue(endText, diagnostics, 'end-of-act card', index)}</Text></Paragraph>`
				);
				lengths.push(endText.length);
				paragraphTexts.push({ text: endText, blocks: [] });
			}
			previousActCard = element.text;
		}

		const attributes = paragraphAttributes(element, fdxType, index);
		/* An omitted scene is written back where Final Draft keeps it: inside
		   the Scene Heading that shows its OMITTED card (§7.3). Its body is
		   not also written as live paragraphs — that is the resurrection this
		   lock exists to prevent. */
		const omission = omissionAfter.get(index);
		const block = omission
			? `<OmittedScene>${script.elements
					.slice(omission.start, omission.end)
					.map((line, at) => paragraphMarkup(line, omission.start + at))
					.join('')}</OmittedScene>`
			: '';
		body.push(`<Paragraph ${attributes.join(' ')}>${textRunsMarkup(element, diagnostics, index)}${block}</Paragraph>`);
		/* A ScriptNote Range counts an embedded block as two units, wherever
		   it sits — so a file this writer produces reads back with the same
		   Range space it was written from. */
		lengths.push(element.text.length + (omission ? BLOCK_UNITS : 0));
		paragraphTexts.push({ text: element.text, blocks: omission ? [element.text.length] : [] });
		for (const note of waiting) notes.push({ element: note, at: body.length - 1 });
		waiting = [];
	}
	for (const note of waiting) notes.push({ element: note, at: body.length - 1 });

	if (omittedStructural > 0) {
		diagnostics.add({
			code: 'FDX_STRUCTURAL_ELEMENTS_OMITTED',
			severity: 'warning',
			message: `${omittedStructural} non-printing structural element(s) were omitted because the supported FDX paragraph subset cannot represent them safely.`,
			count: omittedStructural
		});
	}
	if (omittedUnknown > 0) {
		diagnostics.add({
			code: 'FDX_UNKNOWN_ELEMENTS_OMITTED',
			severity: 'error',
			message: `${omittedUnknown} element(s) with unsupported runtime types were omitted.`,
			count: omittedUnknown
		});
	}

	const out: string[] = [
		XML_HEADER,
		`<FinalDraft xmlns:${EDRAFT_PREFIX}="${EDRAFT_NAMESPACE}" DocumentType="Script" Version="3">`
	];
	if (omittedStructural + omittedUnknown > 0) {
		out.push(
			`<!-- eDraft warning: ${omittedStructural + omittedUnknown} unsupported element(s) omitted; inspect writeFdxWithDiagnostics(). -->`
		);
	}
	out.push('<Content>', ...body, '</Content>');

	if (script.titlePage.length > 0) {
		out.push('<TitlePage>', '<Content>');
		for (const [lineIndex, line] of script.titlePage.entries()) {
			const alignment =
				line.alignment === 'left' ? 'Left' : line.alignment === 'right' ? 'Right' : 'Center';
			const key =
				line.key === undefined
					? ''
					: ` ${EDRAFT_PREFIX}:TitleKey="${encodeXmlValue(line.key, diagnostics, `title-page key ${lineIndex}`)}"`;
			out.push(
				`<Paragraph Alignment="${alignment}" Type="General"${key}>${textRunsMarkup(line, diagnostics, lineIndex)}</Paragraph>`
			);
		}
		out.push('</Content>', '</TitlePage>');
	}

	if (notes.length > 0) {
		const writing = resolvedNoteWriting(options.notes);
		const names = writing.writer ? [writing.writer] : [];
		out.push('<ScriptNotes>');
		notes.forEach(({ element, at }, index) => {
			const lines = scriptNoteLines(
				{
					id: index + 1,
					...noteAuthorship(element.text, names, writing.writer),
					range: noteRange(paragraphRange(lengths, at), paragraphTexts[at], element.anchor, diagnostics)
				},
				writing,
				diagnostics
			);
			out.push(...lines.map((line) => line.text));
		});
		out.push('</ScriptNotes>');
	}

	out.push('</FinalDraft>', '');
	const items = diagnostics.result();
	return { xml: out.join('\n'), warnings: messagesOf(items), diagnostics: items };
}

/**
 * Compatibility helper returning XML only. Call `writeFdxWithDiagnostics` in
 * new integrations so users can review any lossy conversion before download.
 */
export function writeFdx(script: Screenplay): string {
	return writeFdxWithDiagnostics(script).xml;
}
