/**
 * Asset inlining for standalone export — resolver injected, no IndexedDB here.
 */

import { describe, expect, it } from 'vitest';
import { assetIdsIn, inlineAssetDataUrls } from './export-assets';

describe('assetIdsIn', () => {
	it('collects unique ids from image references only', () => {
		const doc = [
			'![one](asset:aaa)',
			'![two](asset:bbb "title")',
			'![one again](asset:aaa)',
			'[a link](asset:ccc)',
			'![web](https://x.test/i.png)'
		].join('\n');
		expect(assetIdsIn(doc)).toEqual(['aaa', 'bbb']);
	});

	it('finds nothing in a plain document', () => {
		expect(assetIdsIn('# No images here\n')).toEqual([]);
	});
});

describe('inlineAssetDataUrls', () => {
	it('replaces every reference with its data URL', async () => {
		const doc = '![a](asset:aaa)\n![a again](asset:aaa)\n![b](asset:bbb)';
		const urls: Record<string, string> = { aaa: 'data:image/png;base64,A', bbb: 'data:image/png;base64,B' };
		const out = await inlineAssetDataUrls(doc, async (id) => urls[id] ?? null);
		expect(out).toBe(
			'![a](data:image/png;base64,A)\n![a again](data:image/png;base64,A)\n![b](data:image/png;base64,B)'
		);
	});

	it('leaves references the resolver cannot fulfil', async () => {
		const doc = '![a](asset:missing)';
		const out = await inlineAssetDataUrls(doc, async () => null);
		expect(out).toBe(doc);
	});
});
