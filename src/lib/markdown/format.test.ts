import { describe, expect, it } from 'vitest';
import {
	blockKind,
	clearFormatting,
	insertBlock,
	toggleBlockKind,
	toggleLink,
	toggleMark
} from './format';

describe('toggleMark', () => {
	it('wraps a selection in bold markers', () => {
		const result = toggleMark('hello world', 0, 5, 'bold');
		expect(result.text).toBe('**hello** world');
		expect(result.start).toBe(2);
		expect(result.end).toBe(7);
	});

	it('removes bold markers when already bold', () => {
		const result = toggleMark('**hello** world', 2, 7, 'bold');
		expect(result.text).toContain('hello');
		expect(result.text).not.toMatch(/^\*\*hello\*\*/);
	});
});

describe('toggleBlockKind', () => {
	it('prefixes lines as a bullet list', () => {
		const result = toggleBlockKind('one\ntwo', 0, 7, 'ul');
		expect(result.text).toMatch(/^- /m);
	});

	it('toggles quote markers', () => {
		const quoted = toggleBlockKind('line', 0, 4, 'quote');
		expect(quoted.text.startsWith('>')).toBe(true);
		const unquoted = toggleBlockKind(quoted.text, 0, quoted.text.length, 'quote');
		expect(unquoted.text.startsWith('>')).toBe(false);
	});
});

describe('blockKind', () => {
	it('detects headings and lists', () => {
		expect(blockKind('# Title', 0)).toBe('h1');
		expect(blockKind('- item', 0)).toBe('ul');
		expect(blockKind('1. item', 0)).toBe('ol');
		expect(blockKind('plain', 0)).toBe('paragraph');
	});
});

describe('toggleLink', () => {
	it('wraps selection as a markdown link', () => {
		const result = toggleLink('docs', 0, 4);
		expect(result.text).toMatch(/\[docs\]\(/);
	});
});

describe('insertBlock / clearFormatting', () => {
	it('inserts a fenced code block snippet', () => {
		const result = insertBlock('before', 6, 6, '```\n\n```', 4);
		expect(result.text).toContain('```');
	});

	it('strips inline markers from a selection', () => {
		const result = clearFormatting('say **hi** there', 4, 10);
		expect(result.text).toContain('hi');
		expect(result.text).not.toContain('**');
	});
});
