/**
 * CRC-32 (IEEE) — the ZIP format's own integrity record. Shared by the
 * reader (verify) and the writer (stamp); one table, built lazily.
 */

let crcTable: Uint32Array | null = null;

/** The CRC-32 of these bytes, as an unsigned 32-bit integer. */
export function crc32(bytes: Uint8Array): number {
	if (crcTable === null) {
		crcTable = new Uint32Array(256);
		for (let n = 0; n < 256; n++) {
			let c = n;
			for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
			crcTable[n] = c >>> 0;
		}
	}
	let crc = 0xffffffff;
	for (let i = 0; i < bytes.length; i++) crc = crcTable[(crc ^ bytes[i]!) & 0xff]! ^ (crc >>> 8);
	return (crc ^ 0xffffffff) >>> 0;
}
