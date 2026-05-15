<script module lang="ts">
	/**
	 * Icon registry — every glyph in Writing Desk lives here.
	 *
	 * One 24-grid, one stroke (1.7), round caps and joins, currentColor:
	 * nothing can drift. Core set ported from the writedown project; the
	 * second block was drawn for this app on the same grid and in the same
	 * hand. Add a glyph here or don't add it at all.
	 */
	const paths = {
		bold: '<path d="M6.5 4.5h5.5a3.25 3.25 0 0 1 0 6.5H6.5zM6.5 11h6.5a3.25 3.25 0 0 1 0 6.5H6.5z"/>',
		italic: '<path d="M10 4.5h8M6 19.5h8M14 4.5l-4 15"/>',
		strike:
			'<path d="M4 12h16M15.5 4.5h-6a3 3 0 0 0-.8 5.9M8.5 19.5h6a3 3 0 0 0 .8-5.9"/>',
		code: '<path d="m8.5 7-5.5 5 5.5 5M15.5 7l5.5 5-5.5 5"/>',
		link: '<path d="M10 13.6a4.2 4.2 0 0 0 6 .3l2.8-2.8a4.24 4.24 0 0 0-6-6L11.3 6.6M14 10.4a4.2 4.2 0 0 0-6-.3l-2.8 2.8a4.24 4.24 0 0 0 6 6l1.5-1.5"/>',
		image: '<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="m3.5 15.5 4.7-4.7 4.6 4.6M12.8 14.4l2.4-2.4 4.3 4.3M15.4 8.6h.01"/>',
		quote: '<path d="M6.5 7.5h4v4c0 3-1.4 4.8-4 5.8M13.5 7.5h4v4c0 3-1.4 4.8-4 5.8"/>',
		list: '<path d="M9.5 6h10.5M9.5 12h10.5M9.5 18h10.5M4.5 6h.01M4.5 12h.01M4.5 18h.01"/>',
		ordered:
			'<path d="M10.5 6H20M10.5 12H20M10.5 18H20M4.2 5.2 5.6 4.2V9M4.2 9h2.8M4.2 12.6c.1-.7.7-1.1 1.4-1.1.8 0 1.4.6 1.4 1.3C7 14 4.2 15 4.2 16.5H7M4.5 18.2c.4-.2 1.1-.3 1.5 0 .5.3.8.8.7 1.4-.1.8-.9 1.4-1.9 1.4-.5 0-1-.2-1.3-.5"/>',
		task: '<path d="M10 6h10M10 12h10M10 18h10M3.5 6l1.2 1.2L7 4.8M3.5 12l1.2 1.2L7 10.8M3.5 18l1.2 1.2L7 16.8"/>',
		table: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M3.5 9.5h17M3.5 14.5h17M9.3 4.5v15M14.7 4.5v15"/>',
		math: '<path d="M18 5H8.5l5.5 7-5.5 7H18"/>',
		codeblock:
			'<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="m9 9.5-2.5 2.5L9 14.5M15 9.5l2.5 2.5-2.5 2.5"/>',
		focus: '<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="3"/>',
		sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2.8v2M12 19.2v2M5 5l1.4 1.4M17.6 17.6 19 19M2.8 12h2M19.2 12h2M5 19l1.4-1.4M17.6 6.4 19 5"/>',
		moon: '<path d="M20 13.6A8.1 8.1 0 0 1 10.4 4 8.1 8.1 0 1 0 20 13.6z"/>',
		auto: '<circle cx="12" cy="12" r="8.5"/><path d="M12 5a7 7 0 0 1 0 14z" fill="currentColor" stroke="none"/>',
		more: '<path d="M5.5 12h.01M12 12h.01M18.5 12h.01" stroke-width="2.6"/>',
		plus: '<path d="M12 5v14M5 12h14"/>',
		search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
		close: '<path d="M6 6l12 12M18 6 6 18"/>',
		download: '<path d="M12 4v10.5M12 14.5 7.8 10.3M12 14.5l4.2-4.2M4.5 19.5h15"/>',
		folder: '<path d="M3.5 6.5A1.5 1.5 0 0 1 5 5h4l2 2.5h8A1.5 1.5 0 0 1 20.5 9v8a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 17z"/>',
		sidebar: '<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="M9.5 4.5v15"/>',
		sparkles:
			'<path d="M12 4.5 13.6 8.7 17.8 10.3 13.6 11.9 12 16.1 10.4 11.9 6.2 10.3 10.4 8.7zM18.5 15.2l.7 1.9 1.9.7-1.9.7-.7 1.9-.7-1.9-1.9-.7 1.9-.7z"/>',
		trash: '<path d="M4.5 6.5h15M9.5 6.5v-2h5v2M6.5 6.5l.9 12.5a1.5 1.5 0 0 0 1.5 1.4h6.2a1.5 1.5 0 0 0 1.5-1.4l.9-12.5M10 10.5v6M14 10.5v6"/>',
		print: '<path d="M7 8V4h10v4M7 16.5H4.5v-7A1.5 1.5 0 0 1 6 8h12a1.5 1.5 0 0 1 1.5 1.5v7H17M7 14h10v6H7zM17.5 10.5h.01"/>',
		globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.3 3.8 5.2 3.8 8.5s-1.3 6.2-3.8 8.5c-2.5-2.3-3.8-5.2-3.8-8.5s1.3-6.2 3.8-8.5z"/>',

		/* Writing Desk additions — same grid, same hand */
		page: '<rect x="5.5" y="3.5" width="13" height="17" rx="2"/><path d="M9 8.5h6M9 12h6M9 15.5h3.5"/>',
		split: '<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="M12 4.5v15"/>',
		read: '<path d="M2.5 5.5C4 4.9 5.7 4.6 7.5 4.6c1.9 0 3.4.5 4.5 1.4 1.1-.9 2.6-1.4 4.5-1.4 1.8 0 3.5.3 5 .9v13.2c-1.5-.6-3.2-.9-5-.9-1.9 0-3.4.5-4.5 1.4-1.1-.9-2.6-1.4-4.5-1.4-1.8 0-3.5.3-5 .9z"/><path d="M12 6v13.2"/>',
		question:
			'<circle cx="12" cy="12" r="8.5"/><path d="M9.6 9.3a2.5 2.5 0 1 1 3.4 2.3c-.8.4-1.2.9-1.2 1.7v.2"/><path d="M12 17h.01"/>',
		outline: '<path d="M4 6h16M7.5 12H20M11 18h9"/>',
		tick: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
		restore: '<path d="M4.5 10a7.5 7.5 0 1 1 .6 5.8"/><path d="M4.5 4.8V10h5.2"/>',
		'chevron-down': '<path d="m6.5 9.5 5.5 5.5 5.5-5.5"/>'
	} as const;

	export type IconName = keyof typeof paths;
</script>

<script lang="ts">
	let { name, size = 16 }: { name: IconName; size?: number } = $props();
</script>

<svg
	viewBox="0 0 24 24"
	width={size}
	height={size}
	fill="none"
	stroke="currentColor"
	stroke-width="1.7"
	stroke-linecap="round"
	stroke-linejoin="round"
	aria-hidden="true"
>
	{@html paths[name]}
</svg>
