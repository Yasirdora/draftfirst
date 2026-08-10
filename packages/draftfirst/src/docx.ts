/**
 * .docx import — lifts screenplay lines out of a Word document with zero
 * dependencies: the OOXML package is a ZIP, the platform inflates it, and
 * the document body is read straight off the XML.
 *
 * What we read: paragraph text, paragraph styles (via styles.xml), direct
 * indentation, alignment, hard page breaks, and tracked-change state.
 * What we skip, loudly in the report: tables and embedded images.
 *
 * Namespaces: Word, Google Docs, and Pages all emit the `w:` prefix for the
 * main document schema; that is the dialect this reader speaks.
 */

import { classifyLines, finalizeImport } from './classify.js';
import type { ImportResult, RawLine } from './classify.js';
import { decodeXmlEntities } from './fdx.js';
import { decodeUtf8 } from './platform.js';
import { findEntry, readZipEntries } from './zip.js';
import type { ZipEntry } from './zip.js';

/** The file is not a readable Word document. */
export class DocxImportError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'DocxImportError';
	}
}

export const DEFAULT_MAX_DOCX_BYTES: number = 32 * 1024 * 1024;

export interface DocxImportOptions {
	/** Refuse files larger than this before unzipping. Default 32 MB. */
	maxBytes?: number;
}

const TWIPS_PER_INCH = 1440;
const WORD_TAB_INCHES = 0.5;
const WORD_SPACE_INCHES = 0.1;

const TABLE = /<w:tbl\b[\s\S]*?<\/w:tbl>/g;
const DELETED = /<w:(?:del|moveFrom)\b[\s\S]*?<\/w:(?:del|moveFrom)>/g;
const INSERTED = /<w:(?:ins|moveTo)\b[^>]*>([\s\S]*?)<\/w:(?:ins|moveTo)>/g;
const IMAGE = /<w:(?:drawing|pict)\b/g;
const PARAGRAPH = /<w:p\b[^>]*\/>|<w:p\b[^>]*>[\s\S]*?<\/w:p>/g;
const PARAGRAPH_PROPS = /<w:pPr>([\s\S]*?)<\/w:pPr>/;
const TOKEN =
	/<w:t\b[^>]*\/>|<w:t\b[^>]*>([\s\S]*?)<\/w:t>|<w:tab\b[^>]*\/>|<w:br\b[^>]*\bw:type="page"[^>]*\/>|<w:(?:br|cr)\b[^>]*\/>/g;

function attribute(xml: string, name: string): string | undefined {
	return new RegExp(`\\b${name}="([^"]*)"`).exec(xml)?.[1];
}

/** styleId → display name, from word/styles.xml. */
function parseStyleNames(stylesXml: string): Map<string, string> {
	const names = new Map<string, string>();
	for (const block of stylesXml.matchAll(/<w:style\b([^>]*)>([\s\S]*?)<\/w:style>/g)) {
		const attrs = block[1];
		const body = block[2];
		if (attrs === undefined || body === undefined) continue;
		const id = attribute(attrs, 'w:styleId');
		const name = /<w:name\b[^>]*>/.exec(body)?.[0];
		if (id !== undefined && name !== undefined) {
			const value = attribute(name, 'w:val');
			if (value !== undefined) names.set(id, decodeXmlEntities(value));
		}
	}
	return names;
}

interface ParagraphLayout {
	styleName?: string;
	indentInches?: number;
	align?: 'left' | 'right' | 'center';
	pageBreakBefore: boolean;
}

/** Read the paragraph properties block of one <w:p>. */
function parseParagraphLayout(block: string, styles: Map<string, string>): ParagraphLayout {
	const layout: ParagraphLayout = { pageBreakBefore: false };
	const props = PARAGRAPH_PROPS.exec(block)?.[1];
	if (props === undefined) return layout;

	const styleTag = /<w:pStyle\b[^>]*>/.exec(props)?.[0];
	if (styleTag !== undefined) {
		const id = attribute(styleTag, 'w:val');
		if (id !== undefined) layout.styleName = styles.get(id) ?? id;
	}

	const indTag = /<w:ind\b[^>]*\/>/.exec(props)?.[0];
	if (indTag !== undefined) {
		const twips = (name: string): number => {
			const value = attribute(indTag, name);
			return value === undefined ? 0 : Number.parseInt(value, 10) || 0;
		};
		const left = twips('w:left') + twips('w:start');
		const effective = left + twips('w:firstLine') - twips('w:hanging');
		if (effective > 0) layout.indentInches = Math.round((effective / TWIPS_PER_INCH) * 100) / 100;
	}

	const jcTag = /<w:jc\b[^>]*>/.exec(props)?.[0];
	if (jcTag !== undefined) {
		const value = attribute(jcTag, 'w:val');
		if (value === 'center') layout.align = 'center';
		else if (value === 'right' || value === 'end') layout.align = 'right';
	}

	if (/<w:pageBreakBefore\b/.test(props)) layout.pageBreakBefore = true;
	return layout;
}

