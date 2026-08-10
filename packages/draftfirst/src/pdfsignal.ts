/**
 * PDF round-trip signal — how a Draft First PDF carries its own source home.
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

export const PDF_MARKER_PREFIX = 'DRAFT_FIRST_FOUNTAIN';
export const PDF_MARKER_VERSION = '1';

/** The hex string to stamp into /Keywords at export. */
export function encodePdfPayload(fountain: string): string {
	const bytes = encodeUtf8(`${PDF_MARKER_PREFIX}:${PDF_MARKER_VERSION}\n${fountain}`);
	let hex = '';
	for (let i = 0; i < bytes.length; i++) hex += bytes[i]!.toString(16).padStart(2, '0');
	return hex;
}

const KEYWORD_FIELD = '/Keywords';
const HEX_DIGIT = /^[0-9a-fA-F]$/;

/** The raw bytes of a `/Keywords <hex>` value starting at `from`, or null. */
function readKeywordsHex(source: Uint8Array, from: number): string | null {
	let at = from + KEYWORD_FIELD.length;
	while (at < source.length && (source[at] === 0x20 || source[at] === 0x09 || source[at] === 0x0a || source[at] === 0x0d)) {
		at++;
	}
	if (source[at] !== 0x3c /* '<' */) return null;
	if (source[at + 1] === 0x3c /* '<<' — a dictionary, not a hex string */) return null;
	at++;
	let hex = '';
	while (at < source.length && source[at] !== 0x3e /* '>' */) {
		const ch = String.fromCharCode(source[at]!);
		if (!HEX_DIGIT.test(ch)) return null;
		hex += ch;
		at++;
	}
	if (at >= source.length || hex.length === 0 || hex.length % 2 !== 0) return null;
	return hex;
}

function hexToBytes(hex: string): Uint8Array {
	const bytes = new Uint8Array(hex.length / 2);
	for (let i = 0; i < bytes.length; i++) bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
	return bytes;
}

/**
 * The Fountain source embedded in a Draft First PDF, or null when the file
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
		if (prefix !== PDF_MARKER_PREFIX || version !== PDF_MARKER_VERSION) continue;
		return payload.slice(separator + 1);
	}
	return null;
}
