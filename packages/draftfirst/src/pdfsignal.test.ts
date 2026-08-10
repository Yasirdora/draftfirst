/** PDF round-trip signal: the marker a Draft First PDF carries home. */
import { describe, expect, it } from 'vitest';
import { encodePdfPayload, extractPdfPayload, PDF_MARKER_PREFIX } from './pdfsignal.js';
import { encodeUtf8 } from './platform.js';

function fakePdfWithKeywords(hex: string | null): Uint8Array {
	const info = hex === null ? '<< /Producer (Someone Else) >>' : `<< /Producer (Draft First) /Keywords <${hex}> >>`;
	return encodeUtf8(`%PDF-1.4\n3 0 obj\n${info}\nendobj\ntrailer\n<< /Root 1 0 R /Info 3 0 R >>\n%%EOF`);
}

function toHex(text: string): string {
	const bytes = encodeUtf8(text);
	let hex = '';
	for (const b of bytes) hex += b.toString(16).padStart(2, '0');
	return hex;
}

describe('encodePdfPayload / extractPdfPayload', () => {
	it('round-trips a screenplay byte-for-byte, Unicode intact', () => {
		const fountain = 'Title: The Long Way Home\n\nINT. CAFÉ - DAY\n\nMolly’s kettle screams — “loudly.” 日本語も。\n';
		const bytes = fakePdfWithKeywords(encodePdfPayload(fountain));
		expect(extractPdfPayload(bytes)).toBe(fountain);
	});

	it('returns null for a PDF with no Info signal', () => {
		expect(extractPdfPayload(fakePdfWithKeywords(null))).toBeNull();
	});

	it('returns null when /Keywords holds a foreign payload', () => {
		expect(extractPdfPayload(fakePdfWithKeywords(toHex('SOMEONE_ELSE:1\n{}')))).toBeNull();
	});

	it('returns null for a payload version it does not understand', () => {
		expect(extractPdfPayload(fakePdfWithKeywords(toHex(`${PDF_MARKER_PREFIX}:99\nfuture`)))).toBeNull();
	});

	it('ignores malformed hex without throwing', () => {
		expect(extractPdfPayload(fakePdfWithKeywords('abc'))).toBeNull();
		expect(extractPdfPayload(fakePdfWithKeywords('zz'))).toBeNull();
	});

	it('skips a foreign /Keywords and finds the valid one later in the file', () => {
		const fountain = 'INT. A - DAY\n';
		const prefix = encodeUtf8(`%PDF-1.4\n1 0 obj\n<< /Keywords <${toHex('foreign')} >>\nendobj\n`);
		const rest = fakePdfWithKeywords(encodePdfPayload(fountain));
		const both = new Uint8Array(prefix.length + rest.length);
		both.set(prefix, 0);
		both.set(rest, prefix.length);
		expect(extractPdfPayload(both)).toBe(fountain);
	});

	it('returns null for bytes that are not a PDF at all', () => {
		expect(extractPdfPayload(encodeUtf8('just some text, no fields here'))).toBeNull();
	});

	it('does not mistake a dictionary for a hex string', () => {
		const bytes = encodeUtf8('%PDF-1.4\n<< /Keywords << /Nested true >> >>\n%%EOF');
		expect(extractPdfPayload(bytes)).toBeNull();
	});
});
