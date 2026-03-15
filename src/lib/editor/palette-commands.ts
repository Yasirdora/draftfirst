/**
 * Command palette catalogue — every action, fuzzy-findable under ⌘K.
 *
 * One command bus: insert entries are derived from the slash catalogue so the
 * two palettes can never drift; app actions are dispatched by the editor shell.
 * Pure and Node-testable — no DOM, no Svelte.
 */

import { SLASH_COMMANDS, type SlashCommand } from './slash-commands';

export type PaletteAction =
	| { type: 'app'; name: string }
	| { type: 'slash'; command: SlashCommand };

export type PaletteGroup = 'Document' | 'View' | 'Insert' | 'Tools';

export interface PaletteCommand {
	id: string;
	group: PaletteGroup;
	label: string;
	keywords: string;
	/** Right-aligned shortcut / affordance hint */
	hint?: string;
	action: PaletteAction;
}

const APP_COMMANDS: readonly PaletteCommand[] = [
	{
		id: 'new',
		group: 'Document',
		label: 'New document',
		keywords: 'create fresh note blank',
		action: { type: 'app', name: 'new' }
	},
	{
		id: 'open',
		group: 'Document',
		label: 'Open / import a .md file…',
		keywords: 'open import file markdown load',
		action: { type: 'app', name: 'open' }
	},
	{
		id: 'export-md',
		group: 'Document',
		label: 'Export as Markdown',
		keywords: 'download save md file',
		hint: '.md',
		action: { type: 'app', name: 'export-md' }
	},
	{
		id: 'export-html',
		group: 'Document',
		label: 'Export as standalone HTML',
		keywords: 'download save html web page offline',
		hint: '.html',
		action: { type: 'app', name: 'export-html' }
	},
	{
		id: 'export-print',
		group: 'Document',
		label: 'Print / save as PDF',
		keywords: 'print pdf paper publish',
		action: { type: 'app', name: 'export-print' }
	},
	{
		id: 'delete',
		group: 'Document',
		label: 'Delete current document…',
		keywords: 'remove trash note undo',
		action: { type: 'app', name: 'delete' }
	},
	{
		id: 'clear',
		group: 'Document',
		label: 'Clear the desk…',
		keywords: 'erase empty reset content',
		action: { type: 'app', name: 'clear' }
	},

	{
		id: 'view-page',
		group: 'View',
		label: 'Page view',
		keywords: 'wysiwyg typeset writing surface',
		action: { type: 'app', name: 'view-page' }
	},
	{
		id: 'view-split',
		group: 'View',
		label: 'Split view',
		keywords: 'side by side source and page',
		action: { type: 'app', name: 'view-split' }
	},
	{
		id: 'view-source',
		group: 'View',
		label: 'Markdown view',
		keywords: 'source raw text plain',
		action: { type: 'app', name: 'view-source' }
	},
	{
		id: 'toggle-library',
		group: 'View',
		label: 'Show or hide the library',
		keywords: 'sidebar documents notes panel',
		action: { type: 'app', name: 'toggle-library' }
	},
	{
		id: 'toggle-focus',
		group: 'View',
		label: 'Toggle focus mode',
		keywords: 'dim concentrate zen calm',
		action: { type: 'app', name: 'toggle-focus' }
	},

	{
		id: 'find',
		group: 'Tools',
		label: 'Find in document',
		keywords: 'search locate text match',
		hint: '⌘F',
		action: { type: 'app', name: 'find' }
	},
	{
		id: 'toggle-truth',
		group: 'Tools',
		label: 'Toggle Versions (truth review)',
		keywords: 'versions truth fidelity restore review baseline',
		action: { type: 'app', name: 'toggle-truth' }
	},
	{
		id: 'shortcuts',
		group: 'Tools',
		label: 'Keyboard shortcuts',
		keywords: 'help keys cheatsheet hotkeys',
		hint: '?',
		action: { type: 'app', name: 'shortcuts' }
	}
] as const;

/** Insert group mirrors the slash catalogue — same bus, same snippets. */
const INSERT_COMMANDS: readonly PaletteCommand[] = SLASH_COMMANDS.map((command) => ({
	id: 'insert-' + command.id,
	group: 'Insert' as const,
	label: command.label,
	keywords: command.keywords,
	hint: command.hint,
	action: { type: 'slash' as const, command }
}));

export const PALETTE_COMMANDS: readonly PaletteCommand[] = [...APP_COMMANDS, ...INSERT_COMMANDS];

/**
 * Filter by query across id, group, label, keywords, and hint.
 * A full substring wins; otherwise every whitespace-separated part must match.
 */
export function filterPaletteCommands(query: string): PaletteCommand[] {
	const q = query.trim().toLowerCase();
	if (!q) return [...PALETTE_COMMANDS];
	return PALETTE_COMMANDS.filter((cmd) => {
		const hay = `${cmd.id} ${cmd.group} ${cmd.label} ${cmd.keywords} ${cmd.hint ?? ''}`.toLowerCase();
		return hay.includes(q) || q.split(/\s+/).every((part) => hay.includes(part));
	});
}
