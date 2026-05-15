<script lang="ts">
	/**
	 * Command palette (⌘K) — every action, fuzzy-findable, keyboard-first.
	 * Top-centre modal like the tools writers already know (VS Code, Linear).
	 * Esc or backdrop click closes; focus returns to the writing surface.
	 */
	import type { PaletteCommand } from '$lib/editor/palette-commands';

	let {
		open = false,
		items = [],
		query = $bindable(''),
		activeIndex = $bindable(0),
		onSelect,
		onClose
	}: {
		open?: boolean;
		items?: PaletteCommand[];
		query?: string;
		activeIndex?: number;
		onSelect?: (cmd: PaletteCommand) => void;
		onClose?: () => void;
	} = $props();

	let inputEl: HTMLInputElement | undefined = $state();
	let listEl: HTMLUListElement | undefined = $state();

	$effect(() => {
		if (!open) return;
		query = '';
		activeIndex = 0;
		const previous = document.activeElement as HTMLElement | null;
		// Defer so the input is in the DOM.
		queueMicrotask(() => inputEl?.focus());
		return () => previous?.focus?.();
	});

	$effect(() => {
		// Keep active index in range as the filtered list changes.
		if (activeIndex >= items.length) activeIndex = Math.max(0, items.length - 1);
	});

	$effect(() => {
		// Keep the active option visible while navigating.
		listEl
			?.querySelector(`[data-index="${activeIndex}"]`)
			?.scrollIntoView({ block: 'nearest' });
	});

	function onKeydown(event: KeyboardEvent) {
		if (event.key === 'ArrowDown') {
			event.preventDefault();
			activeIndex = Math.min(items.length - 1, activeIndex + 1);
		} else if (event.key === 'ArrowUp') {
			event.preventDefault();
			activeIndex = Math.max(0, activeIndex - 1);
		} else if (event.key === 'Enter') {
			event.preventDefault();
			const cmd = items[activeIndex];
			if (cmd) onSelect?.(cmd);
		} else if (event.key === 'Escape') {
			event.preventDefault();
			event.stopPropagation();
			onClose?.();
		}
	}

	function backdropClose(event: MouseEvent) {
		if (event.target === event.currentTarget) onClose?.();
	}
</script>

{#if open}
	<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
	<div class="palette-backdrop" role="presentation" onclick={backdropClose}>
		<div class="palette" role="dialog" aria-modal="true" aria-label="Command palette">
			<div class="palette__input-row">
				<input
					bind:this={inputEl}
					bind:value={query}
					onkeydown={onKeydown}
					type="text"
					placeholder="Type a command…"
					role="combobox"
					aria-expanded="true"
					aria-controls="palette-list"
					aria-autocomplete="list"
					aria-activedescendant={items[activeIndex]
						? `palette-opt-${items[activeIndex].id}`
						: undefined}
					spellcheck="false"
					autocomplete="off"
				/>
				<kbd aria-hidden="true">esc</kbd>
			</div>

			{#if items.length > 0}
				<ul class="palette__list" role="listbox" id="palette-list" bind:this={listEl}>
					{#each items as cmd, i (cmd.id)}
						{#if i === 0 || items[i - 1].group !== cmd.group}
							<li class="palette__group" aria-hidden="true">{cmd.group}</li>
						{/if}
						<li role="option" id="palette-opt-{cmd.id}" aria-selected={i === activeIndex}>
							<button
								type="button"
								class="palette__item"
								class:is-active={i === activeIndex}
								data-index={i}
								onmousedown={(e) => e.preventDefault()}
								onclick={() => onSelect?.(cmd)}
								onmouseenter={() => (activeIndex = i)}
							>
								<span class="palette__label">{cmd.label}</span>
								{#if cmd.hint}<span class="palette__hint">{cmd.hint}</span>{/if}
							</button>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="palette__empty" role="status">No matching commands</p>
			{/if}

			<p class="palette__foot">↑↓ navigate · Enter run · Esc close</p>
		</div>
	</div>
{/if}

<style>
	.palette-backdrop {
		position: fixed;
		inset: 0;
		z-index: 60;
		background: rgba(16, 24, 32, 0.28);
		backdrop-filter: blur(2px);
		display: flex;
		align-items: flex-start;
		justify-content: center;
		padding: 12vh 16px 16px;
		animation: palette-fade 0.12s ease;
	}

	.palette {
		width: min(480px, 100%);
		max-height: min(420px, 70vh);
		display: flex;
		flex-direction: column;
		border-radius: 14px;
		border: 1px solid var(--rule);
		background: var(--panel);
		box-shadow:
			0 1px 2px rgba(16, 24, 32, 0.08),
			0 24px 64px rgba(16, 24, 32, 0.24);
		overflow: hidden;
		animation: palette-in 0.14s ease;
	}

	.palette__input-row {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 12px 14px;
		border-bottom: 1px solid var(--rule-soft);
	}

	.palette__input-row input {
		flex: 1;
		border: 0;
		background: transparent;
		color: var(--ink);
		font: inherit;
		font-size: 15px;
		outline: none;
	}

	.palette__input-row input::placeholder {
		color: var(--placeholder);
	}

	.palette__list {
		list-style: none;
		margin: 0;
		padding: 6px;
		overflow-y: auto;
		min-height: 0;
	}

	.palette__group {
		padding: 8px 10px 3px;
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		color: var(--placeholder);
	}

	.palette__item {
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

	.palette__item.is-active,
	.palette__item:hover {
		background: var(--accent);
		color: var(--on-accent);
	}

	.palette__label {
		font-weight: 600;
		font-size: 13.5px;
	}

	.palette__hint {
		font-family: var(--font-mono);
		font-size: 11.5px;
		color: var(--muted);
	}

	.palette__item.is-active .palette__hint,
	.palette__item:hover .palette__hint {
		color: inherit;
		opacity: 0.72;
	}

	.palette__empty {
		padding: 18px 14px;
		color: var(--muted);
		font-size: 13px;
		text-align: center;
	}

	.palette__foot {
		margin: 0;
		padding: 8px 14px;
		border-top: 1px solid var(--rule-soft);
		font-size: 11px;
		color: var(--placeholder);
	}

	@keyframes palette-in {
		from {
			opacity: 0;
			transform: translateY(-6px) scale(0.99);
		}
		to {
			opacity: 1;
			transform: none;
		}
	}

	@keyframes palette-fade {
		from {
			opacity: 0;
		}
		to {
			opacity: 1;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.palette,
		.palette-backdrop {
			animation: none;
		}
	}

	@media print {
		.palette-backdrop {
			display: none !important;
		}
	}
</style>
