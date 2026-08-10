/**
 * Inline `asset:<id>` image references as data URLs for standalone export.
 *
 * The resolver is injected so this stays pure and Node-testable — the browser
 * passes one backed by IndexedDB, tests pass a stub. Missing assets keep their
 * reference (better a broken link than silent data loss).
 */

/** Every unique asset id referenced by an image in the document. */
export function assetIdsIn(doc: string): string[] {
	const ids = new Set<string>();
	for (const match of doc.matchAll(/!\[[^\]]*\]\(\s*(asset:[a-z0-9-]+)(?:\s+"[^"]*")?\s*\)/gi)) {
		ids.add(match[1].slice('asset:'.length));
	}
	return [...ids];
}

/**
 * Replace each asset reference with the data URL the resolver returns.
 * References the resolver cannot fulfil are left untouched.
 */
export async function inlineAssetDataUrls(
	doc: string,
	resolve: (id: string) => Promise<string | null>
): Promise<string> {
	let out = doc;
	for (const id of assetIdsIn(doc)) {
		const dataUrl = await resolve(id);
		if (!dataUrl) continue;
		out = out.split('asset:' + id).join(dataUrl);
	}
	return out;
}
