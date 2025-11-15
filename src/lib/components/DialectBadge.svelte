<script lang="ts">
	/**
	 * Visible dialect contract — honesty about what this desk understands.
	 */
	import { CORE_DIALECT } from '$lib/editor/dialect';

	let {
		compact = false
	}: {
		/** Shorter label on very narrow layouts */
		compact?: boolean;
	} = $props();

	const title = [
		CORE_DIALECT.summary,
		'',
		...CORE_DIALECT.features.map((f) => `· ${f}`)
	].join('\n');
</script>

<span class="dialect-badge" {title} role="status">
	<span class="dialect-badge__dot" aria-hidden="true"></span>
	<span class="dialect-badge__label">
		{compact ? 'GFM' : CORE_DIALECT.label}
	</span>
</span>

<style>
	.dialect-badge {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 2px 8px 2px 6px;
		border-radius: 999px;
		border: 1px solid var(--rule);
		background: var(--rule-soft);
		color: var(--muted);
		font-size: 11.5px;
		font-weight: 550;
		letter-spacing: 0.01em;
		white-space: nowrap;
		cursor: help;
		user-select: none;
	}

	.dialect-badge__dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--accent);
		flex: none;
	}

	.dialect-badge__label {
		max-width: 14rem;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	@media (max-width: 520px) {
		.dialect-badge__label {
			max-width: 4.5rem;
		}
	}
</style>
