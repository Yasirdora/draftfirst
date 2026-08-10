/**
 * Draft First Screenwriting Engine FDX interoperability.
 *
 * This is deliberately a small, non-validating XML reader. It understands the
 * FDX paragraph/text subset, ignores comments and processing instructions, and
 * never resolves external entities. Import is bounded and best-effort: malformed
 * input produces structured diagnostics instead of escaping as an exception.
 *
 * FDX cannot represent every element in the Draft First document model. Detailed export
 * therefore reports every lossy conversion, and the compatibility `writeFdx`
 * helper embeds an XML warning when non-printing structure must be omitted.
 */

import type { AnyElementType, Screenplay, ScreenplayElement, TitlePageEntry } from './types.js';

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
	general: 'general'
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
	lyrics: 'General'
};

const DRAFTFIRST_NAMESPACE = 'https://draftfirst.xyz/ns/fdx/1';

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

interface FdxParagraph {
	attributes: Map<string, string>;
	text: string;
	paragraphIndex: number;
}

interface ParsedParagraphs {
	body: FdxParagraph[];
	title: FdxParagraph[];
	hasFinalDraftRoot: boolean;
}

type MutableFdxParagraph = FdxParagraph & { inTitlePage: boolean };

function paragraphsOf(
	source: string,
	limits: FdxLimits,
	diagnostics: DiagnosticCollector
): ParsedParagraphs {
	const body: FdxParagraph[] = [];
	const title: FdxParagraph[] = [];
	let hasFinalDraftRoot = false;
	let titleDepth = 0;
	let contentDepth = 0;
	let textDepth = 0;
	let paragraphCount = 0;
	let textRunCount = 0;
	let limitReached = false;
	let current: MutableFdxParagraph | null = null;

	const finishParagraph = (): void => {
		if (!current) return;
		if (current.inTitlePage) title.push(current);
		else body.push(current);
		current = null;
		textDepth = 0;
	};

	scanXml(
		source,
		{
			start(tag, offset): boolean {
				if (tag.name === 'finaldraft') hasFinalDraftRoot = true;
				if (tag.name === 'titlepage') titleDepth++;
				if (tag.name === 'content') contentDepth++;

				if (tag.name === 'paragraph' && contentDepth > 0) {
					if (paragraphCount >= limits.maxParagraphs) {
						limitReached = true;
						return false;
					}
					if (current) {
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
						inTitlePage: titleDepth > 0
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
				}
				return true;
			},
			end(name): boolean {
				if (name === 'text' && textDepth > 0) textDepth--;
				if (name === 'paragraph') finishParagraph();
				if (name === 'content' && contentDepth > 0) contentDepth--;
				if (name === 'titlepage' && titleDepth > 0) titleDepth--;
				return true;
			},
			text(value, cdata): boolean {
				if (current && textDepth > 0) current.text += cdata ? value : decodeXmlEntities(value);
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

/* ---- import ------------------------------------------------------------- */

/** Guess a title-page key from paragraph position when an external FDX has no key metadata. */
function titleKeyFor(index: number): string {
	return ['Title', 'Credit', 'Author', 'Source', 'Contact'][index] ?? 'Contact';
}

function titlePageOf(
	paragraphs: FdxParagraph[],
	diagnostics: DiagnosticCollector
): TitlePageEntry[] {
	const tagged = new Map<number, TitlePageEntry>();
	const untagged: string[] = [];

	for (const paragraph of paragraphs) {
		const key = attributeOf(paragraph, 'draftfirst:titlekey');
		const rawEntryIndex = attributeOf(paragraph, 'draftfirst:titleentry');
		const entryIndex = Number(rawEntryIndex);
		if (
			key !== '' &&
			rawEntryIndex !== '' &&
			Number.isSafeInteger(entryIndex) &&
			entryIndex >= 0
		) {
			const existing = tagged.get(entryIndex);
			if (!existing) tagged.set(entryIndex, { key, values: [paragraph.text] });
			else if (existing.key === key) existing.values.push(paragraph.text);
			else {
				diagnostics.add({
					code: 'FDX_CONFLICTING_TITLE_METADATA',
					severity: 'warning',
					message: `Title entry ${entryIndex} declared conflicting keys; the later paragraph was imported positionally.`,
					paragraphIndex: paragraph.paragraphIndex
				});
				if (paragraph.text.trim() !== '') untagged.push(paragraph.text);
			}
		} else if (paragraph.text.trim() !== '') untagged.push(paragraph.text);
	}

	const titlePage = [...tagged.entries()]
		.sort(([left], [right]) => left - right)
		.map(([, entry]) => entry);
	for (let index = 0; index < untagged.length; index++) {
		const text = untagged[index];
		if (text === undefined) continue;
		const key = titleKeyFor(index);
		const existing = titlePage.find((entry) => entry.key === key);
		if (existing) existing.values.push(text);
		else titlePage.push({ key, values: [text] });
	}
	return titlePage;
}

function emptyImport(diagnostics: DiagnosticCollector): FdxImportResult {
	const items = diagnostics.result();
	return {
		script: { titlePage: [], elements: [] },
		warnings: messagesOf(items),
		diagnostics: items
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
		for (const paragraph of parsed.body) {
			const fdxType = attributeOf(paragraph, 'type');
			const key = fdxType.trim().toLowerCase();
			let type = FDX_TO_MODEL[key];
			if (!type) {
				if (fdxType !== '') {
					diagnostics.add({
						code: 'FDX_UNKNOWN_PARAGRAPH_TYPE',
						severity: 'warning',
						message: `Unknown paragraph type "${fdxType}" — imported as General.`,
						paragraphIndex: paragraph.paragraphIndex
					});
				}
				type = 'general';
			}

			const draftFirstType = attributeOf(paragraph, 'draftfirst:elementtype').toLowerCase();
			if (type === 'general' && draftFirstType === 'lyrics') type = 'lyrics';
			if (type === 'general' && attributeOf(paragraph, 'alignment').toLowerCase() === 'center') {
				type = 'centered';
			}

			const element: ScreenplayElement = { type, text: paragraph.text };
			const sceneNumber = attributeOf(paragraph, 'number');
			if (type === 'scene' && sceneNumber !== '') element.sceneNumber = sceneNumber;
			if (type === 'character' && attributeOf(paragraph, 'dual').toLowerCase() === 'yes') {
				element.dual = true;
			}
			elements.push(element);
		}

		return {
			script: { titlePage: titlePageOf(parsed.title, diagnostics), elements },
			warnings: messagesOf(diagnostics.result()),
			diagnostics: diagnostics.result()
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

/* ---- export ------------------------------------------------------------- */

const XML_HEADER = '<?xml version="1.0" encoding="UTF-8" standalone="no" ?>';

function structuralType(type: AnyElementType): boolean {
	return type === 'note' || type === 'section' || type === 'synopsis' || type === 'pagebreak';
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

	for (const [index, element] of script.elements.entries()) {
		const fdxType = MODEL_TO_FDX[element.type];
		if (!fdxType) {
			if (structuralType(element.type)) omittedStructural++;
			else omittedUnknown++;
			continue;
		}

		const attributes: string[] = [`Type="${fdxType}"`];
		if (element.type === 'centered') attributes.push('Alignment="Center"');
		if (element.type === 'lyrics') attributes.push('DraftFirst:ElementType="lyrics"');
		if (element.type === 'character' && element.dual) attributes.push('Dual="Yes"');
		if (element.type === 'scene' && element.sceneNumber) {
			attributes.push(
				`Number="${encodeXmlValue(element.sceneNumber, diagnostics, 'scene number', index)}"`
			);
		}
		const encoded = encodeXmlValue(element.text, diagnostics, 'paragraph text', index);
		body.push(`<Paragraph ${attributes.join(' ')}><Text>${encoded}</Text></Paragraph>`);
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
		`<FinalDraft xmlns:DraftFirst="${DRAFTFIRST_NAMESPACE}" DocumentType="Script" Version="3">`
	];
	if (omittedStructural + omittedUnknown > 0) {
		out.push(
			`<!-- DraftFirst warning: ${omittedStructural + omittedUnknown} unsupported element(s) omitted; inspect writeFdxWithDiagnostics(). -->`
		);
	}
	out.push('<Content>', ...body, '</Content>');

	if (script.titlePage.length > 0) {
		out.push('<TitlePage>', '<Content>');
		for (const [entryIndex, entry] of script.titlePage.entries()) {
			const values = entry.values.length > 0 ? entry.values : [''];
			const key = encodeXmlValue(entry.key, diagnostics, `title-page key ${entryIndex}`);
			for (const value of values) {
				const encoded = encodeXmlValue(value, diagnostics, `title-page entry ${entryIndex}`);
				out.push(
					`<Paragraph Alignment="Center" Type="General" DraftFirst:TitleKey="${key}" DraftFirst:TitleEntry="${entryIndex}"><Text>${encoded}</Text></Paragraph>`
				);
			}
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
