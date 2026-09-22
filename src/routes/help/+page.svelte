<script lang="ts">
	/**
	 * Help Center home: search, category grid, popular articles, contact.
	 * The full article index is always in the DOM, so the page works as
	 * plain list navigation with JavaScript disabled; the search field
	 * filters it live when JavaScript runs, and the GET form degrades
	 * to a plain page reload.
	 */
	import { page } from '$app/state';
	import { browser } from '$app/environment';
	import HelpLayout from '$lib/help/HelpLayout.svelte';
	import {
		helpCategories,
		articlesInCategory,
		popularArticles,
		getArticle,
		searchArticles
	} from '$lib/help/articles';

	const icons: Record<string, string> = {
		'getting-started': 'M13 3L5 13h5l-1 8 8-10h-5l1-8z',
		writing: 'M4 20l1-4L16 5l3 3L8 19l-4 1zM14 7l3 3',
		notes: 'M4 5h16v10H9l-5 4V5z',
		scenes: 'M3 7h18M3 7v10a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V7M3 7l2-4h14l2 4M9 3v4M15 3v4',
		pages: 'M7 3h8l4 4v14H7V3zM15 3v4h4M10 12h6M10 16h6',
		files: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z',
		export: 'M12 3v10M8 7l4-4 4 4M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6',
		support: 'M4 7h16v10H4V7zM8 11h.01M12 11h.01M16 11h.01M7 20h10'
	};

	let query = $state(browser ? (page.url.searchParams.get('q') ?? '') : '');
	let resultsEl: HTMLElement | undefined = $state();

	const searching = $derived(query.trim().length > 0);
	const results = $derived(searchArticles(query));

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
	<main id="main">
		<section class="hero" aria-labelledby="help-title">
			<p class="label">eDraft Help Center</p>
			<h1 id="help-title">How can we help?</h1>
			<form class="search" role="search" action="/help" onsubmit={(event) => event.preventDefault()}>
				<svg class="search-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.3-4.3" /></svg>
				<input
					bind:value={query}
					type="search"
					name="q"
					placeholder="Search the Help Center"
					aria-label="Search the Help Center"
					onkeydown={(event) => {
						if (event.key === 'ArrowDown' && searching) {
							event.preventDefault();
							focusFirstResult();
						}
					}}
				/>
			</form>
			{#if searching}
				<div class="search-results" bind:this={resultsEl} role="region" aria-live="polite" aria-label="Search results">
					{#if results.length > 0}
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
						<p class="no-results">Nothing matches “{query}”. Try a shorter word, or browse the topics below.</p>
					{/if}
				</div>
			{/if}
		</section>

		{#if !searching}
			<section class="section-width" aria-labelledby="categories-title">
				<h2 id="categories-title" class="visually-hidden">Browse by topic</h2>
				<div class="category-grid">
					{#each helpCategories as category}
						<a class="category-card" href="#topic-{category.id}">
							<svg class="category-icon" viewBox="0 0 24 24" aria-hidden="true"><path d={icons[category.id]} /></svg>
							<span class="category-name">{category.name}</span>
							<span class="category-description">{category.description}</span>
						</a>
					{/each}
				</div>
			</section>

			<section class="popular" aria-labelledby="popular-title">
				<div class="section-width popular-layout">
					<div>
						<p class="label">Popular</p>
						<h2 id="popular-title">The answers people look for most.</h2>
					</div>
					<ul class="popular-list">
						{#each popularArticles as slug}
							{@const article = getArticle(slug)}
							{#if article}
								<li>
									<a href="/help/{article.slug}">
										<span class="result-title">{article.title}</span>
										<span class="result-summary">{article.summary}</span>
									</a>
								</li>
							{/if}
						{/each}
					</ul>
				</div>
			</section>

			<section class="section-width topics" aria-label="All articles">
				{#each helpCategories as category}
					<div class="topic" id="topic-{category.id}">
						<h2>{category.name}</h2>
						<ul>
							{#each articlesInCategory(category.id) as article}
								<li>
									<a href="/help/{article.slug}">
										<span class="result-title">{article.title}</span>
										<span class="result-summary">{article.summary}</span>
									</a>
								</li>
							{/each}
						</ul>
					</div>
				{/each}
			</section>
		{/if}

		<section class="contact" aria-labelledby="contact-title">
			<div class="section-width contact-inner">
				<h2 id="contact-title">Still stuck?</h2>
				<p>Email us, or open an issue on GitHub. Both reach a person.</p>
				<div class="contact-actions">
					<a class="button" href="mailto:[SUPPORT EMAIL]">Email support</a>
					<a class="text-link" href="https://github.com/Yasirdora/edraft/issues" target="_blank" rel="noreferrer">GitHub issues <span aria-hidden="true">›</span></a>
				</div>
			</div>
		</section>
	</main>
</HelpLayout>

<style>
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	.section-width { max-width: 1080px; margin: auto; padding-left: 24px; padding-right: 24px; }
	.visually-hidden { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
	.hero { padding: 96px 24px 56px; text-align: center; }
	.hero h1 { font-size: clamp(40px, 5.6vw, 72px); font-weight: 650; letter-spacing: -.045em; line-height: 1.06; margin-top: 20px; }
	.search { position: relative; max-width: 640px; margin: 34px auto 0; }
	.search-icon { position: absolute; left: 18px; top: 50%; translate: 0 -50%; width: 20px; height: 20px; fill: none; stroke: #86868b; stroke-width: 1.8; stroke-linecap: round; }
	.search input { width: 100%; height: 56px; padding: 0 20px 0 50px; border: 1px solid #d2d2d7; border-radius: 18px; background: #fff; font: inherit; font-size: 17px; color: #1d1d1f; box-shadow: 0 4px 18px #1826370d; }
	.search input::placeholder { color: #86868b; }
	.search input:focus { outline: none; border-color: #0071e3; box-shadow: 0 0 0 4px #0071e326; }
	.search-results { max-width: 640px; margin: 14px auto 0; text-align: left; background: #fff; border: 1px solid #e3e3e8; border-radius: 16px; box-shadow: 0 10px 30px #18263714; overflow: hidden; }
	.search-results ul, .popular-list, .topic ul { list-style: none; margin: 0; padding: 0; }
	.search-results li + li, .popular-list li + li, .topic li + li { border-top: 1px solid #ececf0; }
	.search-results a, .popular-list a, .topic a { display: block; padding: 14px 20px; transition: background .15s; }
	.search-results a:hover, .popular-list a:hover, .topic a:hover { background: #f5f9ff; }
	.result-title { display: block; font-size: 15px; font-weight: 600; color: #1d1d1f; letter-spacing: -.01em; }
	.result-summary { display: block; font-size: 13px; color: #6e6e73; margin-top: 3px; line-height: 1.45; }
	.no-results { padding: 20px; font-size: 14px; color: #6e6e73; }
	.category-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; padding-top: 40px; padding-bottom: 96px; }
	.category-card { display: flex; flex-direction: column; gap: 8px; padding: 22px; background: #fff; border: 1px solid #e6e6eb; border-radius: 16px; transition: border-color .15s, box-shadow .15s; }
	.category-card:hover { border-color: #bcd4ec; box-shadow: 0 6px 20px #1826370f; }
	.category-icon { width: 26px; height: 26px; fill: none; stroke: #1477c9; stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }
	.category-name { font-size: 16px; font-weight: 600; letter-spacing: -.01em; color: #1d1d1f; }
	.category-description { font-size: 13px; line-height: 1.5; color: #6e6e73; }
	.popular { background: #f5f5f7; padding: 96px 0; }
	.popular-layout { display: grid; grid-template-columns: 1fr 1.4fr; gap: 56px; align-items: start; }
	.popular h2 { font-size: clamp(28px, 3vw, 40px); font-weight: 650; letter-spacing: -.035em; line-height: 1.12; margin-top: 18px; }
	.popular-list { background: #fff; border: 1px solid #e6e6eb; border-radius: 16px; overflow: hidden; }
	.topics { display: grid; grid-template-columns: 1fr 1fr; gap: 20px 48px; padding-top: 96px; padding-bottom: 104px; }
	.topic h2 { font-size: 20px; font-weight: 600; letter-spacing: -.02em; padding-bottom: 12px; border-bottom: 1px solid #e3e3e8; scroll-margin-top: 90px; }
	.topic ul { padding-top: 8px; }
	.topic a { border-radius: 10px; padding: 12px 14px; }
	.contact { background: #000; color: #f5f5f7; padding: 104px 24px; text-align: center; }
	.contact h2 { font-size: clamp(30px, 3.6vw, 48px); font-weight: 650; letter-spacing: -.04em; margin-top: 0; }
	.contact p { font-size: 17px; color: #a1a1a6; margin-top: 14px; }
	.contact-actions { display: flex; align-items: center; justify-content: center; gap: 26px; margin-top: 30px; }
	.button { display: inline-flex; align-items: center; justify-content: center; border-radius: 28px; background: #0071e3; color: white; padding: 13px 26px; font-size: 15px; line-height: 1.25; transition: background .18s; }
	.button:hover { background: #0062c4; }
	.text-link { display: inline-flex; align-items: center; gap: 8px; color: #2997ff; font-size: 15px; }
	.text-link:hover { text-decoration: underline; }
	.text-link span { font-size: 22px; line-height: 1; }
	@media (max-width: 900px) {
		.category-grid { grid-template-columns: repeat(2, 1fr); }
		.popular-layout { grid-template-columns: 1fr; gap: 32px; }
		.topics { grid-template-columns: 1fr; }
	}
	@media (max-width: 600px) {
		.hero { padding: 64px 18px 40px; }
		.search input { height: 50px; font-size: 16px; }
		.category-grid { grid-template-columns: 1fr; padding-top: 28px; padding-bottom: 64px; }
		.popular { padding: 64px 0; }
		.topics { padding-top: 64px; padding-bottom: 72px; }
		.contact { padding: 72px 18px; }
		.contact-actions { flex-direction: column; gap: 18px; }
	}
</style>
