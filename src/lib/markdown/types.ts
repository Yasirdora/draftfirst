/**
 * Shared types for Writing Desk markdown + app state.
 */

/** Editor view modes: page = typeset edit, source = markdown, split = both, read = typeset, hands off. */
export type ViewMode = 'page' | 'split' | 'source' | 'read';

/** Persisted application state (localStorage only — never leaves the browser). */
export interface AppState {
	doc: string;
	view: ViewMode;
	focus: boolean;
}

/** Heading entry from the document outline. */
export interface OutlineHeading {
	level: number;
	text: string;
	line: number;
}

/** Result of an EDIT-CORE transform: new source + selection. */
export interface FormatResult {
	text: string;
	start: number;
	end: number;
}

/** Inline marks present at the caret / selection. */
export interface InlineMarks {
	bold: boolean;
	italic: boolean;
	strike: boolean;
	code: boolean;
	link: boolean;
}
