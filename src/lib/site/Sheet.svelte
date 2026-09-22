<script lang="ts">
	/**
	 * A screenplay sheet typeset in Courier to spec — the site's recurring
	 * "proof on paper" visual. Margins follow the classic one-minute page.
	 */
	let {
		lines,
		page = '1.'
	}: { lines: { kind: string; text: string }[]; page?: string } = $props();
</script>

<div class="sheet-wrap">
	<div class="sheet" aria-label="Sample screenplay page">
		<p class="pg" aria-hidden="true">{page}</p>
		{#each lines as line}
			<p class={line.kind}>{line.text}</p>
		{/each}
	</div>
</div>

<style>
	.sheet-wrap { display: flex; justify-content: center; }
	.sheet { background: #fff; border: 1px solid #e6e6ea; width: 100%; max-width: 540px; padding: 56px 60px 60px; box-shadow: 0 32px 80px #18263718, 0 2px 10px #1826370c; font-family: 'Courier New', ui-monospace, Menlo, monospace; font-size: 12.5px; line-height: 1.5; color: #1a1a1c; }
	.sheet p { margin: 0 0 1em; max-width: 60ch; }
	.sheet .pg { text-align: right; color: #8e8e93; }
	.sheet .scene { font-weight: 700; }
	.sheet .character { padding-left: 34ch; }
	.sheet .paren { padding-left: 28ch; max-width: 58ch; }
	.sheet .dialogue { padding-left: 25ch; max-width: 64ch; }
	.sheet .transition { text-align: right; }
	@media (max-width: 600px) {
		.sheet { padding: 36px 26px 40px; font-size: 11px; }
	}
</style>
