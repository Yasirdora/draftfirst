/**
 * Minimal ZIP reader — just enough of the format to open an Office Open XML
 * package (.docx). Zero dependencies: stored entries are sliced, deflated
 * entries inflate through the platform's native DecompressionStream.
 *
 * Doctrine: refuse loudly what we do not understand (ZIP64, encryption,
 * multi-disk, exotic compression). A clear error is a feature; a silent
 * misread is a bug.
 */

import { decodeUtf8, inflateRaw } from './platform.js';
import { crc32 } from './crc32.js';

/** The archive cannot be read as a ZIP — corrupt, encrypted, or exotic. */
export class ZipFormatError extends Error {
	constructor(message: string) {
		super(message);
		this.name = 'ZipFormatError';
	}
}

export interface ZipEntry {
	/** Full path inside the archive, e.g. 'word/document.xml'. */
	name: string;
	/** Uncompressed contents. */
	data: Uint8Array;
}

export interface ZipReadOptions {
	/** Refuse archives with more entries than this. Default 512. */
	maxEntries?: number;
	/** Refuse any single entry whose uncompressed size exceeds this. Default 64 MB. */
	maxEntryBytes?: number;
	/** Refuse when total uncompressed size exceeds this. Default 128 MB. */
	maxTotalBytes?: number;
}

export const DEFAULT_ZIP_MAX_ENTRIES: number = 512;
export const DEFAULT_ZIP_MAX_ENTRY_BYTES: number = 64 * 1024 * 1024;
export const DEFAULT_ZIP_MAX_TOTAL_BYTES: number = 128 * 1024 * 1024;

const EOCD_SIG = 0x06054b50;
const CENTRAL_SIG = 0x02014b50;
const LOCAL_SIG = 0x04034b50;

function u16(bytes: Uint8Array, at: number): number {
	return bytes[at]! | (bytes[at + 1]! << 8);
}

function u32(bytes: Uint8Array, at: number): number {
	return (bytes[at]! | (bytes[at + 1]! << 8) | (bytes[at + 2]! << 16) | (bytes[at + 3]! << 24)) >>> 0;
}

/**
 * Read every entry of a ZIP archive. Async because inflation is streamed.
 * Sizes are trusted from the CENTRAL directory (never the local header),
 * which is what makes data-descriptor archives safe to read.
 */
export async function readZipEntries(source: Uint8Array, options: ZipReadOptions = {}): Promise<ZipEntry[]> {
	const maxEntries = options.maxEntries ?? DEFAULT_ZIP_MAX_ENTRIES;
	const maxEntryBytes = options.maxEntryBytes ?? DEFAULT_ZIP_MAX_ENTRY_BYTES;
	const maxTotalBytes = options.maxTotalBytes ?? DEFAULT_ZIP_MAX_TOTAL_BYTES;
	if (source.length < 22) throw new ZipFormatError('not a ZIP archive (file too small)');

	/* the End Of Central Directory record lives in the last 64 KB + 22 bytes */
	let eocd = -1;
	const scanFrom = Math.max(0, source.length - 22 - 65535);
	for (let i = source.length - 22; i >= scanFrom; i--) {
		if (u32(source, i) === EOCD_SIG) {
			eocd = i;
			break;
		}
	}
	if (eocd < 0) throw new ZipFormatError('not a ZIP archive (end record missing)');

	if (u16(source, eocd + 4) !== 0 || u16(source, eocd + 6) !== 0) {
		throw new ZipFormatError('multi-disk archives are not supported');
	}
	const count = u16(source, eocd + 10);
	const centralOffset = u32(source, eocd + 16);
	if (count === 0xffff || centralOffset === 0xffffffff) {
		throw new ZipFormatError('ZIP64 archives are not supported');
	}
	if (count > maxEntries) throw new ZipFormatError(`archive holds ${count} entries — over the ${maxEntries} limit`);

	const entries: ZipEntry[] = [];
	let totalBytes = 0;
	let at = centralOffset;
	for (let n = 0; n < count; n++) {
		if (u32(source, at) !== CENTRAL_SIG) throw new ZipFormatError('corrupt central directory');
		const flags = u16(source, at + 8);
		const method = u16(source, at + 10);
		const recordedCrc = u32(source, at + 16);
		const packedSize = u32(source, at + 20);
		const rawSize = u32(source, at + 24);
		const nameLength = u16(source, at + 28);
		const extraLength = u16(source, at + 30);
		const commentLength = u16(source, at + 32);
		const localOffset = u32(source, at + 42);
		/* office document names are ASCII; UTF-8 bytes survive decode either way */
		const name = decodeUtf8(source.subarray(at + 46, at + 46 + nameLength));

		if ((flags & 0x1) !== 0) throw new ZipFormatError(`entry "${name}" is encrypted — not supported`);
		if (rawSize > maxEntryBytes) {
			throw new ZipFormatError(`entry "${name}" is ${rawSize} bytes — over the ${maxEntryBytes} limit`);
		}
		if (u32(source, localOffset) !== LOCAL_SIG) {
			throw new ZipFormatError(`corrupt local header for "${name}"`);
		}
		const localNameLength = u16(source, localOffset + 26);
		const localExtraLength = u16(source, localOffset + 28);
		const dataStart = localOffset + 30 + localNameLength + localExtraLength;
		const packed = source.subarray(dataStart, dataStart + packedSize);

		let data: Uint8Array;
		if (method === 0) {
			data = packed.slice();
		} else if (method === 8) {
			try {
				data = await inflateRaw(packed, rawSize);
			} catch (error) {
				throw new ZipFormatError(
					`entry "${name}" could not be inflated: ${error instanceof Error ? error.message : 'unknown failure'}`
				);
			}
		} else {
			throw new ZipFormatError(`entry "${name}" uses compression method ${method} — not supported`);
		}
		if (crc32(data) !== recordedCrc) {
			throw new ZipFormatError(`entry "${name}" failed its integrity check (CRC mismatch)`);
		}
		totalBytes += data.length;
		if (totalBytes > maxTotalBytes) {
			throw new ZipFormatError(`archive expands past the ${maxTotalBytes}-byte limit`);
		}
		entries.push({ name, data });
		at += 46 + nameLength + extraLength + commentLength;
	}
	return entries;
}

