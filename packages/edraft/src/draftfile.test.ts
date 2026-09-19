/** The .draft 1.0 file (docs/RFC-DRAFT-FORMAT.md): write, read, keep, recover. */
import { readFileSync } from 'node:fs';
import { deflateRawSync } from 'node:zlib';
import { describe, expect, it } from 'vitest';
import {
	canonicalJson,
	detectDraftFormat,
	draftAnchorContext,
	draftFromScreenplay,
	draftToScreenplay,
	DraftFormatError,
	jcs,
	parseDraftJson,
	readDraft,
	writeDraft
} from './draftfile.js';
import type { DraftDocument, JsonObject, JsonValue } from './draftfile.js';
import { parseFountain } from './parse.js';
import { sha256Hex } from './sha256.js';
import { readZipEntries } from './zip.js';
import { writeZipStored } from './zipwrite.js';

const WRITER = { name: 'eDraft', version: 'test' };
const utf8 = (text: string): Uint8Array => new TextEncoder().encode(text);
const text = (bytes: Uint8Array): string => new TextDecoder().decode(bytes);

/** Invented script text only — the repository is public. */
const SAMPLE = [
	'Title: The Kettle',
	'Author: Sam Okafor',
	'',
	'INT. KITCHEN - NIGHT',
	'',
	'[[Too still? She should flinch.]]',
	'',
	'The kettle **screams**. Mara doesn’t move.',
	'',
	'MARA',
	'(quietly)',
	'Not yet.',
	'',
	'CUT TO:',
	''
].join('\n');

function sampleDocument(): DraftDocument {
	return draftFromScreenplay(parseFountain(SAMPLE, { emphasis: 'runs' }), { title: 'The Kettle' });
}

/** A document as one comparable string: its trees and its parts. */
function key(document: DraftDocument): string {
	const hex = (bytes: Uint8Array): string => Buffer.from(bytes).toString('hex');
	const tree: JsonObject = new Map<string, JsonValue>([
		['title', document.title ?? null],
		['script', document.script],
		['notes', document.notes ?? null],
		['revisions', document.revisions ?? null],
		['production', document.production ?? null],
		['manifestExtra', document.manifestExtra ?? null],
		[
			'parts',
			[...document.parts]
				.sort((a, b) => (a.path < b.path ? -1 : 1))
				.map((part) => new Map<string, JsonValue>([['path', part.path], ['data', hex(part.data)], ['damaged', part.damaged === true]]))
		]
	]);
	return canonicalJson(tree);
}

async function entriesOf(bytes: Uint8Array): Promise<Map<string, Uint8Array>> {
	return new Map((await readZipEntries(bytes)).map((entry) => [entry.name, entry.data]));
}

/** Rezip entries as a writer that is not eDraft would: same order, stored. */
function rezip(entries: Map<string, Uint8Array>): Uint8Array {
	return writeZipStored([...entries].map(([name, data]) => ({ name, data })), { dosDate: 0x0021 });
}

describe('I-JSON and the canonical form', () => {
	it('parses what it should and keeps member order', () => {
		const value = parseDraftJson('{"b": 1, "a": [true, null, "x"], "2": -3}') as JsonObject;
		expect([...value.keys()]).toEqual(['b', 'a', '2']);
		expect(value.get('a')).toEqual([true, null, 'x']);
	});

	it.each([
		['a duplicate member', '{"a": 1, "a": 2}'],
		['a fraction', '{"a": 1.5}'],
		['an exponent', '{"a": 1e3}'],
		['an integer past 2^53', '{"a": 9007199254740993}'],
		['a lone surrogate', '"\\ud800"'],
		['a byte-order mark', '﻿{}'],
		['trailing characters', '{} x'],
		['a raw control character', '"ab"'],
		['nesting past 64', '['.repeat(65) + ']'.repeat(65)]
	])('refuses %s', (_, source) => {
		expect(() => parseDraftJson(source)).toThrow();
	});

	it('writes what JSON.stringify writes, with a final newline', () => {
		const plain = { a: [1, { b: 'q"\\\n\x01\u2028' }], c: {}, d: [] };
		const tree = parseDraftJson(JSON.stringify(plain));
		expect(canonicalJson(tree)).toBe(JSON.stringify(plain, null, 2) + '\n');
	});

	it('writes RFC 8785 with members sorted by UTF-16 code units', () => {
		const tree = parseDraftJson('{"\\u20ac": 1, "\\ud83d\\ude00": 2, "a": {"z": 0, "b": []}, "\\u0080": 3}');
		expect(jcs(tree)).toBe('{"a":{"b":[],"z":0},"\u0080":3,"\u20ac":1,"\ud83d\ude00":2}');
	});
});

