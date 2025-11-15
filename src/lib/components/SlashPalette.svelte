<script lang="ts">
	/**
	 * Floating slash command palette — structure without leaving the keyboard.
	 */
	import type { SlashCommand } from '$lib/editor/slash-commands';

	let {
		open = false,
		query = '',
		items = [],
		activeIndex = $bindable(0),
		anchor = null as { top: number; left: number } | null,
		onSelect,
		onClose
	}: {
		open?: boolean;
		query?: string;
		items?: SlashCommand[];
		activeIndex?: number;
		anchor?: { top: number; left: number } | null;
		onSelect?: (cmd: SlashCommand) => void;
		onClose?: () => void;
	} = $props();

	$effect(() => {
		// Keep active index in range when the filtered list changes
		if (activeIndex >= items.length) activeIndex = Math.max(0, items.length - 1);
	});
</script>

{#if open && items.length > 0}
	<div
		class="slash-palette"
		style:top="{anchor?.top ?? 80}px"
		style:left="{anchor?.left ?? 24}px"
		role="listbox"
		aria-label="Insert block"
		id="slash-palette"
	>
		<div class="slash-palette__query" aria-hidden="true">/{query}</div>
		<ul class="slash-palette__list">
			{#each items as cmd, i (cmd.id)}
				<li role="option" aria-selected={i === activeIndex}>
					<button
						type="button"
						class="slash-palette__item"
						class:is-active={i === activeIndex}
						onmousedown={(e) => e.preventDefault()}
						onclick={() => onSelect?.(cmd)}
						onmouseenter={() => (activeIndex = i)}
					>
						<span class="slash-palette__label">{cmd.label}</span>
						<span class="slash-palette__hint">{cmd.hint}</span>
					</button>
				</li>
			{/each}
		</ul>
		<p class="slash-palette__foot">↑↓ navigate · Enter insert · Esc cancel</p>
	</div>
{:else if open && items.length === 0}
	<div
		class="slash-palette slash-palette--empty"
		style:top="{anchor?.top ?? 80}px"
		style:left="{anchor?.left ?? 24}px"
		role="status"
	>
		No matching commands
		<button type="button" class="slash-palette__dismiss" onclick={() => onClose?.()}>Esc</button>
	</div>
{/if}

<style>
	.slash-palette {
		position: fixed;
		z-index: 40;
		width: min(280px, calc(100vw - 24px));
		max-height: min(320px, 50vh);
		display: flex;
		flex-direction: column;
		padding: 6px;
		border-radius: 12px;
		border: 1px solid var(--rule);
		background: var(--panel);
		box-shadow:
			0 1px 2px rgba(16, 24, 32, 0.08),
			0 16px 40px rgba(16, 24, 32, 0.18);
		animation: slash-in 0.14s ease;
	}

	.slash-palette--empty {
		padding: 12px 14px;
		color: var(--muted);
		font-size: 13px;
		gap: 8px;
		flex-direction: row;
		align-items: center;
		justify-content: space-between;
	}

	.slash-palette__query {
		padding: 4px 8px 6px;
		font-size: 11.5px;
		font-weight: 600;
		color: var(--muted);
		font-variant-numeric: tabular-nums;
	}

	.slash-palette__list {
		list-style: none;
		margin: 0;
		padding: 0;
		overflow: auto;
		min-height: 0;
	}

	.slash-palette__item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		width: 100%;
		padding: 8px 10px;
		border: 0;
		border-radius: 8px;
		background: transparent;
		color: var(--ink);
		text-align: left;
		font: inherit;
		cursor: pointer;
	}

	.slash-palette__item.is-active,
	.slash-palette__item:hover {
		background: var(--accent-soft);
		color: var(--accent-deep);
	}

	.slash-palette__label {
		font-weight: 600;
		font-size: 13px;
	}

	.slash-palette__hint {
		font-family: var(--font-mono);
		font-size: 11.5px;
		color: var(--muted);
	}

	.slash-palette__item.is-active .slash-palette__hint {
		color: var(--accent);
	}

	.slash-palette__foot {
		margin: 4px 8px 2px;
		padding-top: 6px;
		border-top: 1px solid var(--rule-soft);
		font-size: 11px;
		color: var(--placeholder);
	}

	.slash-palette__dismiss {
		border: 1px solid var(--rule);
		border-radius: 6px;
		background: var(--rule-soft);
		padding: 2px 8px;
		font: inherit;
		font-size: 11px;
		cursor: pointer;
	}

	@keyframes slash-in {
		from {
			opacity: 0;
			transform: translateY(4px);
		}
		to {
			opacity: 1;
			transform: none;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.slash-palette {
			animation: none;
		}
	}

	@media print {
		.slash-palette {
			display: none !important;
		}
	}
</style>
