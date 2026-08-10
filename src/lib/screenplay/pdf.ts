/**
 * Draft First Screenwriting PDF export.
 *
 * The deliverable a production actually runs on. Pure: Screenplay in →
 * PDF bytes out. No DOM, no fonts to load, no network.
 *
 * Typography follows the spec the paginator already guarantees:
 *
 *   · US Letter (612×792pt), Courier 12pt, 6 lines per inch
 *   · 1.5″ left margin (108pt), 1″ top margin, 55 lines per page
 *   · page 1 unnumbered; later pages numbered "N." flush right, 0.5″ down
 *   · assigned scene numbers print in BOTH margins (production convention)
 *   · (MORE) / NAME (CONT'D) come from the paginator untouched
 *
 * Courier is one of the PDF base-14 fonts, so this dependency-free exporter
 * uses the explicitly declared WinAnsi encoding. Characters outside that
 * bounded repertoire are rejected with a structured diagnostic rather than
 * silently replaced. A future Unicode exporter must embed a font and a
 * ToUnicode map; this module does not claim that support.
 *
 * Known gap (honest): dual dialogue prints sequentially rather than in
 * side-by-side columns. No content is lost or mislabelled; the layout is
 * linear. True two-column dual layout lands with the production layer.
 */

import { isPrinting, type Screenplay, type TitlePageEntry } from '@draftfirst/core';
import {
	paginate,
	PAGE_WIDTH_CHARS,
	wrapText,
	type PageLine,
	type ScriptPage
} from '@draftfirst/core/layout';

/* ---- geometry ------------------------------------------------------------ */

const PAGE_W = 612;
const PAGE_H = 792;
const FONT_SIZE = 12;
const LINE_H = 12;
/** Courier advances 0.6em — 7.2pt at 12pt. Constant, by design. */
const CHAR_W = 7.2;
const MARGIN_LEFT = 108; // 1.5″
const MARGIN_TOP = 72; //   1″
/** Baseline of body line i (0-based), measured from the page bottom. */
const lineY = (i: number) => PAGE_H - MARGIN_TOP - 10 - i * LINE_H;
const lineX = (indentChars: number) => MARGIN_LEFT + indentChars * CHAR_W;
const TEXT_RIGHT_CHARS = PAGE_WIDTH_CHARS;

/* ---- text encoding ------------------------------------------------------- */

export interface PdfCompatibilityIssue {
	code: 'unsupported-character';
	character: string;
	codePoint: number;
	offset: number;
	source:
		| { kind: 'title-key'; entry: number }
		| { kind: 'title-value'; entry: number; value: number }
		| { kind: 'element'; element: number }
		| { kind: 'scene-number'; element: number };
}

export class PdfExportError extends Error {
	readonly code: 'UNSUPPORTED_CHARACTER' | 'TITLE_PAGE_OVERFLOW';
	readonly issue?: PdfCompatibilityIssue;

	constructor(
		code: 'UNSUPPORTED_CHARACTER' | 'TITLE_PAGE_OVERFLOW',
		message: string,
		issue?: PdfCompatibilityIssue
	) {
		super(message);
		this.name = 'PdfExportError';
		this.code = code;
		this.issue = issue;
	}
}

/** Unicode code points represented by the non-Latin-1 positions in CP-1252. */
const WIN_ANSI_SPECIAL = new Map<number, number>([
	[0x20ac, 0x80], [0x201a, 0x82], [0x0192, 0x83], [0x201e, 0x84],
	[0x2026, 0x85], [0x2020, 0x86], [0x2021, 0x87], [0x02c6, 0x88],
	[0x2030, 0x89], [0x0160, 0x8a], [0x2039, 0x8b], [0x0152, 0x8c],
	[0x017d, 0x8e], [0x2018, 0x91], [0x2019, 0x92], [0x201c, 0x93],
	[0x201d, 0x94], [0x2022, 0x95], [0x2013, 0x96], [0x2014, 0x97],
	[0x02dc, 0x98], [0x2122, 0x99], [0x0161, 0x9a], [0x203a, 0x9b],
	[0x0153, 0x9c], [0x017e, 0x9e], [0x0178, 0x9f]
]);