describe('writing', () => {
	it('lays the file out in the ISO/IEC 21320-1 profile, stamped 1980-01-01', async () => {
		const bytes = writeDraft(sampleDocument(), { writer: WRITER });
		expect(text(bytes.subarray(30, 38))).toBe('mimetype');
		expect(text(bytes.subarray(38, 38 + 32))).toBe('application/vnd.edraft.draft+zip');
		expect(bytes[8]! | (bytes[9]! << 8)).toBe(0); /* stored */
		expect(bytes[12]! | (bytes[13]! << 8)).toBe(0x0021); /* 1980-01-01 */
		const names = (await readZipEntries(bytes)).map((entry) => entry.name);
		expect(names).toEqual(['mimetype', 'manifest.json', 'script.json', 'notes.json', 'script.fountain']);
	});

	it('writes the same bytes every time', () => {
		expect(writeDraft(sampleDocument(), { writer: WRITER })).toEqual(writeDraft(sampleDocument(), { writer: WRITER }));
	});

	it('lists every part with its digest, and fingerprints the script by JCS', async () => {
		const document = sampleDocument();
		const entries = await entriesOf(writeDraft(document, { writer: WRITER }));
		const manifest = parseDraftJson(text(entries.get('manifest.json')!)) as JsonObject;
		const parts = manifest.get('parts') as JsonObject[];
		expect(parts.map((part) => part.get('path'))).toEqual(['script.json', 'notes.json', 'script.fountain']);
		for (const part of parts) {
			const data = entries.get(part.get('path') as string)!;
			expect(part.get('sha256')).toBe(sha256Hex(data));
			expect(part.get('size')).toBe(data.length);
		}
		const fingerprints = manifest.get('fingerprints') as JsonObject;
		expect(fingerprints.get('script')).toBe(sha256Hex(utf8(jcs(document.script))));
		expect(manifest.get('title')).toBe('The Kettle');
	});

	it('sets the UTF-8 flag for a name that is not ASCII, and orders origin, others, extensions', async () => {
		const document = sampleDocument();
		document.parts = [
			{ path: 'ext/com.example/b.json', data: utf8('{}') },
			{ path: 'revisions.json', data: utf8('{}') },
			{ path: 'origin/source.fountain', data: utf8(SAMPLE) },
			{ path: 'ext/com.example/été.txt', data: utf8('x') }
		];
		const bytes = writeDraft(document, { writer: WRITER });
		const names = (await readZipEntries(bytes)).map((entry) => entry.name);
		expect(names.slice(5)).toEqual(['origin/source.fountain', 'revisions.json', 'ext/com.example/b.json', 'ext/com.example/été.txt']);
		const flags = localHeaders(bytes);
		expect(flags.get('ext/com.example/\u00e9t\u00e9.txt')).toBe(0x0800);
		expect(flags.get('ext/com.example/b.json')).toBe(0);
	});

	it('refuses a document that is not valid', () => {
		const document = sampleDocument();
		(document.script.get('elements') as JsonObject[])[0]!.set('type', 'note');
		expect(() => writeDraft(document, { writer: WRITER })).toThrow(DraftFormatError);
	});
});

