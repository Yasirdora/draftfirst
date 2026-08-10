/**
 * Draft First Screenwriting Engine document model.
 *
 * A screenplay consists of a title page and a typed element stream shared by
 * the Fountain, FDX, pagination, and analysis modules.
 */

/** Printing element types, mirroring Fountain + FDX paragraph types. */
export type ElementType =
	| 'scene'
	| 'action'
	| 'character'
	| 'dialogue'
	| 'parenthetical'
	| 'transition'
	| 'shot'
	| 'general'
	| 'centered'
	| 'lyrics';

/** Non-printing structural types (kept in the model, skipped by the paginator). */
export type StructuralType = 'note' | 'section' | 'synopsis' | 'pagebreak';

export type AnyElementType = ElementType | StructuralType;

const PRINTING_TYPES: ReadonlySet<string> = new Set<ElementType>([
	'scene',
	'action',
	'character',
	'dialogue',
	'parenthetical',
	'transition',
	'shot',
	'general',
	'centered',
	'lyrics'
]);

export interface ScreenplayElement {
	type: AnyElementType;
	/** Plain text of the element. Emphasis markers are preserved raw for now. */
	text: string;
	/** Dual-dialogue marker — character cue ending in `^` (Fountain). */
	dual?: boolean;
	/** Assigned scene number, e.g. "12" or "A12" (production scripts). */
	sceneNumber?: string;
	/** Outline depth for sections (# = 1, ## = 2…). */
	depth?: number;
}

/** One title-page field: `Title: My Script` → { key: 'Title', values: ['My Script'] }. */
export interface TitlePageEntry {
	key: string;
	values: string[];
}

export interface Screenplay {
	titlePage: TitlePageEntry[];
	elements: ScreenplayElement[];
}

/** Element types that carry spoken dialogue blocks (cue → parenthetical? → dialogue+). */
export const DIALOGUE_FLOW: ReadonlySet<AnyElementType> = new Set([
	'character',
	'parenthetical',
	'dialogue'
]);

/** True when the type prints on the page. */
export function isPrinting(type: AnyElementType): type is ElementType {
	return PRINTING_TYPES.has(type);
}
