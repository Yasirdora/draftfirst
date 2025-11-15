<script lang="ts">
	/**
	 * Find in document — calm, keyboard-first.
	 * Parent owns match list and navigation (keeps editor logic centralized).
	 */
	import type { FindMatch } from '$lib/editor/find';

	let {
		open = $bindable(false),
		query = $bindable(''),
		matches = [] as FindMatch[],
		activeIndex = 0,
		onQueryChange,
		onNext,
		onPrev,
		onGoTo,
		onClose
	}: {
		open?: boolean;
		query?: string;
		matches?: FindMatch[];
		activeIndex?: number;
		onQueryChange?: (q: string) => void;
		onNext?: () => void;
		onPrev?: () => void;
		onGoTo?: (index: number) => void;
		onClose?: () => void;
	} = $props();

	let inputEl: HTMLInputElement | undefined = $state();

	$effect(() => {
		if (open) queueMicrotask(() => inputEl?.focus());
	});

	function onKeydown(event: KeyboardEvent) {
		if (event.key === 'Escape') {
			event.preventDefault();
			onClose?.();
			return;
		}
		if (event.key === 'Enter') {
			event.preventDefault();
			if (event.shiftKey) onPrev?.();
			else onNext?.();
		}
	}
</script>

{#if open}
	<div class="find-bar" role="search" aria-label="Find in document">
		<label class="find-bar__field">
			<span class="find-bar__label">Find</span>
			<input
				bind:this={inputEl}
				class="find-bar__input"
				type="search"
				placeholder="Search this document…"
				autocomplete="off"
				spellcheck="false"
				bind:value={query}
				oninput={() => onQueryChange?.(query)}
				onkeydown={onKeydown}
			/>
		</label>

		<span class="find-bar__count" aria-live="polite">
			{#if !query.trim()}
				—
			{:else if matches.length === 0}
				No matches
			{:else}
				{activeIndex + 1} of {matches.length}
			{/if}
		</span>

		<div class="find-bar__nav">
			<button
				type="button"
				class="btn btn-quiet"
				disabled={matches.length === 0}
				onclick={() => onPrev?.()}
				aria-label="Previous match"
				title="Previous (⇧Enter)"
			>
				↑
			</button>
			<button
				type="button"
				class="btn btn-quiet"
				disabled={matches.length === 0}
				onclick={() => onNext?.()}
				aria-label="Next match"
				title="Next (Enter)"
			>
				↓
			</button>
			<button
				type="button"
				class="btn btn-quiet"
				onclick={() => onClose?.()}
				aria-label="Close find"
				title="Close (Esc)"
			>
				Done
			</button>
		</div>

		{#if matches.length > 0 && query.trim()}
			<ul class="find-bar__results">
				{#each matches.slice(0, 40) as match, i (match.index)}
					<li>
						<button
							type="button"
							class="find-bar__hit"
							class:is-active={i === activeIndex}
							onclick={() => onGoTo?.(i)}
						>
							<span class="find-bar__line">L{match.line}</span>
							<span class="find-bar__preview">{match.preview}</span>
						</button>
					</li>
				{/each}
				{#if matches.length > 40}
					<li class="find-bar__more">+{matches.length - 40} more</li>
				{/if}
			</ul>
		{/if}
	</div>
{/if}

<style>
	.find-bar {
		flex: none;
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px 10px;
		padding: 8px 16px;
		background: var(--panel);
		border-bottom: 1px solid var(--rule);
		z-index: 12;
	}

	.find-bar__field {
		display: flex;
		align-items: center;
		gap: 8px;
		flex: 1 1 12rem;
		min-width: 0;
	}

	.find-bar__label {
		font-size: 12px;
		font-weight: 650;
		color: var(--muted);
		flex: none;
	}

	.find-bar__input {
		flex: 1 1 auto;
		min-width: 0;
		padding: 6px 10px;
		border: 1px solid var(--rule);
		border-radius: 8px;
		background: var(--panel-2);
		outline: none;
	}

	.find-bar__input:focus {
		border-color: var(--accent);
		box-shadow: 0 0 0 2px var(--accent-soft);
	}

	.find-bar__count {
		font-size: 12px;
		color: var(--muted);
		font-variant-numeric: tabular-nums;
		min-width: 5.5rem;
	}

	.find-bar__nav {
		display: flex;
		align-items: center;
		gap: 2px;
	}

	.find-bar__results {
		flex: 1 1 100%;
		list-style: none;
		margin: 0;
		padding: 0;
		max-height: 9rem;
		overflow: auto;
		border: 1px solid var(--rule-soft);
		border-radius: 8px;
		background: var(--panel-2);
	}

	.find-bar__hit {
		display: grid;
		grid-template-columns: 3rem 1fr;
		gap: 8px;
		width: 100%;
		padding: 6px 10px;
		border: 0;
		background: transparent;
		text-align: left;
		font: inherit;
		color: var(--ink);
		cursor: pointer;
	}

	.find-bar__hit:hover,
	.find-bar__hit.is-active {
		background: var(--accent-soft);
	}

	.find-bar__line {
		font-size: 11px;
		font-weight: 650;
		color: var(--muted);
		font-variant-numeric: tabular-nums;
	}

	.find-bar__preview {
		font-size: 12.5px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.find-bar__more {
		padding: 6px 10px;
		font-size: 12px;
		color: var(--muted);
	}

	@media print {
		.find-bar {
			display: none !important;
		}
	}
</style>
