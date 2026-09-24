<script lang="ts">
	/**
	 * The frame every help page sits in: the guide's name, its search, and
	 * All topics — the guide's full index. Apple's user-guide chrome.
	 *
	 * The search is a plain GET form to the Help Center home, which reads
	 * `?q=` and lists the matches; All topics is a <details> disclosure
	 * holding every topic and article as a plain link. Both work with
	 * JavaScript off.
	 *
	 * On a phone, All topics sits at the right of the guide's name and opens
	 * as a short list: the topics as rows, each opening its own page, with
	 * the current article's topic showing its articles. Only CSS decides
	 * what shows, so nothing is lost without JavaScript.
	 *
	 * On the Help Center home the bar is `live`: its field is bound to the
	 * page's query, so results filter as the reader types, and ↓ hands focus
	 * to the first result. Everywhere else the field is the plain form input.
	 */
	import { guideTitle, tableOfContents, topicPath } from './guide';
	import { topicIcons } from './icons';

	let {
		current = '',
		live = false,
		query = $bindable(''),
		onArrowDown
	}: { current?: string; live?: boolean; query?: string; onArrowDown?: () => void } = $props();

	/** The topic the current article belongs to — its row lists its articles on a phone. */
	const currentChapter = $derived(
		tableOfContents.find((chapter) => chapter.articles.some((article) => article.slug === current))?.category.id
	);
</script>

