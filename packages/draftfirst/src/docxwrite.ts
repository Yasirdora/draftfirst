/**
 * .docx export — the screenplay as a Word document, with zero dependencies:
 * OOXML is XML in a ZIP, and our own writer stamps it.
 *
 * Layout follows the screenplay spec a production office expects: US Letter,
 * 1.5" left margin, Courier New 12pt, single spacing, one blank line after
 * each element (two before a scene heading), cues at 2.2", parentheticals
 * at 1.6", dialogue at 1.0", transitions flush right. Cues and their
 * parentheticals carry keepNext so Word never severs a speech across pages.
 *
 * The trust round trip closes here: what writeDocx emits, importDocx reads
 * back as the same element stream — the test suite proves it. Line breaks
 * inside an element travel as in-paragraph <w:br/> runs and fold back into
 * one element on import (their text rejoins with a single space).
 */

import type { ElementType, Screenplay } from './types.js';
import { isPrinting } from './types.js';
import { encodeXmlEntities } from './fdx.js';
import { encodeUtf8 } from './platform.js';
import { writeZipStored } from './zipwrite.js';

const CONTENT_TYPES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>`;

const ROOT_RELS = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>`;

const DOCUMENT_RELS = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`;

/* every run is Courier New 12pt (sizes are half-points) */
const STYLES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style></w:styles>`;

/* US Letter, screenplay margins: 1.5" left, 1" elsewhere (values are twips) */
const SECT_PR =
	'<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="2160" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>';

const LINE = 240; /* one single-spaced 12pt line, in twips */

interface ParaSpec {
	before: number;
	after: number;
	left?: number;
	align?: 'center' | 'right';
	keepNext?: boolean;
}

/** Where each element sits on the page, measured from the 1.5" text margin. */
function paraSpec(type: ElementType): ParaSpec {
	switch (type) {
		case 'scene':
			return { before: 2 * LINE, after: LINE, keepNext: true };
		case 'character':
			return { before: 0, after: 0, left: 3168, keepNext: true };
		case 'parenthetical':
			return { before: 0, after: 0, left: 2304, keepNext: true };
		case 'dialogue':
			return { before: 0, after: LINE, left: 1440 };
		case 'transition':
			return { before: 0, after: LINE, align: 'right' };
		case 'centered':
			return { before: 0, after: LINE, align: 'center' };
		default:
			/* action, shot, general, lyrics — the left margin */
			return { before: 0, after: LINE };
	}
}

function paragraph(spec: ParaSpec, text: string): string {
	let props = `<w:spacing w:before="${spec.before}" w:after="${spec.after}" w:line="${LINE}" w:lineRule="auto"/>`;
	if (spec.keepNext === true) props = `<w:keepNext/>${props}`;
	if (spec.left !== undefined) props += `<w:ind w:left="${spec.left}"/>`;
	if (spec.align !== undefined) props += `<w:jc w:val="${spec.align}"/>`;
	if (text === '') return `<w:p><w:pPr>${props}</w:pPr></w:p>`;
	/* Line breaks within an element are in-paragraph <w:br/> runs — the exact
	   shape importDocx folds back into ONE element. Paragraph-per-line would
	   re-import as siblings and flag the continuation as a guess. */
	const runs = text
		.split('\n')
		.map((line, i) => `${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${encodeXmlEntities(line)}</w:t>`)
		.join('');
	return `<w:p><w:pPr>${props}</w:pPr><w:r>${runs}</w:r></w:p>`;
}

const PAGE_BREAK = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';

/** The title page: the title block centered a third down, contact at the foot. */
function titlePageParagraphs(script: Screenplay): string {
	const get = (key: string): string[] =>
		script.titlePage.find((entry) => entry.key.toLowerCase() === key)?.values ?? [];
	const title = get('title');
	if (title.length === 0) return '';
	const centered: ParaSpec = { before: 0, after: LINE, align: 'center' };
	let out = '';
	/* the big drop belongs to the block's first line only — a two-line title
	   must not open a canyon between its own lines */
	for (let i = 0; i < title.length; i++) {
		out += paragraph({ ...centered, before: i === 0 ? 6 * LINE : 0 }, title[i].toUpperCase());
	}
	for (const key of ['credit', 'author']) {
		for (const line of get(key)) out += paragraph(centered, line);
	}
	const contact = get('contact');
	if (contact.length > 0) {
		for (let i = 0; i < contact.length; i++) {
			const line = contact[i] ?? '';
			out += paragraph({ before: i === 0 ? 6 * LINE : 0, after: 0 }, line);
		}
	}
	return out + PAGE_BREAK;
}

/**
 * Serialize the screenplay as a .docx. Synchronous — the archive is stored,
 * never compressed — and small: a feature script lands near 100 KB.
 */
export function writeDocx(script: Screenplay): Uint8Array {
	let body = titlePageParagraphs(script);
	for (const element of script.elements) {
		if (element.type === 'pagebreak') {
			body += PAGE_BREAK;
			continue;
		}
		if (!isPrinting(element.type)) continue;
		body += paragraph(paraSpec(element.type), element.text);
	}
	const documentXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body}${SECT_PR}</w:body></w:document>`;

	return writeZipStored([
		{ name: '[Content_Types].xml', data: encodeUtf8(CONTENT_TYPES) },
		{ name: '_rels/.rels', data: encodeUtf8(ROOT_RELS) },
		{ name: 'word/_rels/document.xml.rels', data: encodeUtf8(DOCUMENT_RELS) },
		{ name: 'word/styles.xml', data: encodeUtf8(STYLES) },
		{ name: 'word/document.xml', data: encodeUtf8(documentXml) }
	]);
}
