<script lang="ts">
	/**
	 * Versions review — each change shows removed (strike) + added (mark),
	 * like track-changes: something taken out, something put in.
	 */
	import type { FidelityReport } from '$lib/markdown/fidelity';
	import { changeVisualPair, groupTruthChanges } from '$lib/markdown/fidelity';

	let {
		report,
		open = false,
		onDismiss,
		onRestoreBaseline,
		onRestoreChange,
		onAcceptBaseline
	}: {
		report: FidelityReport | null;
		open?: boolean;
		onDismiss?: () => void;
		onRestoreBaseline?: () => void;
		onRestoreChange?: (changeId: number) => void;
		onAcceptBaseline?: () => void;
	} = $props();

	const changes = $derived(
		report && report.status !== 'identical' ? groupTruthChanges(report.hunks) : []
	);
</script>

{#if open && report && report.status !== 'identical' && changes.length > 0}
	<aside class="truth" role="region" aria-label="Review version changes">
		<div class="truth__head">
			<span class="truth__title">
				{changes.length}
				{changes.length === 1 ? 'change' : 'changes'}
			</span>
			<div class="truth__actions">
				{#if onRestoreBaseline}
					<button type="button" class="truth__link" onclick={onRestoreBaseline}>
						Restore all
					</button>
				{/if}
				{#if onAcceptBaseline}
					<button type="button" class="truth__link" onclick={onAcceptBaseline}>Keep</button>
				{/if}
				{#if onDismiss}
					<button
						type="button"
						class="truth__close"
						title="Close"
						aria-label="Close"
						onclick={onDismiss}
					>
						<svg class="truth__close-icon" viewBox="0 0 24 24" aria-hidden="true">
							<path
								fill="none"
								stroke="currentColor"
								stroke-width="2"
								stroke-linecap="round"
								d="M6 6l12 12M18 6L6 18"
							/>
						</svg>
					</button>
				{/if}
			</div>
		</div>

		<ul class="truth__list">
			{#each changes as change (change.id)}
				{@const pair = changeVisualPair(change)}
				<li class="truth__item">
					<div
						class="truth__visual"
						title="Removed: {pair.before || '—'} · Added: {pair.after || '—'}"
					>
						{#if pair.before}
							<span class="truth__del">{pair.before}</span>
						{/if}
						{#if pair.before && pair.after}
							<span class="truth__gap" aria-hidden="true"></span>
						{/if}
						{#if pair.after}
							<span class="truth__ins">{pair.after}</span>
						{/if}
						{#if !pair.before && !pair.after}
							<span class="truth__empty">Empty change</span>
						{/if}
					</div>
					{#if onRestoreChange}
						<button
							type="button"
							class="truth__restore"
							title="Restore this change"
							aria-label="Restore this change"
							onclick={() => onRestoreChange(change.id)}
						>
							<svg class="truth__restore-icon" viewBox="0 0 24 24" aria-hidden="true">
								<path
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									d="M3 12a9 9 0 1 0 3-6.7M3 4v5h5"
								/>
							</svg>
						</button>
					{/if}
				</li>
			{/each}
		</ul>
	</aside>
{/if}

<style>
	.truth {
		flex: none;
		border-top: 1px solid var(--rule);
		background: var(--panel);
		z-index: 15;
		position: relative;
	}

	.truth__head {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 6px 14px;
		border-bottom: 1px solid var(--rule-soft);
	}

	.truth__title {
		font-size: 12px;
		font-weight: 650;
		color: var(--ink);
		flex: none;
	}

	.truth__actions {
		display: flex;
		align-items: center;
		gap: 2px;
		margin-left: auto;
	}

	.truth__link {
		appearance: none;
		border: 0;
		background: transparent;
		color: var(--accent);
		font-size: 12px;
		font-weight: 600;
		padding: 4px 8px;
		border-radius: 5px;
	}

	.truth__link:hover {
		background: var(--accent-soft);
	}

	.truth__close {
		appearance: none;
		flex: none;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		padding: 0;
		border: 0;
		background: transparent;
		color: var(--muted);
		border-radius: 7px;
	}

	.truth__close:hover {
		color: var(--ink);
		background: var(--rule-soft);
	}

	.truth__close-icon {
		width: 14px;
		height: 14px;
		display: block;
	}

	.truth__list {
		list-style: none;
		margin: 0;
		padding: 0;
		max-height: 11rem;
		overflow: auto;
	}

	.truth__item {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 8px 10px 8px 14px;
		border-bottom: 1px solid var(--rule-soft);
		min-height: 36px;
	}

	.truth__item:last-child {
		border-bottom: 0;
	}

	.truth__visual {
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 0 4px;
		font-size: 13px;
		line-height: 1.4;
		/* allow wrap so long snippets stay readable */
		overflow: hidden;
	}

	/* Removed — strike + soft red wash (track-changes style) */
	.truth__del {
		color: color-mix(in srgb, var(--danger) 75%, var(--ink));
		text-decoration: line-through;
		text-decoration-thickness: 1.5px;
		text-decoration-color: color-mix(in srgb, var(--danger) 70%, transparent);
		background: color-mix(in srgb, var(--danger) 12%, transparent);
		border-radius: 2px;
		padding: 0 2px;
		/* keep on one visual run when possible */
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.truth__gap {
		flex: none;
		width: 2px;
	}

	/* Added — soft green wash (track-changes style) */
	.truth__ins {
		color: color-mix(in srgb, #1b7a3d 55%, var(--ink));
		background: color-mix(in srgb, #2f9e44 16%, transparent);
		border-radius: 2px;
		padding: 0 2px;
		font-weight: 550;
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	@media (prefers-color-scheme: dark) {
		.truth__del {
			color: color-mix(in srgb, var(--danger) 85%, var(--ink));
			background: color-mix(in srgb, var(--danger) 18%, transparent);
		}

		.truth__ins {
			color: color-mix(in srgb, #6bcf7f 70%, var(--ink));
			background: color-mix(in srgb, #2f9e44 22%, transparent);
		}
	}

	.truth__empty {
		color: var(--muted);
		font-size: 12px;
	}

	.truth__restore {
		appearance: none;
		flex: none;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 30px;
		height: 30px;
		padding: 0;
		border: 0;
		background: transparent;
		color: var(--accent);
		border-radius: 7px;
	}

	.truth__restore:hover {
		background: var(--accent-soft);
	}

	.truth__restore-icon {
		width: 16px;
		height: 16px;
		display: block;
	}
</style>
