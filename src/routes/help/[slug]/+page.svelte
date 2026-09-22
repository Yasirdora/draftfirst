<script lang="ts">
	/**
	 * One help article: title, body blocks, "Was this helpful?", related
	 * articles, and a way back. The feedback buttons are local state only —
	 * there is no backend, and the page says so honestly.
	 */
	import HelpLayout from '$lib/help/HelpLayout.svelte';
	import Blocks from '$lib/help/Blocks.svelte';
	import { getArticle, getCategory, type HelpArticle } from '$lib/help/articles';

	let { data } = $props();
	const article = $derived(data.article);
	const category = $derived(getCategory(article.category));

	let feedback = $state<'yes' | 'no' | null>(null);

	const related = $derived(
		article.related
			.map((slug) => getArticle(slug))
			.filter((candidate): candidate is HelpArticle => candidate !== undefined)
	);
</script>

<svelte:head>
	<title>{article.title} — eDraft Help Center</title>
	<meta name="description" content={article.summary} />
</svelte:head>

<HelpLayout>
	<main id="main">
		<article class="article">
			<nav class="crumbs" aria-label="Breadcrumb">
				<a href="/help">‹ Help Center</a>
				{#if category}<span aria-hidden="true">/</span><a href="/help#topic-{category.id}">{category.name}</a>{/if}
			</nav>
			<header class="article-head">
				{#if category}<p class="label">{category.name}</p>{/if}
				<h1>{article.title}</h1>
				<p class="summary">{article.summary}</p>
			</header>

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
				<section class="related" aria-labelledby="related-title">
					<h2 id="related-title">Related articles</h2>
					<ul>
						{#each related as item (item.slug)}
							<li>
								<a href="/help/{item.slug}">
									<span class="result-title">{item.title}</span>
									<span class="result-summary">{item.summary}</span>
								</a>
							</li>
						{/each}
					</ul>
				</section>
			{/if}

			<p class="contact-strip">
				Still stuck? <a href="mailto:[SUPPORT EMAIL]">Email support</a> or
				<a href="https://github.com/Yasirdora/edraft/issues" target="_blank" rel="noreferrer">open an issue on GitHub</a>.
			</p>
		</article>
	</main>
</HelpLayout>

<style>
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #1477c9; }
	.article { max-width: 740px; margin: auto; padding: 64px 24px 96px; }
	.crumbs { display: flex; gap: 10px; font-size: 13px; color: #6e6e73; }
	.crumbs a { color: #0066cc; }
	.crumbs a:hover { text-decoration: underline; }
	.article-head { margin-top: 30px; padding-bottom: 28px; border-bottom: 1px solid #e3e3e8; }
	h1 { font-size: clamp(32px, 4.4vw, 52px); font-weight: 650; letter-spacing: -.04em; line-height: 1.1; margin-top: 12px; }
	.summary { font-size: 18px; line-height: 1.55; color: #6e6e73; margin-top: 14px; }
	.feedback { margin-top: 52px; padding: 26px; background: #f5f5f7; border-radius: 16px; }
	.feedback h2 { font-size: 16px; font-weight: 600; letter-spacing: -.01em; }
	.feedback-actions { display: flex; gap: 12px; margin-top: 14px; }
	.feedback-actions button { padding: 8px 22px; border-radius: 20px; border: 1px solid #d2d2d7; background: #fff; font-size: 14px; color: #1d1d1f; transition: border-color .15s, background .15s; }
	.feedback-actions button:hover { border-color: #0071e3; background: #f0f7ff; }
	.feedback-thanks { font-size: 14px; color: #6e6e73; margin-top: 12px; }
	.related { margin-top: 56px; }
	.related h2 { font-size: 20px; font-weight: 600; letter-spacing: -.02em; }
	.related ul { list-style: none; margin: 16px 0 0; padding: 0; border: 1px solid #e6e6eb; border-radius: 14px; overflow: hidden; }
	.related li + li { border-top: 1px solid #ececf0; }
	.related a { display: block; padding: 13px 18px; transition: background .15s; }
	.related a:hover { background: #f5f9ff; }
	.result-title { display: block; font-size: 15px; font-weight: 600; letter-spacing: -.01em; color: #1d1d1f; }
	.result-summary { display: block; font-size: 13px; color: #6e6e73; margin-top: 3px; line-height: 1.45; }
	.contact-strip { margin-top: 44px; font-size: 14px; color: #6e6e73; }
	.contact-strip a { color: #0066cc; }
	.contact-strip a:hover { text-decoration: underline; }
	@media (max-width: 600px) {
		.article { padding: 40px 18px 64px; }
	}
</style>
