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
	| 'lyrics'
	/* The card that opens an act. Its page break is a rule of the type (the
	   paginator forces one), and the act's end is derived — the next actbreak
	   or the document's end — never stored. RFC-ACT-BREAK §2, D2-D3. */
	| 'actbreak';

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
	'lyrics',
	'actbreak'
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

/** A note pinned to words inside its paragraph — RFC-NOTES-SYSTEM §5
    (stage 4). `on` is the words exactly as they stand in the paragraph the
    note is about; `nth` selects which occurrence, and is present exactly
    when the words occur more than once (§5.3). Absent from a note means the
    note is about its whole paragraph, which is every note before stage 4.
    The rule that turns one into the other lives in noteanchor.ts. */
export interface NoteAnchor {
	on: string;
	nth?: number;
}

export interface ScreenplayElement {
	/** Absent only on unadopted parser/import projections. */
	id?: import('./identity.js').DraftElementID;
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
	/** Notes only: the words this note is pinned to, within the paragraph
	    that follows it (§5.2). Absent means the whole paragraph. */
	anchor?: NoteAnchor;
}

/** Where a title-page line sits across the measure. Absent means centred. */
export type TitlePageAlignment = 'left' | 'center' | 'right';

/** One line of the title page (docs/RFC-TITLE-PAGE.md, D1): text, its own
    alignment and styled runs — and the blank lines between, which carry
    the vertical rhythm and are therefore real lines in the model, never
    recomputed at render. `key` is an annotation a guided editor may leave
    on a line it created; nothing requires it and nothing invents it. */
export interface TitlePageLine {
	text: string;
	alignment?: TitlePageAlignment;
	runs?: StyleRun[];
	key?: string;
}

/** A scene the production has omitted — RFC-DRAFT-PRODUCTION §7.3.
 *
 * An omission is a *record*, not a deletion: the elements stay in the script
 * with their text, and this names the contiguous span that no longer prints.
 * Removing the record restores the scene; nothing has to be put back.
 *
 * `start` is inclusive and `end` exclusive, as every other span in this
 * model is. The span begins at a scene heading (§7.3). §7.3 addresses its
 * span by DraftElementID; the legacy omission API still uses element indices; migration to
 * persistent identity is a separate production milestone. Accordingly,
 * the scene number stays where it already lives, on the OMITTED card element
 * that precedes the span, rather than being copied here. */
export interface Omission {
	start: number;
	end: number;
}

export interface Screenplay {
	/** Document allocator high-water mark; not part of raw parser projections. */
	nextId?: string;
	titlePage: TitlePageLine[];
	elements: ScreenplayElement[];
	/** Scenes the production has omitted (§7.3). Absent when there are none,
	    so a script without omissions serialises exactly as it always has. */
	omissions?: Omission[];
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