<div class="guide-bar">
	<div class="guide-inner">
		<div class="guide-row">
			<a class="guide-title" href="/help">{guideTitle}</a>
			<form
				class="guide-search"
				role="search"
				action="/help"
				method="get"
				onsubmit={(event) => {
					if (live) event.preventDefault();
				}}
			>
				<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5" /><path d="M15.5 15.5L20 20" /></svg>
				{#if live}
					<input
						type="search"
						name="q"
						placeholder="Search this guide"
						aria-label="Search this guide"
						bind:value={query}
						onkeydown={(event) => {
							if (event.key === 'ArrowDown' && query.trim() && onArrowDown) {
								event.preventDefault();
								onArrowDown();
							}
						}}
					/>
				{:else}
					<input type="search" name="q" placeholder="Search this guide" aria-label="Search this guide" />
				{/if}
			</form>
		</div>

		<details class="toc">
			<summary>
				<span>All topics</span>
				<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path class="bar" d="M8 12h8" /><path class="stem" d="M12 8v8" /></svg>
			</summary>
			<nav class="toc-body" aria-label="All topics">
				{#each tableOfContents as chapter (chapter.category.id)}
					<section class="chapter" class:current={chapter.category.id === currentChapter}>
						<h2>
							<a href={topicPath(chapter.category.id)}>
								<svg class="chapter-icon" viewBox="0 0 24 24" aria-hidden="true"><path d={topicIcons[chapter.category.id]} /></svg>
								<span class="chapter-name">{chapter.category.name}</span>
								<span class="chapter-count"><span class="visually-hidden">, </span>{chapter.articles.length}<span class="visually-hidden"> articles</span></span>
								<span class="chapter-chevron" aria-hidden="true">›</span>
							</a>
						</h2>
						<ul>
							{#each chapter.articles as article (article.slug)}
								<li>
									<a href="/help/{article.slug}" aria-current={article.slug === current ? 'page' : undefined}>{article.title}</a>
								</li>
							{/each}
						</ul>
					</section>
				{/each}
			</nav>
		</details>
	</div>
</div>

<style>
	.guide-bar { border-bottom: 1px solid #e8e8ed; }
	.guide-inner { position: relative; max-width: 1032px; margin: auto; padding: 0 24px; }
	.visually-hidden { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
	.guide-row { display: flex; align-items: center; justify-content: space-between; gap: 24px; min-height: 76px; }
	.guide-title { font-size: 24px; font-weight: 500; letter-spacing: -.015em; line-height: 1.2; color: #1d1d1f; }
	.guide-title:hover { color: #0066cc; }

	.guide-search { position: relative; flex: 0 1 280px; }
	.guide-search svg { position: absolute; left: 11px; top: 50%; translate: 0 -50%; width: 16px; height: 16px; fill: none; stroke: #86868b; stroke-width: 1.7; stroke-linecap: round; pointer-events: none; }
	.guide-search input { width: 100%; height: 36px; padding: 0 12px 0 34px; border: 1px solid #d2d2d7; border-radius: 10px; background: #fff; font: inherit; font-size: 15px; letter-spacing: -.01em; color: #1d1d1f; }
	.guide-search input::placeholder { color: #86868b; }
	.guide-search input:focus { outline: none; border-color: #0071e3; box-shadow: 0 0 0 3px #0071e333; }

	.toc { padding-bottom: 14px; }
	.toc summary { display: inline-flex; align-items: center; gap: 7px; list-style: none; cursor: pointer; font-size: 17px; letter-spacing: -.02em; color: #0066cc; padding: 2px 0; -webkit-tap-highlight-color: transparent; }
	.toc summary::-webkit-details-marker { display: none; }
	.toc summary:hover span { text-decoration: underline; }
	.toc summary svg { width: 18px; height: 18px; fill: none; stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; }
	.toc[open] .stem { display: none; }

	.toc-body { display: grid; grid-template-columns: repeat(4, 1fr); gap: 32px 36px; padding: 26px 0 22px; }
	.chapter h2 { font-size: 13px; font-weight: 600; letter-spacing: -.005em; margin-bottom: 6px; }
	.chapter h2 a { display: inline-flex; align-items: center; gap: 7px; color: #1d1d1f; font-weight: 600; }
	.chapter-icon { flex: none; width: 16px; height: 16px; fill: none; stroke: currentColor; stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round; }
	.chapter-count, .chapter-chevron { display: none; }
	.chapter ul { list-style: none; margin: 0; padding: 0; }
	.chapter li { margin-top: 7px; }
	.chapter a { font-size: 13px; line-height: 1.38; letter-spacing: -.005em; color: #424245; }
	.chapter a:hover { color: #0066cc; text-decoration: underline; }
	.chapter a[aria-current='page'] { color: #1d1d1f; font-weight: 600; }

	@media (max-width: 900px) {
		.toc-body { grid-template-columns: repeat(2, 1fr); }
	}
	/* Phone: All topics beside the guide's name; the index as topic rows */
	@media (max-width: 600px) {
		.guide-inner { padding: 0 18px; }
		.guide-row { flex-direction: column; align-items: stretch; gap: 12px; padding: 16px 0 14px; min-height: 0; }
		.guide-title { font-size: 19px; line-height: 26px; padding-right: 116px; }
		.guide-search { flex-basis: auto; }
		.guide-search input { height: 40px; font-size: 16px; }

		.toc { padding-bottom: 0; }
		.toc summary { position: absolute; top: 16px; right: 18px; height: 26px; font-size: 16px; gap: 6px; }
		.toc-body { display: block; padding: 2px 0 10px; border-top: 1px solid #e8e8ed; }
		.chapter h2 { margin: 0; font-size: 17px; font-weight: 500; }
		.chapter h2 a { display: flex; gap: 14px; min-height: 50px; font-size: 17px; font-weight: 500; letter-spacing: -.02em; color: #1d1d1f; border-bottom: 1px solid #f0f0f2; }
		.chapter h2 a:hover { text-decoration: none; }
		.chapter-icon { width: 22px; height: 22px; stroke-width: 1.4; }
		.chapter-count { display: inline; margin-left: auto; font-size: 15px; font-weight: 400; color: #86868b; font-variant-numeric: tabular-nums; }
		.chapter-chevron { display: inline; font-size: 21px; font-weight: 400; line-height: 1; color: #c7c7cc; }
		.chapter ul { display: none; }
		.chapter.current ul { display: block; padding: 4px 0 10px 36px; border-bottom: 1px solid #f0f0f2; }
		.chapter.current li { margin-top: 0; }
		.chapter.current li a { display: block; padding: 8px 0; font-size: 15px; line-height: 1.35; }
		.chapter.current li a[aria-current='page'] { color: #0066cc; font-weight: 600; }
		.chapter:last-child h2 a { border-bottom: 0; }
	}
</style>