function winAnsiByte(ch: string): number | null {
	const cp = ch.codePointAt(0);
	if (cp === undefined) return null;
	if (cp >= 0x20 && cp <= 0x7e) return cp;
	if (cp >= 0xa0 && cp <= 0xff) return cp;
	return WIN_ANSI_SPECIAL.get(cp) ?? null;
}

function firstUnsupported(text: string): { character: string; codePoint: number; offset: number } | null {
	let offset = 0;
	for (const ch of text) {
		const cp = ch.codePointAt(0) ?? 0;
		/* Whitespace is normalised by wrapping before it reaches a PDF literal. */
		if (!/\s/u.test(ch) && winAnsiByte(ch) === null) return { character: ch, codePoint: cp, offset };
		offset += ch.length;
	}
	return null;
}

/** Preflight the bounded, dependency-free PDF encoding contract. */
export function validatePdfCompatibility(script: Screenplay): PdfCompatibilityIssue[] {
	const issues: PdfCompatibilityIssue[] = [];
	script.titlePage.forEach((entry, entryIndex) => {
		const keyIssue = firstUnsupported(entry.key);
		if (keyIssue) {
			issues.push({
				code: 'unsupported-character',
				...keyIssue,
				source: { kind: 'title-key', entry: entryIndex }
			});
		}
		entry.values.forEach((value, valueIndex) => {
			const valueIssue = firstUnsupported(value);
			if (valueIssue) {
				issues.push({
					code: 'unsupported-character',
					...valueIssue,
					source: { kind: 'title-value', entry: entryIndex, value: valueIndex }
				});
			}
		});
	});
	script.elements.forEach((element, elementIndex) => {
		const issue = firstUnsupported(element.text);
		if (issue) {
			issues.push({
				code: 'unsupported-character',
				...issue,
				source: { kind: 'element', element: elementIndex }
			});
		}
		if (element.sceneNumber) {
			const sceneNumberIssue = firstUnsupported(element.sceneNumber);
			if (sceneNumberIssue) {
				issues.push({
					code: 'unsupported-character',
					...sceneNumberIssue,
					source: { kind: 'scene-number', element: elementIndex }
				});
			}
		}
	});
	return issues;
}

/** Escape a string for a PDF literal, keeping the whole file 7-bit ASCII. */
function pdfStr(s: string): string {
	let out = '';
	for (const ch of s) {
		const byte = winAnsiByte(ch);
		if (byte === null) {
			throw new PdfExportError(
				'UNSUPPORTED_CHARACTER',
				`Character U+${(ch.codePointAt(0) ?? 0).toString(16).toUpperCase().padStart(4, '0')} is not representable in WinAnsi.`
			);
		}
		if (ch === '\\') out += '\\\\';
		else if (ch === '(') out += '\\(';
		else if (ch === ')') out += '\\)';
		else if (byte >= 32 && byte <= 126) out += ch;
		else out += '\\' + byte.toString(8).padStart(3, '0');
	}
	return out;
}

/** Title-case exceptions aside, printing types shout by convention. */
const UPPER_TYPES = new Set(['scene', 'character', 'transition', 'shot']);

function renderText(line: PageLine): string {
	let t = line.text;
	if (line.type === 'character' && t.endsWith(' ^')) t = t.slice(0, -2);
	if (UPPER_TYPES.has(line.type)) t = t.toUpperCase();
	return t;
}

/* ---- page content streams -------------------------------------------------- */

function textOp(x: number, y: number, text: string): string {
	return `BT /F1 ${FONT_SIZE} Tf 1 0 0 1 ${x.toFixed(2)} ${y.toFixed(2)} Tm (${pdfStr(text)}) Tj ET`;
}

