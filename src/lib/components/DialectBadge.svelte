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
		gap: 4px;
		padding: 1px 6px 1px 5px;
		border-radius: 999px;
		border: 0;
		background: var(--rule-soft);
		color: var(--muted);
		font-size: 10.5px;
		font-weight: 550;
		letter-spacing: 0.01em;
		white-space: nowrap;
		cursor: help;
		user-select: none;
		line-height: 1.3;
	}

	.dialect-badge__dot {
		width: 5px;
		height: 5px;
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
