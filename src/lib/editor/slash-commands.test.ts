import { describe, expect, it } from 'vitest';
import { detectSlashQuery, filterSlashCommands } from './slash-commands';

describe('filterSlashCommands', () => {
	it('returns all when query empty', () => {
		expect(filterSlashCommands('').length).toBeGreaterThan(5);
	});

	it('filters by keyword', () => {
		const hits = filterSlashCommands('task');
		expect(hits.some((c) => c.id === 'task')).toBe(true);
		expect(hits.every((c) => c.keywords.includes('task') || c.id.includes('task'))).toBe(true);
	});
});

describe('detectSlashQuery', () => {
	it('detects slash at line start', () => {
		const text = 'hello\n/tab';
		const caret = text.length;
		expect(detectSlashQuery(text, caret)).toEqual({ start: 6, query: 'tab' });
	});

	it('ignores mid-line slash', () => {
		const text = 'see /path';
		expect(detectSlashQuery(text, text.length)).toBeNull();
	});
});
