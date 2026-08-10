import { describe, expect, it } from 'vitest';
import { countWords, escapeHtml, outlineOf, renderMarkdown, safeUrl } from './render';

describe('escapeHtml', () => {
	it('escapes HTML special characters', () => {
		expect(escapeHtml(`<script>"x"&'y'</script>`)).toBe(
			'&lt;script&gt;&quot;x&quot;&amp;&#39;y&#39;&lt;/script&gt;'
		);
	});
});

describe('safeUrl', () => {
	it('allows https and relative paths', () => {
		expect(safeUrl('https://example.com')).toBe('https://example.com');
		expect(safeUrl('/docs/a.md')).toBe('/docs/a.md');
		expect(safeUrl('#anchor')).toBe('#anchor');
	});

	it('blocks dangerous schemes', () => {
		expect(safeUrl('javascript:alert(1)')).toBe('');
		expect(safeUrl('data:text/html,hi')).toBe('');
		expect(safeUrl('vbscript:msgbox')).toBe('');
	});

	it('optionally allows image data URLs', () => {
		const png =
			'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
		expect(safeUrl(png)).toBe('');
		expect(safeUrl(png, { allowImageData: true })).toBe(png);
	});

	it('allows stored-asset references for images only', () => {
		expect(safeUrl('asset:9f1c-42ab', { allowImageData: true })).toBe('asset:9f1c-42ab');
		expect(safeUrl('asset:9f1c-42ab')).toBe('');
	});
});

describe('footnotes pack', () => {
	const on = (src: string) => renderMarkdown(src, { footnotes: true });

	it('renders references as numbered superscripts and collects the section', () => {
		const html = on('Text with a note[^a] and another[^b].\n\n[^a]: First note\n[^b]: Second note\n');
		expect(html).toContain('data-fnref="a"');
		expect(html).toContain('<section class="footnotes" data-footnotes>');
		expect(html).toContain('data-fn="a"');
		expect(html).toContain('First note');
		expect(html.indexOf('First note')).toBeLessThan(html.indexOf('Second note'));
		// definition lines leave the body
		expect(html).not.toContain('<p>[^a]:');
	});

	it('numbers by first reference, not by definition order', () => {
		const html = on('B first[^b], then A[^a].\n\n[^a]: Note A\n[^b]: Note B\n');
		const bSup = html.indexOf('data-fnref="b"');
		const aSup = html.indexOf('data-fnref="a"');
		expect(html.slice(bSup, bSup + 200)).toContain('>1</a>');
		expect(html.slice(aSup, aSup + 200)).toContain('>2</a>');
	});

	it('reuses the number for a repeated reference', () => {
		const html = on('Twice[^a] and again[^a].\n\n[^a]: Note\n');
		const sups = html.match(/data-fnref="a"/g) || [];
		expect(sups).toHaveLength(2);
		expect(html.match(/<li /g) || []).toHaveLength(1);
	});

	it('leaves unreferenced definitions out of the section', () => {
		const html = on('Used[^u].\n\n[^u]: yes\n[^unused]: no\n');
		expect(html).toContain('yes');
		expect(html).not.toContain('>no<');
	});

	it('renders unknown references literally', () => {
		const html = on('Text[^missing].\n');
		expect(html).toContain('[^missing]');
		expect(html).not.toContain('<section');
	});

	it('joins indented continuation lines into the definition', () => {
		const html = on('Note[^a].\n\n[^a]: first\n    second\n');
		expect(html).toContain('first second');
	});

	it('keeps everything literal when the pack is off', () => {
		const html = renderMarkdown('Text[^a].\n\n[^a]: A note\n');
		expect(html).toContain('[^a]');
		expect(html).not.toContain('fnref');
		expect(html).not.toContain('<section');
	});

	it('marks back-links so serialise can drop them', () => {
		const html = on('Note[^a].\n\n[^a]: text\n');
		expect(html).toContain('class="fnback" data-fnback="a"');
	});
});

describe('renderMarkdown', () => {
	it('renders headings and paragraphs safely', () => {
		const html = renderMarkdown('# Hello\n\nWorld **bold**');
		expect(html).toContain('<h1');
		expect(html).toContain('Hello');
		expect(html).toContain('<strong>');
		expect(html).not.toContain('<script');
	});

	it('escapes raw HTML instead of passing it through', () => {
		const html = renderMarkdown('<img src=x onerror=alert(1)>');
		expect(html).toContain('&lt;img');
		expect(html).not.toContain('<img src=x');
	});

	it('renders images, keeping stored-asset references resolvable', () => {
		const html = renderMarkdown('![diagram](asset:9f1c-42ab)');
		expect(html).toContain('data-asset="9f1c-42ab"');
		expect(html).toContain('alt="diagram"');
	});

	it('renders GFM tables and task lists', () => {
		const table = renderMarkdown('| A | B |\n| --- | --- |\n| 1 | 2 |');
		expect(table).toContain('<table');
		expect(table).toContain('<th');

		const tasks = renderMarkdown('- [x] done\n- [ ] todo');
		expect(tasks).toContain('type="checkbox"');
		expect(tasks).toContain('checked');
	});

	it('renders fenced code blocks', () => {
		const html = renderMarkdown('```js\nconst x = 1;\n```');
		expect(html).toContain('<pre');
		expect(html).toContain('const x = 1;');
	});

	it('opens links in a new tab with no opener', () => {
		const link = renderMarkdown('[Example](https://example.com)');
		expect(link).toContain('target="_blank"');
		expect(link).toContain('rel="noopener noreferrer"');

		const auto = renderMarkdown('<https://example.com>');
		expect(auto).toContain('target="_blank"');

		// mailto stays same-tab: a new tab would flash before the mail client
		const mail = renderMarkdown('<a@b.com>');
		expect(mail).toContain('mailto:a@b.com');
		expect(mail).not.toContain('target="_blank"');

		// dangerous schemes stay inert, target or not
		const evil = renderMarkdown('[x](javascript:alert(1))');
		expect(evil).not.toContain('href');
	});
});

describe('outlineOf', () => {
	it('extracts ATX headings with line numbers', () => {
		const outline = outlineOf('# One\n\n## Two\n\ntext');
		expect(outline).toEqual([
			{ level: 1, text: 'One', line: 0 },
			{ level: 2, text: 'Two', line: 2 }
		]);
	});
});

describe('countWords', () => {
	it('counts words the way a writer expects', () => {
		expect(countWords('Hello world')).toBe(2);
		expect(countWords('well-known idea')).toBe(2);
		expect(countWords('```\ncode here\n```\nplus text')).toBe(2);
	});
});
