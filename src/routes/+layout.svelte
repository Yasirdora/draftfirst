<script lang="ts">
	/**
	 * Root layout: global styles, document metadata, PWA hooks, full-height shell.
	 */
	import '../app.css';

	let { children } = $props();
</script>

<svelte:head>
	<title>Draft First Screenwriting</title>
	<meta
		name="description"
		content="A private, browser-based screenplay editor with professional formatting, Fountain, and FDX support."
	/>
	<meta name="application-name" content="Draft First" />
	<meta name="apple-mobile-web-app-capable" content="yes" />
	<meta name="apple-mobile-web-app-status-bar-style" content="default" />
	<meta name="apple-mobile-web-app-title" content="Draft First" />
	<meta name="mobile-web-app-capable" content="yes" />
	<meta name="color-scheme" content="light dark" />
	<meta name="theme-color" media="(prefers-color-scheme: light)" content="#2A5B8C" />
	<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#1C2229" />
	<link rel="icon" href="/favicon.svg" type="image/svg+xml" />
	<link rel="apple-touch-icon" href="/apple-touch-icon.svg" />
	<link rel="manifest" href="/manifest.webmanifest" />
</svelte:head>

{@render children()}
