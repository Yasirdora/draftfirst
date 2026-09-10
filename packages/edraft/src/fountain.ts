/** Fountain parsing, serialization, and commit-time normalization. */

export type { FountainParseOptions } from './parse.js';
export {
	DEFAULT_MAX_FOUNTAIN_SOURCE_CHARACTERS,
	FountainParseError,
	parseFountain,
	SCENE_DETECT,
	TRANSITION_DETECT
} from './parse.js';
export {
	elementToFountain,
	serialiseFountain,
	serialiseFountain as serializeFountain
} from './serialise.js';
export {
	escapeFountainContent,
	liveCollapse,
	normaliseRuns,
	parseEmphasis,
	propagateRuns,
	sliceRuns,
	STYLE_ORDER,
	styleCovered,
	synthesiseEmphasis,
	toggleStyle
} from './style.js';
export type { LiveCollapse } from './style.js';
export {
	looksLikeCue,
	normalizeCue,
	normalizeElementText,
	normalizeParenthetical
} from './normalize.js';
