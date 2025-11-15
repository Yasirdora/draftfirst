/**
 * Local multi-document library — pure helpers + localStorage I/O.
 *
 * Privacy invariant: no network. Quota errors surface to the caller.
 */

import { outlineOf } from '$lib/markdown/render';
import type { AppState } from '$lib/markdown/types';
import type {
	LibraryDocument,
	LibrarySearchHit,
	LibraryState,
	LibraryUiPrefs,
	TrashBin
} from './types';

export const LIBRARY_KEY = 'writing-desk:library:v2';
/** Legacy single-document key (Milestone 0–2). */
export const LEGACY_KEY = 'writing-desk:v1';

const TRASH_TTL_MS = 60_000;

export function createId(): string {
	if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
		return crypto.randomUUID();
	}
	return `doc_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 9)}`;
}

/** Title from first ATX heading or first non-empty line. */
export function deriveTitle(body: string): string {
	const heading = outlineOf(body)[0];
	if (heading?.text?.trim()) return heading.text.trim().slice(0, 80);
	const line = body
		.split('\n')
		.map((l) => l.trim())
		.find((l) => l.length > 0 && !l.startsWith('```'));
	if (!line) return 'Untitled';
	return line.replace(/^#+\s*/, '').slice(0, 80) || 'Untitled';
}

export function defaultUi(): LibraryUiPrefs {
	return { libraryOpen: true, view: 'page', focus: false };
}

export function createDocument(
	partial: { title?: string; body?: string; titleLocked?: boolean } = {}
): LibraryDocument {
	const now = Date.now();
	const body = partial.body ?? '';
	const titleLocked = partial.titleLocked === true;
	const title =
		partial.title?.trim() ||
		(body.trim() ? deriveTitle(body) : 'Untitled');
	return {
		id: createId(),
		title,
		titleLocked,
		body,
		createdAt: now,
		updatedAt: now
	};
}

export function defaultLibrary(sampleBody = ''): LibraryState {
	const doc = createDocument({
		body: sampleBody,
		title: sampleBody.trim() ? deriveTitle(sampleBody) : 'Welcome'
	});
	return {
		version: 2,
		activeId: doc.id,
		documents: [doc],
		ui: defaultUi(),
		trash: null
	};
}

function normalizeDoc(raw: unknown): LibraryDocument | null {
	if (!raw || typeof raw !== 'object') return null;
	const d = raw as Record<string, unknown>;
	if (typeof d.id !== 'string' || typeof d.body !== 'string') return null;
	const body = d.body;
	const titleLocked = d.titleLocked === true;
	const title =
		typeof d.title === 'string' && d.title.trim()
			? d.title.trim().slice(0, 80)
			: deriveTitle(body);
	return {
		id: d.id,
		title,
		titleLocked,
		body,
		createdAt: typeof d.createdAt === 'number' ? d.createdAt : Date.now(),
		updatedAt: typeof d.updatedAt === 'number' ? d.updatedAt : Date.now()
	};
}

export function normalizeLibrary(raw: unknown): LibraryState | null {
	if (!raw || typeof raw !== 'object') return null;
	const data = raw as Record<string, unknown>;
	if (data.version !== 2 || !Array.isArray(data.documents)) return null;

	const documents = data.documents
		.map(normalizeDoc)
		.filter((d): d is LibraryDocument => d !== null);
	if (documents.length === 0) return null;

	let activeId = typeof data.activeId === 'string' ? data.activeId : documents[0].id;
	if (!documents.some((d) => d.id === activeId)) activeId = documents[0].id;

	const uiRaw = (data.ui && typeof data.ui === 'object' ? data.ui : {}) as Record<
		string,
		unknown
	>;
	const view =
		uiRaw.view === 'page' || uiRaw.view === 'split' || uiRaw.view === 'source'
			? uiRaw.view
			: 'page';

	let trash: TrashBin | null = null;
	if (data.trash && typeof data.trash === 'object') {
		const t = data.trash as Record<string, unknown>;
		const doc = normalizeDoc(t.doc);
		if (doc && typeof t.expiresAt === 'number' && t.expiresAt > Date.now()) {
			trash = {
				doc,
				index: typeof t.index === 'number' ? t.index : 0,
				expiresAt: t.expiresAt
			};
		}
	}

	return {
		version: 2,
		activeId,
		documents,
		ui: {
			libraryOpen: uiRaw.libraryOpen !== false,
			view,
			focus: uiRaw.focus === true
		},
		trash
	};
}

/** Migrate legacy single-doc AppState into a library. */
export function migrateFromLegacy(legacy: AppState, sampleIfEmpty: string): LibraryState {
	const body = legacy.doc?.trim() ? legacy.doc : sampleIfEmpty;
	const doc = createDocument({
		body,
		title: body.trim() ? deriveTitle(body) : 'Welcome'
	});
	return {
		version: 2,
		activeId: doc.id,
		documents: [doc],
		ui: {
			libraryOpen: true,
			view: legacy.view === 'page' || legacy.view === 'split' || legacy.view === 'source'
				? legacy.view
				: 'page',
			focus: legacy.focus === true
		},
		trash: null
	};
}

export function loadLibrary(sampleIfEmpty: string): LibraryState {
	try {
		const raw = localStorage.getItem(LIBRARY_KEY);
		if (raw) {
			const parsed = normalizeLibrary(JSON.parse(raw));
			if (parsed) {
				// Drop expired trash
				if (parsed.trash && parsed.trash.expiresAt <= Date.now()) {
					parsed.trash = null;
				}
				return parsed;
			}
		}
	} catch {
		/* fall through */
	}

	// Legacy migration
	try {
		const legacyRaw = localStorage.getItem(LEGACY_KEY);
		if (legacyRaw) {
			const legacy = JSON.parse(legacyRaw) as AppState;
			const migrated = migrateFromLegacy(
				{
					doc: typeof legacy.doc === 'string' ? legacy.doc : '',
					view:
						legacy.view === 'page' || legacy.view === 'split' || legacy.view === 'source'
							? legacy.view
							: 'page',
					focus: legacy.focus === true
				},
				sampleIfEmpty
			);
			saveLibrary(migrated);
			return migrated;
		}
	} catch {
		/* fall through */
	}

	return defaultLibrary(sampleIfEmpty);
}

export function saveLibrary(
	state: LibraryState
): { ok: true } | { ok: false; message: string } {
	try {
		localStorage.setItem(LIBRARY_KEY, JSON.stringify(state));
		return { ok: true };
	} catch {
		return { ok: false, message: 'Could not save — storage is full or blocked' };
	}
}

export function getActiveDocument(state: LibraryState): LibraryDocument {
	return (
		state.documents.find((d) => d.id === state.activeId) ?? state.documents[0]
	);
}

/** Update active document body; auto-title unless locked. */
export function updateActiveBody(state: LibraryState, body: string): LibraryState {
	const now = Date.now();
	const documents = state.documents.map((d) => {
		if (d.id !== state.activeId) return d;
		const title = d.titleLocked ? d.title : deriveTitle(body) || d.title || 'Untitled';
		return { ...d, body, title, updatedAt: now };
	});
	return { ...state, documents };
}

export function setActiveId(state: LibraryState, id: string): LibraryState {
	if (!state.documents.some((d) => d.id === id)) return state;
	return { ...state, activeId: id };
}

export function addDocument(
	state: LibraryState,
	doc: LibraryDocument,
	makeActive = true
): LibraryState {
	return {
		...state,
		documents: [doc, ...state.documents],
		activeId: makeActive ? doc.id : state.activeId
	};
}

export function renameDocument(
	state: LibraryState,
	id: string,
	title: string
): LibraryState {
	const next = title.trim().slice(0, 80) || 'Untitled';
	return {
		...state,
		documents: state.documents.map((d) =>
			d.id === id
				? { ...d, title: next, titleLocked: true, updatedAt: Date.now() }
				: d
		)
	};
}

/**
 * Soft-delete: keep one trash slot for undo. Cannot delete the last document —
 * clear its body instead (caller may handle).
 */
export function deleteDocument(
	state: LibraryState,
	id: string
): { state: LibraryState; deleted: boolean; clearedOnly: boolean } {
	const index = state.documents.findIndex((d) => d.id === id);
	if (index === -1) return { state, deleted: false, clearedOnly: false };

	if (state.documents.length === 1) {
		const only = state.documents[0];
		const cleared: LibraryDocument = {
			...only,
			body: '',
			title: only.titleLocked ? only.title : 'Untitled',
			updatedAt: Date.now()
		};
		return {
			state: {
				...state,
				documents: [cleared],
				activeId: cleared.id,
				trash: null
			},
			deleted: false,
			clearedOnly: true
		};
	}

	const doc = state.documents[index];
	const documents = state.documents.filter((d) => d.id !== id);
	let activeId = state.activeId;
	if (activeId === id) {
		const fallback = documents[Math.min(index, documents.length - 1)];
		activeId = fallback.id;
	}

	return {
		state: {
			...state,
			documents,
			activeId,
			trash: {
				doc,
				index,
				expiresAt: Date.now() + TRASH_TTL_MS
			}
		},
		deleted: true,
		clearedOnly: false
	};
}

export function undoDelete(state: LibraryState): LibraryState {
	if (!state.trash || state.trash.expiresAt <= Date.now()) {
		return { ...state, trash: null };
	}
	const { doc, index } = state.trash;
	if (state.documents.some((d) => d.id === doc.id)) {
		return { ...state, trash: null };
	}
	const documents = state.documents.slice();
	const at = Math.min(Math.max(0, index), documents.length);
	documents.splice(at, 0, doc);
	return {
		...state,
		documents,
		activeId: doc.id,
		trash: null
	};
}

export function searchLibrary(
	documents: LibraryDocument[],
	query: string
): LibrarySearchHit[] {
	const q = query.trim().toLowerCase();
	if (!q) {
		return documents.map((doc) => ({ doc, match: 'title' as const }));
	}

	const hits: LibrarySearchHit[] = [];
	for (const doc of documents) {
		const inTitle = doc.title.toLowerCase().includes(q);
		const inBody = doc.body.toLowerCase().includes(q);
		if (!inTitle && !inBody) continue;
		hits.push({
			doc,
			match: inTitle && inBody ? 'both' : inTitle ? 'title' : 'body'
		});
	}
	// Most recently updated first
	hits.sort((a, b) => b.doc.updatedAt - a.doc.updatedAt);
	return hits;
}

/** Sort documents for sidebar: recent first. */
export function sortDocuments(documents: LibraryDocument[]): LibraryDocument[] {
	return documents.slice().sort((a, b) => b.updatedAt - a.updatedAt);
}

export function formatRelativeTime(ts: number, now = Date.now()): string {
	const sec = Math.round((now - ts) / 1000);
	if (sec < 45) return 'Just now';
	const min = Math.round(sec / 60);
	if (min < 60) return `${min}m ago`;
	const hr = Math.round(min / 60);
	if (hr < 48) return `${hr}h ago`;
	const day = Math.round(hr / 24);
	if (day < 14) return `${day}d ago`;
	return new Date(ts).toLocaleDateString(undefined, {
		month: 'short',
		day: 'numeric'
	});
}
