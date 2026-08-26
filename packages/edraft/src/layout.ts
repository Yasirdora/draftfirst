/** Deterministic screenplay pagination and reporting. */

export type { PageLine, PaginateOptions, ScriptPage } from './paginate.js';
export {
	estimateRuntime,
	LINES_PER_PAGE,
	PAGE_WIDTH_CHARS,
	paginate,
	printedLineCount,
	wrapText
} from './paginate.js';
