<script lang="ts">
	import type { Snippet } from 'svelte';

	/**
	 * The shared top of every feature page: eyebrow, display headline with an
	 * optional accent line, intro, and a back link into the Features hub.
	 */
	let {
		eyebrow,
		title,
		accent = '',
		intro = '',
		back = null as { href: string; label: string } | null,
		children
	}: {
		eyebrow: string;
		title: string;
		accent?: string;
		intro?: string;
		back?: { href: string; label: string } | null;
		children?: Snippet;
	} = $props();
</script>

<header class="page-hero">
	{#if back}<a class="back" href={back.href}><span aria-hidden="true">‹</span> {back.label}</a>{/if}
	<p class="label">{eyebrow}</p>
	<h1>{title}{#if accent}<br /><span>{accent}</span>{/if}</h1>
	{#if intro}<p class="intro">{intro}</p>{/if}
	{@render children?.()}
</header>

<style>
	.page-hero { max-width: 1120px; margin: auto; padding: 84px 24px 72px; text-align: center; }
	.back { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; color: #0066cc; margin-bottom: 26px; }
	.back:hover { text-decoration: underline; }
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	h1 { font-size: clamp(42px, 6.2vw, 80px); font-weight: 650; letter-spacing: -.045em; line-height: 1.05; margin: 20px 0 0; }
	h1 span { color: #0879cf; }
	.intro { font-size: 19px; line-height: 1.55; letter-spacing: -.02em; color: #606066; max-width: 640px; margin: 24px auto 0; }
	@media (max-width: 600px) {
		.page-hero { padding: 56px 18px 48px; }
		h1 { font-size: clamp(32px, 9vw, 46px); }
		.intro { font-size: 16px; }
	}
</style>
