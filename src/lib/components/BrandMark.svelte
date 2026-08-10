<script lang="ts">
	/**
	 * Writing Desk mark — pencil on rounded square.
	 * Decorative by default; parent provides adjacent text for accessibility.
	 */
	let { size = 26 }: { size?: number } = $props();
</script>

<svg
	class="brand-mark"
	viewBox="0 0 32 32"
	width={size}
	height={size}
	aria-hidden="true"
	focusable="false"
>
	<rect width="32" height="32" rx="7" fill="var(--accent)"></rect>
	<path
		d="M8 24l1.5-5L20 8.5a2.1 2.1 0 013 3L12.5 22z"
		fill="none"
		stroke="var(--on-accent)"
		stroke-width="2.2"
		stroke-linejoin="round"
	></path>
	<path
		d="M8 24h16"
		stroke="var(--on-accent)"
		stroke-width="2.2"
		stroke-linecap="round"
	></path>
</svg>
