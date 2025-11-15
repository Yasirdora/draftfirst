<script lang="ts">
	/**
	 * Local document library — calm sidebar, zero network.
	 */
	import type { LibraryDocument, LibrarySearchHit, TrashBin } from '$lib/library/types';
	import { formatRelativeTime } from '$lib/library/library';

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
				<h2 class="library__title">Library</h2>
				<button
					type="button"
					class="btn btn-quiet library__icon-btn"
					title="Close library"
					aria-label="Close library"
					onclick={onClose}
				>
					✕
				</button>
			</div>
			<button type="button" class="btn btn-primary library__new" onclick={onNew}>
				New document
			</button>
			<label class="library__search">
				<span class="visually-hidden">Search library</span>
				<input
					type="search"
					placeholder="Search titles & text…"
					autocomplete="off"
					spellcheck="false"
					bind:value={query}
					oninput={() => onQueryChange?.(query)}
				/>
			</label>
		</header>

		{#if trash && trash.expiresAt > Date.now()}
			<div class="library__undo" role="status">
				<span>Document deleted.</span>
				<button type="button" class="btn btn-quiet" onclick={onUndo}>Undo</button>
			</div>
		{/if}

		<ul class="library__list">
			{#if hits.length === 0}
				<li class="library__empty">
					{query.trim() ? 'No matching documents.' : 'No documents yet.'}
				</li>
			{:else}
				{#each hits as hit (hit.doc.id)}
					{@const doc = hit.doc}
					<li>
						<div
							class="library__item"
							class:is-active={doc.id === activeId}
						>
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
										✎
									</button>
									<button
										type="button"
										class="library__action"
										title="Delete"
										aria-label="Delete {doc.title}"
										onclick={(e) => {
											e.stopPropagation();
											onDelete?.(doc.id);
										}}
									>
										⌫
									</button>
								</div>
							{/if}
						</div>
					</li>
				{/each}
			{/if}
		</ul>

		<p class="library__foot">Stored only in this browser</p>
	</aside>
{/if}

<style>
	.library {
		flex: none;
		width: min(260px, 86vw);
		display: flex;
		flex-direction: column;
		min-height: 0;
		background: var(--panel);
		border-right: 1px solid var(--rule);
		z-index: 8;
	}

	.library__head {
		flex: none;
		padding: 12px 12px 10px;
		display: flex;
		flex-direction: column;
		gap: 8px;
		border-bottom: 1px solid var(--rule-soft);
	}

	.library__title-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
	}

	.library__title {
		margin: 0;
		font-size: 12px;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--muted);
	}

	.library__icon-btn {
		min-width: 28px;
		padding: 4px 8px;
		font-size: 12px;
	}

	.library__new {
		justify-content: center;
		width: 100%;
	}

	.library__search input {
		width: 100%;
		padding: 7px 10px;
		border: 1px solid var(--rule);
		border-radius: 8px;
		background: var(--panel-2);
		outline: none;
	}

	.library__search input:focus {
		border-color: var(--accent);
		box-shadow: 0 0 0 2px var(--accent-soft);
	}

	.library__undo {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		padding: 8px 12px;
		background: var(--accent-soft);
		font-size: 12.5px;
		color: var(--ink);
	}

	.library__list {
		list-style: none;
		margin: 0;
		padding: 6px;
		overflow: auto;
		flex: 1 1 auto;
		min-height: 0;
	}

	.library__empty {
		padding: 16px 10px;
		color: var(--muted);
		font-size: 13px;
		text-align: center;
	}

	.library__item {
		display: flex;
		align-items: stretch;
		gap: 2px;
		border-radius: 9px;
		margin-bottom: 2px;
	}

	.library__item.is-active {
		background: var(--accent-soft);
	}

	.library__open {
		flex: 1 1 auto;
		min-width: 0;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		padding: 8px 10px;
		border: 0;
		border-radius: 9px;
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
		font-weight: 600;
		font-size: 13px;
		letter-spacing: -0.01em;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		width: 100%;
	}

	.library__meta {
		font-size: 11px;
		color: var(--muted);
		font-variant-numeric: tabular-nums;
	}

	.library__actions {
		display: flex;
		flex-direction: column;
		justify-content: center;
		padding: 2px 2px 2px 0;
		opacity: 0;
		transition: opacity 0.12s ease;
	}

	.library__item:hover .library__actions,
	.library__item:focus-within .library__actions,
	.library__item.is-active .library__actions {
		opacity: 1;
	}

	.library__action {
		width: 26px;
		height: 26px;
		padding: 0;
		border: 0;
		border-radius: 6px;
		background: transparent;
		color: var(--muted);
		font-size: 12px;
		cursor: pointer;
	}

	.library__action:hover {
		background: var(--panel);
		color: var(--ink);
	}

	.library__rename {
		flex: 1 1 auto;
		margin: 4px;
		padding: 6px 8px;
		border: 1px solid var(--accent);
		border-radius: 7px;
		background: var(--panel);
		font: inherit;
		font-weight: 600;
		font-size: 13px;
		outline: none;
	}

	.library__foot {
		flex: none;
		margin: 0;
		padding: 10px 12px 12px;
		border-top: 1px solid var(--rule-soft);
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
