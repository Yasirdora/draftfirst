import { describe, expect, it } from 'vitest';
import { highlightSource } from './source-highlight';

const ZWSP = String.fromCharCode(0x200b);

describe('highlightSource — block structure', () => {
	it('dims the heading marker and colors the text', () => {
		expect(highlightSource('# Title')).toBe(
			'<span class="tk-delim">#</span><span class="tk-heading"> Title</span>'
		);
	});

	it('leaves a hash without space as plain text', () => {
		expect(highlightSource('#nope')).toBe('#nope');
	});

	it('dims list markers', () => {
		expect(highlightSource('- item')).toBe('<span class="tk-delim">-</span> item');
		expect(highlightSource('1. item')).toBe('<span class="tk-delim">1.</span> item');
	});

	it('dims task boxes after the marker', () => {
		expect(highlightSource('- [x] done')).toBe(
			'<span class="tk-delim">-</span> <span class="tk-delim">[x]</span> done'
		);
	});

	it('dims quote markers and scans the quoted text', () => {
		expect(highlightSource('> a **b**')).toBe(
			'<span class="tk-delim">&gt; </span>a <span class="tk-delim">**</span>b<span class="tk-delim">**</span>'
		);
	});

	it('treats rules and setext underlines as delimiters', () => {
		expect(highlightSource('---')).toBe('<span class="tk-delim">---</span>');
		expect(highlightSource('===')).toBe('<span class="tk-delim">===</span>');
	});

	it('styles reference and footnote definitions', () => {
		expect(highlightSource('[1]: https://x.test')).toBe(
			'<span class="tk-link">[1]:</span> <span class="tk-url">https://x.test</span>'
		);
		expect(highlightSource('[^a]: the note')).toBe(
			'<span class="tk-fn">[^a]:</span> <span class="tk-url">the note</span>'
		);
	});

	it('dims table pipes', () => {
		expect(highlightSource('| a | b |')).toBe(
			'<span class="tk-delim">|</span> a <span class="tk-delim">|</span> b <span class="tk-delim">|</span>'
		);
	});
});

describe('highlightSource — fences', () => {
	it('tracks fence state and never parses content', () => {
		const html = highlightSource('```\n# not a heading <x>\n```\n\n# Real');
		expect(html).toBe(
			'<span class="tk-fence">```</span>\n' +
				'<span class="tk-code-block"># not a heading &lt;x&gt;</span>\n' +
				'<span class="tk-fence">```</span>\n\n' +
				'<span class="tk-delim">#</span><span class="tk-heading"> Real</span>'
		);
	});

	it('supports tilde fences', () => {
		expect(highlightSource('~~~\nx\n~~~')).toContain('<span class="tk-fence">~~~</span>');
	});

	it('does not close a backtick fence with tildes', () => {
		expect(highlightSource('```\n~~~\n```')).toContain('<span class="tk-code-block">~~~</span>');
	});
});

describe('highlightSource — inline tokens', () => {
	it('tints code spans including the backticks', () => {
		expect(highlightSource('a `x` b')).toBe('a <span class="tk-code">`x`</span> b');
	});

	it('dims emphasis delimiters but keeps the text plain', () => {
		expect(highlightSource('**b**')).toBe(
			'<span class="tk-delim">**</span>b<span class="tk-delim">**</span>'
		);
		expect(highlightSource('*i*')).toBe(
			'<span class="tk-delim">*</span>i<span class="tk-delim">*</span>'
		);
		expect(highlightSource('~~s~~')).toBe(
			'<span class="tk-delim">~~</span>s<span class="tk-delim">~~</span>'
		);
	});

	it('colors link text and dims the url', () => {
		expect(highlightSource('[t](https://x.test)')).toBe(
			'<span class="tk-delim">[</span><span class="tk-link">t</span>' +
				'<span class="tk-delim">](</span><span class="tk-url">https://x.test</span><span class="tk-delim">)</span>'
		);
	});

	it('marks images with a leading bang', () => {
		expect(highlightSource('![alt](asset:1)')).toContain('<span class="tk-delim">![</span>');
	});

	it('colors footnote references', () => {
		expect(highlightSource('note[^a]')).toBe('note<span class="tk-fn">[^a]</span>');
	});

	it('does not italicize snake_case', () => {
		expect(highlightSource('a_b_c')).toBe('a_b_c');
	});

	it('shields code span content from further parsing', () => {
		expect(highlightSource('`**not bold**`')).toBe('<span class="tk-code">`**not bold**`</span>');
	});
});

describe('highlightSource — safety', () => {
	it('escapes HTML in plain text', () => {
		expect(highlightSource('<script>alert(1)</script>')).toBe(
			'&lt;script&gt;alert(1)&lt;/script&gt;'
		);
	});

	it('appends the sentinel for a trailing newline', () => {
		expect(highlightSource('a\n').endsWith(ZWSP)).toBe(true);
	});

	it('returns only the sentinel for empty source', () => {
		expect(highlightSource('')).toBe(ZWSP);
	});

	it('keeps plain lines byte-identical', () => {
		expect(highlightSource('plain text, no tokens 123')).toBe('plain text, no tokens 123');
	});
});
