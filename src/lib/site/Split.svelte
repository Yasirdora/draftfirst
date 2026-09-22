<script lang="ts">
	import type { Snippet } from 'svelte';

	/**
	 * The workhorse of the feature pages: an alternating two-column section —
	 * copy with optional proof points on one side, a visual on the other.
	 * theme: light (white), alt (#f5f5f7), or dark (#000).
	 */
	let {
		eyebrow,
		title,
		accent = '',
		intro = '',
		points = [] as { title: string; text: string }[],
		theme = 'light',
		flip = false,
		children
	}: {
		eyebrow: string;
		title: string;
		accent?: string;
		intro?: string;
		points?: { title: string; text: string }[];
		theme?: 'light' | 'alt' | 'dark';
		flip?: boolean;
		children?: Snippet;
	} = $props();
</script>

<section class:alt={theme === 'alt'} class:dark={theme === 'dark'} class="split reveal">
	<div class="inner" class:flipped={flip} class:alone={!children}>
		<div class="copy">
			<p class="label">{eyebrow}</p>
			<h2>{title}{#if accent}<br /><span>{accent}</span>{/if}</h2>
			{#if intro}<p class="intro">{intro}</p>{/if}
			{#if points.length}
				<div class="points">
					{#each points as point}
						<div>
							<h3>{point.title}</h3>
							<p>{point.text}</p>
						</div>
					{/each}
				</div>
			{/if}
		</div>
		{#if children}
			<div class="visual">
				{@render children?.()}
			</div>
		{/if}
	</div>
</section>

<style>
	section { padding: 132px 0; overflow: hidden; }
	section.alt { background: #f5f5f7; }
	section.dark { background: #000; color: #f5f5f7; }
	.inner { max-width: 1120px; margin: auto; padding: 0 24px; display: grid; grid-template-columns: 1fr 1.1fr; gap: 96px; align-items: center; }
	.inner.flipped { grid-template-columns: 1.1fr 1fr; }
	.inner.flipped .copy { order: 2; }
	.inner.flipped .visual { order: 1; }
	.inner.alone { grid-template-columns: 1fr; max-width: 760px; }
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	h2 { font-size: clamp(34px, 4vw, 56px); font-weight: 650; line-height: 1.08; letter-spacing: -.04em; margin-top: 18px; }
	h2 span { color: #86868b; }
	.dark h2 { color: #f5f5f7; }
	.intro { font-size: 17px; line-height: 1.6; color: #6e6e73; margin-top: 20px; max-width: 440px; }
	.dark .intro { color: #a1a1a6; }
	.points { display: grid; gap: 24px; margin-top: 40px; padding-top: 28px; border-top: 1px solid #e3e3e8; }
	.dark .points { border-top-color: #2c2c2e; }
	h3 { font-size: 16px; font-weight: 600; letter-spacing: -.02em; line-height: 1.35; }
	.dark h3 { color: #f5f5f7; }
	.points p { font-size: 14px; line-height: 1.6; color: #6e6e73; margin-top: 6px; }
	.dark .points p { color: #a1a1a6; }
	@media (max-width: 900px) {
		section { padding: 88px 0; }
		.inner, .inner.flipped { grid-template-columns: 1fr; gap: 48px; }
		.inner.flipped .copy { order: 1; }
		.inner.flipped .visual { order: 2; }
	}
</style>
