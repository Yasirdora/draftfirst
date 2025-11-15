<script lang="ts">
	/**
	 * Root layout: global styles, document metadata, PWA hooks, full-height shell.
	 */
	import '../app.css';

	let { children } = $props();
</script>

<svelte:head>
	<title>Writing Desk — markdown editor, nothing leaves your browser</title>
	<meta
		name="description"
		content="Write in Markdown, see it typeset as you go, export clean HTML or print to PDF. No signup, no upload, no tracking — nothing leaves your browser."
	/>
	<meta name="application-name" content="Writing Desk" />
	<meta name="apple-mobile-web-app-capable" content="yes" />
	<meta name="apple-mobile-web-app-status-bar-style" content="default" />
	<meta name="apple-mobile-web-app-title" content="Writing Desk" />
	<meta name="mobile-web-app-capable" content="yes" />
	<meta name="color-scheme" content="light dark" />
	<meta name="theme-color" media="(prefers-color-scheme: light)" content="#2A5B8C" />
	<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#1C2229" />
	<link rel="icon" href="/favicon.svg" type="image/svg+xml" />
	<link rel="apple-touch-icon" href="/apple-touch-icon.svg" />
	<link rel="manifest" href="/manifest.webmanifest" />
</svelte:head>

{@render children()}
