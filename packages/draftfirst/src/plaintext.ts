/**
 * Plain-text and paste import. Handles the two shapes plain text arrives in:
 * typewriter layout (whitespace indents, wrapped lines, form feeds) and
 * reflowed prose (no layout at all — the classifier's shape rules carry it).
 *
 * Pagination artifacts of a printed script — page numbers, (MORE),
 * CONTINUED — are stripped and counted in the report, never silently.
 */

import { classifyLines, finalizeImport } from './classify.js';
import type { ImportResult, RawLine } from './classify.js';

export const DEFAULT_MAX_TEXT_SOURCE_CHARACTERS: number = 16 * 1024 * 1024;

/** The source text is beyond what an import may hold. */
export class PlainTextImportError extends RangeError {
	constructor(message: string) {
		super(message);
		this.name = 'PlainTextImportError';
	}
}

export interface PlainTextImportOptions {
	/** Refuse sources longer than this. Default 16 M characters. */
	maxSourceCharacters?: number;
	/** Report label — 'text' for files, 'paste' for the clipboard. */
	format?: string;
}

/* artifacts of a printed page, meaningful only to a reader of paper */
const PAGE_NUMBER = /^\d{1,4}\.?$/;
const MORE = /^\(MORE\)$/i;
const CONTD = /^\(CONT['’]?D\)$/i;
const CONTINUED = /^\(?CONTINUED\)?[.:]?$/i;

const TYPEWRITER_TAB_INCHES = 0.8;
const TYPEWRITER_SPACE_INCHES = 0.1;

function isArtifact(text: string): boolean {
	return PAGE_NUMBER.test(text) || MORE.test(text) || CONTD.test(text) || CONTINUED.test(text);
}

function leadingIndentInches(text: string): number {
	const lead = /^[\t ]*/.exec(text)?.[0] ?? '';
	let inches = 0;
	for (const char of lead) inches += char === '\t' ? TYPEWRITER_TAB_INCHES : TYPEWRITER_SPACE_INCHES;
	return Math.round(inches * 100) / 100;
}

/**
 * Import plain text (a .txt file, or pasted clipboard content) into a
 * classified screenplay plus its review report.
 */
export function importPlainText(source: string, options: PlainTextImportOptions = {}): ImportResult {
	const max = options.maxSourceCharacters ?? DEFAULT_MAX_TEXT_SOURCE_CHARACTERS;
	if (source.length > max) {
		throw new PlainTextImportError(`source holds ${source.length} characters — over the ${max} limit`);
	}

	const rawLines: RawLine[] = [];
	let stripped = 0;
	let attached = false;
	let pageBreakPending = false;

	for (const physicalLine of source.replace(/\r\n?/g, '\n').split('\n')) {
		/* a form feed is a hard page break; the next content line starts a page */
		const pageSegments = physicalLine.split('\f');
		for (let s = 0; s < pageSegments.length; s++) {
			if (s > 0) {
				pageBreakPending = true;
				attached = false;
			}
			const segment = pageSegments[s];
			if (segment === undefined) continue;
			const trimmed = segment.trim();
			if (trimmed === '') {
				attached = false;
				continue;
			}
			if (isArtifact(trimmed)) {
				stripped++;
				continue; /* attachment survives — (MORE) splits a speech, not a thought */
			}
			const line: RawLine = { text: trimmed.replace(/[\t ]{2,}/g, ' ') };
			const indent = leadingIndentInches(segment);
			if (indent > 0) line.indentInches = indent;
			if (attached) line.attached = true;
			if (pageBreakPending) {
				line.pageBreak = true;
				pageBreakPending = false;
			}
			rawLines.push(line);
			attached = true;
		}
	}

	const warnings: string[] = [];
	if (stripped > 0) {
		warnings.push(`stripped ${stripped} pagination artifact(s) — page numbers, (MORE), CONTINUED`);
	}
	if (rawLines.length === 0) warnings.push('no text found in the source');

	return finalizeImport(classifyLines(rawLines), options.format ?? 'text', warnings);
}
