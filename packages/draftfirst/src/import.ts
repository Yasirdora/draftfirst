/**
 * Universal import — paste, plain text, and .docx all land on the same
 * classified screenplay + review report — and the matching .docx export,
 * so a writer can leave in the same format they arrived in. The classifier
 * never guesses silently: low-confidence lines are flagged for review.
 */

export type {
	ClassifiedLine,
	FlaggedLine,
	ImportConfidence,
	ImportReport,
	ImportResult,
	RawLine
} from './classify.js';
export { classifyLines, finalizeImport, toScreenplay } from './classify.js';
export type { DocxImportOptions } from './docx.js';
export { DEFAULT_MAX_DOCX_BYTES, DocxImportError, importDocx } from './docx.js';
export { writeDocx } from './docxwrite.js';
export type { PlainTextImportOptions } from './plaintext.js';
export { DEFAULT_MAX_TEXT_SOURCE_CHARACTERS, importPlainText, PlainTextImportError } from './plaintext.js';
