/**
 * Image references in the Markdown source.
 *
 * Pasted/dropped images are stored as blobs (see $lib/assets/asset-store) and
 * referenced as `![alt](asset:<id>)`. These helpers build that reference and
 * splice it into the textarea value without disturbing the surrounding text:
 * on an empty line the image goes inline at the caret; on a busy line it is
 * broken out onto its own line.
 *
 * Pure and Node-testable.
 */

import type { SourceEdit } from './source-keys';

/** Opaque reference scheme for stored assets. Images only — see safeUrl. */
export function assetRef(id: string): string {
	return 'asset:' + id;
}

export const ASSET_REF_PATTERN = /^asset:[a-z0-9-]+$/i;

/** Filenames from the clipboard are generic ("image.png", "Screenshot …") — keep the alt honest. */
export function altFromFileName(name: string): string {
	const base = name.replace(/\.[a-z0-9]+$/i, '').trim();
	if (/^(image|img|screenshot|unnamed)([ ._-].*)?$/i.test(base) || base === '') return 'image';
	return base;
}

/**
 * Insert `![alt](ref)` at the caret (or replace the selection).
 * Mid-line caret: break out — newline before, and one after when text follows.
 */
export function insertImageRef(
	value: string,
	start: number,
	end: number,
	ref: string,
	alt: string
): SourceEdit {
	const snippet = '![' + alt + '](' + ref + ')';
	const lineStart = value.lastIndexOf('\n', start - 1) + 1;
	const beforeOnLine = value.slice(lineStart, start);
	const afterOnLine = value.slice(end, value.indexOf('\n', end) === -1 ? value.length : value.indexOf('\n', end));

	let insert = snippet;
	let cursor = insert.length;
	if (beforeOnLine.trim() !== '') {
		insert = '\n' + insert;
		cursor += 1;
	}
	if (afterOnLine.trim() !== '') {
		insert += '\n';
	}

	const text = value.slice(0, start) + insert + value.slice(end);
	return { text, selectionStart: start + cursor, selectionEnd: start + cursor };
}
