import { error } from '@sveltejs/kit';
import { getArticle, helpArticles } from '$lib/help/articles';

export function entries() {
	return helpArticles.map((article) => ({ slug: article.slug }));
}

export function load({ params }) {
	const article = getArticle(params.slug);
	if (!article) error(404, 'Not found');
	return { article };
}
