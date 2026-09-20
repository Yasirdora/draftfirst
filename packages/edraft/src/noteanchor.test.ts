/** Notes pinned to words — the disambiguation rule and the Fountain header
    (RFC-NOTES-SYSTEM §5.3, §4.1; stage 4). */
import { describe, expect, it } from 'vitest';
import { anchorFor, readNoteHeader, resolveAnchor, writeNoteHeader } from './noteanchor.js';
import { parseFountain } from './parse.js';
import { serialiseFountain } from './serialise.js';
import type { NoteAnchor } from './types.js';

const LINE = "The kettle screams. Mara doesn't move.";

describe('§5.3 the disambiguation rule', () => {
	it('1. searches the paragraph from its start, and 2. takes the first occurrence', () => {
		expect(resolveAnchor(LINE, { on: 'kettle' })).toEqual({ start: 4, end: 10 });
		expect(resolveAnchor('one two one two', { on: 'one' })).toEqual({ start: 0, end: 3 });
	});

	it('2. nth selects the Nth occurrence', () => {
		expect(resolveAnchor('one two one two', { on: 'one', nth: 2 })).toEqual({ start: 8, end: 11 });
		expect(resolveAnchor('one two one two', { on: 'two', nth: 2 })).toEqual({ start: 12, end: 15 });
	});

	it('2. counts overlapping occurrences, and writing agrees with reading', () => {
		expect(resolveAnchor('aaa', { on: 'aa', nth: 2 })).toEqual({ start: 1, end: 3 });
		expect(anchorFor('aaa', 1, 3)).toEqual({ on: 'aa', nth: 2 });
	});

	it('3. writes nth exactly when the words occur more than once', () => {
		expect(anchorFor(LINE, 4, 10)).toEqual({ on: 'kettle' });
		expect(anchorFor('one two one two', 0, 3)).toEqual({ on: 'one', nth: 1 });
		expect(anchorFor('one two one two', 8, 11)).toEqual({ on: 'one', nth: 2 });
	});

	it('4. matches exactly on UTF-16 units, casing included', () => {
		expect(resolveAnchor('Mara and MARA', { on: 'MARA' })).toEqual({ start: 9, end: 13 });
		expect(resolveAnchor('Mara only', { on: 'MARA' })).toBeNull();
	});

	it('5. gives nothing when the words are gone, or there are fewer than N', () => {
		expect(resolveAnchor(LINE, { on: 'the samovar' })).toBeNull();
		expect(resolveAnchor('one two one', { on: 'one', nth: 3 })).toBeNull();
		expect(resolveAnchor(LINE, { on: 'kettle', nth: 0 })).toBeNull();
		expect(resolveAnchor(LINE, { on: '' })).toBeNull();
	});

	it('is its own inverse: every anchor it writes resolves to the span it came from', () => {
		const paragraph = 'one two one two one';
		for (let start = 0; start < paragraph.length; start++) {
			for (let end = start + 1; end <= paragraph.length; end++) {
				const anchor = anchorFor(paragraph, start, end);
				if (anchor === null) continue;
				expect(resolveAnchor(paragraph, anchor)).toEqual({ start, end });
			}
		}
	});

	it('a span over the whole paragraph, or an empty one, is no anchor at all', () => {
		expect(anchorFor(LINE, 0, LINE.length)).toBeNull();
		expect(anchorFor(LINE, 5, 5)).toBeNull();
		expect(anchorFor(LINE, 0, LINE.length + 1)).toBeNull();
	});
});

