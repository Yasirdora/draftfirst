/** Stable root API for the Draft First Screenwriting Engine. */

export type {
	AnyElementType,
	ElementType,
	Screenplay,
	ScreenplayElement,
	StructuralType,
	TitlePageEntry
} from './types.js';
export { isPrinting } from './types.js';

export type {
	DiagnosticSeverity,
	DraftFirstDiagnostic,
	ScreenplayLimits,
	ScreenplayValidationResult
} from './validation.js';
export {
	assertScreenplay,
	DEFAULT_SCREENPLAY_LIMITS,
	DraftFirstValidationError,
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