/**
 * Reduce one paragraph's XML to text with structural sentinels: \n for line
 * breaks, \f for hard page breaks, \t for tabs. Only <w:t>, <w:tab>, and
 * <w:br>/<w:cr> carry visible content; everything else is ignored.
 */
function paragraphText(block: string): string {
	let text = '';
	for (const token of block.matchAll(TOKEN)) {
		const tag = token[0];
		if (tag.startsWith('<w:tab')) {
			text += '\t';
		} else if (token[1] !== undefined) {
			text += decodeXmlEntities(token[1]);
		} else if (tag.includes('w:type="page"')) {
			text += '\f';
		} else if (tag.startsWith('<w:br') || tag.startsWith('<w:cr')) {
			text += '\n';
		}
		/* anything else — an empty <w:t/> — carries no visible content */
	}
	return text;
}

/** Leading whitespace is a writer's hand-made indent — honor it as layout. */
function leadingIndentInches(text: string): number {
	const lead = /^[\t ]*/.exec(text)?.[0] ?? '';
	let inches = 0;
	for (const char of lead) inches += char === '\t' ? WORD_TAB_INCHES : WORD_SPACE_INCHES;
	return Math.round(inches * 100) / 100;
}

/**
 * Import a .docx. Throws DocxImportError for anything that is not a readable
 * Word document — a clear error is a feature, a silent misread is a bug.
 */
export async function importDocx(source: Uint8Array, options: DocxImportOptions = {}): Promise<ImportResult> {
	const maxBytes = options.maxBytes ?? DEFAULT_MAX_DOCX_BYTES;
	if (source.length > maxBytes) {
		throw new DocxImportError(`file is ${source.length} bytes — over the ${maxBytes}-byte limit`);
	}
	if (source.length < 4 || source[0] !== 0x50 || source[1] !== 0x4b) {
		throw new DocxImportError('not a .docx (ZIP signature missing)');
	}

	let entries: ZipEntry[];
	try {
		entries = await readZipEntries(source);
	} catch (error) {
		throw new DocxImportError(error instanceof Error ? error.message : 'the archive could not be read');
	}
	const documentEntry = findEntry(entries, 'word/document.xml');
	if (documentEntry === undefined) {
		throw new DocxImportError('word/document.xml is missing — not a Word document');
	}
	const stylesEntry = findEntry(entries, 'word/styles.xml');
	const styles = stylesEntry === undefined ? new Map<string, string>() : parseStyleNames(decodeUtf8(stylesEntry.data));

	let xml = decodeUtf8(documentEntry.data);
	const warnings: string[] = [];

	const tables = xml.match(TABLE)?.length ?? 0;
	if (tables > 0) warnings.push(`ignored ${tables} table(s) — tables do not map to screenplay elements`);
	xml = xml.replace(TABLE, '');

	const deletions = xml.match(DELETED)?.length ?? 0;
	if (deletions > 0) warnings.push(`dropped ${deletions} tracked deletion(s)`);
	xml = xml.replace(DELETED, '').replace(INSERTED, '$1');

	const images = xml.match(IMAGE)?.length ?? 0;
	if (images > 0) warnings.push(`ignored ${images} embedded image(s)`);

	const rawLines: RawLine[] = [];
	/* a page break in a paragraph with no text after it (a standalone break
	   paragraph, which is how we export them) carries to the next content */
	let pageBreakPending = false;
	for (const paragraph of xml.matchAll(PARAGRAPH)) {
		const block = paragraph[0];
		if (block.endsWith('/>')) continue; /* an empty paragraph is just a gap */
		const layout = parseParagraphLayout(block, styles);
		const text = paragraphText(block);
		/* \f splits first: each segment after a page break starts a fresh line */
		const pageSegments = text.split('\f');
		for (let s = 0; s < pageSegments.length; s++) {
			if (s > 0) pageBreakPending = true;
			const segment = pageSegments[s];
			if (segment === undefined) continue;
			const physicalLines = segment.split('\n');
			for (let n = 0; n < physicalLines.length; n++) {
				const physical = physicalLines[n];
				if (physical === undefined) continue;
				const content = physical.trim().replace(/[\t ]{2,}/g, ' ');
				if (content === '') continue;
				const line: RawLine = { text: content };
				if (layout.indentInches !== undefined) {
					line.indentInches = layout.indentInches;
				} else {
					const leading = leadingIndentInches(physical);
					if (leading > 0) line.indentInches = leading;
				}
				if (layout.align !== undefined) line.align = layout.align;
				if (layout.styleName !== undefined) line.styleName = layout.styleName;
				if (n > 0) line.attached = true; /* a line break, not a new paragraph */
				if (pageBreakPending || (n === 0 && s === 0 && layout.pageBreakBefore)) {
					line.pageBreak = true;
					pageBreakPending = false;
				}
				rawLines.push(line);
			}
		}
	}
	if (rawLines.length === 0) warnings.push('no text found in the document');

	return finalizeImport(classifyLines(rawLines), 'docx', warnings);
}
