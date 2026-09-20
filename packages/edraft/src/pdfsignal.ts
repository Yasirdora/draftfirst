/**
 * PDF round-trip signal — how an eDraft PDF carries its own source home.
 *
 * Parsing arbitrary PDF text back into a screenplay is lossy and would take
 * a dependency we refuse to carry. But a PDF WE exported never needs
 * parsing: its Info dictionary can legally hold the complete Fountain source
 * as a hex string in /Keywords, a field every viewer and print pipeline
 * preserves. Export stamps it; import scans for it. Perfect fidelity, zero
 * dependencies, and foreign PDFs simply have no signal — a clean refusal.
 *
 * The payload is versioned. A future format bumps the version so tomorrow's
 * reader can tell today's files apart — and today's reader says "I can't"
 * instead of reading garbage.
 *
 * Encoding note: the payload hex-encodes UTF-8 BYTES, not UTF-16 code
 * units — curly quotes, em dashes, and every non-Latin script survive
 * intact. (Hex-encoding code units, the tempting shortcut, corrupts beyond
 * the BMP and mangles nothing less than the writer's own punctuation.)
 */

import { decodeUtf8, encodeUtf8 } from './platform.js';

export const PDF_MARKER_PREFIX = 'EDRAFT_FOUNTAIN';
export const PDF_MARKER_VERSION = '1';

/**
 * The prefix written before the eDraft rename. Every PDF exported under the
 * old name still carries it, and those files are writers' backups — so we
 * read it forever and never write it again. A rename is our problem, never
 * theirs.
 *
 * This string must never appear in a find-and-replace: the day the product
 * was renamed, a blanket rewrite of the sources changed this entry to the
 * NEW prefix, and every pre-rename PDF went unread until it was restored.
 * Whatever the product is called next, `DRAFT_FIRST_FOUNTAIN` stays.
 */
export const LEGACY_PDF_MARKER_PREFIXES: readonly string[] = Object.freeze([
	'DRAFT_FIRST_FOUNTAIN'
]);

function isKnownMarkerPrefix(prefix: string): boolean {
	return prefix === PDF_MARKER_PREFIX || LEGACY_PDF_MARKER_PREFIXES.includes(prefix);
}

/** The hex string to stamp into /Keywords at export. */
export function encodePdfPayload(fountain: string): string {
	const bytes = encodeUtf8(`${PDF_MARKER_PREFIX}:${PDF_MARKER_VERSION}\n${fountain}`);
	let hex = '';
	for (let i = 0; i < bytes.length; i++) hex += bytes[i]!.toString(16).padStart(2, '0');
	return hex;
}

const KEYWORD_FIELD = '/Keywords';
const HEX_DIGIT = /^[0-9a-fA-F]$/;

/** Hex digits of a `/Keywords` value starting at `from`, or null.
 *
 *  Three spellings are legal: a PDF hex string `<…>` (what the web exporter
 *  writes into the Info dict), a PDF literal `(…)` (Core Graphics before
 *  macOS 27), and an indirect reference `N G R` naming an object that holds
 *  the string (Core Graphics on macOS 27, measured 2026-09-19: Quartz
 *  writes `/Keywords 6 0 R` with the literal in object 6, and PDFKit's
 *  rewrite keeps the indirection). The payload is hex either way —
 *  `[0-9a-fA-F]` needs no escaping inside a literal — so all three survive
 *  a viewer re-save. Trailing bytes after `%%EOF` do not. */
function readKeywordsHex(source: Uint8Array, from: number): string | null {
	const at = skipWhitespace(source, from + KEYWORD_FIELD.length);
	if (at >= source.length) return null;
	const opener = source[at]!;
	if (opener === 0x3c /* '<' */ || opener === 0x28 /* '(' */) {
		return readStringHex(source, at);
	}
	if (opener >= 0x30 && opener <= 0x39 /* '0'..'9' */) {
		return readIndirectStringHex(source, at);
	}
	return null;
}

