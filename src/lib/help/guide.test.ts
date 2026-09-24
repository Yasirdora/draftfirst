import { describe, expect, it } from 'vitest';
import { helpArticles, helpCategories } from './articles';
import { anchorFor, bookOrder, chapterFor, keyRuns, neighbours, tableOfContents, topicPath } from './guide';

describe('the eDraft User Guide', () => {
	it('walks every article exactly once, chapter by chapter in category order', () => {
		expect(bookOrder.map((article) => article.slug).sort()).toEqual(helpArticles.map((article) => article.slug).sort());
		const categoryOrder = helpCategories.map((category) => category.id);
		const positions = bookOrder.map((article) => categoryOrder.indexOf(article.category));
		expect(positions).toEqual([...positions].sort((a, b) => a - b));
		expect(tableOfContents.map((chapter) => chapter.category.id)).toEqual(categoryOrder);
	});

	it('gives every topic its own address, which no article can take', () => {
		const slugs = new Set(helpArticles.map((article) => article.slug));
		for (const category of helpCategories) {
			expect(slugs.has(category.id), category.id).toBe(false);
			expect(topicPath(category.id)).toBe(`/help/${category.id}`);
			expect(chapterFor(category.id)?.articles.length, category.id).toBeGreaterThan(0);
		}
		expect(chapterFor('no-such-topic')).toBeUndefined();
	});

	it('gives the first article no previous and the last no next', () => {
		expect(neighbours(bookOrder[0].slug).previous).toBeUndefined();
		expect(neighbours(bookOrder[bookOrder.length - 1].slug).next).toBeUndefined();
	});

	it('links neighbours both ways', () => {
		for (const article of bookOrder.slice(0, -1)) {
			const next = neighbours(article.slug).next;
			expect(next, article.slug).toBeDefined();
			expect(neighbours(next!.slug).previous?.slug).toBe(article.slug);
		}
	});

	it('knows nothing about a slug that is not in the guide', () => {
		expect(neighbours('no-such-article')).toEqual({});
	});

	it('anchors a heading by its words', () => {
		expect(anchorFor('Restore a scene')).toBe('restore-a-scene');
		expect(anchorFor('What eDraft keeps without showing')).toBe('what-edraft-keeps-without-showing');
		expect(anchorFor('Work around an omitted scene')).toBe('work-around-an-omitted-scene');
		expect(anchorFor('Don’t: Tab & Return!')).toBe('dont-tab-return');
	});

	it('never gives two headings in one article the same anchor', () => {
		for (const article of helpArticles) {
			const anchors = article.blocks.flatMap((block) => (block.type === 'h' ? [anchorFor(block.text)] : []));
			expect(new Set(anchors).size, article.slug).toBe(anchors.length);
			for (const anchor of anchors) expect(anchor, article.slug).not.toBe('');
		}
	});

	it('sets glyph-led shortcuts as keys in sentences, and leaves key names as words', () => {
		const keys = (text: string, bareKeys = false) =>
			keyRuns(text, { bareKeys }).filter((run) => run.key).map((run) => run.text);
		expect(keys('Choose Edit > Add Note (⇧⌘K).')).toEqual(['⇧⌘K']);
		expect(keys('Choose eDraft > Settings (⌘,).')).toEqual(['⌘,']);
		expect(keys('Press ⌘→, or choose Edit > Accept Suggestion.')).toEqual(['⌘→']);
		expect(keys('See Move between elements with Tab and Return.')).toEqual([]);
		expect(keys('Press Shift-Tab to go back.')).toEqual([]);
	});

	it('also sets bare Tab, Return and Space as keys in table cells', () => {
		const keys = (text: string) =>
			keyRuns(text, { bareKeys: true }).filter((run) => run.key).map((run) => run.text);
		expect(keys('⌘→, or Space at the end of the line')).toEqual(['⌘→', 'Space']);
		expect(keys('⇧Tab')).toEqual(['⇧Tab']);
		expect(keys('⌃⌘Space')).toEqual(['⌃⌘Space']);
		expect(keys('Scene Heading, Action, Character')).toEqual([]);
	});

	it('keeps every character of the text, in order', () => {
		for (const article of helpArticles) {
			for (const block of article.blocks) {
				const texts = block.type === 'table' ? block.rows.flat() : 'text' in block ? [block.text] : block.items;
				for (const text of texts) {
					expect(keyRuns(text).map((run) => run.text).join('')).toBe(text);
					expect(keyRuns(text, { bareKeys: true }).map((run) => run.text).join('')).toBe(text);
				}
			}
		}
	});
});
