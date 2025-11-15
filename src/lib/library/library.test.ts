import { describe, expect, it } from 'vitest';
import {
	createDocument,
	defaultLibrary,
	deleteDocument,
	deriveTitle,
	migrateFromLegacy,
	renameDocument,
	searchLibrary,
	undoDelete,
	updateActiveBody
} from './library';

describe('deriveTitle', () => {
	it('uses the first heading', () => {
		expect(deriveTitle('# Hello\n\nbody')).toBe('Hello');
	});

	it('falls back to first line', () => {
		expect(deriveTitle('Plain title\n\nmore')).toBe('Plain title');
	});
});

describe('searchLibrary', () => {
	const docs = [
		createDocument({ title: 'Alpha notes', body: 'cats and dogs', titleLocked: true }),
		createDocument({ title: 'Beta', body: 'only birds here', titleLocked: true })
	];

	it('returns all when query empty', () => {
		expect(searchLibrary(docs, '').length).toBe(2);
	});

	it('matches title and body', () => {
		expect(searchLibrary(docs, 'alpha').map((h) => h.doc.title)).toEqual(['Alpha notes']);
		expect(searchLibrary(docs, 'birds')[0].match).toBe('body');
	});
});

describe('delete and undo', () => {
	it('soft-deletes and restores', () => {
		let state = defaultLibrary('# One\n');
		const second = createDocument({ title: 'Two', body: '# Two\n', titleLocked: true });
		state = {
			...state,
			documents: [second, ...state.documents],
			activeId: second.id
		};
		const { state: after, deleted } = deleteDocument(state, second.id);
		expect(deleted).toBe(true);
		expect(after.documents.length).toBe(1);
		expect(after.trash?.doc.id).toBe(second.id);

		const restored = undoDelete(after);
		expect(restored.documents.some((d) => d.id === second.id)).toBe(true);
		expect(restored.activeId).toBe(second.id);
	});

	it('clears the last document instead of removing it', () => {
		const state = defaultLibrary('keep structure');
		const { clearedOnly, state: after } = deleteDocument(state, state.activeId);
		expect(clearedOnly).toBe(true);
		expect(after.documents.length).toBe(1);
		expect(after.documents[0].body).toBe('');
	});
});

describe('updateActiveBody / rename', () => {
	it('auto-titles unlocked documents', () => {
		let state = defaultLibrary('');
		state = updateActiveBody(state, '# New Title\n\nHi');
		expect(state.documents[0].title).toBe('New Title');
	});

	it('respects locked titles', () => {
		let state = defaultLibrary('# X\n');
		state = renameDocument(state, state.activeId, 'Locked');
		state = updateActiveBody(state, '# Different\n');
		expect(state.documents[0].title).toBe('Locked');
	});
});

describe('migrateFromLegacy', () => {
	it('wraps a v1 document', () => {
		const lib = migrateFromLegacy(
			{ doc: '# Legacy\n\ntext', view: 'split', focus: false },
			''
		);
		expect(lib.documents).toHaveLength(1);
		expect(lib.documents[0].body).toContain('Legacy');
		expect(lib.ui.view).toBe('split');
	});
});
