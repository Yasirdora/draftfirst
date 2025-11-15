<script lang="ts">
	/**
	 * Footer metrics + dialect honesty + discoverable help.
	 */
	import DialectBadge from './DialectBadge.svelte';

	let {
		wordCount = 0,
		charCount = 0,
		readTime = 0,
		cursorPos = 'Line 1, column 1',
		onOpenShortcuts
	}: {
		wordCount?: number;
		charCount?: number;
		readTime?: number;
		cursorPos?: string;
		onOpenShortcuts?: () => void;
	} = $props();
</script>

<footer class="status-bar">
	<span><b>{wordCount.toLocaleString()}</b> words</span>
	<span><b>{charCount.toLocaleString()}</b> characters</span>
	<span><b>{readTime.toLocaleString()}</b> min read</span>
	<span class="spacer"></span>
	<span class="status-bar__cursor">{cursorPos}</span>
	<DialectBadge />
	<button
		type="button"
		class="status-help"
		title="Keyboard shortcuts (?)"
		aria-label="Show keyboard shortcuts"
		onclick={onOpenShortcuts}
	>
		?
	</button>
</footer>

<style>
	.status-bar__cursor {
		font-variant-numeric: tabular-nums;
	}

	.status-help {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 24px;
		height: 24px;
		padding: 0;
		border: 1px solid var(--rule);
		border-radius: 6px;
		background: transparent;
		color: var(--muted);
		font-weight: 700;
		font-size: 12px;
		line-height: 1;
		flex: none;
	}

	.status-help:hover {
		color: var(--ink);
		background: var(--rule-soft);
	}
</style>
