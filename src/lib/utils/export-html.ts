/**
 * Build a standalone HTML file for export.
 * Styles are inlined so the file opens with no network requests.
 */

import { escapeHtml, outlineOf, renderMarkdown } from '$lib/markdown/render';
import { documentName } from '$lib/utils/document-name';
import { download } from '$lib/utils/download';

/** Minimal print-safe document stylesheet (mirrors the sheet tokens). */
const EXPORT_CSS = [
	'body{margin:0;background:#f4f6f8;color:#16202B;',
	'font:17px/1.62 Charter,"Bitstream Charter",Georgia,"Times New Roman",serif}',
	'main{max-width:44rem;margin:0 auto;padding:48px 24px 80px}',
	'h1,h2,h3,h4,h5,h6{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;',
	'line-height:1.25;margin:1.9em 0 .55em;letter-spacing:-.012em}',
	'h1{font-size:1.9em;margin-top:0}h2{font-size:1.42em;padding-bottom:.2em;border-bottom:1px solid #DFE4E9}',
	'h3{font-size:1.18em}p{margin:0 0 1.05em}a{color:#2A5B8C}',
	'blockquote{margin:0 0 1.05em;padding:.1em 0 .1em 1.1em;border-left:3px solid #DFE4E9;color:#5A6875}',
	'code{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:.86em;background:#F2F4F7;padding:.12em .35em;border-radius:4px}',
	'pre{padding:14px 16px;overflow:auto;background:#F2F4F7;border-radius:7px}pre code{background:none;padding:0;font-size:.82em}',
	'table{border-collapse:collapse;width:100%;font-size:.93em}th,td{border:1px solid #DFE4E9;padding:.45em .7em;text-align:left}',
	'th{background:#F2F4F7}hr{border:0;border-top:1px solid #DFE4E9;margin:2em 0}',
	'img{max-width:100%;height:auto}li.task{list-style:none;margin-left:-1.35em}'
].join('');

export function exportStandaloneHtml(doc: string): void {
	const title = (outlineOf(doc)[0] || {}).text || 'Document';
	const page =
		'<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n' +
		'<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
		'<title>' +
		escapeHtml(title) +
		'</title>\n<style>' +
		EXPORT_CSS +
		'</style>\n</head>\n<body>\n<main>\n' +
		renderMarkdown(doc) +
		'</main>\n</body>\n</html>\n';

	download(page, documentName(doc) + '.html', 'text/html');
}
