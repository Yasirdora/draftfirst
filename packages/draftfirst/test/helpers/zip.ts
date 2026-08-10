/**
 * Test-only ZIP writer — builds small archives (stored or deflated) so the
 * reader tests run against real bytes, not mocks. Uses the platform's native
 * CompressionStream; no Node APIs, no dependencies.
 */

interface CompressSession {
	writable: {
		getWriter(): {
			write(chunk: Uint8Array): Promise<void>;
			close(): Promise<void>;
		};
	};
	readable: {
		getReader(): {
			read(): Promise<{ done: boolean; value?: Uint8Array }>;
		};
	};
}

declare const CompressionStream: (new (format: 'deflate-raw') => CompressSession) | undefined;
declare const TextEncoder: (new () => { encode(text: string): Uint8Array }) | undefined;

export function textBytes(text: string): Uint8Array {
	if (typeof TextEncoder === 'undefined') throw new Error('this runtime cannot encode text');
	return new TextEncoder().encode(text);
}

async function deflateRaw(data: Uint8Array): Promise<Uint8Array> {
	if (typeof CompressionStream === 'undefined') throw new Error('this runtime cannot deflate data');
	const session = new CompressionStream('deflate-raw');
	const writer = session.writable.getWriter();
	const reader = session.readable.getReader();
	const written = writer.write(data).then(() => writer.close());
	const chunks: Uint8Array[] = [];
	let length = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		if (value) {
			chunks.push(value);
			length += value.length;
		}
	}
	await written;
	const out = new Uint8Array(length);
	let at = 0;
	for (const chunk of chunks) {
		out.set(chunk, at);
		at += chunk.length;
	}
	return out;
}

let crcTable: Uint32Array | null = null;
function crc32(bytes: Uint8Array): number {
	if (crcTable === null) {
		crcTable = new Uint32Array(256);
		for (let n = 0; n < 256; n++) {
			let c = n;
			for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
			crcTable[n] = c >>> 0;
		}
	}
	let crc = 0xffffffff;
	for (let i = 0; i < bytes.length; i++) crc = crcTable[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
	return (crc ^ 0xffffffff) >>> 0;
}

export interface TestZipEntry {
	name: string;
	data: Uint8Array;
	/** 0 = stored, 8 = deflated. Default 8. */
	method?: 0 | 8;
}

/** Assemble a single-disk ZIP: local headers, central directory, EOCD. */
export async function buildZip(entries: TestZipEntry[]): Promise<Uint8Array> {
	const locals: Uint8Array[] = [];
	const records: Uint8Array[] = [];
	let offset = 0;
	for (const entry of entries) {
		const name = textBytes(entry.name);
		const method = entry.method ?? 8;
		const packed = method === 8 ? await deflateRaw(entry.data) : entry.data;
		const crc = crc32(entry.data);

		const local = new Uint8Array(30 + name.length);
		const lv = new DataView(local.buffer);
		lv.setUint32(0, 0x04034b50, true);
		lv.setUint16(4, 20, true);
		lv.setUint16(8, method, true);
		lv.setUint32(14, crc, true);
		lv.setUint32(18, packed.length, true);
		lv.setUint32(22, entry.data.length, true);
		lv.setUint16(26, name.length, true);
		local.set(name, 30);
		locals.push(local, packed);

		const record = new Uint8Array(46 + name.length);
		const rv = new DataView(record.buffer);
		rv.setUint32(0, 0x02014b50, true);
		rv.setUint16(4, 20, true);
		rv.setUint16(6, 20, true);
		rv.setUint16(10, method, true);
		rv.setUint32(16, crc, true);
		rv.setUint32(20, packed.length, true);
		rv.setUint32(24, entry.data.length, true);
		rv.setUint16(28, name.length, true);
		rv.setUint32(42, offset, true);
		record.set(name, 46);
		records.push(record);

		offset += local.length + packed.length;
	}

	let centralSize = 0;
	for (const record of records) centralSize += record.length;
	const eocd = new Uint8Array(22);
	const ev = new DataView(eocd.buffer);
	ev.setUint32(0, 0x06054b50, true);
	ev.setUint16(8, entries.length, true);
	ev.setUint16(10, entries.length, true);
	ev.setUint32(12, centralSize, true);
	ev.setUint32(16, offset, true);

	const total = offset + centralSize + eocd.length;
	const out = new Uint8Array(total);
	let at = 0;
	for (const chunk of [...locals, ...records, eocd]) {
		out.set(chunk, at);
		at += chunk.length;
	}
	return out;
}

/** Offset of the first central-directory record — for byte-surgery tests. */
export function centralDirectoryAt(zip: Uint8Array): number {
	for (let i = 0; i + 4 <= zip.length; i++) {
		if (zip[i] === 0x50 && zip[i + 1] === 0x4b && zip[i + 2] === 0x01 && zip[i + 3] === 0x02) return i;
	}
	return -1;
}

/** Offset of the end-of-central-directory record (last 22 bytes when no comment). */
export function endRecordAt(zip: Uint8Array): number {
	return zip.length - 22;
}
