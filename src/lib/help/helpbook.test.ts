/**
 * The help book generator renders articles.ts faithfully: a page per
 * article and per topic, a valid bundle Info.plist, escaped text, and no
 * internal link that points nowhere.
 */
import macOSInfoPlist from '../../../apple/macOS/Info.plist?raw';
import { describe, expect, it } from 'vitest';
import { helpArticles, helpCategories } from './articles';
import { buildBookFiles, renderBlocks, BOOK_IDENTIFIER, BOOK_TITLE } from './helpbook';

const files = buildBookFiles();
const byPath = new Map(files.map((file) => [file.path, file.contents]));
const LPROJ = 'Contents/Resources/en.lproj';

/** Resolve an href against the page that contains it, inside the bundle. */
function resolveHref(pagePath: string, href: string): string {
	const clean = href.split('#')[0];
	if (clean === '') return pagePath;
	const base = pagePath.split('/').slice(0, -1);
	for (const part of clean.split('/')) {
		if (part === '.') continue;
		if (part === '..') base.pop();
		else base.push(part);
	}
	return base.join('/');
}

function internalHrefs(html: string): string[] {
	return [...html.matchAll(/href="([^"]+)"/g)]
		.map((match) => match[1])
		.filter((href) => !href.startsWith('http://') && !href.startsWith('https://') && !href.startsWith('mailto:'));
}

describe('macOS app registration', () => {
	it('uses the generated book identifier and folder', () => {
		expect(macOSInfoPlist).toContain('<key>CFBundleHelpBookFolder</key>\n\t<string>eDraft.help</string>');
		expect(macOSInfoPlist).toContain(`<key>CFBundleHelpBookName</key>\n\t<string>${BOOK_IDENTIFIER}</string>`);
	});
});

describe('buildBookFiles', () => {
	it('emits a page for every article and every topic, plus the bundle parts', () => {
		expect(byPath.has('Contents/Info.plist')).toBe(true);
		expect(byPath.has(`${LPROJ}/index.html`)).toBe(true);
		expect(byPath.has(`${LPROJ}/shrd/help.css`)).toBe(true);
		for (const category of helpCategories) {
			expect(byPath.has(`${LPROJ}/topic/${category.id}.html`), `topic page ${category.id}`).toBe(true);
		}
		for (const article of helpArticles) {
			expect(byPath.has(`${LPROJ}/article/${article.slug}.html`), `article page ${article.slug}`).toBe(true);
		}
		expect(files.length).toBe(3 + helpCategories.length + helpArticles.length);
	});

	it('links every topic from the access page', () => {
		const index = byPath.get(`${LPROJ}/index.html`)!;
		for (const category of helpCategories) {
			expect(index).toContain(`href="topic/${category.id}.html"`);
		}
	});

	it('resolves every related slug to a real page', () => {
		for (const article of helpArticles) {
			for (const slug of article.related) {
				expect(byPath.has(`${LPROJ}/article/${slug}.html`), `${article.slug} relates to missing ${slug}`).toBe(true);
			}
		}
	});

	it('every internal href points at a file the book contains', () => {
		for (const file of files) {
			if (!file.path.endsWith('.html')) continue;
			for (const href of internalHrefs(file.contents)) {
				const resolved = resolveHref(file.path, href);
				expect(byPath.has(resolved), `${file.path} links to missing ${resolved}`).toBe(true);
			}
		}
	});

	it('the bundle Info.plist carries identifier, title, access path and index path', () => {
		const plist = byPath.get('Contents/Info.plist')!;
		expect(plist).toContain(`<string>${BOOK_IDENTIFIER}</string>`);
		expect(plist).toContain(`<string>${BOOK_TITLE}</string>`);
		expect(plist).toContain('<key>HPDBookAccessPath</key>');
		expect(plist).toContain('<string>index.html</string>');
		expect(plist).toContain('<key>HPDBookIndexPath</key>');
		expect(plist).toContain('<string>search.helpindex</string>');
	});

	it('every page carries its title, charset and the shared stylesheet', () => {
		for (const file of files) {
			if (!file.path.endsWith('.html')) continue;
			expect(file.contents, file.path).toContain('<meta charset="utf-8">');
			expect(file.contents, file.path).toContain('shrd/help.css');
			expect(file.contents, file.path).toMatch(/<title>.+<\/title>/);
		}
	});
});

describe('renderBlocks escaping', () => {
	it('escapes &, < and > in every text position', () => {
		const html = renderBlocks([
			{ type: 'p', text: 'Fish & Chips <script> "quoted"' },
			{ type: 'h', text: 'A & B' },
			{ type: 'list', items: ['x < y'] },
			{ type: 'steps', items: ['1 > 0'] },
			{ type: 'tip', text: 'Tom & Jerry' },
			{ type: 'note', text: 'a < b' },
			{ type: 'table', head: ['A & B'], rows: [['<cell>']] }
		]);
		expect(html).toContain('Fish &amp; Chips &lt;script&gt; "quoted"');
		expect(html).toContain('<h2>A &amp; B</h2>');
		expect(html).toContain('<li>x &lt; y</li>');
		expect(html).toContain('<li>1 &gt; 0</li>');
		expect(html).toContain('Tom &amp; Jerry');
		expect(html).toContain('a &lt; b');
		expect(html).toContain('<th scope="col">A &amp; B</th>');
		expect(html).toContain('<td>&lt;cell&gt;</td>');
		expect(html).not.toContain('<script>');
	});

	it('renders no markup for an unknown-safe empty block list', () => {
		expect(renderBlocks([])).toBe('');
	});
});
