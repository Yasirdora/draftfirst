/** ZIP writer: the reader is the judge — every archive must read back exactly. */
import { describe, expect, it } from 'vitest';
import { readZipEntries, findEntry } from './zip.js';
import { writeZipStored } from './zipwrite.js';
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
