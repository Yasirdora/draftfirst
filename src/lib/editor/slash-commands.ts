/**
 * Slash command catalogue — progressive structure insertion.
 * Trigger: `/` at line start (Markdown) or empty page block.
 * Each command maps to existing command()/snippet paths for one bus.
 */

export type SlashAction =
	| { type: 'command'; name: string; argument?: string }
	| { type: 'snippet'; id: string };

export interface SlashCommand {
	id: string;
	/** Primary label */
	label: string;
	/** Keywords for filter (includes aliases) */
	keywords: string;
	/** Short hint in the palette */
	hint: string;
	action: SlashAction;
}

export const SLASH_COMMANDS: readonly SlashCommand[] = [
	{
		id: 'h1',
		label: 'Heading 1',
		keywords: 'h1 heading title',
		hint: '#',
		action: { type: 'command', name: 'style', argument: 'h1' }
	},
	{
		id: 'h2',
		label: 'Heading 2',
		keywords: 'h2 heading section',
		hint: '##',
		action: { type: 'command', name: 'style', argument: 'h2' }
	},
	{
		id: 'h3',
		label: 'Heading 3',
		keywords: 'h3 heading',
		hint: '###',
		action: { type: 'command', name: 'style', argument: 'h3' }
	},
	{
		id: 'ul',
		label: 'Bulleted list',
		keywords: 'ul bullet list unordered',
		hint: '-',
		action: { type: 'command', name: 'ul' }
	},
	{
		id: 'ol',
		label: 'Numbered list',
		keywords: 'ol numbered ordered list',
		hint: '1.',
		action: { type: 'command', name: 'ol' }
	},
	{
		id: 'task',
		label: 'Task list',
		keywords: 'task todo checkbox checklist',
		hint: '- [ ]',
		action: { type: 'command', name: 'task' }
	},
	{
		id: 'quote',
		label: 'Quote',
		keywords: 'quote blockquote cite',
		hint: '>',
		action: { type: 'command', name: 'quote' }
	},
	{
		id: 'codeblock',
		label: 'Code block',
		keywords: 'code fence pre',
		hint: '```',
		action: { type: 'snippet', id: 'codeblock' }
	},
	{
		id: 'table',
		label: 'Table',
		keywords: 'table grid columns',
		hint: '2×2',
		action: { type: 'snippet', id: 'table' }
	},
	{
		id: 'table3',
		label: 'Table (3 columns)',
		keywords: 'table three grid',
		hint: '3×2',
		action: { type: 'snippet', id: 'table3' }
	},
	{
		id: 'rule',
		label: 'Divider',
		keywords: 'rule hr divider line',
		hint: '---',
		action: { type: 'snippet', id: 'rule' }
	},
	{
		id: 'image',
		label: 'Image',
		keywords: 'image img picture photo',
		hint: '![]()',
		action: { type: 'snippet', id: 'image' }
	},
	{
		id: 'link',
		label: 'Link',
		keywords: 'link url href',
		hint: '⌘K',
		action: { type: 'command', name: 'link' }
	}
] as const;

/** Filter and rank commands by query (after the leading `/`). */
export function filterSlashCommands(query: string): SlashCommand[] {
	const q = query.trim().toLowerCase();
	if (!q) return [...SLASH_COMMANDS];

	return SLASH_COMMANDS.filter((cmd) => {
		const hay = `${cmd.id} ${cmd.label} ${cmd.keywords} ${cmd.hint}`.toLowerCase();
		return hay.includes(q) || q.split(/\s+/).every((part) => hay.includes(part));
	});
}

/**
 * Detect an open slash query in a textarea: `/` at line start (optional indent)
 * followed by the filter text up to the caret. Returns null if not in a slash gesture.
 */
export function detectSlashQuery(
	text: string,
	caret: number
): { start: number; query: string } | null {
	if (caret < 1) return null;
	const lineStart = text.lastIndexOf('\n', caret - 1) + 1;
	const before = text.slice(lineStart, caret);
	// Allow optional indent, then `/`, then query without spaces (or with for multi-word filter)
	// `/` must be the first non-whitespace character on the line (not mid-URL).
	const match = /^([ \t]*)\/([^\n]*)$/.exec(before);
	if (!match) return null;
	return {
		start: lineStart + match[1].length,
		query: match[2]
	};
}
