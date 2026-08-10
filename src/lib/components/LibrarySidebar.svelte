<script lang="ts">
	/**
	 * Document library — Gemini-style left nav: quiet field, pill selection.
	 */
	import type { LibraryDocument, LibrarySearchHit, TrashBin } from '$lib/library/types';
	import { formatRelativeTime } from '$lib/library/library';
	import Icon from './Icon.svelte';

	let {
		open = true,
		activeId = '',
		hits = [] as LibrarySearchHit[],
		query = $bindable(''),
		trash = null as TrashBin | null,
		onSelect,
		onNew,
		onRename,
		onDelete,
		onUndo,
		onClose,
		onQueryChange
	}: {
		open?: boolean;
		activeId?: string;
		hits?: LibrarySearchHit[];
		query?: string;
		trash?: TrashBin | null;
		onSelect?: (id: string) => void;
		onNew?: () => void;
		onRename?: (id: string, title: string) => void;
		onDelete?: (id: string) => void;
		onUndo?: () => void;
		onClose?: () => void;
		onQueryChange?: (q: string) => void;
	} = $props();

	let renamingId = $state<string | null>(null);
	let renameValue = $state('');
	let renameInput: HTMLInputElement | undefined = $state();

	function startRename(doc: LibraryDocument, event: Event) {
		event.stopPropagation();
		renamingId = doc.id;
		renameValue = doc.title;
		queueMicrotask(() => {
			renameInput?.focus();
			renameInput?.select();
		});
	}

	function commitRename() {
		if (!renamingId) return;
		onRename?.(renamingId, renameValue);
		renamingId = null;
	}

	function cancelRename() {
		renamingId = null;
	}

	function onRenameKey(event: KeyboardEvent) {
		if (event.key === 'Enter') {
			event.preventDefault();
			commitRename();
		} else if (event.key === 'Escape') {
			event.preventDefault();
			cancelRename();
		}
	}
</script>

