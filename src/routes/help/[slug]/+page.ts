import { error } from '@sveltejs/kit';
import type { EntryGenerator, PageLoad } from './$types';
import { getArticle, helpArticles } from '$lib/help/articles';
import { chapterFor, tableOfContents } from '$lib/help/guide';

/* Articles and topics share /help/<name>: every article, and every topic
   that has articles, is prerendered. */
export const entries: EntryGenerator = () => {
	return [
		...helpArticles.map((article) => ({ slug: article.slug })),
		...tableOfContents.map((chapter) => ({ slug: chapter.category.id }))
	];
};

export const load: PageLoad = ({ params }) => {
	const article = getArticle(params.slug);
	if (article) return { kind: 'article' as const, article };
	const chapter = chapterFor(params.slug);
	if (chapter) return { kind: 'topic' as const, chapter };
	error(404, 'Not found');
};