describe('reading', () => {
	it('reads back exactly what was written, and says nothing', async () => {
		const document = sampleDocument();
		const result = await readDraft(writeDraft(document, { writer: WRITER }));
		expect(result.diagnostics).toEqual([]);
		expect(result.readOnly).toBe(false);
		expect(key(result.document)).toBe(key(document));
	});

	it('keeps every member and part it does not know, byte for byte (must-preserve)', async () => {
		const document = sampleDocument();
		document.script.set('x-future', new Map<string, JsonValue>([['2', 1], ['a', [null]]]));
		(document.script.get('elements') as JsonObject[])[1]!.set('com.example.tag', 'kept');
		((document.notes!.get('threads') as JsonObject[])[0]!.get('messages') as JsonObject[])[0]!.set('mood', 'wry');
		document.manifestExtra = new Map<string, JsonValue>([['generator', 'another tool']]);
		document.parts = [
			{ path: 'ext/com.example/data.bin', data: new Uint8Array([0, 1, 2, 255]) },
			{ path: 'history/2026-09-01.json', data: utf8('{"kept": true}') }
		];
		const first = writeDraft(document, { writer: WRITER });
		const read = await readDraft(first);
		expect(read.diagnostics).toEqual([]);
		expect(writeDraft(read.document, { writer: WRITER })).toEqual(first);
	});

	it('opens a newer minor version read-only, and refuses a newer major', async () => {
		const entries = await entriesOf(writeDraft(sampleDocument(), { writer: WRITER }));
		const bump = (minReader: string, version: string): Uint8Array => {
			const manifest = parseDraftJson(text(entries.get('manifest.json')!)) as JsonObject;
			manifest.set('minReader', minReader);
			manifest.set('version', version);
			return rezip(new Map([...entries, ['manifest.json', utf8(canonicalJson(manifest))]]));
		};
		const newerMinor = await readDraft(bump('1.4', '1.4'));
		expect(newerMinor.readOnly).toBe(true);
		expect(newerMinor.diagnostics).toEqual([{ code: 'read-only-newer-minor', detail: '1.4' }]);
		await expect(readDraft(bump('2.0', '2.0'))).rejects.toMatchObject({ code: 'newer-major' });
	});
});



describe('production parts (RFC-DRAFT-PRODUCTION §6–§7)', () => {
	const sha = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
	const pageAnchor = (element: string, offset: number): JsonObject =>
		new Map<string, JsonValue>([['element', element], ['offset', offset]]);
	const pages = (): JsonObject => new Map<string, JsonValue>([
		['fingerprint', new Map<string, JsonValue>([['paginator', '1.0'], ['paper', 'us-letter'], ['sha256', sha]])],
		['locks', [new Map<string, JsonValue>([
			['label', '1'],
			['start', pageAnchor('1', 0)],
			['end', pageAnchor('8', 0)]
		])]]
	]);

	function prepared(): DraftDocument {
		const document = sampleDocument();
		document.revisions = new Map<string, JsonValue>([['sets', []], ['nextId', '1']]);
		document.production = new Map<string, JsonValue>([
			['state', 'prepared'],
			['sceneNumbers', new Map<string, JsonValue>([['locked', true]])],
			['pages', pages()]
		]);
		return document;
	}

	it('round-trips a prepared file with revisions.json and production.json', async () => {
		const document = prepared();
		const bytes = writeDraft(document, { writer: WRITER });
		const names = [...(await entriesOf(bytes)).keys()];
		expect(names.indexOf('script.fountain')).toBeLessThan(names.indexOf('revisions.json'));
		expect(names.indexOf('revisions.json')).toBeLessThan(names.indexOf('production.json'));
		const result = await readDraft(bytes);
		expect(result.diagnostics).toEqual([]);
		expect(writeDraft(result.document, { writer: WRITER })).toEqual(bytes);
		expect(key(result.document)).toBe(key(document));
	});

	it('round-trips an issued file with two sets and a snapshot path', async () => {
		const document = prepared();
		document.revisions = new Map<string, JsonValue>([
			['sets', [
				new Map<string, JsonValue>([
					['id', '1'], ['colour', 'White'], ['mark', '*'], ['name', 'White draft'],
					['at', '2026-09-01T12:00:00Z'], ['snapshot', 'history/prepared.json']
				]),
				new Map<string, JsonValue>([
					['id', '2'], ['colour', 'Blue'], ['mark', '*'], ['name', 'Blue revisions'],
					['at', '2026-09-18T10:00:00Z'], ['snapshot', 'history/2.json']
				])
			]],
			['nextId', '3']
		]);
		document.production!.set('state', 'issued');
		const bytes = writeDraft(document, { writer: WRITER });
		const result = await readDraft(bytes);
		expect(result.diagnostics).toEqual([]);
		expect(writeDraft(result.document, { writer: WRITER })).toEqual(bytes);
		expect((result.document.revisions!.get('sets') as JsonObject[]).map((s) => s.get('snapshot'))).toEqual([
			'history/prepared.json', 'history/2.json'
		]);
	});

	it('round-trips an omission, keeping the body in script.json', async () => {
		const document = prepared();
		document.production!.set('omissions', [
			new Map<string, JsonValue>([['id', '1'], ['number', '1'], ['elements', ['1']], ['issued', '1']])
		]);
		const bytes = writeDraft(document, { writer: WRITER });
		const result = await readDraft(bytes);
		expect(result.diagnostics).toEqual([]);
		expect(writeDraft(result.document, { writer: WRITER })).toEqual(bytes);
		expect((document.script.get('elements') as JsonObject[])[0]!.get('text')).toBe('INT. KITCHEN - NIGHT');
	});

	it('keeps unknown members inside sets, locks, omissions and tags', async () => {
		const document = prepared();
		(document.revisions!.get('sets') as JsonValue[]);
		document.revisions!.set('sets', [
			new Map<string, JsonValue>([
				['id', '1'], ['colour', 'White'], ['snapshot', 'history/prepared.json'], ['com.example.note', 'kept']
			])
		]);
		document.revisions!.set('nextId', '2');
		const lock = ((document.production!.get('pages') as JsonObject).get('locks') as JsonObject[])[0]!;
		lock.set('com.example.gap', true);
		document.production!.set('omissions', [
			new Map<string, JsonValue>([['id', '1'], ['number', '1'], ['elements', ['1']], ['mood', 'wry']])
		]);
		document.production!.set('tags', [
			new Map<string, JsonValue>([['id', 't1'], ['label', 'kettle'], ['color', 'teal']])
		]);
		const first = writeDraft(document, { writer: WRITER });
		const read = await readDraft(first);
		expect(read.diagnostics).toEqual([]);
		expect(writeDraft(read.document, { writer: WRITER })).toEqual(first);
		expect(((read.document.revisions!.get('sets') as JsonObject[])[0]!.get('com.example.note'))).toBe('kept');
	});

	it('a development file writes neither part', async () => {
		const names = [...(await entriesOf(writeDraft(sampleDocument(), { writer: WRITER }))).keys()];
		expect(names).not.toContain('revisions.json');
		expect(names).not.toContain('production.json');
	});

	it('reports issued state with empty sets, and does not pick a state', async () => {
		const document = prepared();
		document.production!.set('state', 'issued');
		const result = await readDraft(writeDraft(document, { writer: WRITER }));
		expect(result.document.production!.get('state')).toBe('issued');
		expect(result.document.revisions!.get('sets')).toEqual([]);
		expect(result.diagnostics).toEqual([{
			code: 'state-contradiction',
			path: 'production.json',
			detail: 'state is "issued" but revisions.json has no sets'
		}]);
	});
});

