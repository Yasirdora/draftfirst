/** Stable root API for the eDraft Screenwriting Engine. */

export type {
	AnyElementType,
	ContentIndex,
	ElementType,
	FountainIndex,
	NoteAnchor,
	Screenplay,
	ScreenplayElement,
	StructuralType,
	StyleRun,
	StyleToken,
	TitlePageAlignment,
	TitlePageLine
} from './types.js';
export { contentIndex, fountainIndex, isPrinting } from './types.js';

/** Notes pinned to words — RFC-NOTES-SYSTEM §5 (stage 4). */
export type { AnchorSpan, NoteHeaderReading } from './noteanchor.js';
export { anchorFor, quoteAnchorWords, readNoteHeader, resolveAnchor, writeNoteHeader } from './noteanchor.js';

export {
	deriveTitlePage,
	STANDARD_CREDIT_PHRASES,
	TITLE_CONTACT_LAST_LINE,
	TITLE_STACK_LEADING_BLANKS,
	titlePageLinesFromEntries,
	titlePageValues
} from './titlepage.js';
export type { DerivedTitlePageEntry, LegacyTitlePageEntry } from './titlepage.js';

export {
	ACT_ORDINAL_WORDS,
	actOrdinal,
	defaultActCard,
	isActCard,
	isCanonicalActCard,
	isEndActCard,
	renumberActs
} from './acts.js';

export { parseNumberedSceneHeading } from './sceneheading.js';
export type { NumberedSceneHeading } from './sceneheading.js';

export {
	escapeFountainContent,
	liveCollapse,
	normaliseRuns,
	highlightCovered,
	toggleHighlight,
	parseEmphasis,
	propagateRuns,
	sliceRuns,
	STYLE_ORDER,
	styleCovered,
	synthesiseEmphasis,
	toggleStyle
} from './style.js';
export type { LiveCollapse } from './style.js';

export type {
	DiagnosticSeverity,
	EDraftDiagnostic,
	ScreenplayLimits,
	ScreenplayValidationResult
} from './validation.js';
export {
	assertScreenplay,
	DEFAULT_SCREENPLAY_LIMITS,
	EDraftValidationError,
	validateScreenplay
} from './validation.js';

export type { FountainParseOptions } from './parse.js';
export {
	DEFAULT_MAX_FOUNTAIN_SOURCE_CHARACTERS,
	FountainParseError,
	parseFountain
} from './parse.js';
export {
	elementToFountain,
	serialiseFountain,
	serialiseFountain as serializeFountain
} from './serialise.js';
