/**
 * One line icon per Help Center topic, keyed by category id — drawn by the
 * Help Center home and by each topic's own page, so a topic looks the same
 * wherever it appears.
 *
 * Thin, geometric glyphs in the SF Symbols manner: one stroke weight, round
 * caps, as little detail as the metaphor allows. Each is a single path in a
 * 24 × 24 box, stroked by the page that draws it.
 */
export const topicIcons: Record<string, string> = {
	'getting-started': 'M13 2.5L6 13.5h4.8L9.5 21.5l7.5-11h-4.8l.8-8z',
	writing:
		'M4.5 19.5l.7-3.4L16.4 4.9a1.9 1.9 0 0 1 2.7 0l0 0a1.9 1.9 0 0 1 0 2.7L7.9 18.8l-3.4.7zM14.6 6.7l2.7 2.7',
	notes: 'M5 4.5h14a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1-1.5 1.5h-7.8L6.5 20v-3.5H5A1.5 1.5 0 0 1 3.5 15V6A1.5 1.5 0 0 1 5 4.5zM8 9h8M8 12.5h5',
	scenes:
		'M3.5 8.5h17v9a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2v-9zM4.3 8.5L6.2 4h13.6l-1.9 4.5',
	pages: 'M6.5 3.5h7.5l4 4v13h-11.5v-17zM14 3.5v4h4',
	files: 'M3.5 7a2 2 0 0 1 2-2h3.8l2 2h7.7a2 2 0 0 1 2 2v8.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2V7z',
	export: 'M5 12.5V18a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-5.5M12 3.5v10.5M8.2 7L12 3.2 15.8 7',
	support:
		'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM9.7 9.3a2.4 2.4 0 0 1 4.7.7c0 1.6-2.4 2-2.4 3.4M12 16.8h.01'
};