/** One entry as the tolerant reader found it (docs/RFC-DRAFT-FORMAT.md §7.2). */
export interface ZipTolerantEntry {
	/** The name as the archive spells it, decoded as UTF-8. */
	name: string;
	/** The name's bytes, so a caller can tell whether they were valid UTF-8. */
	nameBytes: Uint8Array;
	/** The entry's contents: uncompressed when it could be read, otherwise
		whatever bytes the archive holds for it (see `error`). */
	data: Uint8Array;
	/** Why the entry could not be read whole — absent when it was. */
	error?: string;
}

export interface ZipTolerantResult {
	entries: ZipTolerantEntry[];
	/** Where the entries came from: the central directory, or — when it is
		missing or damaged, as in a truncated file — the local headers. */
	directory: 'central' | 'local';
}

export interface ZipTolerantReadOptions extends ZipReadOptions {
	/** Largest uncompressed-to-compressed ratio an entry may declare. Default 200. */
	maxRatio?: number;
}

export const DEFAULT_ZIP_MAX_RATIO: number = 200;

/**
 * Read every entry that can be read, and keep the bytes of every entry that
 * cannot — the .draft reader's recovery ladder stands on this. Unlike
 * `readZipEntries`, one damaged entry does not refuse the archive: it comes
 * back with an `error` and its bytes. A declared size is never trusted to
 * allocate: an entry that declares more than the limits allow is not
 * expanded, and says so. Only an archive that is not a ZIP at all, or holds
 * more entries than allowed, is refused.
 */
export async function readZipEntriesTolerant(
	source: Uint8Array,
	options: ZipTolerantReadOptions = {}
): Promise<ZipTolerantResult> {
	const maxEntries = options.maxEntries ?? DEFAULT_ZIP_MAX_ENTRIES;
	const central = centralRecords(source);
	if (central !== null && central.length > maxEntries) {
		throw new ZipFormatError(`archive holds ${central.length} entries — over the ${maxEntries} limit`);
	}
	const records = central ?? localRecords(source, maxEntries);
	if (records === null) throw new ZipFormatError('not a ZIP archive');
	const entries: ZipTolerantEntry[] = [];
	let total = 0;
	for (const record of records) {
		const entry = await readRecord(source, record, options, total);
		if (entry.error === undefined) total += entry.data.length;
		entries.push(entry);
	}
	return { entries, directory: central === null ? 'local' : 'central' };
}

interface ZipRecord {
	nameBytes: Uint8Array;
	flags: number;
	method: number;
	crc: number;
	packedSize: number;
	rawSize: number;
	dataStart: number;
	/** Set when the record itself shows the entry cannot be read. */
	problem?: string;
}

