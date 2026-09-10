/** Zero-dependency ZIP reader: real archives, refusal cases, integrity. */
import { describe, expect, it } from 'vitest';
import { findEntry, readZipEntries, ZipFormatError } from './zip.js';
import { buildZip, centralDirectoryAt, endRecordAt, textBytes } from '../test/helpers/zip.js';

describe('readZipEntries', () => {
	it('reads deflated and stored entries from one archive', async () => {
		const zip = await buildZip([
			{ name: 'word/document.xml', data: textBytes('<w:document><w:body/></w:document>') },
			{ name: 'docProps/core.xml', data: textBytes('<core/>'), method: 0 }
		]);
		const entries = await readZipEntries(zip);
		expect(entries).toHaveLength(2);
		expect(findEntry(entries, 'word/document.xml')?.data).toEqual(textBytes('<w:document><w:body/></w:document>'));
		expect(findEntry(entries, 'docProps/core.xml')?.data).toEqual(textBytes('<core/>'));
	});

	it('refuses a file under the minimum archive size', async () => {
		await expect(readZipEntries(new Uint8Array(10))).rejects.toThrow(ZipFormatError);
	});

	it('refuses bytes with no end record', async () => {
		const junk = textBytes('this is not a zip archive, it just has some length');
		await expect(readZipEntries(junk)).rejects.toThrow(/end record missing/);
	});

	it('refuses multi-disk archives', async () => {
		const zip = await buildZip([{ name: 'a.txt', data: textBytes('a'), method: 0 }]);
		zip[endRecordAt(zip) + 4] = 1;
		await expect(readZipEntries(zip)).rejects.toThrow(/multi-disk/);
	});

	it('refuses ZIP64 markers', async () => {
		const zip = await buildZip([{ name: 'a.txt', data: textBytes('a'), method: 0 }]);
		zip[endRecordAt(zip) + 10] = 0xff;
		zip[endRecordAt(zip) + 11] = 0xff;
		await expect(readZipEntries(zip)).rejects.toThrow(/ZIP64/);
	});

	it('refuses encrypted entries', async () => {
		const zip = await buildZip([{ name: 'secret.txt', data: textBytes('s'), method: 0 }]);
		zip[centralDirectoryAt(zip) + 8] = 0x1;
		await expect(readZipEntries(zip)).rejects.toThrow(/encrypted/);
	});

	it('refuses compression methods it does not understand', async () => {
		const zip = await buildZip([{ name: 'a.txt', data: textBytes('a'), method: 0 }]);
		zip[centralDirectoryAt(zip) + 10] = 12;
		await expect(readZipEntries(zip)).rejects.toThrow(/method 12/);
	});

	it('refuses a broken local header', async () => {
		const zip = await buildZip([{ name: 'a.txt', data: textBytes('a'), method: 0 }]);
		zip[0] = 0x00;
		await expect(readZipEntries(zip)).rejects.toThrow(/corrupt local header/);
	});

	it('refuses an entry that fails its CRC integrity check', async () => {
		const data = textBytes('integrity matters');
		const zip = await buildZip([{ name: 'a.txt', data, method: 0 }]);
		zip[30 + 'a.txt'.length] = data[0] === 0x69 ? 0x6a : 0x69;
		await expect(readZipEntries(zip)).rejects.toThrow(/CRC mismatch/);
	});

	it('refuses archives over the entry-count limit', async () => {
		const zip = await buildZip([
			{ name: 'a.txt', data: textBytes('a'), method: 0 },
			{ name: 'b.txt', data: textBytes('b'), method: 0 }
		]);
		await expect(readZipEntries(zip, { maxEntries: 1 })).rejects.toThrow(/entries/);
	});

	it('refuses entries over the single-entry size limit', async () => {
		const zip = await buildZip([{ name: 'big.txt', data: textBytes('more than two bytes'), method: 0 }]);
		await expect(readZipEntries(zip, { maxEntryBytes: 2 })).rejects.toThrow(/limit/);
	});

	it('refuses archives over the total size limit', async () => {
		const zip = await buildZip([{ name: 'a.txt', data: textBytes('some content'), method: 0 }]);
		await expect(readZipEntries(zip, { maxTotalBytes: 2 })).rejects.toThrow(/expands past/);
	});

	it('stops inflating the moment an entry outgrows its declared size', async () => {
		/* A bomb in miniature: four megabytes of zeros deflate to kilobytes,
		   and the central directory lies that they inflate to one. The reader
		   must die at the declared size — the message below only exists on the
		   early-abort path; the old accumulate-everything code threw a
		   different, post-hoc one after the memory was already spent. */
		const data = new Uint8Array(4 * 1024 * 1024);
		const zip = await buildZip([{ name: 'bomb.xml', data }]);
		const view = new DataView(zip.buffer);
		view.setUint32(centralDirectoryAt(zip) + 24, 1024, true);
		await expect(readZipEntries(zip)).rejects.toThrow(/inflated past that/);
	});
});