describe('the recovery ladder (§7.2)', () => {
	it('uses an outside edit and says so', async () => {
		const entries = await entriesOf(writeDraft(sampleDocument(), { writer: WRITER }));
		const script = parseDraftJson(text(entries.get('script.json')!)) as JsonObject;
		(script.get('elements') as JsonObject[])[0]!.set('text', 'INT. KITCHEN - DAY');
		const result = await readDraft(rezip(new Map([...entries, ['script.json', utf8(canonicalJson(script))]])));
		expect(result.diagnostics).toEqual([{ code: 'outside-edit', path: 'script.json' }]);
		expect(((result.document.script.get('elements') as JsonObject[])[0]!).get('text')).toBe('INT. KITCHEN - DAY');
	});

	it('keeps a damaged part byte for byte and writes it back where it was', async () => {
		const entries = await entriesOf(writeDraft(sampleDocument(), { writer: WRITER }));
		const broken = utf8('{"threads": [ oops');
		const result = await readDraft(rezip(new Map([...entries, ['notes.json', broken]])));
		expect(result.diagnostics).toEqual([{ code: 'part-damaged', path: 'notes.json', detail: 'it is not valid I-JSON' }]);
		expect(result.document.notes).toBeUndefined();
		const again = await entriesOf(writeDraft(result.document, { writer: WRITER }));
		expect(again.get('notes.json')).toEqual(broken);
	});

	it('opens a damaged script from its rendition, re-finding or detaching its threads', async () => {
		const entries = await entriesOf(writeDraft(sampleDocument(), { writer: WRITER }));
		const result = await readDraft(rezip(new Map([...entries, ['script.json', utf8('not json')]])));
		expect(result.diagnostics.map((d) => d.code)).toEqual(['part-damaged', 'script-from-rendition', 'anchor-detached']);
		const elements = result.document.script.get('elements') as JsonObject[];
		expect(elements.map((e) => e.get('type'))).toEqual(['scene', 'action', 'character', 'parenthetical', 'dialogue', 'transition']);
		const again = await entriesOf(writeDraft(result.document, { writer: WRITER }));
		expect(again.get('damaged/script.json')).toEqual(utf8('not json'));
	});

	it('reads a truncated file from its local headers', async () => {
		const bytes = writeDraft(sampleDocument(), { writer: WRITER });
		const entries = await readZipEntries(bytes);
		const renditionEnd = [...entries].reduce((at, entry) => at + 30 + utf8(entry.name).length + entry.data.length, 0);
		const result = await readDraft(bytes.slice(0, renditionEnd));
		expect(result.diagnostics.map((d) => d.code)).toEqual(['directory-damaged']);
		expect(key(result.document)).toBe(key(sampleDocument()));
	});

	it('refuses a file with no readable script, and never opens it empty', async () => {
		const entries = await entriesOf(writeDraft(sampleDocument(), { writer: WRITER }));
		const bytes = rezip(new Map([...entries, ['script.json', utf8('x')], ['script.fountain', new Uint8Array([0xff, 0xfe])]]));
		await expect(readDraft(bytes)).rejects.toMatchObject({ code: 'no-script' });
	});

	it('refuses an archive over the entry limit, and does not expand a bomb', async () => {
		const many = new Map<string, Uint8Array>([['mimetype', utf8('application/vnd.edraft.draft+zip')]]);
		for (let i = 0; i < 520; i++) many.set(`ext/x/${i}`, new Uint8Array(0));
		await expect(readDraft(rezip(many))).rejects.toMatchObject({ code: 'over-limits' });

		const good = await entriesOf(writeDraft(sampleDocument(), { writer: WRITER }));
		const zeros = deflateRawSync(new Uint8Array(1_000_000));
		/* One more entry, deflated, declaring a 1,000,000-byte expansion. */
		const result = await readDraft(appendDeflated(rezip(good), 'ext/x/bomb', zeros, 1_000_000));
		expect(result.diagnostics.some((d) => d.code === 'part-damaged' && d.path === 'ext/x/bomb')).toBe(true);
	});
});

