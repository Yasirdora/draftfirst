/**
 * localStorage persistence for Writing Desk.
 *
 * Documents never leave the browser. Failures (quota, private mode) surface
 * as soft errors so the writer is never silently left without a save path.
 */

import type { AppState, ViewMode } from '$lib/markdown/types';

export const STORAGE_KEY = 'writing-desk:v1';

export function defaultState(): AppState {
	return { doc: '', view: 'page', focus: false };
}

/** Coerce anything stored or imported into a safe, well-formed state. */
export function normalize(raw: unknown): AppState {
	const base = defaultState();
	if (!raw || typeof raw !== 'object') return base;
	const data = raw as Record<string, unknown>;
	const view: ViewMode =
		data.view === 'page' ||
		data.view === 'split' ||
		data.view === 'source' ||
		data.view === 'read'
			? data.view
			: base.view;
	return {
		doc: typeof data.doc === 'string' ? data.doc : base.doc,
		view,
		focus: data.focus === true
	};
}

export function loadState(): AppState {
	try {
		const stored = localStorage.getItem(STORAGE_KEY);
		if (stored) return normalize(JSON.parse(stored));
	} catch {
		/* corrupt or unavailable */
	}
	return defaultState();
}

export function saveState(state: AppState): { ok: true } | { ok: false; message: string } {
	try {
		localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
		return { ok: true };
	} catch {
		return { ok: false, message: 'Could not save — storage is full or blocked' };
	}
}
