import { describe, expect, it } from 'vitest';
import { draftFromScreenplay } from './draftfile.js';
import type { Screenplay } from './types.js';
describe('persistent draft identity', () => {
	it('preserves ids and the retired-id high-water counter in script.json', () => {
		const model = JSON.parse('{"titlePage":[],"elements":[{"type":"action","text":"Alpha","id":"a"},{"type":"action","text":"Beta","id":"z"}],"nextId":"20"}') as Screenplay;
		const document = draftFromScreenplay(model);
		expect((document.script.get('elements') as Map<string, unknown>[]).map(e => e.get('id'))).toEqual(['a', 'z']);
		expect(document.script.get('nextId')).toBe('20');
	});
});
import { readFileSync } from 'node:fs';
import { DraftIDAllocator, draftElementID, identifyScreenplay, restoreIdentifiedScreenplay } from './identity.js';
import { canonicalJson, draftFromIdentifiedScreenplay, draftToIdentifiedScreenplay, parseDraftJson } from './draftfile.js';
import type { JsonObject } from './draftfile.js';
const corpus = JSON.parse(readFileSync(new URL('../../../apple/eDraftEngine/Fixtures/identity.json', import.meta.url), 'utf8'));
it('matches all pinned allocator traces', () => {
	for (const c of corpus.allocations) {
		const allocator = new DraftIDAllocator(c.nextId, c.reserved.map(draftElementID));
		const trace = c.events.map((e: {
			mint?: number;
			retain?: string;
		}) => {
			const ids = [];
			if (e.retain)
				allocator.retain(e.retain);
			for (let i = 0; i < (e.mint ?? 0); i++)
				ids.push(allocator.mint());
			return { ids, nextId: allocator.nextId };
		});
		expect(trace, c.name).toEqual(c.trace);
	}
});
it('writes and reopens the identical script.json bytes', () => {
	for (const c of corpus.documents) {
		const model = restoreIdentifiedScreenplay(c.model);
		const document = draftFromIdentifiedScreenplay(model);
		expect(canonicalJson(document.script), c.name).toBe(c.script);
		const reopened = draftToIdentifiedScreenplay({ ...document, script: parseDraftJson(c.script) as JsonObject }).screenplay;
		expect(reopened, c.name).toEqual(model);
	}
});
it('rejects invalid, missing, duplicate, and exhausted identities without consuming a value', () => {
	for (const c of corpus.invalidCounters)
		expect(() => new DraftIDAllocator(c)).toThrow();
	for (const id of corpus.invalidIDs)
		expect(() => draftElementID(id)).toThrow();
	const allocator = new DraftIDAllocator('z'.repeat(64));
	expect(() => allocator.mint()).toThrow();
	expect(allocator.nextId).toBe('z'.repeat(64));
	expect(() => restoreIdentifiedScreenplay({ titlePage: [], elements: [], nextId: undefined })).toThrow();
	expect(() => restoreIdentifiedScreenplay({ titlePage: [], elements: [{ type: 'action', text: 'a' }], nextId: '2' })).toThrow();
	expect(() => restoreIdentifiedScreenplay({ titlePage: [], elements: [{ type: 'action', text: 'a', id: draftElementID('1') }, { type: 'action', text: 'b', id: draftElementID('1') }], nextId: '2' })).toThrow();
});
it('imports allocate from the receiving counter and never bring source IDs', () => {
	const allocator = new DraftIDAllocator('a');
	const imported = identifyScreenplay({ titlePage: [], elements: [{ type: 'action', text: 'a', id: draftElementID('1') }, { type: 'action', text: 'b', id: draftElementID('2') }] }, allocator);
	expect(imported.elements.map(e => e.id)).toEqual(['a', 'b']);
	expect(allocator.nextId).toBe('c');
});
import { readDraft, writeDraft } from './draftfile.js';
it('persists identity through the real draft ZIP container', async () => {
	for (const c of corpus.documents) {
		const doc = draftFromIdentifiedScreenplay(restoreIdentifiedScreenplay(c.model));
		const bytes = writeDraft(doc, { writer: { name: 'identity', version: '1' } });
		expect(Buffer.from(bytes).toString('hex')).toBe(c.zip);
		const reopened = await readDraft(bytes);
		expect(draftToIdentifiedScreenplay(reopened.document).screenplay).toEqual(c.model);
	}
});
it('failed multi-element adoption does not partially consume the counter', () => {
	const before = 'z'.repeat(63) + 'y';
	const allocator = new DraftIDAllocator(before);
	expect(() => identifyScreenplay({ titlePage: [], elements: [{ type: 'action', text: 'a' }, { type: 'action', text: 'b' }] }, allocator)).toThrow();
	expect(allocator.nextId).toBe(before);
});
