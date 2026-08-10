/**
 * PDF core tests. The byte-level contract matters: a broken xref table or a
 * missing (MORE) is a production-floor bug, so we parse the output back.
 */
import { describe, expect, it } from 'vitest';
import { PdfExportError, scriptToPdf, validatePdfCompatibility } from './pdf';
import { paginate } from '@draftfirst/core/layout';
import { parseFountain } from '@draftfirst/core/fountain';
import { extractPdfPayload } from '@draftfirst/core/import';
import type { Screenplay } from '@draftfirst/core';

function el(type: any, text: string, extra: Record<string, unknown> = {}) {
	return { type, text, ...extra };
}

function decode(pdf: Uint8Array): string {
	let s = '';
	for (const b of pdf) s += String.fromCharCode(b);
	return s;
}

/** Extract the literal strings of every Tj op, in order. */
function textOps(src: string): string[] {
	const out: string[] = [];
	const re = /\((?:\\.|[^\\()])*\) Tj/g;
	let m: RegExpExecArray | null;
	while ((m = re.exec(src))) {
		out.push(
			m[0]
				.slice(1, -4)
				.replace(/\\([()\\])/g, '$1')
				.replace(/\\([0-7]{3})/g, (_, o) => String.fromCharCode(parseInt(o, 8)))
		);
	}
	return out;
}

const SCRIPT: Screenplay = {
	titlePage: [
		{ key: 'Title', values: ['The Long Way Home'] },
		{ key: 'Author', values: ['A. Writer'] },
		{ key: 'Contact', values: ['aw@example.com'] },
		{ key: 'Draft date', values: ['August 2026'] }
	],
	elements: [
		el('scene', 'INT. KITCHEN - DAY', { sceneNumber: '1' }),
		el('action', 'A kettle screams.'),
		el('character', 'Molly'),
		el('dialogue', 'I heard it first.'),
		el('transition', 'CUT TO:'),
		el('scene', 'EXT. STREET - NIGHT', { sceneNumber: '2' }),
		el('action', 'Rain again.')
	]
};

describe('scriptToPdf — file structure', () => {
	it('produces a well-formed PDF with resolvable xref offsets', () => {
		const src = decode(scriptToPdf(SCRIPT));
		expect(src.startsWith('%PDF-1.4\n')).toBe(true);
		expect(src.trimEnd().endsWith('%%EOF')).toBe(true);

		// every xref offset must point at its object header
		const xref = src.match(/xref\n0 (\d+)\n/);
		expect(xref).toBeTruthy();
		const count = Number(xref![1]);
		const entries = [
			...src.slice(src.indexOf('xref')).matchAll(/^(\d{10}) 00000 n $/gm)
		];
		expect(entries.length).toBe(count - 1);
		entries.forEach((e, i) => {
			const at = Number(e[1]);
			expect(src.slice(at, at + 16)).toContain(`${i + 1} 0 obj`);
		});
		expect(src).toContain(`/Type /Pages /Kids`);
		expect(src).toContain('/BaseFont /Courier');
	});

	it('is pure 7-bit ASCII', () => {
		const pdf = scriptToPdf(SCRIPT);
		for (const b of pdf) expect(b).toBeLessThan(128);
	});

	it('declares WinAnsi and encodes common screenplay punctuation without substitution', () => {
		const s: Screenplay = {
			titlePage: [],
			elements: [el('action', 'Molly’s pause—then “go.”')]
		};
		const src = decode(scriptToPdf(s));
		expect(src).toContain('/Encoding /WinAnsiEncoding');
		expect(src).toContain('Molly\\222s pause\\227then \\223go.\\224');
		expect(src).not.toContain('?');
	});

	it('reports unsupported Unicode with source provenance instead of replacing it', () => {
		const s: Screenplay = { titlePage: [], elements: [el('dialogue', '你好')] };
		expect(validatePdfCompatibility(s)[0]).toMatchObject({
			code: 'unsupported-character',
			character: '你',
			source: { kind: 'element', element: 0 }
		});
		try {
			scriptToPdf(s);
			expect.fail('Expected the bounded exporter to reject unsupported Unicode.');
		} catch (error) {
			expect(error).toBeInstanceOf(PdfExportError);
			expect(error).toMatchObject({ code: 'UNSUPPORTED_CHARACTER' });
		}
	});

	it('page count = title page + paginated body pages', () => {
		const src = decode(scriptToPdf(SCRIPT));
		const body = paginate(SCRIPT).length;
		expect(src).toContain(`/Count ${1 + body}`);
	});

	it('escapes parentheses and backslashes in text', () => {
		const s: Screenplay = {
			titlePage: [],
			elements: [el('action', 'A (sudden) turn \\ left.')]
		};
		const src = decode(scriptToPdf(s));
		expect(src).toContain('A \\(sudden\\) turn \\\\ left.');
	});
});

