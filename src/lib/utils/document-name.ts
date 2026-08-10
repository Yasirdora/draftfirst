/**
 * Derive a safe download filename from the first heading or first line.
 */

import { outlineOf } from '$lib/markdown/render';

export function documentName(doc: string): string {
	const heading = outlineOf(doc)[0];
	const raw = (heading && heading.text) || doc.trim().split('\n')[0] || 'document';
	const slug = raw
		.toLowerCase()
		.replace(/[^\w\s-]/g, '')
		.trim()
		.replace(/\s+/g, '-')
		.slice(0, 60);
	return slug || 'document';
}