function bodyStream(
	page: ScriptPage,
	sceneNumberByElement: Map<number, string>,
	showPageNumber: boolean
): string {
	const ops: string[] = [];
	page.lines.forEach((line, i) => {
		if (line.type === 'blank') return;
		const text = renderText(line);
		if (text !== '') ops.push(textOp(lineX(line.indent), lineY(i), text));

		/* scene numbers print in both margins, aligned with the heading */
		const sn = line.type === 'scene' ? sceneNumberByElement.get(line.element) : undefined;
		if (sn) {
			const y = lineY(i);
			ops.push(textOp(MARGIN_LEFT - CHAR_W * (sn.length + 1), y, sn));
			ops.push(textOp(lineX(TEXT_RIGHT_CHARS + 1), y, sn));
		}
	});
	if (showPageNumber) {
		const label = `${page.number}.`;
		const x = lineX(TEXT_RIGHT_CHARS) - label.length * CHAR_W;
		ops.push(textOp(x, PAGE_H - 42, label));
	}
	/* scene continuation markers live in the margins, outside the 55 lines */
	if (page.continuedTop) {
		ops.push(textOp(MARGIN_LEFT, lineY(-1) + 6, 'CONTINUED:'));
	}
	if (page.continuedBottom) {
		const label = '(CONTINUED)';
		ops.push(textOp(lineX(TEXT_RIGHT_CHARS) - label.length * CHAR_W, lineY(55) - 6, label));
	}
	return ops.join('\n');
}

/* ---- title page ------------------------------------------------------------ */

function tpValues(titlePage: TitlePageEntry[], ...keys: string[]): string[] {
	const want = keys.map((k) => k.toLowerCase());
	return titlePage
		.filter((entry) => want.includes(entry.key.trim().toLowerCase()))
		.flatMap((entry) => entry.values)
		.map((value) => value.trim())
		.filter(Boolean);
}

function centerOp(y: number, text: string): string {
	const x = lineX(Math.max(0, Math.floor((TEXT_RIGHT_CHARS - text.length) / 2)));
	return textOp(x, y, text);
}

function titleStream(titlePage: TitlePageEntry[]): string {
	const ops: string[] = [];
	const title = tpValues(titlePage, 'title').join(' ').toUpperCase();
	const credit = tpValues(titlePage, 'credit')[0] ?? 'written by';
	const authors = tpValues(titlePage, 'author', 'authors', 'written by').filter(
		(v) => v.toLowerCase() !== 'written by'
	);
	const contact = tpValues(titlePage, 'contact', 'address');
	const draft = tpValues(titlePage, 'draft date', 'draft', 'date');
	const rest = titlePage.filter(
		(e) =>
			!['title', 'credit', 'author', 'authors', 'written by', 'contact', 'address', 'draft date', 'draft', 'date'].includes(
				e.key.trim().toLowerCase()
			)
	);

	const footerWidth = 28;
	const contactLines = contact.flatMap((value) => wrapText(value, footerWidth));
	const draftLines = draft.flatMap((value) => wrapText(value, footerWidth));
	if (contactLines.length > 6 || draftLines.length > 6) {
		throw new PdfExportError(
			'TITLE_PAGE_OVERFLOW',
			'Title-page contact or draft metadata exceeds the supported six-line footer.'
		);
	}
	const footerTop = 36 + (Math.max(contactLines.length, draftLines.length, 1) - 1) * LINE_H;

	let line = 24; // title sits a third of the way down
	const centered = (text: string): void => {
		for (const wrapped of wrapTitle(text)) {
			const y = lineY(line++);
			if (y < footerTop + LINE_H * 2) {
				throw new PdfExportError(
					'TITLE_PAGE_OVERFLOW',
					'Title-page content does not fit without overlapping the footer.'
				);
			}
			ops.push(centerOp(y, wrapped));
		}
	};
	if (title) {
		centered(title);
	}
	line += 2;
	centered(credit);
	line += 2;
	for (const a of authors) centered(a);
	for (const e of rest) {
		line++;
		centered(`${e.key}:`);
		for (const v of e.values) centered(v);
	}

	/* contact block bottom-left, draft bottom-right — production convention */
	contactLines.forEach((c, i) => {
		ops.push(textOp(MARGIN_LEFT, 36 + (contactLines.length - 1 - i) * LINE_H, c));
	});
	draftLines.forEach((d, i) => {
		const x = lineX(TEXT_RIGHT_CHARS) - d.length * CHAR_W;
		ops.push(textOp(x, 36 + (draftLines.length - 1 - i) * LINE_H, d));
	});
	return ops.join('\n');
}