describe('scriptToPdf — content', () => {
	it('renders the title page: title, default credit, author, contact, draft', () => {
		const texts = textOps(decode(scriptToPdf(SCRIPT)));
		expect(texts).toContain('THE LONG WAY HOME');
		expect(texts).toContain('written by');
		expect(texts).toContain('A. Writer');
		expect(texts).toContain('aw@example.com');
		expect(texts).toContain('August 2026');
	});

	it('collects repeated title-page keys instead of dropping later values', () => {
		const s: Screenplay = {
			titlePage: [
				{ key: 'Author', values: ['A. Writer'] },
				{ key: 'Author', values: ['B. Writer'] }
			],
			elements: []
		};
		const texts = textOps(decode(scriptToPdf(s)));
		expect(texts).toContain('A. Writer');
		expect(texts).toContain('B. Writer');
	});

	it('does not append a blank body page to a title-only screenplay', () => {
		const s: Screenplay = {
			titlePage: [{ key: 'Title', values: ['Only a Title'] }],
			elements: []
		};
		expect(decode(scriptToPdf(s))).toContain('/Count 1');
	});

	it('uppercases scene/character/transition but not dialogue or action', () => {
		const s: Screenplay = {
			titlePage: [],
			elements: [
				el('scene', 'int. kitchen - day'),
				el('character', 'molly'),
				el('dialogue', 'i speak in lower case.'),
				el('action', 'quiet action.'),
				el('transition', 'cut to:')
			]
		};
		const texts = textOps(decode(scriptToPdf(s)));
		expect(texts).toContain('INT. KITCHEN - DAY');
		expect(texts).toContain('MOLLY');
		expect(texts).toContain('i speak in lower case.');
		expect(texts).toContain('quiet action.');
		expect(texts).toContain('CUT TO:');
	});

	it('prints scene numbers in both margins', () => {
		const src = decode(scriptToPdf(SCRIPT));
		const texts = textOps(src);
		// each assigned number appears exactly twice (left + right margin)
		expect(texts.filter((t) => t === '1').length).toBe(2);
		expect(texts.filter((t) => t === '2').length).toBe(2);
	});

	it('page 1 carries no number; later pages do', () => {
		// force a second page with a pagebreak
		const s: Screenplay = {
			titlePage: [],
			elements: [
				el('action', 'Page one.'),
				el('pagebreak', ''),
				el('action', 'Page two.')
			]
		};
		const texts = textOps(decode(scriptToPdf(s)));
		expect(texts).not.toContain('1.');
		expect(texts).toContain('2.');
	});

	it('long dialogue splits with (MORE) and NAME (CONT\'D)', () => {
		// 140 repetitions wrap to ~90+ dialogue lines at 35 chars — well past one page
		const long = Array.from({ length: 140 }, (_, i) => `Line ${i + 1} of the speech.`).join(' ');
		const s: Screenplay = {
			titlePage: [],
			elements: [el('character', 'Molly'), el('dialogue', long)]
		};
		const texts = textOps(decode(scriptToPdf(s)));
		expect(texts).toContain('(MORE)');
		expect(texts.some((t) => t.includes("MOLLY (CONT'D)"))).toBe(true);
	});

	it('strips the dual-dialogue caret marker from printed cues', () => {
		const s: Screenplay = {
			titlePage: [],
			elements: [
				el('character', 'Molly'),
				el('dialogue', 'We speak—'),
				el('character', 'Joan', { dual: true }),
				el('dialogue', '—at the same time.')
			]
		};
		const texts = textOps(decode(scriptToPdf(s)));
		expect(texts).toContain('JOAN');
		expect(texts.some((t) => t.includes('^'))).toBe(false);
	});

	it('handles an empty screenplay without crashing', () => {
		const pdf = scriptToPdf({ titlePage: [], elements: [] });
		const src = decode(pdf);
		expect(src).toContain('/Count 1');
	});
});

describe('scriptToPdf — round trip and metadata', () => {
	it('stamps /Producer, a UTF-16BE /Title, and the /Keywords payload in a trailer-referenced Info dict', () => {
		const src = decode(scriptToPdf(SCRIPT));
		expect(src).toContain('/Producer (Draft First)');
		/* "The Long Way Home" as UTF-16BE hex with BOM */
		const titleHex = 'FEFF' + [...'The Long Way Home'].map((c) => c.charCodeAt(0).toString(16).padStart(4, '0')).join('');
		expect(src).toContain(`/Title <${titleHex}>`);
		const trailer = src.slice(src.indexOf('trailer'));
		expect(trailer).toMatch(/\/Info \d+ 0 R/);
		const infoNum = Number(trailer.match(/\/Info (\d+) 0 R/)![1]);
		expect(src).toContain(`${infoNum} 0 obj\n<< /Producer (Draft First)`);
	});

	it('carries the complete screenplay home: pdf bytes → extract → parse → identical stream', () => {
		const pdf = scriptToPdf(SCRIPT);
		const fountain = extractPdfPayload(pdf);
		expect(fountain).not.toBeNull();
		const recovered = parseFountain(fountain!);
		expect(recovered.elements.map((e) => [e.type, e.text])).toEqual(
			SCRIPT.elements.map((e) => [e.type, e.text])
		);
		expect(recovered.titlePage.map((e) => [e.key, e.values])).toEqual(
			SCRIPT.titlePage.map((e) => [e.key, e.values])
		);
		/* scene numbers survive the round trip too */
		expect(recovered.elements[0]!.sceneNumber).toBe('1');
		expect(recovered.elements[5]!.sceneNumber).toBe('2');
	});

	it('keeps screenplay punctuation byte-exact through the payload, even when WinAnsi-encoded on the page', () => {
		const s: Screenplay = {
			titlePage: [],
			elements: [el('action', 'Molly’s pause—then “go.”')]
		};
		const fountain = extractPdfPayload(scriptToPdf(s));
		expect(fountain).toContain('Molly’s pause—then “go.”');
	});

	it('omits /Title when the screenplay has no title', () => {
		const src = decode(scriptToPdf({ titlePage: [], elements: [el('action', 'Body only.')] }));
		expect(src).not.toContain('/Title');
		expect(extractPdfPayload(scriptToPdf({ titlePage: [], elements: [el('action', 'Body only.')] }))).not.toBeNull();
	});
});
