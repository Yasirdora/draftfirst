/**
 * The eDraft User Guide as a book: its table of contents, its reading
 * order, and each article's neighbours.
 *
 * Everything here is derived from the help data in `articles.ts` — the
 * categories in their order, then each category's articles in theirs — so
 * the guide can never list an article the data does not have, or walk them
 * in an order the home page does not show.
 */
import { articlesInCategory, helpCategories, type HelpArticle, type HelpCategory } from './articles';

export const guideTitle = 'eDraft User Guide for Mac';

export interface GuideChapter {
	category: HelpCategory;
	articles: HelpArticle[];
}

/** One chapter per category, in category order. A category with no articles is left out. */
export const tableOfContents: GuideChapter[] = helpCategories
	.map((category) => ({ category, articles: articlesInCategory(category.id) }))
	.filter((chapter) => chapter.articles.length > 0);

/** A topic's chapter — its category and articles — or undefined for an unknown id. */
export function chapterFor(categoryId: string): GuideChapter | undefined {
	return tableOfContents.find((chapter) => chapter.category.id === categoryId);
}

/**
 * Where a topic's own page lives. Topics and articles share /help/<name>:
 * a category id is never an article slug (guide.test.ts pins it), so the
 * route can tell them apart by name alone.
 */
export function topicPath(categoryId: string): string {
	return `/help/${categoryId}`;
}

/** Every article once, chapter by chapter — the order Previous and Next walk. */
export const bookOrder: HelpArticle[] = tableOfContents.flatMap((chapter) => chapter.articles);

/** The articles before and after this one in book order. */
export function neighbours(slug: string): { previous?: HelpArticle; next?: HelpArticle } {
	const index = bookOrder.findIndex((article) => article.slug === slug);
	if (index < 0) return {};
	return { previous: bookOrder[index - 1], next: bookOrder[index + 1] };
}

/**
 * The fragment a section heading answers to: "Restore a scene" is
 * #restore-a-scene. Stable while the heading's words are, so a support
 * reply can link straight to the part of an article that answers it.
 */
export function anchorFor(heading: string): string {
	return heading
		.toLowerCase()
		.replace(/[’']/g, '')
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '');
}

/** A stretch of article text: plain words, or a keyboard shortcut to set as a key. */
export interface TextRun {
	text: string;
	key: boolean;
}

/* A shortcut as a menu writes it: modifier glyphs, then one key — ⇧⌘K, ⌘→,
   ⌘, (Settings), ⌃⌘Space. Only glyph-led sequences count in running text,
   so "Tab and Return" in a sentence or a cross-reference stays words. */
const modified = '[⌃⌥⇧⌘]+(?:Space|Tab|Return|[A-Z0-9+−→,])';
const inProse = new RegExp(modified, 'g');
/* A table's shortcut column also names bare keys. */
const inTable = new RegExp(`${modified}|\\b(?:Tab|Return|Space)\\b`, 'g');

/**
 * Splits text into plain runs and shortcut runs, so a renderer can set each
 * shortcut as a keycap and leave everything else as text. `bareKeys` also
 * matches Tab, Return and Space on their own — for table cells, where they
 * are keys; never for sentences, where they may be words.
 */
export function keyRuns(text: string, { bareKeys = false }: { bareKeys?: boolean } = {}): TextRun[] {
	const pattern = bareKeys ? inTable : inProse;
	const runs: TextRun[] = [];
	let at = 0;
	for (const match of text.matchAll(pattern)) {
		const index = match.index ?? 0;
		if (index > at) runs.push({ text: text.slice(at, index), key: false });
		runs.push({ text: match[0], key: true });
		at = index + match[0].length;
	}
	if (at < text.length) runs.push({ text: text.slice(at), key: false });
	return runs;
}
