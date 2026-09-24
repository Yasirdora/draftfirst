<script lang="ts">
	/**
	 * /help/<name>: a topic's own page, or one article of the user guide —
	 * the loader decides which (topic ids and article slugs never collide).
	 */
	import HelpLayout from '$lib/help/HelpLayout.svelte';
	import ArticlePage from '$lib/help/ArticlePage.svelte';
	import TopicPage from '$lib/help/TopicPage.svelte';

	let { data } = $props();
</script>

<HelpLayout>
	{#if data.kind === 'topic'}
		<TopicPage chapter={data.chapter} />
	{:else}
		<!-- Keyed so the table of contents closes and the feedback resets
		     when the reader moves on to another article. -->
		{#key data.article.slug}
			<ArticlePage article={data.article} />
		{/key}
	{/if}
</HelpLayout>
