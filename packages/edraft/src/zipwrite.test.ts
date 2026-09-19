/** ZIP writer: the reader is the judge — every archive must read back exactly. */
import { describe, expect, it } from 'vitest';
import { readZipEntries, findEntry } from './zip.js';
import { writeZipStored } from './zipwrite.js';
import { sha256Hex } from './sha256.js';
import { textBytes } from '../test/helpers/zip.js';

describe('writeZipStored', () => {
	it('writes an archive the reader reads back exactly', async () => {
		const entries = [
			{ name: 'word/document.xml', data: textBytes('<w:document><w:body/></w:document>') },
			{ name: '[Content_Types].xml', data: textBytes('<?xml version="1.0"?><Types/>') },
			{ name: '_rels/.rels', data: textBytes('<Relationships/>') }
		];
		const read = await readZipEntries(writeZipStored(entries));
		expect(read.map((entry) => entry.name)).toEqual(entries.map((entry) => entry.name));
		for (const entry of entries) {
			expect(findEntry(read, entry.name)?.data).toEqual(entry.data);
		}
	});

	it('handles empty entries and unicode content', async () => {
		const data = textBytes('INT. CAFÉ — NÄHTAVYYS — 日本語');
		const read = await readZipEntries(
			writeZipStored([
				{ name: 'empty.xml', data: new Uint8Array(0) },
				{ name: 'unicode.xml', data }
			])
		);
		expect(findEntry(read, 'empty.xml')?.data).toHaveLength(0);
		expect(findEntry(read, 'unicode.xml')?.data).toEqual(data);
	});
});

describe('writeZipStored options', () => {
	const entries = [
		{ name: '[Content_Types].xml', data: textBytes('<?xml version="1.0"?><Types/>') },
		{ name: 'word/document.xml', data: textBytes('<w:document><w:body/></w:document>') },
		{ name: 'unicode/\u00e9t\u00e9.xml', data: textBytes('INT. CAF\u00c9 \u2014 \u65e5\u672c\u8a9e') }
	];

	it('writes, by default, exactly the bytes it always has (the .docx exporter depends on it)', () => {
		/* The pre-change writer's output for these entries, measured. */
		expect(sha256Hex(writeZipStored(entries))).toBe('0970c76248ab8db315f02a19743042d7bdbd358050b8315de2b371999a2f5c58');
	});

	it('stamps the date and time it is given, and the UTF-8 flag on names that are not ASCII', async () => {
		const zip = writeZipStored(entries, { dosDate: 0x0021, dosTime: 0x1234, utf8Names: true });
		const view = new DataView(zip.buffer);
		const headers: Array<[number, number, number]> = [];
		for (let at = 0; view.getUint32(at, true) === 0x04034b50; ) {
			headers.push([view.getUint16(at + 6, true), view.getUint16(at + 10, true), view.getUint16(at + 12, true)]);
			at += 30 + view.getUint16(at + 26, true) + view.getUint32(at + 18, true);
		}
		expect(headers).toEqual([[0, 0x1234, 0x0021], [0, 0x1234, 0x0021], [0x0800, 0x1234, 0x0021]]);
		expect((await readZipEntries(zip)).map((entry) => entry.name)).toEqual(entries.map((entry) => entry.name));
	});
});
