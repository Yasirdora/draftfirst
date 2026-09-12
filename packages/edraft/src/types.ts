/**
 * eDraft Screenwriting Engine document model.
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

/** Offset within one element's marker-free content text, in UTF-16 code
    units — the same coordinate space as `String.length` and `NSRange`, so
    the web editor, both engines and TextKit share it exactly. Brand only;
    JSON fixtures and the wire format carry plain numbers. */
export type ContentIndex = number & { readonly __brand: 'content' };
export const contentIndex = (value: number): ContentIndex => value as ContentIndex;

/** Offset in Fountain source text. Exists transiently inside the parser and
    serialiser; never stored and never crosses the engine boundary. */
export type FountainIndex = number & { readonly __brand: 'fountain' };
export const fountainIndex = (value: number): FountainIndex => value as FountainIndex;

/** The complete Style vocabulary of the FDX corpus: the six tokens Final
    Draft puts on a <Text> run. AllCaps is display casing — the text keeps
    what the writer typed — and HiddenText is invisible on the printed page;
    neither has a Fountain spelling (see style.ts). */
export type StyleToken = 'Bold' | 'Italic' | 'Underline' | 'Strikeout' | 'AllCaps' | 'HiddenText';

/** One span of content sharing identical presentation. `start`/`end` are a
    half-open ContentIndex range into the owning element's marker-free text.
    `revisionID` and `tagNumbers` live on the run because FDX puts
    RevisionID and TagNumber on <Text> next to Style — one span mechanism,
    and the model can never express a span the format cannot hear. */
/** Highlight colors. v1 is yellow alone; the field is a value, not a
    flag, so a palette is an additive UI change and never a format
    migration (docs/RFC-HIGHLIGHTER.md, D7). */
export type HighlightColor = 'yellow';

export interface StyleRun {
	start: number;
	end: number;
	/** Canonical token order (see STYLE_ORDER in style.ts). */
	styles: StyleToken[];
	revisionID?: number;
	tagNumbers?: number[];
	/** The attention mark (docs/RFC-HIGHLIGHTER.md): one color in v1,
	    carried on the run beside styles like `revisionID`. */
	highlight?: HighlightColor;
}

export interface ScreenplayElement {
	type: AnyElementType;
	/** Plain text of the element — marker-free content when `runs` is
	    present; emphasis markers are boundary artefacts, not model text. */
	text: string;
	/** Styled spans of `text`. Canonical: sorted, non-overlapping, merged
	    where identical, clamped to the text, never empty. Absent when the
	    element carries no styling. */
	runs?: StyleRun[];
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
