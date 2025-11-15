/**
 * Multi-document library types.
 * Everything stays in localStorage until the writer exports.
 */

import type { ViewMode } from '$lib/markdown/types';

export interface LibraryDocument {
	id: string;
	/** Display title — may be user-set or derived from body */
	title: string;
	/** Whether title was set by the user (skip auto-derive while true) */
	titleLocked: boolean;
	body: string;
	createdAt: number;
	updatedAt: number;
}

export interface LibraryUiPrefs {
	/** Sidebar open */
	libraryOpen: boolean;
	view: ViewMode;
	focus: boolean;
}

/** Soft-deleted doc for one-step undo */
export interface TrashBin {
	doc: LibraryDocument;
	/** Index to restore into when possible */
	index: number;
	expiresAt: number;
}

export interface LibraryState {
	version: 2;
	activeId: string;
	documents: LibraryDocument[];
	ui: LibraryUiPrefs;
	trash: TrashBin | null;
}

export type LibrarySearchHit = {
	doc: LibraryDocument;
	/** Where the query matched */
	match: 'title' | 'body' | 'both';
};