/** The central directory's records, or null when it is missing or damaged. */
function centralRecords(source: Uint8Array): ZipRecord[] | null {
	if (source.length < 22) return null;
	let eocd = -1;
	const scanFrom = Math.max(0, source.length - 22 - 65535);
	for (let i = source.length - 22; i >= scanFrom; i--) {
		if (u32(source, i) === EOCD_SIG) {
			eocd = i;
			break;
		}
	}
	if (eocd < 0) return null;
	if (u16(source, eocd + 4) !== 0 || u16(source, eocd + 6) !== 0) return null;
	const count = u16(source, eocd + 10);
	const centralOffset = u32(source, eocd + 16);
	if (count === 0xffff || centralOffset === 0xffffffff) return null;
	const records: ZipRecord[] = [];
	let at = centralOffset;
	for (let n = 0; n < count; n++) {
		if (at + 46 > source.length || u32(source, at) !== CENTRAL_SIG) return null;
		const nameLength = u16(source, at + 28);
		const extraLength = u16(source, at + 30);
		const commentLength = u16(source, at + 32);
		const localOffset = u32(source, at + 42);
		if (at + 46 + nameLength > source.length) return null;
		const record: ZipRecord = {
			nameBytes: source.slice(at + 46, at + 46 + nameLength),
			flags: u16(source, at + 8),
			method: u16(source, at + 10),
			crc: u32(source, at + 16),
			packedSize: u32(source, at + 20),
			rawSize: u32(source, at + 24),
			dataStart: 0
		};
		if (localOffset + 30 > source.length || u32(source, localOffset) !== LOCAL_SIG) {
			record.problem = 'its local header is damaged';
		} else {
			record.dataStart = localOffset + 30 + u16(source, localOffset + 26) + u16(source, localOffset + 28);
		}
		records.push(record);
		at += 46 + nameLength + extraLength + commentLength;
	}
	return records;
}

/**
 * Records found by walking the local headers from the start — the way to
 * read a file whose end is missing. Stops at the first header that is not
 * whole. Null when the file does not begin with one.
 */
function localRecords(source: Uint8Array, maxEntries: number): ZipRecord[] | null {
	if (source.length < 30 || u32(source, 0) !== LOCAL_SIG) return null;
	const records: ZipRecord[] = [];
	let at = 0;
	while (at + 30 <= source.length && u32(source, at) === LOCAL_SIG) {
		if (records.length === maxEntries) {
			throw new ZipFormatError(`archive holds more than ${maxEntries} entries — over the limit`);
		}
		const flags = u16(source, at + 6);
		const nameLength = u16(source, at + 26);
		const extraLength = u16(source, at + 28);
		const dataStart = at + 30 + nameLength + extraLength;
		if (dataStart > source.length) break;
		const record: ZipRecord = {
			nameBytes: source.slice(at + 30, at + 30 + nameLength),
			flags,
			method: u16(source, at + 8),
			crc: u32(source, at + 14),
			packedSize: u32(source, at + 18),
			rawSize: u32(source, at + 22),
			dataStart
		};
		records.push(record);
		/* A data descriptor leaves the sizes out of the local header, so the
           next header cannot be found: stop at this entry. */
		if ((flags & 0x8) !== 0) {
			record.problem = 'its sizes are only in a data descriptor';
			break;
		}
		at = dataStart + record.packedSize;
	}
	return records;
}

async function readRecord(
	source: Uint8Array,
	record: ZipRecord,
	options: ZipTolerantReadOptions,
	totalSoFar: number
): Promise<ZipTolerantEntry> {
	const maxEntryBytes = options.maxEntryBytes ?? DEFAULT_ZIP_MAX_ENTRY_BYTES;
	const maxTotalBytes = options.maxTotalBytes ?? DEFAULT_ZIP_MAX_TOTAL_BYTES;
	const maxRatio = options.maxRatio ?? DEFAULT_ZIP_MAX_RATIO;
	const name = decodeUtf8(record.nameBytes);
	const base = { name, nameBytes: record.nameBytes };
	const end = Math.min(source.length, record.dataStart + record.packedSize);
	const packed = record.problem === undefined ? source.slice(record.dataStart, end) : new Uint8Array(0);
	const damaged = (error: string): ZipTolerantEntry => ({ ...base, data: packed, error });

	if (record.problem !== undefined) return damaged(record.problem);
	if ((record.flags & 0x1) !== 0) return damaged('it is encrypted');
	if (record.dataStart + record.packedSize > source.length) return damaged('it is cut short');
	if (record.rawSize > maxEntryBytes) return damaged(`it declares ${record.rawSize} bytes, over the ${maxEntryBytes} limit`);
	if (totalSoFar + record.rawSize > maxTotalBytes) return damaged(`the archive would expand past the ${maxTotalBytes}-byte limit`);

	let data: Uint8Array;
	if (record.method === 0) {
		if (record.rawSize !== record.packedSize) return damaged('its sizes disagree');
		data = packed;
	} else if (record.method === 8) {
		if (record.rawSize > Math.max(1, record.packedSize) * maxRatio) {
			return damaged(`it declares a compression ratio over ${maxRatio}:1`);
		}
		try {
			data = await inflateRaw(packed, record.rawSize);
		} catch {
			return damaged('it could not be inflated');
		}
		if (data.length !== record.rawSize) return damaged('it inflated to a different size than it declares');
	} else {
		return damaged(`it uses compression method ${record.method}`);
	}
	if (crc32(data) !== record.crc) return { ...base, data, error: 'it failed its CRC-32 check' };
	return { ...base, data };
}

/** The entry with this exact archive path, or undefined. */
export function findEntry(entries: ZipEntry[], name: string): ZipEntry | undefined {
	return entries.find((entry) => entry.name === name);
}
