/**
 * .docx export: the round trip is the proof — what writeDocx emits,
 * importDocx reads back as the same element stream.
 */
import { describe, expect, it } from 'vitest';
import { importDocx } from './docx.js';
import { writeDocx } from './docxwrite.js';
import { readZipEntries, findEntry } from './zip.js';
import { decodeUtf8 } from './platform.js';
import type { Screenplay } from './types.js';

const SCRIPT: Screenplay = {
	titlePage: [],
	elements: [
		{ type: 'scene', text: 'INT. FISH & CHIP SHOP - DAY' },
		{ type: 'action', text: 'A tiny, "quiet" room — somehow <warm>.' },
		{ type: 'character', text: 'MARA (V.O.)' },
		{ type: 'parenthetical', text: '(whispering)' },
		{ type: 'dialogue', text: "We're closed." },
		{ type: 'transition', text: 'CUT TO:' },
		{ type: 'scene', text: 'EXT. STREET - NIGHT' },
		{ type: 'centered', text: 'THE END' }
	]
};

async function documentXmlOf(bytes: Uint8Array): Promise<string> {
	const entries = await readZipEntries(bytes);
	const entry = findEntry(entries, 'word/document.xml');
	return entry === undefined ? '' : decodeUtf8(entry.data);
}

describe('writeDocx', () => {
	it('round-trips the core element stream through importDocx', async () => {
		const { script, report } = await importDocx(writeDocx(SCRIPT));
		expect(script.elements.map((element) => element.type)).toEqual(
			SCRIPT.elements.map((element) => element.type)
		);
		expect(script.elements.map((element) => element.text)).toEqual(
			SCRIPT.elements.map((element) => element.text)
		);
		expect(report.flagged).toEqual([]);
	});

	it('lays out Courier New 12pt with screenplay margins and indents', async () => {
		const bytes = writeDocx(SCRIPT);
		const entries = await readZipEntries(bytes);
		const styles = decodeUtf8(findEntry(entries, 'word/styles.xml')?.data ?? new Uint8Array());
		const document = await documentXmlOf(bytes);
		expect(styles).toContain('Courier New');
		expect(styles).toContain('w:val="24"');
		expect(document).toContain('w:left="2160"'); /* the 1.5" page margin */
		expect(document).toContain('w:left="3168"'); /* character: 2.2" */
		expect(document).toContain('w:left="2304"'); /* parenthetical: 1.6" */
		expect(document).toContain('w:left="1440"'); /* dialogue: 1.0" */
		expect(document).toContain('<w:jc w:val="right"/>'); /* transition flush right */
		expect(document).toContain('<w:jc w:val="center"/>');
	});

	it('escapes XML entities in element text', async () => {
		const document = await documentXmlOf(writeDocx(SCRIPT));
		expect(document).toContain('FISH &amp; CHIP SHOP');
		expect(document).toContain('&quot;quiet&quot;');
		expect(document).not.toContain('<warm>');
	});

	it('keeps cues and parentheticals with their speech', async () => {
		const document = await documentXmlOf(writeDocx(SCRIPT));
		expect(document).toContain('<w:keepNext/>');
	});

	it('emits the title page followed by a page break', async () => {
		const withTitle: Screenplay = {
			titlePage: [
				{ key: 'Title', values: ['The Empty Cinema'] },
				{ key: 'Credit', values: ['written by'] },
				{ key: 'Author', values: ['A. Writer'] },
				{ key: 'Contact', values: ['a@writer.example'] }
			],
			elements: [{ type: 'scene', text: 'INT. LOBBY - DAY' }]
		};
		const document = await documentXmlOf(writeDocx(withTitle));
		expect(document.indexOf('THE EMPTY CINEMA')).toBeLessThan(document.indexOf('INT. LOBBY - DAY'));
		expect(document).toContain('<w:br w:type="page"/>');
		expect(document).toContain('a@writer.example');
	});

	it('round-trips a structural page break', async () => {
		const script: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'scene', text: 'INT. A - DAY' },
				{ type: 'pagebreak', text: '' },
				{ type: 'scene', text: 'INT. B - NIGHT' }
			]
		};
		const { script: reread } = await importDocx(writeDocx(script));
		expect(reread.elements.map((element) => element.type)).toEqual(['scene', 'pagebreak', 'scene']);
	});

	it('round-trips a multi-line element as ONE element, unflagged', async () => {
		const script: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'character', text: 'MARA' },
				{ type: 'dialogue', text: 'First line.\nSecond line.' }
			]
		};
		const document = await documentXmlOf(writeDocx(script));
		expect(document).toContain('<w:br/>');
		const { script: reread, report } = await importDocx(writeDocx(script));
		expect(reread.elements).toEqual([
			{ type: 'character', text: 'MARA' },
			{ type: 'dialogue', text: 'First line. Second line.' }
		]);
		expect(report.flagged).toEqual([]);
	});

	it('drops a multi-line title once, not between every line', async () => {
		const script: Screenplay = {
			titlePage: [{ key: 'Title', values: ['THE EMPTY', 'CINEMA'] }],
			elements: [{ type: 'scene', text: 'INT. LOBBY - DAY' }]
		};
		const document = await documentXmlOf(writeDocx(script));
		expect(document.match(/w:before="1440"/g)?.length ?? 0).toBe(1);
	});
});
