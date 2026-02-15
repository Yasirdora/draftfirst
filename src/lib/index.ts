/**
 * Public $lib surface for Writing Desk.
 * Prefer deep imports (`$lib/markdown/render`, `$lib/components/...`) in app code.
 */

export { renderMarkdown, outlineOf, countWords, escapeHtml, safeUrl } from './markdown/render';
export { serialiseMarkdown } from './markdown/serialise';
export {
	assessFidelity,
	diffLines,
	groupTruthChanges,
	normalizeCosmetic,
	plainTextSkeleton,
	restoreTruthChange,
	applyTruthRestores
} from './markdown/fidelity';
export { SAMPLE } from './markdown/sample';
export type { AppState, ViewMode, OutlineHeading, FormatResult } from './markdown/types';
export type {
	FidelityReport,
	FidelityStatus,
	DiffHunk,
	TruthChange
} from './markdown/fidelity';
