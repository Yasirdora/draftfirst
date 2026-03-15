/**
 * Desk store — document & persistence flows against in-memory storage.
 * The store is DOM-free by design, so these run in Node.
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DeskStore } from './desk.svelte';
import { LIBRARY_KEY } from '$lib/library/library';
import type { LibraryUiPrefs } from '$lib/library/types';

function shimLocalStorage() {
	const map = new Map<string, string>();
	const storage = {
		getItem: (key: string) => (map.has(key) ? map.get(key)! : null),
		setItem: (key: string, value: string) => void map.set(key, String(value)),
		removeItem: (key: string) => void map.delete(key),
		clear: () => map.clear(),
		key: (index: number) => [...map.keys()][index] ?? null,
		get length() {
			return map.size;
		}
	};
	vi.stubGlobal('localStorage', storage);
	return map;
}

const UI: LibraryUiPrefs = { libraryOpen: true, view: 'page', focus: false };

function freshDesk() {
	const store = new DeskStore();
	store.uiSnapshot = () => UI;
	return store;
}

beforeEach(() => {
	shimLocalStorage();
});

describe('init', () => {
	it('creates a default library from the sample when storage is empty', () => {
		const store = freshDesk();
		const ui = store.init('# Sample\n');
		expect(store.library?.documents).toHaveLength(1);
		expect(store.doc).toBe('# Sample\n');
		expect(ui).toEqual(UI);
	});

	it('reloads a persisted library instead of the sample', () => {
		const first = freshDesk();
		first.init('# Sample\n');
		first.doc = '# Saved work\n';
		first.persistImmediate();

		const second = freshDesk();
		second.init('# Sample\n');
		expect(second.doc).toBe('# Saved work\n');
		expect(second.library?.activeId).toBe(first.library?.activeId);
	});
});

describe('derived counts', () => {
	it('tracks words, characters, and reading time from the body', () => {
		const store = freshDesk();
		store.init('');
		store.doc = 'one two three';
		expect(store.wordCount).toBe(3);
		expect(store.charCount).toBe(13);
		expect(store.readTime).toBe(1);
		store.doc = '';
		expect(store.wordCount).toBe(0);
		expect(store.readTime).toBe(0);
	});
});

describe('persistence', () => {
	it('persistImmediate writes merged UI prefs and reports Saved', () => {
		const store = freshDesk();
		store.init('# A\n');
		store.doc = '# A\n\nedited';
		store.persistImmediate();
		expect(store.saveLabel).toBe('Saved');
		expect(store.saveOn).toBe(true);

		const raw = JSON.parse(localStorage.getItem(LIBRARY_KEY)!);
		expect(raw.documents[0].body).toBe('# A\n\nedited');
		expect(raw.ui).toEqual(UI);
	});

	it('surfaces storage failure as a sticky label instead of throwing', () => {
		const store = freshDesk();
		store.init('# A\n');
		vi.stubGlobal('localStorage', {
			getItem: () => null,
			setItem: () => {
				throw new Error('quota');
			}
		});
		store.persistImmediate();
		expect(store.saveLabel).not.toBe('Saved');
		expect(store.saveOn).toBe(true);
	});

	it('debounced persist eventually saves', () => {
		vi.useFakeTimers();
		try {
			const store = freshDesk();
			store.init('# A\n');
			store.persistImmediate(); // establish a saved baseline
			store.doc = '# A\n\nlater';
			store.persist();
			expect(JSON.parse(localStorage.getItem(LIBRARY_KEY)!).documents[0].body).toBe('# A\n');
			vi.advanceTimersByTime(500);
			expect(JSON.parse(localStorage.getItem(LIBRARY_KEY)!).documents[0].body).toBe(
				'# A\n\nlater'
			);
		} finally {
			vi.useRealTimers();
		}
	});
});

describe('document operations', () => {
	it('newDocument creates and activates an empty document', () => {
		const store = freshDesk();
		store.init('# First\n');
		store.newDocument();
		expect(store.library?.documents).toHaveLength(2);
		expect(store.doc).toBe('');
		expect(store.activeId).toBe(store.library?.documents[0].id);
	});

	it('switchDocument flushes the outgoing body before switching', () => {
		const store = freshDesk();
		store.init('# First\n');
		const firstId = store.activeId;
		store.newDocument();
		store.doc = '# Second\n';
		const secondId = store.activeId;

		store.switchDocument(firstId!);
		expect(store.doc).toBe('# First\n');
		const second = store.library?.documents.find((d) => d.id === secondId);
		expect(second?.body).toBe('# Second\n');
	});

	it('switchDocument ignores the already-active id', () => {
		const store = freshDesk();
		store.init('# Only\n');
		const before = store.library;
		store.switchDocument(store.activeId!);
		expect(store.library).toBe(before);
	});

	it('renameDocument locks the title against auto-derive', () => {
		const store = freshDesk();
		store.init('# Heading title\n');
		store.renameDocument(store.activeId!, 'Custom');
		const active = store.library?.documents[0];
		expect(active?.title).toBe('Custom');
		expect(active?.titleLocked).toBe(true);
	});

	it('importDocument keeps the file name as a locked title', () => {
		const store = freshDesk();
		store.init('# Existing\n');
		store.importDocument('# Imported body\n', 'notes');
		expect(store.library?.documents).toHaveLength(2);
		expect(store.doc).toBe('# Imported body\n');
		const active = store.library?.documents[0];
		expect(active?.title).toBe('notes');
		expect(active?.titleLocked).toBe(true);
	});

	it('deleteDocument soft-deletes and undoDelete restores', () => {
		const store = freshDesk();
		store.init('# First\n');
		const firstId = store.activeId;
		store.newDocument();
		store.doc = '# Second\n';

		store.deleteDocument(store.activeId!);
		expect(store.library?.documents).toHaveLength(1);
		expect(store.doc).toBe('# First\n');
		expect(store.library?.trash).not.toBeNull();

		store.undoDelete();
		expect(store.library?.documents).toHaveLength(2);
		expect(store.library?.activeId).not.toBe(firstId);
		expect(store.doc).toBe('# Second\n');
	});
});
