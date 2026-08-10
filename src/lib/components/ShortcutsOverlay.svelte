<script lang="ts">
	/**
	 * Keyboard shortcuts panel — progressive disclosure of power.
	 * Opened with ? · closed with Escape or backdrop click.
	 * Focus is trapped on the dialog while open for accessibility.
	 */
	import { SHORTCUT_GROUPS } from '$lib/editor/shortcuts';

	let {
		open = $bindable(false)
	}: {
		open?: boolean;
	} = $props();

	let panelEl: HTMLDivElement | undefined = $state();
	let closeBtn: HTMLButtonElement | undefined = $state();

	$effect(() => {
		if (!open) return;
		const previous = document.activeElement as HTMLElement | null;
		// Defer so the panel is in the DOM
		queueMicrotask(() => closeBtn?.focus());

		const onKey = (event: KeyboardEvent) => {
			if (event.key === 'Escape') {
				event.preventDefault();
				event.stopPropagation();
				open = false;
			}
		};
		document.addEventListener('keydown', onKey, true);

		return () => {
			document.removeEventListener('keydown', onKey, true);
			previous?.focus?.();
		};
	});

	function backdropClose(event: MouseEvent) {
		if (event.target === event.currentTarget) open = false;
	}
</script>

{#if open}
	<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
	<div
		class="shortcuts-backdrop"
		role="presentation"
		onclick={backdropClose}
	>
		<div
			class="shortcuts-panel"
			bind:this={panelEl}
			role="dialog"
			aria-modal="true"
			aria-labelledby="shortcuts-title"
		>
			<header class="shortcuts-header">
				<div>
					<h2 id="shortcuts-title">Keyboard shortcuts</h2>
					<p class="shortcuts-sub">
						⌘ is Control on Windows and Linux. Formatting shortcuts apply in Markdown view;
						the page surface also accepts standard system editing commands.
					</p>
				</div>
				<button
					type="button"
					class="btn btn-quiet shortcuts-close"
					bind:this={closeBtn}
					aria-label="Close shortcuts"
					onclick={() => (open = false)}
				>
					Esc
				</button>
			</header>

			<div class="shortcuts-grid">
				{#each SHORTCUT_GROUPS as group (group.title)}
					<section class="shortcuts-group" aria-labelledby="sg-{group.title}">
						<h3 id="sg-{group.title}">{group.title}</h3>
						<ul>
							{#each group.items as item (item.keys + item.action)}
								<li>
									<kbd>{item.keys}</kbd>
									<span>{item.action}</span>
								</li>
							{/each}
						</ul>
					</section>
				{/each}
			</div>

			<p class="shortcuts-foot">
				Nothing leaves your browser. Documents stay in this device until you export.
			</p>
		</div>
	</div>
{/if}

<style>
	.shortcuts-backdrop {
		position: fixed;
		inset: 0;
		z-index: 50;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 24px 16px;
		background: rgba(16, 24, 32, 0.42);
		backdrop-filter: blur(6px);
		-webkit-backdrop-filter: blur(6px);
		animation: fade-in 0.16s ease;
	}

	.shortcuts-panel {
		width: min(560px, 100%);
		max-height: min(82vh, 720px);
		overflow: auto;
		padding: 22px 24px 18px;
		border-radius: 14px;
		border: 1px solid var(--rule);
		background: var(--panel);
		color: var(--ink);
		box-shadow:
			0 1px 2px rgba(16, 24, 32, 0.08),
			0 24px 64px rgba(16, 24, 32, 0.28);
		animation: rise-panel 0.2s cubic-bezier(0.2, 0.9, 0.3, 1);
	}

	.shortcuts-header {
		display: flex;
		align-items: flex-start;
		gap: 16px;
		margin-bottom: 18px;
	}

	.shortcuts-header h2 {
		margin: 0 0 6px;
		font-size: 1.15rem;
		font-weight: 700;
		letter-spacing: -0.02em;
	}

	.shortcuts-sub {
		margin: 0;
		color: var(--muted);
		font-size: 12.5px;
		line-height: 1.45;
		max-width: 36em;
	}

	.shortcuts-close {
		flex: none;
		font-variant-numeric: tabular-nums;
		font-size: 12px;
	}

	.shortcuts-grid {
		display: grid;
		gap: 18px;
	}

	.shortcuts-group h3 {
		margin: 0 0 8px;
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--muted);
	}

	.shortcuts-group ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		gap: 6px;
	}

	.shortcuts-group li {
		display: grid;
		grid-template-columns: minmax(7.5rem, auto) 1fr;
		gap: 12px;
		align-items: baseline;
		padding: 6px 8px;
		border-radius: 8px;
	}

	.shortcuts-group li:hover {
		background: var(--rule-soft);
	}

	.shortcuts-group kbd {
		font-family: var(--font-ui);
		font-size: 12px;
		font-weight: 600;
		color: var(--ink);
		background: var(--rule-soft);
		border: 1px solid var(--rule);
		border-radius: 6px;
		padding: 3px 7px;
		white-space: nowrap;
		box-shadow: 0 1px 0 rgba(16, 24, 32, 0.06);
	}

	.shortcuts-group span {
		font-size: 13px;
		color: var(--ink);
	}

	.shortcuts-foot {
		margin: 18px 0 0;
		padding-top: 14px;
		border-top: 1px solid var(--rule-soft);
		color: var(--muted);
		font-size: 12px;
		line-height: 1.4;
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
		to {
			opacity: 1;
		}
	}

	@keyframes rise-panel {
		from {
			opacity: 0;
			transform: translateY(8px) scale(0.98);
		}
		to {
			opacity: 1;
			transform: none;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.shortcuts-backdrop,
		.shortcuts-panel {
			animation: none;
		}
	}

	@media (max-width: 480px) {
		.shortcuts-group li {
			grid-template-columns: 1fr;
			gap: 4px;
		}
	}
</style>
