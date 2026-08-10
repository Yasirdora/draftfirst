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

/** The entry with this exact archive path, or undefined. */
export function findEntry(entries: ZipEntry[], name: string): ZipEntry | undefined {
	return entries.find((entry) => entry.name === name);
}
