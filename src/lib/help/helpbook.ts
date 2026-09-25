/**
 * Apple Help Book generator — turns the Help Center's article data into a
 * complete offline help book (build/help-book/eDraft.help). One source of
 * truth: this module never invents content; it renders articles.ts.
 *
 * Layout follows Apple's Help Programming Guide: a bundle Info.plist, an
 * lproj with the access page (index.html), one page per topic and per
 * article, a shared stylesheet, and (written by the runner) a hiutil
 * search index so the Help menu's search field works.
 */
import {
	helpArticles,
	helpCategories,
	getArticle,
	getCategory,
	type HelpArticle,
	type HelpBlock,
	type HelpCategory
} from './articles';

export const BOOK_IDENTIFIER = 'xyz.edraft.help';
export const BOOK_TITLE = 'eDraft Help';
export const ONLINE_BASE = 'https://edraft.xyz/help';

export interface BookFile {
	/** Path inside the bundle, e.g. Contents/Resources/en.lproj/index.html */
	path: string;
	contents: string;
}

const LPROJ = 'Contents/Resources/en.lproj';

export function escapeText(text: string): string {
	return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function escapeAttribute(text: string): string {
	return escapeText(text).replace(/"/g, '&quot;');
}

export function renderBlocks(blocks: HelpBlock[]): string {
	const out: string[] = [];
	for (const block of blocks) {
		if (block.type === 'h') {
			out.push(`<h2>${escapeText(block.text)}</h2>`);
		} else if (block.type === 'p') {
			out.push(`<p>${escapeText(block.text)}</p>`);
		} else if (block.type === 'list') {
			out.push(`<ul>${block.items.map((item) => `<li>${escapeText(item)}</li>`).join('')}</ul>`);
		} else if (block.type === 'steps') {
			out.push(`<ol>${block.items.map((item) => `<li>${escapeText(item)}</li>`).join('')}</ol>`);
		} else if (block.type === 'table') {
			const head = block.head.map((cell) => `<th scope="col">${escapeText(cell)}</th>`).join('');
			const rows = block.rows
				.map((row) => `<tr>${row.map((cell) => `<td>${escapeText(cell)}</td>`).join('')}</tr>`)
				.join('');
			out.push(`<table><thead><tr>${head}</tr></thead><tbody>${rows}</tbody></table>`);
		} else if (block.type === 'tip') {
			out.push(`<aside class="tip"><p><strong>Tip:</strong> ${escapeText(block.text)}</p></aside>`);
		} else if (block.type === 'note') {
			out.push(`<aside class="note"><p><strong>Note:</strong> ${escapeText(block.text)}</p></aside>`);
		}
	}
	return out.join('\n');
}

function page(title: string, description: string, depth: number, body: string): string {
	const css = `${'../'.repeat(depth)}shrd/help.css`;
	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${escapeText(title)}</title>
<meta name="AppleTitle" content="${escapeAttribute(BOOK_TITLE)}">
<meta name="description" content="${escapeAttribute(description)}">
<link rel="stylesheet" href="${css}">
</head>
<body>
${body}
</body>
</html>
`;
}

function onlineLink(href: string, label: string): string {
	return `<p class="online"><a href="${href}">${escapeText(label)}</a></p>`;
}

function renderAccessPage(categories: HelpCategory[]): string {
	const topics = categories
		.map(
			(category) => `<li>
<a href="topic/${category.id}.html"><strong>${escapeText(category.name)}</strong><br>
<span class="summary">${escapeText(category.description)}</span></a>
</li>`
		)
		.join('\n');
	const body = `<header>
<h1>${escapeText(BOOK_TITLE)}</h1>
<p class="tagline">Answers, guides, and shortcuts for eDraft.</p>
</header>
<ul class="topics">
${topics}
</ul>
${onlineLink(ONLINE_BASE, 'View eDraft Help online ›')}`;
	return page(BOOK_TITLE, 'Answers, guides, and shortcuts for eDraft.', 0, body);
}

function renderTopicPage(category: HelpCategory, articles: HelpArticle[]): string {
	const items = articles
		.map(
			(article) => `<li>
<a href="../article/${article.slug}.html"><strong>${escapeText(article.title)}</strong><br>
<span class="summary">${escapeText(article.summary)}</span></a>
</li>`
		)
		.join('\n');
	const body = `<nav class="crumbs"><a href="../index.html">‹ ${escapeText(BOOK_TITLE)}</a></nav>
<header>
<h1>${escapeText(category.name)}</h1>
<p class="tagline">${escapeText(category.description)}</p>
</header>
<ul class="topics">
${items}
</ul>
${onlineLink(`${ONLINE_BASE}/${category.id}`, 'View this topic online ›')}`;
	return page(`${category.name} — ${BOOK_TITLE}`, category.description, 1, body);
}

function renderArticlePage(article: HelpArticle, category: HelpCategory | undefined): string {
	const crumbs = category
		? `<a href="../index.html">‹ ${escapeText(BOOK_TITLE)}</a> <span class="sep">/</span> <a href="../topic/${category.id}.html">${escapeText(category.name)}</a>`
		: `<a href="../index.html">‹ ${escapeText(BOOK_TITLE)}</a>`;
	const related = article.related
		.map((slug) => getArticle(slug))
		.filter((item): item is HelpArticle => item !== undefined);
	const seeAlso =
		related.length > 0
			? `<section class="see-also">
<h2>See also</h2>
<ul>${related.map((item) => `<li><a href="${item.slug}.html">${escapeText(item.title)}</a></li>`).join('')}</ul>
</section>`
			: '';
	const body = `<nav class="crumbs">${crumbs}</nav>
<header>
<h1>${escapeText(article.title)}</h1>
<p class="tagline">${escapeText(article.summary)}</p>
</header>
${renderBlocks(article.blocks)}
${seeAlso}
${onlineLink(`${ONLINE_BASE}/${article.slug}`, 'View this article online ›')}`;
	return page(`${article.title} — ${BOOK_TITLE}`, article.summary, 1, body);
}

function renderInfoPlist(): string {
	return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleIdentifier</key>
	<string>${BOOK_IDENTIFIER}</string>
	<key>CFBundleName</key>
	<string>${BOOK_TITLE}</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>HPDBookTitle</key>
	<string>${BOOK_TITLE}</string>
	<key>HPDBookAccessPath</key>
	<string>index.html</string>
	<key>HPDBookIndexPath</key>
	<string>search.helpindex</string>
</dict>
</plist>
`;
}

const HELP_CSS = `body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 17px; line-height: 1.6; color: #1d1d1f; max-width: 680px; margin: 0 auto; padding: 32px 28px 64px; -webkit-font-smoothing: antialiased; }
h1 { font-size: 28px; font-weight: 600; letter-spacing: -.02em; line-height: 1.15; margin: 0; }
h2 { font-size: 20px; font-weight: 600; letter-spacing: -.01em; margin: 32px 0 0; }
p { margin: 14px 0 0; }
a { color: #0066cc; text-decoration: none; }
a:hover { text-decoration: underline; }
header { margin-bottom: 20px; }
.tagline { color: #6e6e73; margin-top: 10px; }
.crumbs { font-size: 13px; margin-bottom: 24px; }
.crumbs .sep { color: #86868b; margin: 0 8px; }
ul, ol { padding-left: 24px; margin: 14px 0 0; }
li { margin-top: 8px; }
ul.topics { list-style: none; padding: 0; margin: 20px 0 0; border-top: 1px solid #d2d2d7; }
ul.topics li { margin: 0; border-bottom: 1px solid #e8e8ed; }
ul.topics a { display: block; padding: 12px 2px; color: #1d1d1f; }
ul.topics a:hover strong { color: #0066cc; }
ul.topics a:hover { text-decoration: none; }
.summary { font-size: 14px; color: #6e6e73; }
table { border-collapse: collapse; width: 100%; margin-top: 18px; font-size: 15px; }
th, td { text-align: left; padding: 9px 14px; border-bottom: 1px solid #e8e8ed; vertical-align: top; }
th { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: .05em; color: #6e6e73; background: #f5f5f7; }
aside { margin-top: 20px; padding: 14px 18px; border-radius: 10px; }
aside p { margin: 0; font-size: 15px; }
aside.tip { background: #f0f7ff; }
aside.note { background: #f5f5f7; }
.see-also ul { list-style: none; padding: 0; }
.online { margin-top: 36px; padding-top: 18px; border-top: 1px solid #e8e8ed; font-size: 14px; }
`;

/** Every file in the bundle, keyed by path. The search index is added by the runner. */
export function buildBookFiles(): BookFile[] {
	const files: BookFile[] = [
		{ path: 'Contents/Info.plist', contents: renderInfoPlist() },
		{ path: `${LPROJ}/shrd/help.css`, contents: HELP_CSS },
		{ path: `${LPROJ}/index.html`, contents: renderAccessPage(helpCategories) }
	];
	for (const category of helpCategories) {
		const articles = helpArticles.filter((article) => article.category === category.id);
		files.push({ path: `${LPROJ}/topic/${category.id}.html`, contents: renderTopicPage(category, articles) });
	}
	for (const article of helpArticles) {
		files.push({
			path: `${LPROJ}/article/${article.slug}.html`,
			contents: renderArticlePage(article, getCategory(article.category))
		});
	}
	return files;
}
