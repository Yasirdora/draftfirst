/**
 * Public $lib surface for Writing Desk.
 * Prefer deep imports (`$lib/markdown/render`, `$lib/components/...`) in app code.
 */

export { renderMarkdown, outlineOf, countWords, escapeHtml, safeUrl } from './markdown/render';
export { serialiseMarkdown } from './markdown/serialise';
export { SAMPLE } from './markdown/sample';
export type { AppState, ViewMode, OutlineHeading, FormatResult } from './markdown/types';