{#if open}
	<aside class="library" aria-label="Document library">
		<header class="library__head">
			<div class="library__title-row">
				<span class="library__section">Library</span>
				<button
					type="button"
					class="library__icon-btn"
					title="Close library"
					aria-label="Close library"
					onclick={onClose}
				>
					<Icon name="close" />
				</button>
			</div>

			<button type="button" class="library__new" onclick={onNew}>
				<span class="library__new-plus" aria-hidden="true"><Icon name="plus" size={14} /></span>
				New document
			</button>

			<label class="library__search">
				<span class="visually-hidden">Search library</span>
				<span class="library__search-icon" aria-hidden="true"><Icon name="search" size={14} /></span>
				<input
					type="search"
					placeholder="Search"
					autocomplete="off"
					spellcheck="false"
					bind:value={query}
					oninput={() => onQueryChange?.(query)}
				/>
			</label>
		</header>

		{#if trash && trash.expiresAt > Date.now()}
			<div class="library__undo" role="status">
				<span>Deleted</span>
				<button type="button" class="library__undo-btn" onclick={onUndo}>Undo</button>
			</div>
		{/if}

		<div class="library__section-label">Documents</div>

		<ul class="library__list">
			{#if hits.length === 0}
				<li class="library__empty">
					{query.trim() ? 'No matches' : 'No documents yet'}
				</li>
			{:else}
				{#each hits as hit (hit.doc.id)}
					{@const doc = hit.doc}
					<li>
						<div class="library__item" class:is-active={doc.id === activeId}>
							{#if renamingId === doc.id}
								<input
									bind:this={renameInput}
									class="library__rename"
									bind:value={renameValue}
									onkeydown={onRenameKey}
									onblur={commitRename}
									aria-label="Rename document"
								/>
							{:else}
								<button
									type="button"
									class="library__open"
									onclick={() => onSelect?.(doc.id)}
								>
									<span class="library__name">{doc.title || 'Untitled'}</span>
									<span class="library__meta">
										{formatRelativeTime(doc.updatedAt)}
										{#if query.trim() && hit.match !== 'title'}
											· in text
										{/if}
									</span>
								</button>
								<div class="library__actions">
									<button
										type="button"
										class="library__action"
										title="Rename"
										aria-label="Rename {doc.title}"
										onclick={(e) => startRename(doc, e)}
									>
										<Icon name="edit" size={14} />
									</button>
									<button
										type="button"
										class="library__action library__action--danger"
										title="Delete"
										aria-label="Delete {doc.title}"
										onclick={(e) => {
											e.stopPropagation();
											onDelete?.(doc.id);
										}}
									>
										<Icon name="trash" size={14} />
									</button>
								</div>
							{/if}
						</div>
					</li>
				{/each}
			{/if}
		</ul>

		<p class="library__foot">Only on this device</p>
	</aside>
{/if}

<style>
	.library {
		flex: none;
		width: min(var(--nav-width, 248px), 88vw);
		display: flex;
		flex-direction: column;
		min-height: 0;
		/* Blend the sidebar into the application field. */
		background: var(--bg);
		border-right: 0;
		z-index: 8;
		padding: 8px 10px 12px;
	}

	.library__head {
		flex: none;
		padding: 4px 2px 6px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	.library__title-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		padding: 2px 4px 4px;
	}

	.library__section {
		font-size: 13px;
		font-weight: 600;
		letter-spacing: -0.02em;
		color: var(--ink);
	}

	.library__icon-btn {
		appearance: none;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 30px;
		height: 30px;
		padding: 0;
		border: 0;
		border-radius: 10px;
		background: transparent;
		color: var(--muted);
		cursor: pointer;
	}

	.library__icon-btn:hover {
		background: var(--rule-soft);
		color: var(--ink);
	}

	/* Primary library action. */
	.library__new {
		appearance: none;
		display: flex;
		align-items: center;
		gap: 10px;
		width: 100%;
		padding: 9px 12px;
		border: 1px solid var(--rule);
		border-radius: 14px;
		background: var(--panel);
		color: var(--ink);
		font: inherit;
		font-size: 13px;
		font-weight: 500;
		letter-spacing: -0.01em;
		cursor: pointer;
		text-align: left;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.12);
	}

	.library__new:hover {
		background: color-mix(in srgb, var(--panel) 70%, var(--rule-soft));
		border-color: color-mix(in srgb, var(--rule) 80%, var(--ink));
	}

	.library__new-plus {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.1em;
		font-size: 16px;
		font-weight: 400;
		line-height: 1;
		color: var(--muted);
	}

	.library__search {
		position: relative;
		display: block;
	}

	.library__search-icon {
		position: absolute;
		left: 12px;
		top: 50%;
		transform: translateY(-50%);
		display: inline-flex;
		align-items: center;
		color: var(--placeholder);
		pointer-events: none;
	}

	.library__search input {
		width: 100%;
		padding: 9px 12px 9px 34px;
		border: 1px solid transparent;
		border-radius: 12px;
		background: var(--rule-soft);
		color: var(--ink);
		outline: none;
		font-size: 13px;
	}

	.library__search input:focus {
		background: var(--panel);
		border-color: var(--rule);
		box-shadow: 0 0 0 1px var(--rule);
	}

	.library__undo {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		margin: 4px 4px 0;
		padding: 8px 12px;
		border-radius: 12px;
		background: var(--accent-soft);
		font-size: 12.5px;
		color: var(--ink);
	}

	.library__undo-btn {
		appearance: none;
		border: 0;
		background: transparent;
		color: var(--accent);
		font: inherit;
		font-weight: 650;
		font-size: 12.5px;
		cursor: pointer;
		padding: 2px 4px;
	}

	.library__section-label {
		flex: none;
		margin: 16px 10px 6px;
		font-size: 11px;
		font-weight: 500;
		letter-spacing: 0.01em;
		color: var(--placeholder);
	}

	.library__list {
		list-style: none;
		margin: 0;
		padding: 0 2px;
		overflow: auto;
		flex: 1 1 auto;
		min-height: 0;
	}

	.library__empty {
		padding: 20px 12px;
		color: var(--muted);
		font-size: 12.5px;
		text-align: center;
	}

	/* Use the accent only for the active document. */
	.library__item {
		display: flex;
		align-items: stretch;
		gap: 0;
		border-radius: 12px;
		margin-bottom: 1px;
	}

	.library__item.is-active {
		background: var(--accent-soft);
		box-shadow: none;
	}

	.library__open {
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 1px;
		padding: 9px 12px;
		border: 0;
		border-radius: 12px;
		background: transparent;
		color: var(--ink);
		text-align: left;
		font: inherit;
		cursor: pointer;
	}

	.library__open:hover {
		background: var(--rule-soft);
	}

	.library__item.is-active .library__open:hover {
		background: transparent;
	}

	.library__name {
		font-weight: 450;
		font-size: 13px;
		letter-spacing: -0.01em;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		width: 100%;
		color: var(--muted);
	}

	.library__item.is-active .library__name {
		font-weight: 550;
		color: var(--accent);
	}

	.library__meta {
		font-size: 11px;
		color: var(--muted);
		font-variant-numeric: tabular-nums;
	}

	.library__actions {
		display: flex;
		flex-direction: row;
		align-items: center;
		padding-right: 6px;
		opacity: 0;
		transition: opacity 0.12s ease;
	}

	.library__item:hover .library__actions,
	.library__item:focus-within .library__actions,
	.library__item.is-active .library__actions {
		opacity: 1;
	}

	.library__action {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 22px;
		height: 22px;
		padding: 0;
		border: 0;
		border-radius: 6px;
		background: transparent;
		color: var(--placeholder);
		cursor: pointer;
	}

	.library__action:hover {
		background: var(--rule-soft);
		color: var(--ink);
	}

	.library__action--danger:hover {
		background: var(--rule-soft);
		color: var(--danger);
	}

	.library__rename {
		flex: 1 1 auto;
		margin: 4px 8px;
		padding: 8px 12px;
		border: 0;
		border-radius: 8px;
		background: var(--bg-deep);
		box-shadow: 0 0 0 2px var(--accent-soft);
		font: inherit;
		font-weight: 600;
		font-size: 13px;
		color: var(--ink);
		outline: none;
	}

	.library__foot {
		flex: none;
		margin: 0;
		padding: 12px 10px 4px;
		font-size: 11px;
		color: var(--placeholder);
		text-align: center;
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		border: 0;
	}

	@media (prefers-reduced-motion: reduce) {
		.library__actions {
			transition: none;
		}
	}

	@media print {
		.library {
			display: none !important;
		}
	}
</style>
