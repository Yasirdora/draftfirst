import { describe, expect, it } from 'vitest';
import { FIND_MIN_LENGTH, findMatches } from './find';

describe('findMatches', () => {
	it('returns empty for blank or short query', () => {
		expect(findMatches('hello', '')).toEqual([]);
		expect(findMatches('hello', 'h')).toEqual([]);
		expect(FIND_MIN_LENGTH).toBe(2);
	});

	it('finds case-insensitive matches with line info', () => {
		const doc = 'Alpha\nbeta BETA\ngamma';
		const matches = findMatches(doc, 'beta');
		expect(matches.length).toBe(2);
		expect(matches[0].line).toBe(2);
		expect(matches[0].preview.toLowerCase()).toContain('beta');
	});
});
