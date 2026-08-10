/**
 * Image reference insertion — caret placement and line breaking.
 */

import { describe, expect, it } from 'vitest';
import { altFromFileName, assetRef, insertImageRef } from './image-insert';

describe('assetRef / altFromFileName', () => {
	it('builds the opaque scheme', () => {
		expect(assetRef('a-b-c')).toBe('asset:a-b-c');
	});

	it('keeps meaningful names, genericises clipboard names', () => {
		expect(altFromFileName('diagram.png')).toBe('diagram');
		expect(altFromFileName('image.png')).toBe('image');
		expect(altFromFileName('Screenshot 2026-08-06.png')).toBe('image');
		expect(altFromFileName('')).toBe('image');
	});
});

describe('insertImageRef', () => {
	it('inserts inline on an empty document', () => {
		const edit = insertImageRef('', 0, 0, 'asset:x1', 'image');
		expect(edit.text).toBe('![image](asset:x1)');
		expect(edit.selectionStart).toBe(edit.text.length);
	});

	it('inserts at the caret on an empty line', () => {
		const edit = insertImageRef('para\n', 5, 5, 'asset:x1', 'image');
		expect(edit.text).toBe('para\n![image](asset:x1)');
		expect(edit.selectionStart).toBe('para\n'.length + '![image](asset:x1)'.length);
	});

	it('breaks out of a busy line with newlines around the image', () => {
		const edit = insertImageRef('beforeafter', 6, 6, 'asset:x1', 'image');
		expect(edit.text).toBe('before\n![image](asset:x1)\nafter');
		expect(edit.selectionStart).toBe('before\n![image](asset:x1)'.length);
	});

	it('breaks out only before when the caret ends the line', () => {
		const edit = insertImageRef('busy line\nnext', 9, 9, 'asset:x1', 'image');
		expect(edit.text).toBe('busy line\n![image](asset:x1)\nnext');
	});

	it('replaces a selection', () => {
		const edit = insertImageRef('xxpickyy', 2, 6, 'asset:x1', 'image');
		expect(edit.text).toBe('xx\n![image](asset:x1)\nyy');
	});

	it('escapes nothing — alt and ref go in verbatim (renderer owns safety)', () => {
		const edit = insertImageRef('', 0, 0, 'asset:a-b-c', 'a b');
		expect(edit.text).toBe('![a b](asset:a-b-c)');
	});
});
