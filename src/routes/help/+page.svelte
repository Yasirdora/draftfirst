<script lang="ts">
	/**
	 * Help Center home, in Apple Support's grammar: the guide bar (whose
	 * field is this page's one search, and whose All topics lists every
	 * topic and article), a title, the topics as bare line icons that open
	 * each topic's page, one panel that opens the user guide, and common
	 * tasks and contact side by side. With JavaScript off the guide bar's
	 * index is the page's navigation; with it on, the search filters live,
	 * and a GET to ?q= from any page lands here with the matches.
	 */
	import { page } from '$app/state';
	import { browser } from '$app/environment';
	import HelpLayout from '$lib/help/HelpLayout.svelte';
	import GuideBar from '$lib/help/GuideBar.svelte';
	import {
		helpCategories,
		popularArticles,
		getArticle,
		searchArticles,
		type HelpArticle
	} from '$lib/help/articles';
	import { bookOrder, guideTitle, topicPath } from '$lib/help/guide';
	import { topicIcons } from '$lib/help/icons';


	const firstArticle = bookOrder[0];

	let query = $state(browser ? (page.url.searchParams.get('q') ?? '') : '');
	let resultsEl: HTMLElement | undefined = $state();

	const searching = $derived(query.trim().length > 0);
	const results = $derived(titleMatchesFirst(searchArticles(query), query));

	/* The search finds every article that mentions the words; the ones that
	   are about them — the words are in the title — are listed first. */
	function titleMatchesFirst(found: HelpArticle[], words: string): HelpArticle[] {
		const terms = words.trim().toLowerCase().split(/\s+/);
		const inTitle = (article: HelpArticle) => terms.every((term) => article.title.toLowerCase().includes(term));
		return [...found.filter(inTitle), ...found.filter((article) => !inTitle(article))];
	}

	function focusFirstResult() {
		const first = resultsEl?.querySelector('a');
		if (first instanceof HTMLAnchorElement) first.focus();
	}
</script>

<svelte:head>
	<title>Help Center — eDraft</title>
	<meta
		name="description"
		content="eDraft Help Center. Search answers about writing, notes, scenes, pages, files, and exporting your screenplay."
	/>
</svelte:head>

