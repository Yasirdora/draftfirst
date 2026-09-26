import { describe, expect, it } from 'vitest';
import {
	articlesInCategory,
	getArticle,
	helpArticles,
	helpCategories,
	popularArticles,
	searchArticles,
	type HelpArticle
} from './articles';

/** Every string a reader can see in an article. */
function visibleText(article: HelpArticle): string[] {
	const parts = [article.title, article.summary];
	for (const block of article.blocks) {
		if (block.type === 'table') parts.push(...block.head, ...block.rows.flat());
		else if ('text' in block) parts.push(block.text);
		else parts.push(...block.items);
	}
	return parts;
}

describe('help articles', () => {
	it('gives every article a unique kebab-case slug', () => {
		const slugs = helpArticles.map((article) => article.slug);
		expect(new Set(slugs).size).toBe(slugs.length);
		for (const slug of slugs) expect(slug).toMatch(/^[a-z0-9]+(-[a-z0-9]+)*$/);
	});

	it('keeps the category ids the help home page keys its icons by', () => {
		expect(helpCategories.map((category) => category.id)).toEqual([
			'getting-started', 'writing', 'notes', 'scenes', 'pages', 'files', 'export', 'support'
		]);
	});

	it('files every article under a known category, and leaves no category empty', () => {
		const ids = new Set(helpCategories.map((category) => category.id));
		for (const article of helpArticles) expect(ids).toContain(article.category);
		for (const category of helpCategories) expect(articlesInCategory(category.id).length).toBeGreaterThan(0);
	});

	it('points related and popular links at real articles', () => {
		for (const article of helpArticles) {
			for (const slug of article.related) {
				expect(getArticle(slug), `${article.slug} → ${slug}`).toBeDefined();
				expect(slug).not.toBe(article.slug);
			}
		}
		for (const slug of popularArticles) expect(getArticle(slug), slug).toBeDefined();
	});

	it('stays plain data — it round-trips through JSON unchanged', () => {
		const data = { helpCategories, popularArticles, helpArticles };
		expect(JSON.parse(JSON.stringify(data))).toStrictEqual(data);
	});

	it('keeps the article the page-lock notice links to', () => {
		expect(getArticle('final-draft-page-locks')?.category).toBe('files');
	});

	it('writes menu paths with ">" and ships no placeholders', () => {
		for (const article of helpArticles) {
			for (const text of visibleText(article)) {
				// ⌘→ is a shortcut; any other arrow is a menu path written the old way.
				expect(text, article.slug).not.toMatch(/(^|[^⌘])→/);
				expect(text, article.slug).not.toMatch(/\[[A-Z][A-Z ]{2,}\]/);
			}
		}
	});

	it('finds articles by the words they contain, and nothing for an empty query', () => {
		expect(searchArticles('locked pages').map((article) => article.slug)).toContain('final-draft-page-locks');
		expect(searchArticles('   ')).toEqual([]);
	});
});

/* Interim (IL-0117). No save keeps a highlight in any type of file: the save
   re-parses Fountain text, and Fountain cannot spell a highlight. The help
   said .fdx files keep them, which sent writers into the loss. When the save
   takes the editor's live script (IL-0109/IL-0110), change the help and this
   test together. */
describe('highlights, while no save keeps them (interim, IL-0117)', () => {
	it('says highlights aren’t kept in any type of file yet', () => {
		const article = getArticle('add-emphasis');
		expect(article).toBeDefined();
		expect(visibleText(article!).join('\n')).toContain('Highlights aren’t kept in any type of file yet.');
	});

	it('claims no file keeps highlights', () => {
		for (const article of helpArticles) {
			for (const text of visibleText(article)) {
				expect(text, article.slug).not.toMatch(/highlights are kept|kept only in final draft|removes eDraft highlights/i);
			}
		}
	});
});
