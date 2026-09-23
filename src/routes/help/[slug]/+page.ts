import { error } from '@sveltejs/kit';
import type { EntryGenerator, PageLoad } from './$types';
import { getArticle, helpArticles } from '$lib/help/articles';

export const entries: EntryGenerator = () => {
	return helpArticles.map((article) => ({ slug: article.slug }));
};

export const load: PageLoad = ({ params }) => {
	const article = getArticle(params.slug);
	if (!article) error(404, 'Not found');
	return { article };
}
