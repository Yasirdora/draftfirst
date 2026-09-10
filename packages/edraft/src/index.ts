/** Stable root API for the eDraft Screenwriting Engine. */

export type {
	AnyElementType,
	ContentIndex,
	ElementType,
	FountainIndex,
	Screenplay,
	ScreenplayElement,
	StructuralType,
	StyleRun,
	StyleToken,
	TitlePageEntry
} from './types.js';
export { contentIndex, fountainIndex, isPrinting } from './types.js';

export {
	escapeFountainContent,
	normaliseRuns,
	parseEmphasis,
	STYLE_ORDER,
	synthesiseEmphasis
} from './style.js';

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
