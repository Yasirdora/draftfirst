/**
 * Canonical keyboard map for Writing Desk.
 * Single source of truth for the shortcuts overlay and documentation.
 *
 * Modifiers: ⌘ = Meta (Mac) / Ctrl (Windows & Linux) in labels; handlers use metaKey || ctrlKey.
 */

export interface ShortcutEntry {
	keys: string;
	action: string;
}

export interface ShortcutGroup {
	title: string;
	items: readonly ShortcutEntry[];
}

export const SHORTCUT_GROUPS: readonly ShortcutGroup[] = [
	{
		title: 'Format',
		items: [
			{ keys: '⌘ B', action: 'Bold' },
			{ keys: '⌘ I', action: 'Italic' },
			{ keys: '⌘ E', action: 'Inline code' },
			{ keys: '⌘ K', action: 'Link' },
			{ keys: '⌘ ⇧ X', action: 'Strikethrough' },
			{ keys: '⌘ ⇧ 7', action: 'Numbered list' },
			{ keys: '⌘ ⇧ 8', action: 'Bulleted list' },
			{ keys: '⌥ ⌘ 0–3', action: 'Paragraph / Heading 1–3' }
		]
	},
	{
		title: 'Structure',
		items: [
			{ keys: '/', action: 'Slash menu — insert heading, list, table, task…' },
			{ keys: '⌘ F', action: 'Find — highlights update as you type' },
			{ keys: 'Enter / ↓', action: 'Find: next match' },
			{ keys: '⇧ Enter / ↑', action: 'Find: previous match' },
			{ keys: 'Tab', action: 'Indent (Markdown) · next table cell (Page)' }
		]
	},
	{
		title: 'Views & focus',
		items: [
			{ keys: 'Esc', action: 'Leave focus mode · close menus · close panels' },
			{ keys: '?', action: 'Show keyboard shortcuts' },
			{
				keys: 'Versions',
				action: 'Status bar — review page rewrites vs trusted version (Restore / Keep)'
			}
		]
	},
	{
		title: 'Library & files',
		items: [
			{ keys: '☰', action: 'Show or hide the document library' },
			{ keys: 'Drop file', action: 'Import a .md file into the open document' },
			{ keys: 'Export', action: 'Markdown, standalone HTML, or print to PDF' }
		]
	}
] as const;
