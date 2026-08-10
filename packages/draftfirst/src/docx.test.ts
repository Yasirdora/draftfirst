/** .docx import: styles, indents, tracked changes, breaks, entities, refusals. */
import { describe, expect, it } from 'vitest';
import { DocxImportError, importDocx } from './docx.js';
import { buildZip, textBytes } from '../test/helpers/zip.js';

const STYLES_XML = `<?xml version="1.0"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
	<w:style w:type="paragraph" w:styleId="SceneHeading"><w:name w:val="Scene Heading"/></w:style>
	<w:style w:type="paragraph" w:styleId="Action"><w:name w:val="Action"/></w:style>
	<w:style w:type="paragraph" w:styleId="Character"><w:name w:val="Character"/></w:style>
	<w:style w:type="paragraph" w:styleId="Parenthetical"><w:name w:val="Parenthetical"/></w:style>
	<w:style w:type="paragraph" w:styleId="Dialogue"><w:name w:val="Dialogue"/></w:style>
</w:styles>`;

function documentXml(body: string): string {
	return `<?xml version="1.0"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body}</w:body></w:document>`;
}

async function docxBytes(body: string, options: { styles?: boolean } = {}): Promise<Uint8Array> {
	const entries = [
		{ name: '[Content_Types].xml', data: textBytes('<?xml version="1.0"?><Types/>'), method: 0 as const },
		{ name: 'word/document.xml', data: textBytes(documentXml(body)) }
	];
	if (options.styles !== false) {
		entries.push({ name: 'word/styles.xml', data: textBytes(STYLES_XML), method: 0 as const });
	}
	return buildZip(entries);
}

describe('importDocx', () => {
	it('classifies a styled screenplay at high confidence', async () => {
		const bytes = await docxBytes(`
			<w:p><w:pPr><w:pStyle w:val="SceneHeading"/></w:pPr><w:r><w:t>INT. FISH &amp; CHIP SHOP - DAY</w:t></w:r></w:p>
			<w:p><w:pPr><w:pStyle w:val="Action"/></w:pPr><w:r><w:t>A tiny room.</w:t></w:r></w:p>
			<w:p><w:pPr><w:pStyle w:val="Character"/></w:pPr><w:r><w:t>MARA (CONT&#x2019;D)</w:t></w:r></w:p>
			<w:p><w:pPr><w:pStyle w:val="Parenthetical"/></w:pPr><w:r><w:t>(whispering)</w:t></w:r></w:p>
			<w:p><w:pPr><w:pStyle w:val="Dialogue"/></w:pPr><w:r><w:t>We&apos;re closed.</w:t></w:r></w:p>`);
		const { script, report } = await importDocx(bytes);
		expect(script.elements.map((element) => element.type)).toEqual([
			'scene',
			'action',
			'character',
			'parenthetical',
			'dialogue'
		]);
		expect(script.elements[0]?.text).toBe('INT. FISH & CHIP SHOP - DAY');
		expect(script.elements[2]?.text).toBe('MARA (CONT’D)');
		expect(script.elements[4]?.text).toBe("We're closed.");
		expect(report.format).toBe('docx');
		expect(report.scenes).toBe(1);
		expect(report.characters).toEqual(['MARA']);
		expect(report.flagged).toEqual([]);
	});

	it('falls back to paragraph indents when styles say nothing', async () => {
		const bytes = await docxBytes(
			`
			<w:p><w:pPr><w:ind w:left="3168"/></w:pPr><w:r><w:t>MARA</w:t></w:r></w:p>
			<w:p><w:pPr><w:ind w:left="1440"/></w:pPr><w:r><w:t>We need to talk.</w:t></w:r></w:p>`,
			{ styles: false }
		);
		const { script } = await importDocx(bytes);
		expect(script.elements.map((element) => element.type)).toEqual(['character', 'dialogue']);
	});

	it('flags bare-indent guesses as low confidence', async () => {
		const bytes = await docxBytes(
			`<w:p><w:pPr><w:ind w:left="1440"/></w:pPr><w:r><w:t>Indented prose, no other signal.</w:t></w:r></w:p>`,
			{ styles: false }
		);
		const { report } = await importDocx(bytes);
		expect(report.flagged).toHaveLength(1);
		expect(report.flagged[0]?.type).toBe('dialogue');
	});

	it('reads hand-made tab indents as layout', async () => {
		const bytes = await docxBytes(
			`<w:p><w:r><w:t xml:space="preserve">&#9;&#9;Indented by tabs.</w:t></w:r></w:p>`,
			{ styles: false }
		);
		const { script, report } = await importDocx(bytes);
		expect(script.elements[0]?.text).toBe('Indented by tabs.');
		expect(script.elements[0]?.type).toBe('dialogue');
		expect(report.flagged).toHaveLength(1);
	});

	it('keeps tracked insertions and drops tracked deletions, with a warning', async () => {
		const bytes = await docxBytes(`
			<w:p><w:r><w:t>Keep </w:t></w:r><w:ins><w:r><w:t>this</w:t></w:r></w:ins><w:del><w:r><w:delText>not this</w:delText></w:r></w:del><w:r><w:t> text.</w:t></w:r></w:p>`);
		const { script, report } = await importDocx(bytes);
		expect(script.elements).toHaveLength(1);
		expect(script.elements[0]?.text).toBe('Keep this text.');
		expect(report.warnings.join(' ')).toMatch(/dropped 1 tracked deletion/);
	});

	it('ignores tables and says so', async () => {
		const bytes = await docxBytes(`
			<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell text</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
			<w:p><w:r><w:t>INT. CAFE - DAY</w:t></w:r></w:p>`);
		const { script, report } = await importDocx(bytes);
		expect(script.elements.map((element) => element.type)).toEqual(['scene']);
		expect(report.warnings.join(' ')).toMatch(/ignored 1 table/);
	});

	it('turns a hard page break into a structural pagebreak element', async () => {
		const bytes = await docxBytes(`
			<w:p><w:r><w:t>INT. A - DAY</w:t><w:br w:type="page"/><w:t>INT. B - NIGHT</w:t></w:r></w:p>`);
		const { script } = await importDocx(bytes);
		expect(script.elements.map((element) => element.type)).toEqual(['scene', 'pagebreak', 'scene']);
	});

	it('folds a soft line break back into its paragraph', async () => {
		const bytes = await docxBytes(`
			<w:p><w:pPr><w:pStyle w:val="Action"/></w:pPr><w:r><w:t>First line</w:t><w:br/><w:t>second line.</w:t></w:r></w:p>`);
		const { script } = await importDocx(bytes);
		expect(script.elements).toHaveLength(1);
		expect(script.elements[0]?.text).toBe('First line second line.');
	});

	it('refuses bytes that are not a ZIP archive', async () => {
		await expect(importDocx(textBytes('definitely not a word document at all'))).rejects.toThrow(DocxImportError);
	});

	it('refuses archives without word/document.xml', async () => {
		const bytes = await buildZip([{ name: 'word/styles.xml', data: textBytes(STYLES_XML), method: 0 }]);
		await expect(importDocx(bytes)).rejects.toThrow(/document\.xml/);
	});

	it('refuses files over the size limit before unzipping', async () => {
		await expect(importDocx(new Uint8Array(100), { maxBytes: 10 })).rejects.toThrow(/limit/);
	});
});
