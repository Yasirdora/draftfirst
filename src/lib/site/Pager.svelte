<script lang="ts">
	/** End-of-page navigation between feature pages — "Next: Story". */
	let { href, kicker = 'Next', title }: { href: string; kicker?: string; title: string } = $props();
</script>

<nav class="pager" aria-label="More features">
	<a href={href}>
		<span class="kicker">{kicker}</span>
		<span class="title">{title} <span class="arrow" aria-hidden="true">›</span></span>
	</a>
</nav>

<style>
	.pager { background: #f5f5f7; }
	a { display: block; max-width: 1120px; margin: auto; padding: 64px 24px; text-align: center; }
	.kicker { display: block; font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	.title { display: block; font-size: clamp(26px, 3vw, 38px); font-weight: 650; letter-spacing: -.035em; color: #1d1d1f; margin-top: 10px; transition: color .18s; }
	a:hover .title { color: #0066cc; }
	.arrow { color: #86868b; }
</style>
