/**
 * Minimal ZIP writer — the mirror of zip.ts. Entries are stored, never
 * compressed: a screenplay is a hundred kilobytes of text, and a stored
 * archive is readable by every unzipper ever shipped, with no async and no
 * platform compression API in the write path.
 *
 * The reader (zip.ts) verifies what this writer stamps — the round trip is
 * the test.
 */

import { crc32 } from './crc32.js';
import { encodeUtf8 } from './platform.js';

export interface ZipWriteEntry {
	/** Full path inside the archive, e.g. 'word/document.xml'. ASCII or UTF-8. */
	name: string;
	/** Uncompressed contents. */
	data: Uint8Array;
}

const LOCAL_SIG = 0x04034b50;
const CENTRAL_SIG = 0x02014b50;
const EOCD_SIG = 0x06054b50;

/**
 * Assemble a single-disk ZIP of stored entries: local headers, central
 * directory, end record — the exact layout zip.ts reads back.
 */
export function writeZipStored(entries: readonly ZipWriteEntry[]): Uint8Array {
	const locals: Uint8Array[] = [];
	const records: Uint8Array[] = [];
	let offset = 0;

	for (const entry of entries) {
		const name = encodeUtf8(entry.name);
		const crc = crc32(entry.data);

		const local = new Uint8Array(30 + name.length);
		const lv = new DataView(local.buffer);
		lv.setUint32(0, LOCAL_SIG, true);
		lv.setUint16(4, 20, true); /* version needed */
		lv.setUint32(14, crc, true);
		lv.setUint32(18, entry.data.length, true);
		lv.setUint32(22, entry.data.length, true);
		lv.setUint16(26, name.length, true);
		local.set(name, 30);
		locals.push(local, entry.data);

		const record = new Uint8Array(46 + name.length);
		const rv = new DataView(record.buffer);
		rv.setUint32(0, CENTRAL_SIG, true);
		rv.setUint16(4, 20, true); /* version made by */
		rv.setUint16(6, 20, true); /* version needed */
		rv.setUint32(16, crc, true);
		rv.setUint32(20, entry.data.length, true);
		rv.setUint32(24, entry.data.length, true);
		rv.setUint16(28, name.length, true);
		rv.setUint32(42, offset, true);
		record.set(name, 46);
		records.push(record);

		offset += local.length + entry.data.length;
	}

	let centralSize = 0;
	for (const record of records) centralSize += record.length;

	const eocd = new Uint8Array(22);
	const ev = new DataView(eocd.buffer);
	ev.setUint32(0, EOCD_SIG, true);
	ev.setUint16(8, entries.length, true);
	ev.setUint16(10, entries.length, true);
	ev.setUint32(12, centralSize, true);
	ev.setUint32(16, offset, true);

	const out = new Uint8Array(offset + centralSize + eocd.length);
	let at = 0;
	for (const chunk of [...locals, ...records, eocd]) {
		out.set(chunk, at);
		at += chunk.length;
	}
	return out;
}
