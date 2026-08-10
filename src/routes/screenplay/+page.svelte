<script lang="ts">
	/**
	 * Legacy route. The editor's canonical home is `/`; anyone arriving from an
	 * old /screenplay link is forwarded instantly (meta refresh for no-JS,
	 * client navigation when JS is up).
	 */
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';

	onMount(() => {
		void goto('/', { replaceState: true });
	});
</script>

<svelte:head>
	<title>Draft First Screenwriting</title>
	<meta http-equiv="refresh" content="0; url=/" />
	<link rel="canonical" href="/" />
</svelte:head>

<p style="font-family: sans-serif; padding: 2rem">
	The editor has moved home — <a href="/">continue to Draft First</a>.
</p>
