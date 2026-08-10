import { describe, expect, it } from 'vitest';
import {
	assertScreenplay,
	DraftFirstValidationError,
	validateScreenplay
} from './validation.js';

describe('validateScreenplay', () => {
	it('accepts a valid document without cloning it', () => {
		const document = {
			titlePage: [{ key: 'Title', values: ['A Film'] }],
			elements: [{ type: 'scene', text: 'INT. LAB - DAY', sceneNumber: '1' }]
		};

		const result = validateScreenplay(document);

		expect(result.ok).toBe(true);
		if (result.ok) expect(result.value).toBe(document);
	});

	it('returns stable diagnostics for malformed external data', () => {
		const result = validateScreenplay({
			titlePage: [{ key: '', values: ['ok', 3] }],
			elements: [{ type: 'unknown', text: 42, depth: 0 }]
		});

		expect(result.ok).toBe(false);
		expect(result.diagnostics.map((diagnostic) => diagnostic.code)).toEqual([
			'TITLE_KEY_INVALID',
			'TITLE_VALUE_INVALID',
			'ELEMENT_TYPE_INVALID',
			'ELEMENT_TEXT_INVALID',
			'ELEMENT_DEPTH_INVALID'
		]);
	});

	it('enforces configurable resource limits', () => {
		const result = validateScreenplay(
			{ titlePage: [], elements: [{ type: 'action', text: 'too long' }] },
			{ maxElementTextLength: 3 }
		);

		expect(result.ok).toBe(false);
		expect(result.diagnostics[0]?.code).toBe('ELEMENT_TEXT_TOO_LONG');
	});

	it('rejects invalid limit configuration', () => {
		expect(() => validateScreenplay({ titlePage: [], elements: [] }, { maxElements: Number.NaN })).toThrow(
			RangeError
		);
	});

	it('throws a typed error through the assertion API', () => {
		try {
			assertScreenplay({ titlePage: [], elements: null });
			expect.fail('expected validation to throw');
		} catch (error) {
			expect(error).toBeInstanceOf(DraftFirstValidationError);
			expect((error as DraftFirstValidationError).diagnostics[0]?.code).toBe('ELEMENTS_NOT_ARRAY');
		}
	});
});