/** Each local header's general-purpose flags, by entry name. */
function localHeaders(bytes: Uint8Array): Map<string, number> {
	const out = new Map<string, number>();
	const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
	for (let at = 0; view.getUint32(at, true) === 0x04034b50; ) {
		const nameLength = view.getUint16(at + 26, true);
		out.set(text(bytes.subarray(at + 30, at + 30 + nameLength)), view.getUint16(at + 6, true));
		at += 30 + nameLength + view.getUint16(at + 28, true) + view.getUint32(at + 18, true);
	}
	return out;
}

/** A copy of `archive` with one more, deflated, entry — built by hand, as
	another tool would, so the reader's limits can be tested. */
function appendDeflated(archive: Uint8Array, name: string, packed: Uint8Array, rawSize: number): Uint8Array {
	const view = new DataView(archive.buffer, archive.byteOffset, archive.byteLength);
	const eocd = archive.length - 22;
	const count = view.getUint16(eocd + 10, true);
	const centralSize = view.getUint32(eocd + 12, true);
	const centralOffset = view.getUint32(eocd + 16, true);
	const nameBytes = utf8(name);
	const local = new Uint8Array(30 + nameBytes.length);
	const lv = new DataView(local.buffer);
	lv.setUint32(0, 0x04034b50, true);
	lv.setUint16(4, 20, true);
	lv.setUint16(8, 8, true);
	lv.setUint32(18, packed.length, true);
	lv.setUint32(22, rawSize, true);
	lv.setUint16(26, nameBytes.length, true);
	local.set(nameBytes, 30);
	const record = new Uint8Array(46 + nameBytes.length);
	const rv = new DataView(record.buffer);
	rv.setUint32(0, 0x02014b50, true);
	rv.setUint16(4, 20, true);
	rv.setUint16(6, 20, true);
	rv.setUint16(10, 8, true);
	rv.setUint32(20, packed.length, true);
	rv.setUint32(24, rawSize, true);
	rv.setUint16(28, nameBytes.length, true);
	rv.setUint32(42, centralOffset, true);
	record.set(nameBytes, 46);
	const end = new Uint8Array(22);
	const ev = new DataView(end.buffer);
	ev.setUint32(0, 0x06054b50, true);
	ev.setUint16(8, count + 1, true);
	ev.setUint16(10, count + 1, true);
	ev.setUint32(12, centralSize + record.length, true);
	ev.setUint32(16, centralOffset + local.length + packed.length, true);
	const out = new Uint8Array(centralOffset + local.length + packed.length + centralSize + record.length + 22);
	let at = 0;
	for (const chunk of [archive.subarray(0, centralOffset), local, packed, archive.subarray(centralOffset, centralOffset + centralSize), record, end]) {
		out.set(chunk, at);
		at += chunk.length;
	}
	return out;
}

