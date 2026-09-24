<script lang="ts">
	/**
	 * A Help Center topic's own page, in Apple Support's product-page
	 * grammar: the topic's icon, name and description; each of its articles
	 * as a tile; a search for more; the other topics as a row of icons.
	 *
	 * Every word comes from the help data — the category's name and
	 * description, each article's title and summary — so this page can never
	 * say something the guide does not. Every tile and icon is a plain link.
	 */
	import { tableOfContents, topicPath, type GuideChapter } from './guide';
	import { topicIcons } from './icons';

	let { chapter }: { chapter: GuideChapter } = $props();

	const category = $derived(chapter.category);
	const others = $derived(tableOfContents.filter((other) => other.category.id !== category.id));
</script>

<svelte:head>
	<title>{category.name} — eDraft Help Center</title>
	<meta name="description" content={category.description} />
</svelte:head>

<main id="main">
	<nav class="section-width crumbs" aria-label="Breadcrumb">
		<ol>
			<li><a href="/help">Help Center</a></li>
			<li aria-current="page">{category.name}</li>
		</ol>
	</nav>

	<header class="topic-hero">
		<svg class="topic-icon" viewBox="0 0 24 24" aria-hidden="true"><path d={topicIcons[category.id]} /></svg>
		<h1>{category.name}</h1>
		<p>{category.description}</p>
	</header>

	<section class="section-width" aria-label="Articles in {category.name}">
		<ul class="tiles">
			{#each chapter.articles as article (article.slug)}
				<li>
					<a class="tile" href="/help/{article.slug}">
						<span class="tile-title">{article.title}</span>
						<span class="tile-summary">{article.summary}</span>
					</a>
				</li>
			{/each}
		</ul>
	</section>

	<section class="section-width more-search" aria-labelledby="search-title">
		<h2 id="search-title">Search for more topics</h2>
		<form class="search" role="search" action="/help" method="get">
			<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5" /><path d="M15.5 15.5L20 20" /></svg>
			<input type="search" name="q" placeholder="Search the Help Center" aria-label="Search the Help Center" />
		</form>
	</section>

	<section class="section-width other-topics" aria-labelledby="other-title">
		<h2 id="other-title">More topics</h2>
		<ul class="topic-row">
			{#each others as other (other.category.id)}
				<li>
					<a class="other" href={topicPath(other.category.id)}>
						<svg viewBox="0 0 24 24" aria-hidden="true"><path d={topicIcons[other.category.id]} /></svg>
						<span>{other.category.name}</span>
					</a>
				</li>
			{/each}
		</ul>
	</section>

	<p class="section-width contact-line">Can’t find what you need? Email <a href="mailto:support@edraft.xyz">support@edraft.xyz</a>.</p>
</main>

<style>
	.section-width { max-width: 1032px; margin-left: auto; margin-right: auto; padding-left: 24px; padding-right: 24px; }

	.crumbs { padding-top: 22px; }
	.crumbs ol { display: flex; flex-wrap: wrap; list-style: none; margin: 0; padding: 0; font-size: 12px; letter-spacing: -.005em; color: #6e6e73; }
	.crumbs li + li::before { content: '›'; padding: 0 9px; color: #86868b; }
	.crumbs a { color: #424245; }
	.crumbs a:hover { color: #0066cc; text-decoration: underline; }

	/* The topic, introduced the way Apple introduces a product */
	.topic-hero { padding: 56px 24px 0; text-align: center; }
	.topic-icon { width: 60px; height: 60px; fill: none; stroke: #1d1d1f; stroke-width: 1.15; stroke-linecap: round; stroke-linejoin: round; }
	.topic-hero h1 { margin-top: 18px; font-size: clamp(40px, 5vw, 56px); font-weight: 600; letter-spacing: -.02em; line-height: 1.07; color: #1d1d1f; text-wrap: balance; }
	.topic-hero p { max-width: 580px; margin: 14px auto 0; font-size: 21px; line-height: 1.38; letter-spacing: -.02em; color: #6e6e73; text-wrap: balance; }

	/* One tile per article — the whole tile is the link */
	.tiles { list-style: none; margin: 0; padding: 64px 0 0; display: grid; grid-template-columns: repeat(2, 1fr); gap: 20px; }
	.tiles li { display: flex; }
	.tile { flex: 1; display: flex; flex-direction: column; gap: 8px; padding: 28px 30px 30px; border-radius: 18px; background: #f5f5f7; transition: background .18s; }
	.tile:hover { background: #ededf0; }
	.tile-title { font-size: 21px; font-weight: 600; letter-spacing: -.018em; line-height: 1.24; color: #1d1d1f; text-wrap: balance; transition: color .18s; }
	.tile:hover .tile-title { color: #0066cc; }
	.tile-title::after { content: ' ›'; color: #0066cc; }
	.tile-summary { font-size: 17px; line-height: 25px; letter-spacing: -.022em; color: #424245; text-wrap: pretty; }

	.more-search { padding-top: 96px; text-align: center; }
	.more-search h2, .other-topics h2 { font-size: clamp(26px, 3vw, 32px); font-weight: 600; letter-spacing: -.02em; line-height: 1.12; color: #1d1d1f; }
	.search { position: relative; max-width: 560px; margin: 26px auto 0; }
	.search svg { position: absolute; left: 15px; top: 50%; translate: 0 -50%; width: 18px; height: 18px; fill: none; stroke: #86868b; stroke-width: 1.7; stroke-linecap: round; pointer-events: none; }
	.search input { width: 100%; height: 48px; padding: 0 16px 0 42px; border: 1px solid #d2d2d7; border-radius: 12px; background: #fff; font: inherit; font-size: 17px; letter-spacing: -.022em; color: #1d1d1f; }
	.search input::placeholder { color: #86868b; }
	.search input:focus { outline: none; border-color: #0071e3; box-shadow: 0 0 0 4px #0071e329; }

	/* The other topics, one tap away */
	.other-topics { padding-top: 96px; text-align: center; }
	.topic-row { list-style: none; margin: 0; padding: 44px 0 0; display: grid; grid-template-columns: repeat(auto-fit, minmax(124px, 1fr)); gap: 36px 12px; }
	.other { display: flex; flex-direction: column; align-items: center; gap: 12px; }
	.other svg { width: 38px; height: 38px; fill: none; stroke: #1d1d1f; stroke-width: 1.3; stroke-linecap: round; stroke-linejoin: round; transition: stroke .15s; }
	.other span { font-size: 15px; letter-spacing: -.01em; line-height: 1.3; color: #1d1d1f; transition: color .15s; }
	.other:hover svg { stroke: #0066cc; }
	.other:hover span { color: #0066cc; }

	.contact-line { padding-top: 88px; padding-bottom: 88px; text-align: center; font-size: 12px; color: #6e6e73; }
	.contact-line a { color: #0066cc; }
	.contact-line a:hover { text-decoration: underline; }

	@media (max-width: 760px) {
		.tiles { grid-template-columns: 1fr; gap: 14px; }
	}
	@media (max-width: 600px) {
		.section-width { padding-left: 18px; padding-right: 18px; }
		.topic-hero { padding-top: 36px; }
		.topic-icon { width: 48px; height: 48px; }
		.topic-hero p { font-size: 19px; }
		.tiles { padding-top: 44px; }
		.tile { padding: 22px 22px 24px; }
		.tile-title { font-size: 19px; }
		.more-search, .other-topics { padding-top: 72px; }
		.contact-line { padding-top: 64px; padding-bottom: 64px; }
	}
</style>