<HelpLayout>
	<!-- The guide's bar, as every article opens; its field is this page's search. -->
	<GuideBar live bind:query onArrowDown={focusFirstResult} />

	<main id="main">
		<section class="hero" aria-labelledby="help-title">
			<h1 id="help-title">How can we help?</h1>
			{#if searching}
				<div class="search-results" bind:this={resultsEl} role="region" aria-live="polite" aria-label="Search results">
					{#if results.length > 0}
						<p class="result-count">{results.length} {results.length === 1 ? 'article' : 'articles'}</p>
						<ul>
							{#each results as article (article.slug)}
								<li>
									<a href="/help/{article.slug}">
										<span class="result-title">{article.title}</span>
										<span class="result-summary">{article.summary}</span>
									</a>
								</li>
							{/each}
						</ul>
					{:else}
						<p class="no-results">Nothing matches “{query}”. Try a shorter word, or clear the search to browse every topic.</p>
					{/if}
				</div>
			{/if}
		</section>

		{#if !searching}
			<section class="section-width categories" aria-labelledby="categories-title">
				<h2 id="categories-title">Get the help you need</h2>
				<ul class="category-grid">
					{#each helpCategories as category (category.id)}
						<li>
							<a class="category" href={topicPath(category.id)}>
								<svg class="category-icon" viewBox="0 0 24 24" aria-hidden="true"><path d={topicIcons[category.id]} /></svg>
								<span class="category-name">{category.name}</span>
							</a>
						</li>
					{/each}
				</ul>
			</section>

			{#if firstArticle}
				<section class="section-width" aria-labelledby="guide-title">
					<div class="guide-panel">
						<span class="app-icon" aria-hidden="true"><img src="/edraft-mark.svg" alt="" width="46" height="46" /></span>
						<h2 id="guide-title">{guideTitle}</h2>
						<p>Step-by-step help for writing, notes, scenes, pages, and Final Draft files — one topic at a time.</p>
						<a class="more" href="/help/{firstArticle.slug}">Read the guide</a>
					</div>
				</section>
			{/if}

			<div class="section-width columns">
				<section class="column" aria-labelledby="tasks-title">
					<h2 id="tasks-title">Common tasks</h2>
					<ul class="link-list">
						{#each popularArticles as slug (slug)}
							{@const article = getArticle(slug)}
							{#if article}
								<li><a class="more" href="/help/{article.slug}">{article.title}</a></li>
							{/if}
						{/each}
					</ul>
				</section>
				<section class="column" aria-labelledby="contact-title">
					<h2 id="contact-title">Contact support</h2>
					<p>Email us about eDraft, your files, or your privacy. To report a problem, open an issue on GitHub.</p>
					<ul class="link-list">
						<li><a class="more" href="mailto:support@edraft.xyz">Email support</a></li>
						<li><a class="more" href="https://github.com/Yasirdora/eDraft/issues" target="_blank" rel="noreferrer">Report a problem on GitHub</a></li>
					</ul>
				</section>
			</div>
		{/if}
	</main>
</HelpLayout>

<style>
	.section-width { max-width: 1032px; margin: auto; padding-left: 24px; padding-right: 24px; }
	h2 { text-wrap: balance; }

	/* Title — the guide bar above carries the search */
	.hero { padding: 76px 24px 8px; text-align: center; }
	.hero h1 { font-size: clamp(40px, 5.4vw, 64px); font-weight: 600; letter-spacing: -.02em; line-height: 1.06; color: #1d1d1f; text-wrap: balance; }

	.search-results { max-width: 640px; margin: 28px auto 80px; text-align: left; }
	.result-count { font-size: 13px; color: #6e6e73; padding-bottom: 10px; border-bottom: 1px solid #d2d2d7; }
	.search-results ul { list-style: none; margin: 0; padding: 0; }
	.search-results li { border-bottom: 1px solid #e8e8ed; }
	.search-results a { display: block; padding: 14px 0; }
	.result-title { display: block; font-size: 17px; letter-spacing: -.022em; color: #0066cc; }
	.search-results a:hover .result-title { text-decoration: underline; }
	.result-summary { display: block; font-size: 14px; line-height: 20px; color: #6e6e73; margin-top: 3px; }
	.no-results { font-size: 15px; color: #6e6e73; padding-top: 4px; text-align: center; }

	/* Topics as bare line icons, the way Apple Support shows products */
	.categories { padding-top: 88px; }
	.categories h2 { text-align: center; font-size: clamp(28px, 3.2vw, 40px); font-weight: 600; letter-spacing: -.02em; line-height: 1.1; color: #1d1d1f; }
	.category-grid { list-style: none; margin: 0; padding: 56px 0 0; display: grid; grid-template-columns: repeat(4, 1fr); gap: 48px 24px; }
	.category { display: flex; flex-direction: column; align-items: center; gap: 14px; text-align: center; }
	.category-icon { width: 44px; height: 44px; fill: none; stroke: #1d1d1f; stroke-width: 1.3; stroke-linecap: round; stroke-linejoin: round; transition: stroke .15s; }
	.category-name { font-size: 17px; letter-spacing: -.022em; line-height: 1.3; color: #1d1d1f; transition: color .15s; }
	.category:hover .category-icon { stroke: #0066cc; }
	.category:hover .category-name { color: #0066cc; }

	/* One grey panel — the guide, introduced */
	.guide-panel { margin-top: 112px; background: #f5f5f7; border-radius: 18px; padding: 56px 32px 60px; text-align: center; }
	/* The Mac app's icon as it looks in light mode: the charcoal swirl on a
	   white rounded square (apple/eDraft.icon), with a neutral shadow. */
	.app-icon { display: grid; place-items: center; width: 88px; height: 88px; margin: 0 auto; border-radius: 20px; background: #fff; box-shadow: 0 0 0 .5px rgb(0 0 0 / 8%), 0 1px 2px rgb(0 0 0 / 6%), 0 8px 22px rgb(0 0 0 / 10%); }
	.app-icon img { display: block; }
	.guide-panel h2 { margin-top: 22px; font-size: 32px; font-weight: 600; letter-spacing: -.02em; line-height: 1.12; color: #1d1d1f; }
	.guide-panel p { max-width: 560px; margin: 14px auto 0; font-size: 17px; line-height: 25px; letter-spacing: -.022em; color: #1d1d1f; text-wrap: pretty; }
	.guide-panel .more { display: inline-block; margin-top: 18px; }

	/* Links written the Apple way: blue, with a chevron after */
	.more { font-size: 17px; letter-spacing: -.022em; color: #0066cc; }
	.more::after { content: ' ›'; }
	.more:hover { text-decoration: underline; }

	.columns { display: grid; grid-template-columns: 1fr 1fr; gap: 48px 64px; padding-top: 88px; padding-bottom: 120px; }
	.column { padding: 0 24px; }
	.column h2 { font-size: 24px; font-weight: 600; letter-spacing: -.015em; line-height: 1.2; color: #1d1d1f; }
	.column p { margin-top: 12px; font-size: 17px; line-height: 25px; letter-spacing: -.022em; color: #1d1d1f; text-wrap: pretty; }
	.link-list { list-style: none; margin: 14px 0 0; padding: 0; }
	.link-list li + li { margin-top: 8px; }

	@media (max-width: 900px) {
		.category-grid { grid-template-columns: repeat(2, 1fr); }
		.columns { grid-template-columns: 1fr; }
		.column { padding: 0; }
	}
	@media (max-width: 600px) {
		.section-width { padding-left: 18px; padding-right: 18px; }
		.hero { padding: 48px 18px 4px; }
		.categories { padding-top: 64px; }
		.category-grid { gap: 36px 16px; padding-top: 40px; }
		.category-icon { width: 38px; height: 38px; }
		.category-name { font-size: 15px; }
		.guide-panel { margin-top: 80px; padding: 44px 22px 48px; }
		.guide-panel h2 { font-size: 26px; }
		.columns { padding-top: 64px; padding-bottom: 80px; }
	}
</style>