describe('anchors (§6.5)', () => {
	async function reread(edit: (document: DraftDocument) => void, scriptEdit?: (script: JsonObject) => void) {
		const document = sampleDocument();
		edit(document);
		const entries = await entriesOf(writeDraft(document, { writer: WRITER }));
		if (scriptEdit) {
			const script = parseDraftJson(text(entries.get('script.json')!)) as JsonObject;
			scriptEdit(script);
			entries.set('script.json', utf8(canonicalJson(script)));
		}
		return readDraft(rezip(entries));
	}
	const onWords = (document: DraftDocument): void => {
		const thread = (document.notes!.get('threads') as JsonObject[])[0]!;
		const words = 'Mara doesn’t move';
		const line = (document.script.get('elements') as JsonObject[])[1]!.get('text') as string;
		const start = line.indexOf(words);
		const { prefix, suffix } = draftAnchorContext(line, start, start + words.length);
		thread.set('anchor', new Map<string, JsonValue>([
			['element', '2'], ['start', start], ['end', start + words.length], ['quote', words], ['prefix', prefix], ['suffix', suffix]
		]));
	};
	const anchorOf = (document: DraftDocument): JsonObject | undefined =>
		(document.notes!.get('threads') as JsonObject[])[0]!.get('anchor') as JsonObject | undefined;

	it('writes whole words of context either side', () => {
		expect(draftAnchorContext('The kettle screams. Mara doesn\u2019t move.', 20, 37)).toEqual({ prefix: 'kettle screams. ', suffix: '.' });
		expect(draftAnchorContext('The quick brown foxes jump over it', 22, 26)).toEqual({ prefix: 'brown foxes ', suffix: ' over it' });
		expect(draftAnchorContext('Unbroken', 2, 4)).toEqual({ prefix: 'Un', suffix: 'oken' });
	});

	it('holds an anchor whose words are where it says', async () => {
		const result = await reread(onWords);
		expect(result.diagnostics).toEqual([]);
		expect(anchorOf(result.document)?.get('start')).toBe(20);
	});

	it('moves an anchor within its element when the words moved, silently', async () => {
		const result = await reread(onWords, (script) =>
			(script.get('elements') as JsonObject[])[1]!.set('text', 'Steam. The kettle screams. Mara doesn’t move.'));
		expect(result.diagnostics).toEqual([{ code: 'outside-edit', path: 'script.json' }]);
		expect(anchorOf(result.document)?.get('start')).toBe(27);
	});

	it('flags words that changed, and never guesses', async () => {
		const result = await reread(onWords, (script) =>
			(script.get('elements') as JsonObject[])[1]!.set('text', 'The kettle screams. Mara runs.'));
		expect(result.diagnostics).toEqual([
			{ code: 'outside-edit', path: 'script.json' },
			{ code: 'anchor-words-changed', thread: '1' }
		]);
	});

	it('follows its words to another element, with a flag, when its element is gone', async () => {
		const result = await reread(onWords, (script) => {
			const elements = script.get('elements') as JsonObject[];
			elements.splice(1, 1);
			elements.push(new Map<string, JsonValue>([['id', '9'], ['type', 'action'], ['text', 'The kettle screams. Mara doesn’t move.']]));
		});
		expect(result.diagnostics).toEqual([
			{ code: 'outside-edit', path: 'script.json' },
			{ code: 'anchor-moved', thread: '1' }
		]);
		expect(anchorOf(result.document)?.get('element')).toBe('9');
	});

	it('detaches a thread whose element and words are gone, and keeps it', async () => {
		const result = await reread(onWords, (script) => (script.get('elements') as JsonObject[]).splice(1, 1));
		expect(result.diagnostics.at(-1)).toEqual({ code: 'anchor-detached', thread: '1' });
		expect(anchorOf(result.document)).toBeUndefined();
		expect((result.document.notes!.get('threads') as JsonObject[]).length).toBe(1);
	});
});

