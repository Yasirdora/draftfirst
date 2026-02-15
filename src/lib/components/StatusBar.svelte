<script lang="ts">
	/**
	 * Footer metrics + dialect + Versions (Truth) + help.
	 * When versions have drifted: show Review · N — Apple-quiet, not a wall of diffs.
	 */
	import DialectBadge from './DialectBadge.svelte';
	import type { FidelityStatus } from '$lib/markdown/fidelity';

	let {
		wordCount = 0,
		charCount = 0,
		readTime = 0,
		cursorPos = 'Line 1, column 1',
		truthEnabled = false,
		truthStatus = null as FidelityStatus | null,
		truthChangeCount = 0,
		onToggleTruth,
		onOpenShortcuts
	}: {
		wordCount?: number;
		charCount?: number;
		readTime?: number;
		cursorPos?: string;
		truthEnabled?: boolean;
		truthStatus?: FidelityStatus | null;
		truthChangeCount?: number;
		onToggleTruth?: () => void;
		onOpenShortcuts?: () => void;
	} = $props();

	const pending = $derived(truthEnabled && truthChangeCount > 0);

	const truthTitle = $derived(
		!truthEnabled
			? 'Versions — watch for rewrites when you edit on the page'
			: pending
				? `${truthChangeCount} change${truthChangeCount === 1 ? '' : 's'} from your trusted version — open Review above`
				: 'Versions on — page matches your trusted Markdown'
	);

	const truthLabel = $derived(
		!truthEnabled ? 'Versions' : pending ? `${truthChangeCount}` : 'On'
	);
</script>

<footer class="status-bar">
	<span class="status-bar__metrics" title="{wordCount.toLocaleString()} words · {charCount.toLocaleString()} characters · {readTime} min read">
		<b>{wordCount.toLocaleString()}</b>w
		<span class="status-bar__dot" aria-hidden="true">·</span>
		<b>{charCount.toLocaleString()}</b>c
		<span class="status-bar__dot" aria-hidden="true">·</span>
		<b>{readTime}</b>m
	</span>
	<span class="spacer"></span>
	<span class="status-bar__cursor">{cursorPos}</span>
	<DialectBadge compact />
	<button
		type="button"
		class="status-truth"
		class:status-truth--on={truthEnabled}
		class:status-truth--pending={pending}
		class:status-truth--warn={truthEnabled && truthStatus === 'lossy'}
		title={truthTitle}
		aria-label={truthEnabled ? 'Turn off Versions' : 'Turn on Versions'}
		aria-pressed={truthEnabled}
		onclick={onToggleTruth}
	>
		{truthLabel}
	</button>
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
	.status-bar__metrics {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		white-space: nowrap;
		font-variant-numeric: tabular-nums;
	}

	.status-bar__dot {
		opacity: 0.45;
		user-select: none;
	}

	.status-bar__cursor {
		font-variant-numeric: tabular-nums;
		font-size: 10.5px;
		opacity: 0.9;
	}

	.status-truth {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		height: 20px;
		padding: 0 8px;
		border: 1px solid transparent;
		border-radius: 980px;
		background: var(--rule-soft);
		color: var(--muted);
		font-weight: 600;
		font-size: 10.5px;
		letter-spacing: 0.01em;
		line-height: 1;
		flex: none;
	}

	.status-truth:hover {
		color: var(--ink);
		background: var(--rule-soft);
	}

	.status-truth--on {
		border-color: color-mix(in srgb, var(--accent) 40%, var(--rule));
		background: var(--accent-soft);
		color: var(--accent-deep);
	}

	.status-truth--pending {
		border-color: color-mix(in srgb, var(--accent) 50%, var(--rule));
		background: var(--accent);
		color: var(--on-accent);
	}

	.status-truth--warn.status-truth--pending {
		background: var(--danger);
		border-color: var(--danger);
		color: #fff;
	}

	.status-help {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 20px;
		height: 20px;
		padding: 0;
		border: 0;
		border-radius: 980px;
		background: transparent;
		color: var(--muted);
		font-weight: 700;
		font-size: 11px;
		line-height: 1;
		flex: none;
	}

	.status-help:hover {
		color: var(--ink);
		background: var(--rule-soft);
	}

	@media (max-width: 640px) {
		.status-bar__cursor {
			display: none;
		}
	}
</style>
