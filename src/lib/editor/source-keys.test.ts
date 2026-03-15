/**
 * Smart source keys — list/task/quote continuation, hard breaks, indentation.
 */

import { describe, expect, it } from 'vitest';
import { continueOnEnter, hardBreak, indentOnTab } from './source-keys';

/** Caret-marked input: "|" stands for the collapsed caret. */
function setup(marked: string): [string, number] {
	const pos = marked.indexOf('|');
	return [marked.slice(0, pos) + marked.slice(pos + 1), pos];
}

describe('continueOnEnter — lists', () => {
	it('continues an unordered item with the same bullet', () => {
		for (const bullet of ['-', '*', '+']) {
			const [value, pos] = setup(`${bullet} foo|`);
			const edit = continueOnEnter(value, pos)!;
			expect(edit.text).toBe(`${bullet} foo\n${bullet} `);
			expect(edit.selectionStart).toBe(edit.text.length);
		}
	});

	it('increments ordered numbers, keeping the delimiter', () => {
		const [dot, dotPos] = setup('3. foo|');
		expect(continueOnEnter(dot, dotPos)!.text).toBe('3. foo\n4. ');
		const [paren, parenPos] = setup('12) foo|');
		expect(continueOnEnter(paren, parenPos)!.text).toBe('12) foo\n13) ');
	});

	it('starts a fresh unchecked box after a task item', () => {
		const [done, donePos] = setup('- [x] shipped|');
		expect(continueOnEnter(done, donePos)!.text).toBe('- [x] shipped\n- [ ] ');
		const [open, openPos] = setup('- [ ] todo|');
		expect(continueOnEnter(open, openPos)!.text).toBe('- [ ] todo\n- [ ] ');
	});

	it('keeps the indentation of a nested item', () => {
		const [value, pos] = setup('  - nested|');
		expect(continueOnEnter(value, pos)!.text).toBe('  - nested\n  - ');
	});

	it('splits mid-item: the remainder follows the new marker', () => {
		const [value, pos] = setup('- foo|bar');
		const edit = continueOnEnter(value, pos)!;
		expect(edit.text).toBe('- foo\n- bar');
		expect(edit.selectionStart).toBe('- foo\n- '.length);
	});

	it('ends the list when the item is empty', () => {
		const [value, pos] = setup('- foo\n- |');
		const edit = continueOnEnter(value, pos)!;
		expect(edit.text).toBe('- foo\n');
		expect(edit.selectionStart).toBe('- foo\n'.length);
	});

	it('un-lists a line when Enter lands between marker and text', () => {
		const [value, pos] = setup('- |foo');
		const edit = continueOnEnter(value, pos)!;
		expect(edit.text).toBe('foo');
		expect(edit.selectionStart).toBe(0);
	});
});

describe('continueOnEnter — quotes', () => {
	it('continues a quote with the same prefix', () => {
		const [value, pos] = setup('> foo|');
		const edit = continueOnEnter(value, pos)!;
		expect(edit.text).toBe('> foo\n> ');
		expect(edit.selectionStart).toBe(edit.text.length);
	});

	it('continues nested quotes with the full chain', () => {
		const [value, pos] = setup('> > deep|');
		expect(continueOnEnter(value, pos)!.text).toBe('> > deep\n> > ');
	});

	it('ends the quote when the line is empty', () => {
		const [value, pos] = setup('> foo\n> |');
		const edit = continueOnEnter(value, pos)!;
		expect(edit.text).toBe('> foo\n');
		expect(edit.selectionStart).toBe('> foo\n'.length);
	});

	it('continues the quote (not the list) on a quoted list line', () => {
		const [value, pos] = setup('> - item|');
		expect(continueOnEnter(value, pos)!.text).toBe('> - item\n> ');
	});
});

describe('continueOnEnter — everything else', () => {
	it('returns null on plain paragraphs and headings', () => {
		for (const marked of ['foo|', '# heading|', '    code()|', '---|']) {
			const [value, pos] = setup(marked);
			expect(continueOnEnter(value, pos)).toBeNull();
		}
	});
});

describe('hardBreak', () => {
	it('appends two trailing spaces before the newline', () => {
		const [value, pos] = setup('foo|');
		const edit = hardBreak(value, pos);
		expect(edit.text).toBe('foo  \n');
		expect(edit.selectionStart).toBe(edit.text.length);
	});

	it('splits mid-line, moving the remainder down', () => {
		const [value, pos] = setup('foo|bar');
		const edit = hardBreak(value, pos);
		expect(edit.text).toBe('foo  \nbar');
		expect(edit.selectionStart).toBe('foo  \n'.length);
	});

	it('stays inside the quote', () => {
		const [value, pos] = setup('> foo|');
		expect(hardBreak(value, pos).text).toBe('> foo  \n> ');
	});

	it('keeps the indent of an indented line', () => {
		const [value, pos] = setup('  - foo|');
		expect(hardBreak(value, pos).text).toBe('  - foo  \n  ');
	});
});

describe('indentOnTab', () => {
	it('inserts two spaces at a collapsed caret', () => {
		const edit = indentOnTab('foobar', 3, 3, false);
		expect(edit.text).toBe('foo  bar');
		expect(edit.selectionStart).toBe(5);
	});

	it('indents every touched line and keeps the block selected', () => {
		const edit = indentOnTab('a\nb\nc', 0, 4, false);
		expect(edit.text).toBe('  a\n  b\n  c');
		expect(edit.selectionStart).toBe(0);
		expect(edit.text.slice(edit.selectionStart, edit.selectionEnd)).toBe('  a\n  b\n  ');
	});

	it('outdents one or two leading spaces per line', () => {
		const edit = indentOnTab('  a\n   b\nc', 0, 8, true);
		expect(edit.text).toBe('a\n b\nc');
	});

	it('leaves unindented lines untouched on outdent', () => {
		const edit = indentOnTab('a\nb', 0, 3, true);
		expect(edit.text).toBe('a\nb');
	});
});