function skipWhitespace(source: Uint8Array, from: number): number {
	let at = from;
	while (at < source.length && (source[at] === 0x20 || source[at] === 0x09 || source[at] === 0x0a || source[at] === 0x0d)) {
		at++;
	}
	return at;
}

/** Follows one level of indirection: `N G R` resolves to the string inside
 *  `N G obj`. One level only — a reference to a reference is not a shape we
 *  write, and chasing one risks a loop. */
function readIndirectStringHex(source: Uint8Array, at: number): string | null {
	const objectNumber = readInteger(source, at);
	if (objectNumber === null) return null;
	const generation = readInteger(source, skipWhitespace(source, objectNumber.end));
	if (generation === null) return null;
	const rAt = skipWhitespace(source, generation.end);
	if (rAt >= source.length || source[rAt] !== 0x52 /* 'R' */) return null;

	const needle = encodeUtf8(`${objectNumber.value} ${generation.value} obj`);
	for (let i = 0; i + needle.length <= source.length; i++) {
		let match = true;
		for (let n = 0; n < needle.length; n++) {
			if (source[i + n] !== needle[n]) { match = false; break; }
		}
		if (!match) continue;
		// "6 0 obj" is a suffix of "26 0 obj" — the byte before the match
		// must not be a digit, or object 26 answers for object 6.
		if (i > 0 && source[i - 1]! >= 0x30 && source[i - 1]! <= 0x39) continue;
		const hex = readStringHex(source, skipWhitespace(source, i + needle.length));
		if (hex !== null) return hex;
	}
	return null;
}

function readInteger(source: Uint8Array, at: number): { value: number; end: number } | null {
	let value = 0;
	let end = at;
	while (end < source.length && source[end]! >= 0x30 && source[end]! <= 0x39) {
		value = value * 10 + (source[end]! - 0x30);
		end++;
	}
	return end > at ? { value, end } : null;
}

/** Hex digits inside a PDF hex string `<…>` or literal `(…)` starting at
 *  `at`. `<<` is a dictionary, not a hex string. */
function readStringHex(source: Uint8Array, at: number): string | null {
	const opener = source[at];
	let closer: number;
	if (opener === 0x3c /* '<' */) {
		if (source[at + 1] === 0x3c /* '<<' — a dictionary, not a hex string */) return null;
		closer = 0x3e; /* '>' */
	} else if (opener === 0x28 /* '(' */) {
		closer = 0x29; /* ')' */
	} else {
		return null;
	}
	let i = at + 1;
	let hex = '';
	while (i < source.length && source[i] !== closer) {
		const ch = String.fromCharCode(source[i]!);
		if (!HEX_DIGIT.test(ch)) return null;
		hex += ch;
		i++;
	}
	if (i >= source.length || hex.length === 0 || hex.length % 2 !== 0) return null;
	return hex;
}

function hexToBytes(hex: string): Uint8Array {
	const bytes = new Uint8Array(hex.length / 2);
	for (let i = 0; i < bytes.length; i++) bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
	return bytes;
}

/**
 * The Fountain source embedded in an eDraft PDF, or null when the file
 * carries no valid signal — a foreign PDF, an older export, or a newer
 * format version this build does not understand.
 */
export function extractPdfPayload(source: Uint8Array): string | null {
	const needle = encodeUtf8(KEYWORD_FIELD);
	outer: for (let i = 0; i + needle.length <= source.length; i++) {
		for (let n = 0; n < needle.length; n++) {
			if (source[i + n] !== needle[n]) continue outer;
		}
		const hex = readKeywordsHex(source, i);
		if (hex === null) continue;
		const payload = decodeUtf8(hexToBytes(hex));
		const separator = payload.indexOf('\n');
		if (separator < 0) continue;
		const header = payload.slice(0, separator);
		const [prefix, version] = header.split(':');
		if (prefix === undefined || !isKnownMarkerPrefix(prefix)) continue;
		if (version !== PDF_MARKER_VERSION) continue;
		return payload.slice(separator + 1);
	}
	return null;
}