describe('§4.1 the header line, the fields stage 4 owns', () => {
	const header = (anchor: NoteAnchor) => writeNoteHeader(anchor);

	it('writes on, and nth only when it is needed', () => {
		expect(header({ on: "doesn't move" })).toBe('[eDraft on:"doesn\'t move"]');
		expect(header({ on: 'one', nth: 2 })).toBe('[eDraft on:"one" nth:2]');
	});

	it('reads its own spelling back, and takes the header off the words', () => {
		const reading = readNoteHeader('[eDraft on:"one" nth:2]\nDana Reyes (Director): Too still?');
		expect(reading).toEqual({ anchor: { on: 'one', nth: 2 }, body: 'Dana Reyes (Director): Too still?' });
	});

	it('reads keys case-insensitively, and quotes with escapes', () => {
		expect(readNoteHeader('[EDRAFT ON:"a"]\nx')?.anchor).toEqual({ on: 'a' });
		expect(readNoteHeader('[eDraft on:"a \\"b\\" c"]\nx')?.anchor).toEqual({ on: 'a "b" c' });
		expect(header({ on: 'a "b" c' })).toBe('[eDraft on:"a \\"b\\" c"]');
	});

	it('leaves alone every header this stage does not own — stage 2 and 3 are not built', () => {
		expect(readNoteHeader('[eDraft thread:t4k9qz status:open]\nx')).toBeNull();
		expect(readNoteHeader('[eDraft on:"a" thread:t4k9qz]\nx')).toBeNull();
		expect(readNoteHeader('[eDraft from:"Dana Reyes (Director)"]\nx')).toBeNull();
	});

	it('a malformed header is not a header', () => {
		expect(readNoteHeader('[eDraft on:"a"\nx')).toBeNull();
		expect(readNoteHeader('[eDraft on:"a"] trailing\nx')).toBeNull();
		expect(readNoteHeader('[eDraft on:"a" nth:0]\nx')).toBeNull();
		expect(readNoteHeader('[eDraft on:"a" nth:two]\nx')).toBeNull();
		expect(readNoteHeader('[eDraft on:"a" on:"b"]\nx')).toBeNull();
		expect(readNoteHeader('Dana: just a note')).toBeNull();
	});

	it('a line built to make a parser backtrack is read in a straight line', () => {
		/* The grammar needs nested quantifiers as a regular expression, and a
		   note's first line is attacker-controlled in any file eDraft opens.
		   The scanner is one pass: this returns at once, and says no. */
		const hostile = `[eDraft ${'a:b '.repeat(4000)}`;
		const started = performance.now();
		expect(readNoteHeader(`${hostile}!]\nx`)).toBeNull();
		expect(readNoteHeader(`${'['.repeat(4000)}eDraft on:"a"]\nx`)).toBeNull();
		expect(performance.now() - started).toBeLessThan(250);
	});

	it('a note with no header keeps every byte of its words', () => {
		expect(readNoteHeader('[[not a header]]')).toBeNull();
		expect(readNoteHeader('')).toBeNull();
	});
});

describe('Fountain round trip (§5.2)', () => {
	/* No trailing newline: that is what the serialiser writes. */
	const fountain = "[[[eDraft on:\"doesn't move\"]\nDana Reyes (Director): Too still?]]\n\nThe kettle screams. Mara doesn't move.";

	it('reads an anchored note, with the header off its words', () => {
		const note = parseFountain(fountain).elements[0];
		expect(note.type).toBe('note');
		expect(note.text).toBe('Dana Reyes (Director): Too still?');
		expect(note.anchor).toEqual({ on: "doesn't move" });
	});

	it('writes it back exactly, and the anchor survives the round trip', () => {
		const once = parseFountain(fountain);
		expect(serialiseFountain(once)).toBe(fountain);
		expect(parseFountain(serialiseFountain(once))).toEqual(once);
	});

	it('a note with no anchor is written exactly as before', () => {
		const plain = '[[Dana Reyes (Director): Too still?]]\n\nThe kettle screams.';
		const script = parseFountain(plain);
		expect(script.elements[0].anchor).toBeUndefined();
		expect(serialiseFountain(script)).toBe(plain);
	});

	it('words holding `]]` survive: the writer spaces them, the reader closes them up', () => {
		const script = parseFountain('The kettle screams.\n');
		const anchored = {
			titlePage: script.titlePage,
			elements: [{ type: 'note' as const, text: 'Why?', anchor: { on: 'kettle]] screams' } }, ...script.elements]
		};
		const written = serialiseFountain(anchored);
		expect(written).not.toContain(']]]');
		expect(parseFountain(written).elements[0].anchor).toEqual({ on: 'kettle]] screams' });
	});

	it('an anchored note inside a dialogue block is never written inline', () => {
		const script = {
			titlePage: [],
			elements: [
				{ type: 'character' as const, text: 'MARA' },
				{ type: 'note' as const, text: 'Too flat?', anchor: { on: 'same' } },
				{ type: 'dialogue' as const, text: "It's the same lab." }
			]
		};
		const written = serialiseFountain(script);
		expect(written).toContain('[eDraft on:"same"]');
		expect(parseFountain(written).elements.map((e) => e.type)).toEqual(['note', 'character', 'dialogue']);
	});
});
