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
import type {
	AnyElementType,
	ElementType,
	Screenplay,
	ScreenplayElement,
	TitlePageLine, StyleRun } from './types.js';

/* ---- diagnostics and limits -------------------------------------------- */

export type FdxDiagnosticSeverity = 'warning' | 'error';

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
	return diagnostics.map((diagnostic) => diagnostic.message);
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
						runs: []
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
			layout.push({ length: paragraph.text.length, element: key === 'end of act' ? -1 : elements.length });
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
			elements.push(element);
		}

		const scriptNotes = scriptNotesOf(source, layout, limits, diagnostics);
		return {
			script: { titlePage: titlePageLinesOf(parsed.title), elements },
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

/** One body paragraph as a ScriptNote Range counts it: its text length, and
    the element it became — -1 when the import absorbed it. */
interface ParagraphLayout {
	length: number;
	element: number;
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
		return { element: layout[low].element, offset: position - starts[low] };
	}
	for (let next = low + 1; next < layout.length; next++) {
		if (layout[next].element !== -1) return { element: layout[next].element, offset: 0 };
	}
	for (let previous = low - 1; previous >= 0; previous--) {
		if (layout[previous].element !== -1) {
			return { element: layout[previous].element, offset: layout[previous].length };
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
	diagnostics: DiagnosticCollector
): FdxScriptNote[] {
	const text = scriptTextOf(layout);
	const notes: FdxScriptNote[] = [];
	const open: string[] = [];
	let note: { attributes: Map<string, string>; depth: number; paragraphs: string[] } | null = null;
	let paragraph: { text: string; depth: number } | null = null;
	let run: { uppercases: boolean; depth: number } | null = null;
	let paragraphCount = 0;
	let textRunCount = 0;
	let limitReached = false;

	const finishNote = (): void => {
		if (!note) return;
		if (paragraph) note.paragraphs.push(paragraph.text);
		notes.push(scriptNoteOf(note.attributes, note.paragraphs, text));
		note = null;
		paragraph = null;
		run = null;
	};

	scanXml(
		source,
		{
			start(tag): boolean {
				const parent = open[open.length - 1];
				open.push(tag.name);
				const opensNote = tag.name === 'scriptnote' && parent === 'scriptnotes' && !note;
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
					note = { attributes: tag.attributes, depth: open.length, paragraphs: [] };
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
			end(name): boolean {
				if (run && name === 'text' && open.length === run.depth) {
					run = null;
				} else if (note && paragraph && name === 'paragraph' && open.length === paragraph.depth) {
					note.paragraphs.push(paragraph.text);
					paragraph = null;
				} else if (note && name === 'scriptnote' && open.length === note.depth) {
					finishNote();
				}
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
	rewrite(script: Screenplay): FdxExportResult;
}

/** One paragraph as it sits in the original file. */
interface OriginParagraph {
	key: string;
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
	/** The runs the file itself declared, for the content gate on a
	    preserving save — a run changed without a character moving still
	    rewrites the paragraph. */
	runs: StyleRun[];
	/**
	 * Whether the import absorbed this paragraph — an End of Act — so that no
	 * element will ever stand for it. The rewrite writes these back itself
	 * and never lets the alignment see them; see `openFdx`.
	 */
	absorbed: boolean;
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
	const spans = bodySpansOf(source, options);
	const first = spans.length > 0 ? spans[0].start : -1;
	const last = spans.length > 0 ? spans[spans.length - 1].end : -1;
	/* Only paragraphs the import turned into elements can be matched to one.
	   An absorbed End of Act left in the alignment was deleted by every save,
	   and — typed General when it has no Alignment — was paired with the
	   writer's next edit and given their text. */
	const aligned = spans.filter((span) => !span.absorbed);

	return {
		...imported,
		rewrite(script: Screenplay): FdxExportResult {
			// Nothing recognisable to edit: write a whole new file rather than
			// pretend, so a malformed or empty original cannot corrupt a save.
			if (spans.length === 0 || first < 0) return writeFdxWithDiagnostics(script);

			const diagnostics = new DiagnosticCollector(
				positiveInteger(options.maxWarnings, DEFAULT_FDX_LIMITS.maxWarnings)
			);
			const paired = alignParagraphs(aligned, script.elements);

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

			const out: string[] = [];
			// A new paragraph is laid out like the one it follows, so an insert
			// does not announce itself as the one differently-indented line in
			// the file.
			let lead = '';
			const restore = (span: OriginParagraph): void => {
				if (out.length > 0) out.push(span.lead === '' ? lead : span.lead);
				if (span.lead !== '') lead = span.lead;
				out.push(source.slice(span.start, span.end));
			};
			for (const [index, element] of script.elements.entries()) {
				const origin = paired[index];
				if (origin) {
					for (const span of absorbedBefore.get(origin.start) ?? []) restore(span);
					if (out.length > 0) out.push(origin.lead === '' ? lead : origin.lead);
					if (origin.lead !== '') lead = origin.lead;
					out.push(rewriteParagraph(source, origin, element, diagnostics, index));
					continue;
				}
				if (out.length > 0) out.push(lead === '' ? '\n' : lead);
				const fresh = writeFdxWithDiagnostics(
					{ titlePage: [], elements: [element] },
					options
				);
				const body = fresh.xml.match(/<Paragraph[\s\S]*<\/Paragraph>/);
				if (body) out.push(body[0]);
			}
			for (const span of waiting) restore(span);

			return {
				xml: ensureNamespaceDeclared(
					source.slice(0, first) + out.join('') + source.slice(last)
				),
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
function bodySpansOf(source: string, options: FdxImportOptions): OriginParagraph[] {
	const diagnostics = new DiagnosticCollector(1);
	const parsed = paragraphsOf(source, importLimits(options), diagnostics);
	let previousEnd = -1;
	return parsed.body.map((paragraph) => {
		const held = paragraph as FdxParagraph & {
			start: number;
			end: number;
			textStart: number;
			textEnd: number;
		};
		const fdxType = attributeOf(paragraph, 'type').trim().toLowerCase();
		/* End of Act is kept as a span, marked absorbed, by the same rule the
		   import absorbs it with (RFC-ACT-BREAK D3). No element ever stands
		   for it, so the rewrite owns its bytes: dropping the span here would
		   lose them, and leaving it unmarked let the alignment delete it. */
		const type = refineGeneral(fdxElementKind(fdxType)?.type ?? 'general', paragraph);
		const lead = previousEnd === -1 ? '' : source.slice(previousEnd, held.start);
		previousEnd = held.end;
		return {
			key: originKey(type, paragraph.text),
			type,
			start: held.start,
			end: held.end,
			textStart: held.textStart,
			textEnd: held.textEnd,
			lead,
			runs: paragraph.runs,
			absorbed: fdxType === 'end of act'
		};
	});
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
	let omittedStructural = 0;
	let omittedUnknown = 0;
	let actCount = 0;
	/* the card the previous act break carries, so the generated End of Act
	   can name the act the way the act names itself */
	let previousActCard: string | undefined;

	for (const [index, element] of script.elements.entries()) {
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
			}
			previousActCard = element.text;
		}

		const attributes: string[] = [`Type="${fdxType}"`];
		if (element.type === 'centered' || element.type === 'actbreak') {
			attributes.push('Alignment="Center"');
		}
		if (element.type === 'lyrics') attributes.push(`${EDRAFT_PREFIX}:ElementType="lyrics"`);
		if (element.type === 'character' && element.dual) attributes.push('Dual="Yes"');
		if (element.type === 'scene' && element.sceneNumber) {
			attributes.push(
				`Number="${encodeXmlValue(element.sceneNumber, diagnostics, 'scene number', index)}"`
			);
		}
		body.push(`<Paragraph ${attributes.join(' ')}>${textRunsMarkup(element, diagnostics, index)}</Paragraph>`);
	}

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
