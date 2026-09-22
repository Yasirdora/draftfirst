<script lang="ts">
	/**
	 * Help Center pages render inside the same site chrome as everything
	 * else — one header, one footer, one design language.
	 */
	import SiteLayout from '$lib/site/SiteLayout.svelte';

	let { children } = $props();
</script>

<SiteLayout
	eyebrow="Help Center"
	links={[
		{ href: '/', label: 'eDraft home' },
		{ href: '/privacy', label: 'Privacy' }
	]}
>
	{@render children()}
</SiteLayout>
