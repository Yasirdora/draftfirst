/**
 * Toolbar style catalogue and insert snippets.
 *
 * Two labels per style: the compact token on the toolbar button, and the full
 * name in the menu (with the token beside it so the pairing is obvious).
 */

export const STYLES = [
	{ kind: 'paragraph', token: 'Aa', label: 'Normal text', menu: '', hint: '⌥⌘0' },
	{ kind: 'h1', token: 'H1', label: 'Heading 1', menu: 'as-h1', hint: '⌥⌘1' },
	{ kind: 'h2', token: 'H2', label: 'Heading 2', menu: 'as-h2', hint: '⌥⌘2' },
	{ kind: 'h3', token: 'H3', label: 'Heading 3', menu: 'as-h3', hint: '⌥⌘3' }
] as const;

/** Blocks the style menu does not offer still need something to show. */
export const OTHER_TOKENS: Record<string, string> = {
	quote: '❝',
	code: '`',
	h4: 'H4',
	h5: 'H5',
	h6: 'H6'
};

export const OTHER_NAMES: Record<string, string> = {
	quote: 'Quote',
	code: 'Code block',
	h4: 'Heading 4',
	h5: 'Heading 5',
	h6: 'Heading 6'
};

export const SNIPPETS: Record<string, { text: string; caret?: number }> = {
	codeblock: { text: '```\n\n```', caret: 4 },
	table: { text: '| Column | Column |\n| --- | --- |\n|  |  |', caret: 2 },
	rule: { text: '---' },
	image: { text: '![description](https://)', caret: 2 }
};

/** Map style kinds to contenteditable formatBlock tags. */
export const BLOCK_FOR: Record<string, string> = {
	paragraph: 'p',
	h1: 'h1',
	h2: 'h2',
	h3: 'h3',
	quote: 'blockquote',
	code: 'pre'
};

/** Viewport width below which split view becomes unusable. */
export const NARROW = 720;
