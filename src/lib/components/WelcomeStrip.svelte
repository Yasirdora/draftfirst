<script lang="ts">
	/**
	 * First-run calm strip — one dismissible moment of orientation.
	 * Never blocks writing; never returns after dismiss.
	 */
	let {
		visible = $bindable(false),
		onOpenShortcuts,
		onDismiss
	}: {
		visible?: boolean;
		onOpenShortcuts?: () => void;
		onDismiss?: () => void;
	} = $props();

	function dismiss() {
		visible = false;
		onDismiss?.();
	}
</script>

{#if visible}
	<div class="welcome" role="region" aria-label="Welcome to Writing Desk">
		<div class="welcome__copy">
			<strong>Write on the page.</strong>
			<span>
				Markdown stays underneath — switch views anytime. Press
				<button type="button" class="welcome__link" onclick={onOpenShortcuts}>?</button>
				for shortcuts. Nothing leaves this browser.
			</span>
		</div>
		<button type="button" class="btn btn-quiet welcome__dismiss" onclick={dismiss}>
			Got it
		</button>
	</div>
{/if}

<style>
	.welcome {
		flex: none;
		display: flex;
		align-items: center;
		gap: 12px;
		flex-wrap: wrap;
		padding: 10px 16px;
		background: var(--accent-soft);
		border-bottom: 1px solid var(--rule);
		color: var(--ink);
		font-size: 13px;
		line-height: 1.45;
		animation: welcome-in 0.28s ease;
	}

	.welcome__copy {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 6px 10px;
		flex: 1 1 16rem;
		min-width: 0;
	}

	.welcome__copy strong {
		font-weight: 650;
		letter-spacing: -0.01em;
	}

	.welcome__copy span {
		color: var(--muted);
	}

	.welcome__link {
		display: inline;
		padding: 0 5px;
		margin: 0 1px;
		border: 1px solid var(--rule);
		border-radius: 5px;
		background: var(--panel);
		color: var(--ink);
		font: inherit;
		font-weight: 650;
		font-size: 12px;
		line-height: 1.4;
		cursor: pointer;
	}

	.welcome__link:hover {
		border-color: var(--accent);
		color: var(--accent);
	}

	.welcome__dismiss {
		flex: none;
		font-weight: 600;
	}

	@keyframes welcome-in {
		from {
			opacity: 0;
			transform: translateY(-4px);
		}
		to {
			opacity: 1;
			transform: none;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.welcome {
			animation: none;
		}
	}

	@media print {
		.welcome {
			display: none !important;
		}
	}
</style>
