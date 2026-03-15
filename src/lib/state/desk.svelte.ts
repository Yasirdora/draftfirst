/**
 * Desk store — the editor's document & persistence state.
 *
 * Extracted from WritingDesk.svelte so the shell component only wires surfaces
 * and menus. Owns: the multi-document library, the active document body, save
 * status, and derived reading counts. All document operations flush-then-persist
 * through here, so localStorage is never out of sync with what the writer sees.
 *
 * UI-only state (menus, find, slash, truth strip) stays in the component.
 * The store never touches the DOM; the component reloads editor surfaces from
 * `desk.doc` after any operation that switches documents.
 */

import { countWords } from '$lib/markdown/render';
import {
	addDocument,
	createDocument,
	deleteDocument as deleteDocumentOp,
	getActiveDocument,
	loadLibrary,
	renameDocument as renameDocumentOp,
	saveLibrary,
	setActiveId,
	undoDelete as undoDeleteOp,
	updateActiveBody
} from '$lib/library/library';
import type { LibraryState, LibraryUiPrefs } from '$lib/library/types';

const SAVE_DEBOUNCE_MS = 400;
const SAVED_FLASH_MS = 1400;

export class DeskStore {
	library = $state<LibraryState | null>(null);
	/** Active document body — the single source both surfaces read and write. */
	doc = $state('');
	saveLabel = $state('Saved');
	saveOn = $state(false);

	wordCount = $derived(countWords(this.doc));
	charCount = $derived(this.doc.length);
	readTime = $derived(Math.max(this.wordCount > 0 ? 1 : 0, Math.round(this.wordCount / 220)));
	activeId = $derived(this.library?.activeId ?? null);

	/**
	 * Component-owned UI prefs merged into every persisted state.
	 * Set once after init; kept as a callback so the store stays DOM-free.
	 */
	uiSnapshot: () => LibraryUiPrefs = () => ({ libraryOpen: true, view: 'page', focus: false });

	private saveTimer: ReturnType<typeof setTimeout> | undefined;
	private statusTimer: ReturnType<typeof setTimeout> | undefined;

	/** Load (and migrate) the library; returns persisted UI prefs for the shell. */
	init(sample: string): LibraryUiPrefs {
		this.library = loadLibrary(sample);
		this.doc = getActiveDocument(this.library).body;
		return this.library.ui;
	}

	/** The library with the current body written into the active document. */
	flush(): LibraryState | null {
		if (!this.library) return null;
		return updateActiveBody(this.library, this.doc);
	}

	/** Debounced save — call on every edit. */
	persist(): void {
		clearTimeout(this.saveTimer);
		this.saveTimer = setTimeout(() => this.persistImmediate(), SAVE_DEBOUNCE_MS);
	}

	/** Immediate flush + write. */
	persistImmediate(): void {
		const flushed = this.flush();
		if (!flushed) return;
		this.persistNow(flushed);
	}

	/** Write a concrete state now and reflect the outcome in the save status. */
	persistNow(next: LibraryState): void {
		const withUi = { ...next, ui: this.uiSnapshot() };
		this.library = withUi;
		const result = saveLibrary(withUi);
		this.saveLabel = result.ok ? 'Saved' : result.message;
		this.saveOn = true;
		clearTimeout(this.statusTimer);
		this.statusTimer = setTimeout(() => (this.saveOn = false), SAVED_FLASH_MS);
	}

	/**
	 * Show a transient (or sticky, when `ms` is omitted) status message.
	 * Sticky is for errors that must not fade before the writer sees them.
	 */
	flashStatus(message: string, ms?: number): void {
		this.saveLabel = message;
		this.saveOn = true;
		clearTimeout(this.statusTimer);
		if (ms != null) {
			this.statusTimer = setTimeout(() => (this.saveOn = false), ms);
		}
	}

	switchDocument(id: string): void {
		if (!this.library || id === this.library.activeId) return;
		const flushed = this.flush();
		if (!flushed) return;
		const next = setActiveId(flushed, id);
		this.library = next;
		this.doc = getActiveDocument(next).body;
		this.persistNow(next);
	}

	newDocument(): void {
		if (!this.library) return;
		const flushed = this.flush() ?? this.library;
		const fresh = createDocument({ body: '', title: 'Untitled' });
		const next = addDocument(flushed, fresh, true);
		this.library = next;
		this.doc = fresh.body;
		this.persistNow(next);
	}

	/** Import a file as a new library document — never overwrites without intent. */
	importDocument(body: string, title?: string): void {
		if (!this.library) return;
		const flushed = this.flush() ?? this.library;
		const fresh = createDocument({ body, title, titleLocked: Boolean(title) });
		const next = addDocument(flushed, fresh, true);
		this.library = next;
		this.doc = fresh.body;
		this.persistNow(next);
	}

	renameDocument(id: string, title: string): void {
		if (!this.library) return;
		const flushed = this.flush() ?? this.library;
		const next = renameDocumentOp(flushed, id, title);
		this.library = next;
		this.persistNow(next);
	}

	deleteDocument(id: string): void {
		const flushed = this.flush();
		if (!flushed) return;
		const { state: next } = deleteDocumentOp(flushed, id);
		this.library = next;
		this.doc = getActiveDocument(next).body;
		this.persistNow(next);
	}

	undoDelete(): void {
		if (!this.library) return;
		const next = undoDeleteOp(this.library);
		this.library = next;
		this.doc = getActiveDocument(next).body;
		this.persistNow(next);
	}
}

export const desk = new DeskStore();