describe('bridges to today’s model', () => {
	const corpus = JSON.parse(
		readFileSync(new URL('../../../apple/eDraftEngine/Fixtures/parse.json', import.meta.url), 'utf8')
	) as Array<{ name: string; source: string }>;

	it.each(corpus.map((c) => [c.name, c.source]))('round-trips the parse corpus: %s', (_, source) => {
		const screenplay = parseFountain(source, { emphasis: 'runs' });
		expect(draftToScreenplay(draftFromScreenplay(screenplay)).screenplay).toEqual(screenplay);
	});

	it('anchors a note to the element after it, and keeps a trailing note detached at the end', () => {
		const document = draftFromScreenplay(parseFountain('[[First]]\n\nA line.\n\n[[Last]]\n', { emphasis: 'runs' }));
		const threads = document.notes!.get('threads') as JsonObject[];
		expect((threads[0]!.get('anchor') as JsonObject).get('element')).toBe('1');
		expect(threads[1]!.get('anchor')).toBeUndefined();
		expect(draftToScreenplay(document).diagnostics).toEqual([{ code: 'anchor-detached', thread: '3' }]);
	});

	it('writes each message as a line, with its author, and says when a word anchor degrades', () => {
		const document = sampleDocument();
		const thread = (document.notes!.get('threads') as JsonObject[])[0]!;
		thread.set('messages', [
			new Map<string, JsonValue>([['id', '2'], ['by', 'Dana Reyes'], ['role', 'Director'], ['text', 'Too still?']]),
			new Map<string, JsonValue>([['id', '3'], ['by', 'Sam Okafor'], ['text', 'On purpose.']])
		]);
		(thread.get('anchor') as JsonObject).set('quote', 'screams');
		const { screenplay, diagnostics } = draftToScreenplay(document);
		expect(screenplay.elements[1]).toEqual({ type: 'note', text: 'Dana Reyes (Director): Too still?\nSam Okafor: On purpose.' });
		expect(diagnostics).toEqual([{ code: 'anchor-degraded', thread: '1' }]);
	});
});

describe('recognising a file by its bytes (§11.1)', () => {
	it.each([
		['a .draft', () => writeDraft(sampleDocument(), { writer: WRITER }), 'draft'],
		['a PDF', () => utf8('%PDF-1.7\n'), 'pdf'],
		['an FDX', () => utf8('<?xml version="1.0"?><FinalDraft/>'), 'fdx'],
		['an FDX with a byte-order mark', () => utf8('﻿\n<FinalDraft/>'), 'fdx'],
		['Fountain text', () => utf8(SAMPLE), 'text'],
		['an empty file', () => new Uint8Array(0), 'text'],
		['bytes that are not UTF-8', () => new Uint8Array([0xc3, 0x28]), 'unknown'],
		['another ZIP', () => writeZipStored([{ name: 'word/document.xml', data: utf8('<w/>') }]), 'unknown']
	])('%s', (_, bytes, format) => {
		expect(detectDraftFormat(bytes())).toBe(format);
	});
});

describe('fuzz: damage never opens silently (B3)', () => {
	const documents: Array<[string, DraftDocument]> = [
		['the sample', sampleDocument()],
		['no notes', draftFromScreenplay(parseFountain('INT. HALL - DAY\n\nQuiet.\n', { emphasis: 'runs' }))],
		['with parts', (() => {
			const document = sampleDocument();
			document.parts = [{ path: 'origin/source.fountain', data: utf8(SAMPLE) }];
			return document;
		})()]
	];

	it.each(documents)('%s: every byte changed and every truncation', async (_, document) => {
		const original = writeDraft(document, { writer: WRITER });
		const expected = key((await readDraft(original)).document);
		const check = async (bytes: Uint8Array): Promise<void> => {
			let result;
			try {
				result = await readDraft(bytes);
			} catch (error) {
				expect(error).toBeInstanceOf(DraftFormatError);
				return;
			}
			if (result.diagnostics.length === 0) expect(key(result.document)).toBe(expected);
		};
		for (let i = 0; i < original.length; i++) {
			const bytes = original.slice();
			bytes[i] = bytes[i]! ^ 0xff;
			await check(bytes);
		}
		for (let length = 0; length < original.length; length++) await check(original.slice(0, length));
	}, 120_000);
});
