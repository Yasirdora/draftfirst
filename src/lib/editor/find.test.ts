import { describe, expect, it } from 'vitest';
import { findMatches } from './find';

describe('findMatches', () => {
	it('returns empty for blank query', () => {
		expect(findMatches('hello', '')).toEqual([]);
	});

	it('finds case-insensitive matches with line info', () => {
		const doc = 'Alpha\nbeta BETA\ngamma';
		const matches = findMatches(doc, 'beta');
		expect(matches.length).toBe(2);
		expect(matches[0].line).toBe(2);
		expect(matches[0].preview.toLowerCase()).toContain('beta');
	});
});