function wrapTitle(title: string): string[] {
	return wrapText(title, TEXT_RIGHT_CHARS);
}

/* ---- PDF file assembly ----------------------------------------------------- */

/**
 * Serialise the screenplay to a US Letter PDF. Returns raw bytes (7-bit
 * ASCII) suitable for a Blob or file write.
 */
export function scriptToPdf(script: Screenplay): Uint8Array {
	const issue = validatePdfCompatibility(script)[0];
	if (issue) {
		throw new PdfExportError(
			'UNSUPPORTED_CHARACTER',
			`Character U+${issue.codePoint.toString(16).toUpperCase().padStart(4, '0')} is not representable in the dependency-free WinAnsi PDF exporter.`,
			issue
		);
	}
	const hasTitle = script.titlePage.some((e) => e.values.some((v) => v.trim() !== ''));
	const hasBody = script.elements.some((element) => isPrinting(element.type));
	/* A title-only screenplay is one title page, not a title page plus an
	   accidental blank body page. A wholly empty screenplay remains one page. */
	const pages = hasBody || !hasTitle ? paginate(script) : [];

	const sceneNumbers = new Map<number, string>();
	script.elements.forEach((el, i) => {
		if (el.type === 'scene' && el.sceneNumber) sceneNumbers.set(i, el.sceneNumber);
	});

	interface PageSpec {
		stream: string;
	}
	const specs: PageSpec[] = [];
	if (hasTitle) specs.push({ stream: titleStream(script.titlePage) });
	pages.forEach((p, i) =>
		specs.push({ stream: bodyStream(p, sceneNumbers, /* page 1 of the body shows no number */ i > 0) })
	);

	/* objects: 1 catalog, 2 pages, 3 font, then per page: page obj + content obj */
	const objects: string[] = [];
	const kids: string[] = [];
	specs.forEach((_, i) => {
		const pageObj = 4 + i * 2;
		kids.push(`${pageObj} 0 R`);
	});

	objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
	objects[2] = `<< /Type /Pages /Kids [${kids.join(' ')}] /Count ${specs.length} >>`;
	objects[3] =
		'<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>';

	specs.forEach((spec, i) => {
		const pageObj = 4 + i * 2;
		const contentObj = pageObj + 1;
		objects[pageObj] =
			`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_W} ${PAGE_H}] ` +
			`/Resources << /Font << /F1 3 0 R >> >> /Contents ${contentObj} 0 R >>`;
		objects[contentObj] =
			`<< /Length ${spec.stream.length} >>\nstream\n${spec.stream}\nendstream`;
	});

	let out = '%PDF-1.4\n';
	const offsets: number[] = [];
	for (let n = 1; n < objects.length; n++) {
		offsets[n] = out.length;
		out += `${n} 0 obj\n${objects[n]}\nendobj\n`;
	}
	const xrefAt = out.length;
	out += `xref\n0 ${objects.length}\n0000000000 65535 f \n`;
	for (let n = 1; n < objects.length; n++) {
		out += `${String(offsets[n]).padStart(10, '0')} 00000 n \n`;
	}
	out += `trailer\n<< /Size ${objects.length} /Root 1 0 R >>\nstartxref\n${xrefAt}\n%%EOF\n`;

	const bytes = new Uint8Array(out.length);
	for (let i = 0; i < out.length; i++) bytes[i] = out.charCodeAt(i) & 0xff;
	return bytes;
}
