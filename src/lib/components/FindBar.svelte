<script lang="ts">
	/**
	 * Find bar — search field + count + prev/next.
	 * Matches are highlighted in the page viewer (parent), not listed in a dropdown.
	 *
	 * Focus stays in this field while typing and while stepping with Enter / arrows.
	 */
	import { FIND_MIN_LENGTH } from '$lib/editor/find';

	let {
		open = $bindable(false),
		query = $bindable(''),
		matchCount = 0,
		activeIndex = 0,
		focusToken = 0,
		onQueryChange,
		onNext,
		onPrev,
		onClose
	}: {
		open?: boolean;
		query?: string;
		matchCount?: number;
		activeIndex?: number;
		focusToken?: number;
		onQueryChange?: (q: string) => void;
		onNext?: () => void;
		onPrev?: () => void;
		onClose?: () => void;
	} = $props();

	let inputEl: HTMLInputElement | undefined = $state();
	let lastFocusToken = -1;

	const trimmed = $derived(query.trim());
	const ready = $derived(trimmed.length >= FIND_MIN_LENGTH);
	const canStep = $derived(ready && matchCount > 0);

	const statusText = $derived.by(() => {
		if (!trimmed) return '—';
		if (!ready) {
			const need = FIND_MIN_LENGTH - trimmed.length;
			return need === 1 ? '1 more letter…' : `${need} more letters…`;
		}
		if (matchCount === 0) return 'No matches';
		return `${activeIndex + 1} of ${matchCount}`;
	});

	function focusField(selectAll: boolean) {
		queueMicrotask(() => {
			if (!inputEl || !open) return;
			inputEl.focus();
			const len = inputEl.value.length;
			if (selectAll && len > 0) inputEl.setSelectionRange(0, len);
			else inputEl.setSelectionRange(len, len);
		});
	}

	$effect(() => {
		if (!open) {
			lastFocusToken = -1;
			return;
		}
		if (focusToken !== lastFocusToken) {
			lastFocusToken = focusToken;
			focusField(focusToken > 1 && query.length > 0);
		}
	});

	function keepInputFocus(event: Event) {
		event.preventDefault();
	}

	function focusInputSoon() {
		queueMicrotask(() => inputEl?.focus());
	}

	function onKeydown(event: KeyboardEvent) {
		if (event.key === 'Escape') {
			event.preventDefault();
			event.stopPropagation();
			onClose?.();
			return;
		}

		// Live find: Enter / ⇧Enter step matches (search already runs as you type).
		if (event.key === 'Enter') {
			event.preventDefault();
			event.stopPropagation();
			if (event.shiftKey) onPrev?.();
			else onNext?.();
			focusInputSoon();
			return;
		}

		// Arrows step when there are hits; otherwise leave caret movement alone.
		if (canStep && !event.metaKey && !event.ctrlKey && !event.altKey) {
			if (event.key === 'ArrowDown') {
				event.preventDefault();
				onNext?.();
				focusInputSoon();
				return;
			}
			if (event.key === 'ArrowUp') {
				event.preventDefault();
				onPrev?.();
				focusInputSoon();
				return;
			}
		}

		if (event.key === 'F3') {
			event.preventDefault();
			event.stopPropagation();
			if (event.shiftKey) onPrev?.();
			else onNext?.();
			focusInputSoon();
		}
	}

	function onInput() {
		// Parent highlights live as the query changes.
		onQueryChange?.(query);
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
				placeholder="Find in document…"
				autocomplete="off"
				autocorrect="off"
				autocapitalize="off"
				spellcheck="false"
				enterkeyhint="search"
				bind:value={query}
				oninput={onInput}
				onkeydown={onKeydown}
			/>
		</label>

		<span class="find-bar__count" aria-live="polite">{statusText}</span>

		<div class="find-bar__nav" role="group" aria-label="Find navigation">
			<button
				type="button"
				class="btn btn-quiet"
				disabled={!canStep}
				onmousedown={keepInputFocus}
				onclick={() => {
					onPrev?.();
					focusInputSoon();
				}}
				aria-label="Previous match"
				title="Previous (↑ or ⇧Enter)"
			>
				↑
			</button>
			<button
				type="button"
				class="btn btn-quiet"
				disabled={!canStep}
				onmousedown={keepInputFocus}
				onclick={() => {
					onNext?.();
					focusInputSoon();
				}}
				aria-label="Next match"
				title="Next (↓ or Enter)"
			>
				↓
			</button>
			<button
				type="button"
				class="btn btn-quiet"
				onmousedown={keepInputFocus}
				onclick={() => onClose?.()}
				aria-label="Close find"
				title="Close (Esc)"
			>
				Done
			</button>
		</div>
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
		flex: 1 1 14rem;
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

	.find-bar__input::-webkit-search-cancel-button {
		-webkit-appearance: none;
		appearance: none;
	}

	.find-bar__count {
		font-size: 12px;
		color: var(--muted);
		font-variant-numeric: tabular-nums;
		min-width: 6.5rem;
		white-space: nowrap;
	}

	.find-bar__nav {
		display: flex;
		align-items: center;
		gap: 2px;
	}

	@media print {
		.find-bar {
			display: none !important;
		}
	}
</style>
