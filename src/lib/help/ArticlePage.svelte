<script lang="ts">
	/**
	 * One article of the eDraft User Guide, in the guide's frame: the guide
	 * bar, the article, "Was this helpful?", See also, the neighbouring
	 * articles in book order, and where you are.
	 *
	 * The feedback buttons are local state only — there is no backend, so
	 * an answer is acknowledged on the page and goes nowhere else.
	 */
	import GuideBar from './GuideBar.svelte';
	import Blocks from './Blocks.svelte';
	import { getArticle, getCategory, type HelpArticle } from './articles';
	import { neighbours, topicPath } from './guide';

	let { article }: { article: HelpArticle } = $props();

	const category = $derived(getCategory(article.category));
	const around = $derived(neighbours(article.slug));
	const related = $derived(
		article.related
			.map((slug) => getArticle(slug))
			.filter((candidate): candidate is HelpArticle => candidate !== undefined)
	);

	let feedback = $state<'yes' | 'no' | null>(null);
</script>

<svelte:head>
	<title>{article.title} — eDraft User Guide</title>
	<meta name="description" content={article.summary} />
</svelte:head>

<GuideBar current={article.slug} />

<main id="main">
	<article class="article">
		<h1>{article.title}</h1>
		<p class="lede">{article.summary}</p>

		<Blocks blocks={article.blocks} />

		<section class="feedback" aria-labelledby="feedback-title">
			<h2 id="feedback-title">Was this helpful?</h2>
			{#if feedback === null}
				<div class="feedback-actions">
					<button onclick={() => (feedback = 'yes')}>Yes</button>
					<button onclick={() => (feedback = 'no')}>No</button>
				</div>
			{:else}
				<p class="feedback-thanks">Thanks for letting us know.</p>
			{/if}
		</section>

		{#if related.length > 0}
			<section class="see-also" aria-labelledby="see-also-title">
				<h2 id="see-also-title">See also</h2>
				<ul>
					{#each related as item (item.slug)}
						<li><a href="/help/{item.slug}">{item.title}</a></li>
					{/each}
				</ul>
			</section>
		{/if}
	</article>

	{#if around.previous || around.next}
		<nav class="pager" aria-label="Previous and next articles">
			{#if around.previous}
				<a class="previous" href="/help/{around.previous.slug}" rel="prev">
					<span class="direction"><span class="glyph" aria-hidden="true">‹</span>Previous</span>
					<span class="pager-title">{around.previous.title}</span>
				</a>
			{:else}
				<span></span>
			{/if}
			{#if around.next}
				<a class="next" href="/help/{around.next.slug}" rel="next">
					<span class="direction">Next<span class="glyph" aria-hidden="true">›</span></span>
					<span class="pager-title">{around.next.title}</span>
				</a>
			{/if}
		</nav>
	{/if}

	<div class="guide-foot">
		<nav class="crumbs" aria-label="Breadcrumb">
			<ol>
				<li><a href="/help">Help Center</a></li>
				{#if category}<li><a href={topicPath(category.id)}>{category.name}</a></li>{/if}
				<li aria-current="page">{article.title}</li>
			</ol>
		</nav>
		<p class="contact-line">Can’t find what you need? Email <a href="mailto:support@edraft.xyz">support@edraft.xyz</a>.</p>
	</div>
</main>

<style>
	.article, .pager, .guide-foot { max-width: 740px; margin: 0 auto; padding-left: 24px; padding-right: 24px; }
	.article { padding-top: 60px; }
	h1 { font-size: 34px; font-weight: 500; letter-spacing: -.015em; line-height: 1.12; color: #1d1d1f; text-wrap: balance; }
	.lede { font-size: 19px; line-height: 28px; letter-spacing: -.022em; color: #6e6e73; margin-top: 12px; text-wrap: pretty; }

	.feedback { margin-top: 52px; padding: 26px; background: #f5f5f7; border-radius: 16px; }
	.feedback h2 { font-size: 16px; font-weight: 600; letter-spacing: -.01em; color: #1d1d1f; }
	.feedback-actions { display: flex; gap: 12px; margin-top: 14px; }
	.feedback-actions button { padding: 8px 22px; border-radius: 999px; border: 1px solid #d2d2d7; background: #fff; font-size: 14px; color: #1d1d1f; transition: border-color .15s, color .15s; }
	.feedback-actions button:hover { border-color: #0071e3; color: #0071e3; }
	.feedback-thanks { font-size: 14px; color: #6e6e73; margin-top: 12px; }

	.see-also { margin-top: 56px; }
	.see-also h2 { font-size: 17px; font-weight: 600; letter-spacing: -.022em; color: #1d1d1f; }
	.see-also ul { list-style: none; margin: 10px 0 0; padding: 0; }
	.see-also li { margin-top: 6px; }
	.see-also a { font-size: 17px; line-height: 26px; letter-spacing: -.022em; color: #0066cc; }
	.see-also a:hover { text-decoration: underline; }

	.pager { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-top: 64px; }
	.pager a { display: flex; flex-direction: column; gap: 4px; padding-top: 18px; border-top: 1px solid #d2d2d7; }
	.pager .next { text-align: right; }
	.direction { font-size: 13px; letter-spacing: -.005em; color: #6e6e73; }
	.previous .glyph { margin-right: 5px; }
	.next .glyph { margin-left: 5px; }
	.pager-title { font-size: 17px; line-height: 24px; letter-spacing: -.022em; color: #0066cc; text-wrap: balance; }
	.pager a:hover .pager-title { text-decoration: underline; }

	.guide-foot { padding-top: 56px; padding-bottom: 88px; }
	.crumbs ol { display: flex; flex-wrap: wrap; list-style: none; margin: 0; padding: 0; font-size: 12px; letter-spacing: -.005em; color: #6e6e73; }
	.crumbs li + li::before { content: '›'; padding: 0 9px; color: #86868b; }
	.crumbs a { color: #424245; }
	.crumbs a:hover { color: #0066cc; text-decoration: underline; }
	.contact-line { margin-top: 14px; font-size: 12px; color: #6e6e73; }
	.contact-line a { color: #0066cc; }
	.contact-line a:hover { text-decoration: underline; }

	@media (max-width: 600px) {
		.article, .pager, .guide-foot { padding-left: 18px; padding-right: 18px; }
		.article { padding-top: 36px; }
		h1 { font-size: 28px; }
		.lede { font-size: 17px; line-height: 25px; }
		.pager { grid-template-columns: 1fr; gap: 0; }
		.pager .next { text-align: left; }
		.guide-foot { padding-bottom: 64px; }
	}
</style>
