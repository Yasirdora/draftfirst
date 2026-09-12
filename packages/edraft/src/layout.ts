/** Deterministic screenplay pagination and reporting. */

export type { PageLine, PaginateOptions, ScriptPage, WrappedLine } from './paginate.js';
export {
	estimateRuntime,
	GEOMETRY,
	LINES_PER_PAGE,
	PAGE_WIDTH_CHARS,
	paginate,
	printedLineCount,
	wrapLines,
	wrapText
} from './paginate.js';
