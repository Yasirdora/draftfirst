<script lang="ts">
	/**
	 * Writing Desk — main editor shell.
	 *
	 * Architecture (mirrors the original single-file app):
	 *   markdown cores  → $lib/markdown/*  (render, serialise, format)
	 *   this component  → dual surfaces, toolbar, menus, persistence, export
	 *
	 * Critical rule: selection is remembered on each surface and restored before
	 * any toolbar command. Focus is the wrong thing to hang commands on —
	 * pressing a toolbar button moves focus, so we never trust activeElement alone.
	 */
	import { onMount, tick } from 'svelte';
	import { renderMarkdown, outlineOf, safeUrl } from '$lib/markdown/render';
	import { serialiseMarkdown } from '$lib/markdown/serialise';
	import {
		MARKS,
		inlineMarks,
		toggleMark,
		blockKind,
		setBlockKind,
		toggleBlockKind,
		toggleLink,
		insertBlock,
		clearFormatting
	} from '$lib/markdown/format';
	import { SAMPLE } from '$lib/markdown/sample';
	import type { FormatResult, InlineMarks, ViewMode } from '$lib/markdown/types';
	import {
		STYLES,
		OTHER_TOKENS,
		OTHER_NAMES,
		SNIPPETS,
		BLOCK_FOR,
		NARROW
	} from '$lib/editor/constants';
	import { download } from '$lib/utils/download';
	import { documentName } from '$lib/utils/document-name';
	import { exportStandaloneHtml } from '$lib/utils/export-html';
	import { loadOnboarding, saveOnboarding } from '$lib/utils/onboarding';
	import { loadDialectPrefs, setFootnotesEnabled } from '$lib/utils/dialect-prefs';
	import {
		getTruthBaseline,
		loadTruthPrefs,
		pruneTruthBaselines,
		removeTruthBaseline,
		setTruthBaselineForDoc,
		setTruthEnabled
	} from '$lib/utils/truth-prefs';
	import {
		loadThemePrefs,
		nextTheme,
		resolveDark,
		saveThemePrefs,
		type ThemeMode
	} from '$lib/utils/theme-prefs';
	import {
		assessFidelity,
		groupTruthChanges,
		restoreTruthChange,
		type FidelityReport
	} from '$lib/markdown/fidelity';
	import {
		detectSlashQuery,
		filterSlashCommands,
		type SlashCommand
	} from '$lib/editor/slash-commands';
	import { FIND_MIN_LENGTH, findMatches, type FindMatch } from '$lib/editor/find';
	import { clearFindHighlights, paintFindHighlights } from '$lib/editor/find-highlight';
	import { continueOnEnter, hardBreak, indentOnTab } from '$lib/editor/source-keys';
	import { altFromFileName, assetRef, insertImageRef } from '$lib/editor/image-insert';
	import { blobToDataUrl, getAsset, putAsset } from '$lib/assets/asset-store';
	import { inlineAssetDataUrls } from '$lib/utils/export-assets';
	import { reorderOutlineSections } from '$lib/editor/outline-reorder';
	import { searchLibrary, sortDocuments } from '$lib/library/library';
	import { desk } from '$lib/state/desk.svelte';
	import {
		filterPaletteCommands,
		type PaletteCommand
	} from '$lib/editor/palette-commands';
	import { highlightSource } from '$lib/editor/source-highlight';
	import BrandMark from './BrandMark.svelte';
	import StatusBar from './StatusBar.svelte';
	import ShortcutsOverlay from './ShortcutsOverlay.svelte';
	import WelcomeStrip from './WelcomeStrip.svelte';
	import SlashPalette from './SlashPalette.svelte';
	import FindBar from './FindBar.svelte';
	import LibrarySidebar from './LibrarySidebar.svelte';
	import TruthStrip from './TruthStrip.svelte';
	import CommandPalette from './CommandPalette.svelte';
	import Icon from './Icon.svelte';

	/* ---------- reactive app state -------------------------------------- */

	let libraryQuery = $state('');
	let libraryOpen = $state(true);

	/** Narrowed view of the store's library for template bindings. */
	const lib = $derived(desk.library);

	let view = $state<ViewMode>('page');
	let focus = $state(false);

	/* Theme — chrome only; the sheet stays paper either way */
	let theme = $state<ThemeMode>('system');
	let systemDark = $state(false);
	const resolvedDark = $derived(resolveDark(theme, systemDark));
	const themeNext = $derived(nextTheme(theme, systemDark));
	const themeLabel = $derived(
		`Theme: ${theme}${theme === 'system' ? ` (${resolvedDark ? 'dark' : 'light'})` : ''} — click for ${themeNext}`
	);

	/* Keep <html data-theme> in sync with the mode and the OS setting. */
	$effect(() => {
		document.documentElement.dataset.theme = resolvedDark ? 'dark' : 'light';
	});

	let dragging = $state(false);
	let keyboardUp = $state(false);
	let shortcutsOpen = $state(false);
	let welcomeVisible = $state(false);

	/* Slash palette */
	let slashOpen = $state(false);
	let slashQuery = $state('');
	let slashItems = $state<SlashCommand[]>([]);
	let slashIndex = $state(0);
	let slashMode = $state<'source' | 'page'>('source');
	let slashAnchor = $state<{ top: number; left: number } | null>(null);

	/* Find */
	let findOpen = $state(false);
	let findQuery = $state('');
	let findMatchesList = $state<FindMatch[]>([]);
	let findIndex = $state(0);
	/** Bumped to re-focus the find field (e.g. second ⌘F). */
	let findFocusToken = $state(0);
	/** Debounce live find paint so fast typing stays smooth. */
	let findPaintTimer = 0;

	/* Command palette (⌘K) */
	let paletteOpen = $state(false);
	let paletteQuery = $state('');
	let paletteIndex = $state(0);
	const paletteItems = $derived(filterPaletteCommands(paletteQuery));

	/* Truth mode — fidelity of page serialise vs trusted source baseline */
	let truthEnabled = $state(false);
	let truthBaseline = $state('');
	let truthReport = $state<FidelityReport | null>(null);
	let truthStripOpen = $state(false);

	/* Opt-in dialect packs */
	let footnotesOn = $state(false);

	let cursorPos = $state('Line 1, column 1');

	/** Toolbar reflection of caret context. */
	let styleToken = $state('Aa');
	let styleName = $state('Normal text');
	let marks = $state({ bold: false, italic: false, strike: false, code: false, link: false });
	let activeBlock = $state('paragraph');
	let inTable = $state(false);

	/* Open menu id: null | outline | file | export | style | more */
	let openMenu = $state<string | null>(null);

	/* Outline items rebuilt when the outline menu opens. */
	let outlineItems = $state<{ level: number; text: string; line: number }[]>([]);

	/* ---------- DOM refs ------------------------------------------------ */

	let deskEl: HTMLDivElement | undefined = $state();
	let editor: HTMLTextAreaElement | undefined = $state();
	let sheet: HTMLElement | undefined = $state();
	let readingPane: HTMLElement | undefined = $state();
	let fileInput: HTMLInputElement | undefined = $state();
	let toolbarEl: HTMLElement | undefined = $state();
	let backdrop: HTMLElement | undefined = $state();

	/* The highlight backdrop follows the document no matter which path changed
	   it — typing, slash inserts, undo, document switches, imports. */
	$effect(() => {
		void desk.doc;
		syncBackdrop();
	});

	/* Menu elements (ported to body for overflow clipping). */
	let outlineMenuEl: HTMLUListElement | undefined = $state();
	let fileMenuEl: HTMLUListElement | undefined = $state();
	let exportMenuEl: HTMLUListElement | undefined = $state();
	let styleMenuEl: HTMLUListElement | undefined = $state();
	let moreMenuEl: HTMLUListElement | undefined = $state();

	let outlineBtnEl: HTMLButtonElement | undefined = $state();
	let fileBtnEl: HTMLButtonElement | undefined = $state();
	let exportBtnEl: HTMLButtonElement | undefined = $state();
	let styleBtnEl: HTMLButtonElement | undefined = $state();
	let moreBtnEl: HTMLButtonElement | undefined = $state();

	/* ---------- selection memory ---------------------------------------- */

	type Surface = 'page' | 'source';
	let lastSurface: Surface = 'page';
	let savedSourceSelection: { start: number; end: number } | null = null;
	let savedPageRange: Range | null = null;
	let viewBeforeFocus: ViewMode | null = null;

	let dragDepth = 0;
	let ready = $state(false);

	const isNarrow = () => typeof window !== 'undefined' && window.innerWidth <= NARROW;

	const onPage = () =>
		Boolean(sheet && (document.activeElement === sheet || sheet.contains(document.activeElement)));
	const onSource = () => Boolean(editor && document.activeElement === editor);

	function surface(): Surface {
		if (view === 'page') return 'page';
		if (view === 'source') return 'source';
		return lastSurface;
	}

	function rememberSource() {
		if (!editor) return;
		savedSourceSelection = { start: editor.selectionStart, end: editor.selectionEnd };
		lastSurface = 'source';
	}

	function rememberPage() {
		if (!sheet) return;
		const selection = window.getSelection();
		if (!selection || selection.rangeCount === 0) return;
		const range = selection.getRangeAt(0);
		if (!sheet.contains(range.commonAncestorContainer)) return;
		savedPageRange = range.cloneRange();
		lastSurface = 'page';
	}

	function restoreSelection() {
		if (!editor || !sheet) return;

		if (surface() === 'source') {
			if (onSource()) {
				rememberSource();
				return;
			}
			editor.focus();
			if (savedSourceSelection) {
				editor.setSelectionRange(savedSourceSelection.start, savedSourceSelection.end);
			}
			return;
		}

		if (onPage()) {
			rememberPage();
			return;
		}

		sheet.focus();
		const selection = window.getSelection();
		if (!selection || !savedPageRange || !sheet.contains(savedPageRange.commonAncestorContainer))
			return;
		selection.removeAllRanges();
		selection.addRange(savedPageRange);
	}

	/* ---------- library + persistence ----------------------------------- */

	function libraryHits() {
		if (!desk.library) return [];
		return searchLibrary(sortDocuments(desk.library.documents), libraryQuery);
	}

	function loadActiveIntoEditor() {
		if (!desk.library || !editor) return;
		if (editor.value !== desk.doc) editor.value = desk.doc;
		renderDocument();
		updateCursor();
		updateToolbar();
		closeSlash();
		if (findOpen) updateFindMatches(findQuery);
		// Restore this note's trusted baseline (survives reload) — do not clobber it.
		restoreTruthForActiveDoc();
	}

	/**
	 * Load Truth baseline for the active note and re-evaluate fidelity.
	 * Baseline is persisted separately so page→source rewrites still show after reload.
	 */
	function restoreTruthForActiveDoc() {
		const id = desk.activeId;
		const body = desk.doc;
		if (!id) {
			truthBaseline = body;
			truthReport = assessFidelity(body, body);
			truthStripOpen = false;
			return;
		}
		const baseline = getTruthBaseline(id, body);
		truthBaseline = baseline;
		const report = assessFidelity(baseline, body);
		truthReport = report;
		// If we had no stored baseline yet, seed it so future reloads have a reference.
		if (baseline === body) {
			setTruthBaselineForDoc(id, body);
		}
		truthStripOpen = truthEnabled && report.status !== 'identical';
	}

	/** Trusted source for Truth mode — intentional Markdown edits / Accept reset it. */
	function setTruthBaseline(source: string) {
		truthBaseline = source;
		truthReport = assessFidelity(source, source);
		truthStripOpen = false;
		const id = desk.activeId;
		if (id) setTruthBaselineForDoc(id, source);
	}

	function refreshTruthFromPage(serialised: string) {
		const report = assessFidelity(truthBaseline, serialised);
		truthReport = report;
		if (!truthEnabled) {
			truthStripOpen = false;
			return;
		}
		// Soft strip: only when something non-identical happened.
		truthStripOpen = report.status !== 'identical';
		// Baseline stays put; body is what persist() saves. Both survive reload.
	}

	function toggleTruthMode() {
		truthEnabled = !truthEnabled;
		setTruthEnabled(truthEnabled);
		if (!truthEnabled) {
			truthStripOpen = false;
			return;
		}
		// Re-evaluate current doc against persisted baseline when enabling.
		const report = assessFidelity(truthBaseline, desk.doc);
		truthReport = report;
		truthStripOpen = report.status !== 'identical';
	}

	function acceptTruthBaseline() {
		// Writer trusts the current source — baseline catches up to the body.
		setTruthBaseline(desk.doc);
		desk.flashStatus('Trusted source updated', 1600);
	}

	/**
	 * Apply a new body without treating it as a new trusted baseline.
	 * Used for selective restore so remaining differences stay reviewable.
	 */
	function applyBodyKeepBaseline(text: string, statusMessage: string) {
		desk.doc = text;
		if (editor && editor.value !== text) editor.value = text;
		renderDocument();
		updateCursor();
		updateToolbar();
		const report = assessFidelity(truthBaseline, text);
		truthReport = report;
		truthStripOpen = truthEnabled && report.status !== 'identical';
		desk.persist();
		desk.flashStatus(statusMessage, 1600);
	}

	/**
	 * Put the full trusted Markdown back — undoes every rewrite since baseline.
	 */
	function restoreTruthBaseline() {
		const trusted = truthBaseline;
		if (trusted === desk.doc) {
			truthStripOpen = false;
			return;
		}
		const ok = confirm(
			'Restore all trusted Markdown?\n\n' +
				'Every change from the trusted version will be undone. ' +
				'To undo only one change, open the change list and use “Restore this”.'
		);
		if (!ok) return;
		// Full restore: body and baseline match again.
		setDoc(trusted);
		truthStripOpen = false;
		desk.flashStatus('Restored all trusted Markdown', 1600);
	}

	/**
	 * Restore a single change region from the trusted baseline; keep other edits.
	 */
	function restoreTruthChangeAt(changeId: number) {
		const next = restoreTruthChange(truthBaseline, desk.doc, changeId);
		if (next === desk.doc) return;
		applyBodyKeepBaseline(next, 'Restored one change');
	}

	function dismissTruthStrip() {
		truthStripOpen = false;
	}

	/* ---------- document operations (via the desk store) ------------------ */

	function switchDocument(id: string) {
		if (!desk.library || id === desk.library.activeId) return;
		desk.switchDocument(id);
		loadActiveIntoEditor();
		closeMenus();
	}

	function newDocument() {
		if (!desk.library) return;
		if (!libraryOpen) libraryOpen = true;
		desk.newDocument();
		loadActiveIntoEditor();
		closeMenus();
	}

	function renameActiveLibraryDoc(id: string, title: string) {
		desk.renameDocument(id, title);
	}

	function deleteLibraryDoc(id: string) {
		if (!desk.library) return;
		const flushed = desk.flush() ?? desk.library;
		const target = flushed.documents.find((d) => d.id === id);
		if (!target) return;

		if (flushed.documents.length === 1) {
			if (target.body.trim() !== '' && !confirm('Clear this document? This is your only note.')) {
				return;
			}
		} else if (!confirm('Delete this document? You can Undo for about a minute.')) {
			return;
		}

		desk.deleteDocument(id);
		removeTruthBaseline(id);
		pruneTruthBaselines(desk.library?.documents.map((d) => d.id) ?? []);
		loadActiveIntoEditor();
	}

	function undoLibraryDelete() {
		if (!desk.library) return;
		desk.undoDelete();
		loadActiveIntoEditor();
	}

	function toggleLibrary() {
		libraryOpen = !libraryOpen;
		desk.persistImmediate();
	}

	function enableTaskBoxes() {
		if (!sheet) return;
		const readOnly = view === 'read';
		sheet.querySelectorAll('input[type="checkbox"]').forEach((box) => {
			const input = box as HTMLInputElement;
			input.disabled = readOnly;
			input.setAttribute('contenteditable', 'false');
		});
	}

	/** Mirror the source into the highlight backdrop; scroll stays in lockstep. */
	function syncBackdrop() {
		if (!backdrop || !editor) return;
		const html = highlightSource(editor.value);
		if (backdrop.innerHTML !== html) backdrop.innerHTML = html;
		backdrop.scrollTop = editor.scrollTop;
	}

	/** Repaint the page from source. Never while someone is typing on it. */
	/* ---------- pasted images (IndexedDB assets) -------------------------- */

	/** Session cache of minted object URLs — revoked on destroy. */
	const assetUrls = new Map<string, string>();

	/** Swap asset placeholders for freshly minted object URLs after each render. */
	async function resolveAssetImages(root: HTMLElement) {
		for (const img of Array.from(root.querySelectorAll<HTMLImageElement>('img[data-asset]'))) {
			const id = img.dataset.asset!;
			let url = assetUrls.get(id);
			if (!url) {
				try {
					const blob = await getAsset(id);
					if (!blob) {
						if (img.isConnected) img.classList.add('asset-missing');
						continue;
					}
					url = URL.createObjectURL(blob);
					assetUrls.set(id, url);
				} catch {
					continue;
				}
			}
			if (img.isConnected && img.getAttribute('src') !== url) img.src = url;
		}
	}

	function renderDocument() {
		if (!sheet) return;
		// The only innerHTML path — and only ever with our own renderer output.
		sheet.innerHTML = renderMarkdown(desk.doc, { footnotes: footnotesOn });
		enableTaskBoxes();
		void resolveAssetImages(sheet);
		if (findOpen && findQuery.trim().length >= FIND_MIN_LENGTH) {
			// Marks were wiped with innerHTML — restore after paint.
			queueMicrotask(() => revealFindMatch(findIndex));
		}
	}

	function pageChanged() {
		if (!sheet || !editor) return;
		// Strip temporary find marks before serialising source.
		clearFindHighlights(sheet);
		let markdown: string;
		try {
			markdown = serialiseMarkdown(sheet);
		} catch {
			desk.flashStatus('Could not read the page — switch to Markdown to check it');
			return;
		}
		desk.doc = markdown;
		if (!onSource()) editor.value = desk.doc;
		updateCursor();
		refreshTruthFromPage(markdown);
		// Re-apply highlights if Find is still active.
		if (findOpen && findQuery.trim().length >= FIND_MIN_LENGTH) {
			revealFindMatch(findIndex);
		}
		desk.persist();
	}

	function sourceChanged() {
		if (!editor || !sheet) return;
		desk.doc = editor.value;
		if (!onPage()) {
			sheet.innerHTML = renderMarkdown(desk.doc);
			enableTaskBoxes();
		}
		// Writer owns source — baseline follows intentional Markdown edits.
		setTruthBaseline(desk.doc);
		desk.persist();
	}

	function setDoc(text: string) {
		if (!editor) return;
		desk.doc = text;
		if (editor.value !== text) editor.value = text;
		renderDocument();
		updateCursor();
		updateToolbar();
		setTruthBaseline(text);
		desk.persist();
	}

	function applyView() {
		if (isNarrow() && view === 'split') view = 'page';
	}

	function updateCursor() {
		if (!editor) return;
		const upto = editor.value.slice(0, editor.selectionStart);
		const line = upto.split('\n').length;
		const column = upto.length - upto.lastIndexOf('\n');
		cursorPos = 'Line ' + line + ', column ' + column;
	}

	/* ---------- menus --------------------------------------------------- */

	function menuEl(id: string): HTMLUListElement | undefined {
		if (id === 'outline') return outlineMenuEl;
		if (id === 'file') return fileMenuEl;
		if (id === 'export') return exportMenuEl;
		if (id === 'style') return styleMenuEl;
		if (id === 'more') return moreMenuEl;
		return undefined;
	}

	function menuBtn(id: string): HTMLButtonElement | undefined {
		if (id === 'outline') return outlineBtnEl;
		if (id === 'file') return fileBtnEl;
		if (id === 'export') return exportBtnEl;
		if (id === 'style') return styleBtnEl;
		if (id === 'more') return moreBtnEl;
		return undefined;
	}

	/**
	 * Port menus to document.body so scroll containers (toolbar) cannot clip them.
	 * Fixed positioning against the trigger button.
	 */
	function placeMenu(menu: HTMLElement, button: HTMLElement) {
		if (menu.parentNode !== document.body) document.body.appendChild(menu);

		menu.style.position = 'fixed';
		menu.style.visibility = 'hidden';
		menu.hidden = false;

		const anchor = button.getBoundingClientRect();
		const width = menu.offsetWidth;
		const height = menu.offsetHeight;
		const margin = 8;

		let left = menu.classList.contains('menu-style') ? anchor.left : anchor.right - width;
		left = Math.max(margin, Math.min(left, window.innerWidth - width - margin));

		const below = anchor.bottom + margin + height <= window.innerHeight;
		const top = below ? anchor.bottom + 6 : Math.max(margin, anchor.top - height - 6);

		menu.style.left = Math.round(left) + 'px';
		menu.style.top = Math.round(top) + 'px';
		menu.style.right = 'auto';
		menu.style.bottom = 'auto';
		menu.style.visibility = '';
	}

	function closeMenus() {
		openMenu = null;
		for (const id of ['outline', 'file', 'export', 'style', 'more']) {
			const menu = menuEl(id);
			if (menu) menu.hidden = true;
		}
	}

	function toggleMenu(id: string, onOpen?: () => void) {
		const willOpen = openMenu !== id;
		closeMenus();
		if (!willOpen) return;

		const menu = menuEl(id);
		const button = menuBtn(id);
		if (!menu || !button) return;

		onOpen?.();
		openMenu = id;
		placeMenu(menu, button);
	}

	function rebuildOutline() {
		outlineItems = outlineOf(desk.doc);
	}

	function jumpToHeading(heading: { level: number; text: string; line: number }, index: number) {
		if (!sheet || !editor) return;
		if (view === 'page') {
			const found = sheet.querySelectorAll('h1, h2, h3, h4, h5, h6')[index];
			if (found && 'scrollIntoView' in found) {
				(found as HTMLElement).scrollIntoView({ block: 'start' });
			}
			return;
		}
		jumpToLine(heading.line);
	}

	function jumpToLine(index: number) {
		if (!editor) return;
		const lines = desk.doc.split('\n');
		let offset = 0;
		for (let i = 0; i < index && i < lines.length; i++) offset += lines[i].length + 1;
		if (view === 'page') {
			view = 'split';
			applyView();
		}
		editor.focus();
		editor.setSelectionRange(offset, offset);
		const ratio = offset / Math.max(1, desk.doc.length);
		editor.scrollTop = ratio * editor.scrollHeight - editor.clientHeight / 3;
		updateCursor();
	}

	/* ---------- page editing helpers ------------------------------------ */

	function run(name: string, value?: string) {
		try {
			// execCommand remains the only cross-browser contenteditable command API.
			document.execCommand(name, false, value);
		} catch {
			/* ignore */
		}
	}

	function currentBlock(): HTMLElement | null {
		if (!sheet) return null;
		const selection = window.getSelection();
		if (!selection || selection.rangeCount === 0) return null;
		let node: Node | null = selection.getRangeAt(0).startContainer;
		if (node.nodeType === 3) node = node.parentNode;
		while (node && node !== sheet) {
			if (
				node.nodeType === 1 &&
				/^(H[1-6]|P|DIV|BLOCKQUOTE|PRE|LI|TABLE)$/.test((node as Element).tagName)
			) {
				return node as HTMLElement;
			}
			node = node.parentNode;
		}
		return null;
	}

	function ancestorTag(tag: string): HTMLElement | null {
		if (!sheet) return null;
		const selection = window.getSelection();
		if (!selection || selection.rangeCount === 0) return null;
		let node: Node | null = selection.getRangeAt(0).startContainer;
		while (node && node !== sheet) {
			if (node.nodeType === 1 && (node as Element).tagName === tag) return node as HTMLElement;
			node = node.parentNode;
		}
		return null;
	}

	function pageState() {
		const block = currentBlock();
		let kind = 'paragraph';

		if (block) {
			const tag = block.tagName;
			if (/^H[1-6]$/.test(tag)) kind = 'h' + tag[1];
			else if (tag === 'BLOCKQUOTE') kind = 'quote';
			else if (tag === 'PRE') kind = 'code';
			else if (tag === 'LI') {
				const list = block.parentNode as HTMLElement | null;
				kind = block.querySelector('input[type="checkbox"]')
					? 'task'
					: list && list.tagName === 'OL'
						? 'ol'
						: 'ul';
			}
		}

		const query = (name: string) => {
			try {
				return document.queryCommandState(name);
			} catch {
				return false;
			}
		};

		return {
			kind,
			marks: {
				bold: query('bold'),
				italic: query('italic'),
				strike: query('strikeThrough'),
				code: Boolean(ancestorTag('CODE')),
				link: Boolean(ancestorTag('A'))
			}
		};
	}

	function toggleTag(tagName: string) {
		const existing = ancestorTag(tagName);
		if (existing) {
			const parent = existing.parentNode;
			if (!parent) return;
			while (existing.firstChild) parent.insertBefore(existing.firstChild, existing);
			parent.removeChild(existing);
			return;
		}

		const selection = window.getSelection();
		if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return;

		const range = selection.getRangeAt(0);
		const wrapper = document.createElement(tagName.toLowerCase());
		try {
			wrapper.appendChild(range.extractContents());
			range.insertNode(wrapper);
			selection.removeAllRanges();
			const after = document.createRange();
			after.selectNodeContents(wrapper);
			selection.addRange(after);
		} catch {
			/* selection across blocks */
		}
	}

	/**
	 * Lists are built by hand. execCommand('insertUnorderedList') nests the
	 * <ul> inside the current <p> when defaultParagraphSeparator is 'p' —
	 * invalid HTML that silently breaks serialisation (the list round-trips
	 * as running text). Every list toggle here produces structure that
	 * serialises cleanly: a list is always a direct child of the sheet.
	 */
	function toggleListOnPage(kind: 'ul' | 'ol' | 'task') {
		if (!sheet) return;
		const selection = window.getSelection();
		if (!selection || !selection.rangeCount) return;
		const listTag = kind === 'ol' ? 'OL' : 'UL';

		const freshBox = () => {
			const box = document.createElement('input');
			box.type = 'checkbox';
			box.setAttribute('contenteditable', 'false');
			return box;
		};
		const ensureBreak = (el: HTMLElement) => {
			if (!(el.textContent || '').trim() && !el.querySelector('br'))
				el.appendChild(document.createElement('br'));
		};
		const matchesKind = (li: Element) =>
			li.parentElement?.tagName === listTag &&
			(kind === 'task' ? li.classList.contains('task') : !li.classList.contains('task'));

		/* One item back to a paragraph, splitting the list when it sits in
		   the middle — the way the good editors do it. */
		const unwrapItem = (li: HTMLElement) => {
			const list = li.parentElement!;
			const after = list.cloneNode(false) as HTMLElement;
			let node = li.nextSibling;
			while (node) {
				const following = node.nextSibling;
				after.appendChild(node);
				node = following;
			}
			const p = document.createElement('p');
			li.querySelector('input[type="checkbox"]')?.remove();
			while (li.firstChild) p.appendChild(li.firstChild);
			ensureBreak(p);
			list.after(p);
			if (after.childNodes.length) p.after(after);
			li.remove();
			if (!list.childNodes.length) list.remove();
			placeCaretIn(p);
		};

		const block = currentBlock();

		if (block && block.tagName === 'LI' && selection.isCollapsed) {
			const li = block as HTMLElement;
			if (matchesKind(li)) {
				unwrapItem(li);
				return;
			}
			if (kind === 'task' || li.classList.contains('task')) {
				/* bullet ↔ task: per-item, the <ul> stays */
				if (kind === 'task') {
					li.classList.add('task');
					li.insertBefore(freshBox(), li.firstChild);
				} else {
					li.classList.remove('task');
					li.querySelector('input[type="checkbox"]')?.remove();
				}
			} else {
				/* bullet ↔ numbered: the whole list changes tag */
				const list = li.parentElement!;
				const converted = document.createElement(listTag);
				while (list.firstChild) converted.appendChild(list.firstChild);
				list.after(converted);
				list.remove();
			}
			return;
		}

		/* Blocks → items: the current block, or every top-level block the
		   selection touches becomes one item in a single new list. */
		const targets: HTMLElement[] = [];
		if (selection.isCollapsed) {
			if (block && block !== sheet && sheet.contains(block)) targets.push(block as HTMLElement);
		} else {
			const range = selection.getRangeAt(0);
			for (const child of Array.from(sheet.children)) {
				if (range.intersectsNode(child)) targets.push(child as HTMLElement);
			}
		}
		if (!targets.length) return;

		/* A selection spanning only items of this kind unwraps them all. */
		if (
			!selection.isCollapsed &&
			targets.every(
				(el) =>
					el.tagName === listTag &&
					Array.from(el.children).every((c) => matchesKind(c))
			)
		) {
			for (const list of targets)
				for (const item of Array.from(list.children)) unwrapItem(item as HTMLElement);
			return;
		}

		const list = document.createElement(listTag);
		targets[0].before(list);
		for (const target of targets) {
			if (target.tagName === 'UL' || target.tagName === 'OL') {
				for (const item of Array.from(target.children)) {
					const li = item as HTMLElement;
					if (kind === 'task' && !li.classList.contains('task')) {
						li.classList.add('task');
						li.insertBefore(freshBox(), li.firstChild);
					} else if (kind !== 'task' && li.classList.contains('task')) {
						li.classList.remove('task');
						li.querySelector('input[type="checkbox"]')?.remove();
					}
					list.appendChild(li);
				}
				target.remove();
			} else {
				const li = document.createElement('li');
				if (kind === 'task') {
					li.className = 'task';
					li.appendChild(freshBox());
				}
				while (target.firstChild) li.appendChild(target.firstChild);
				ensureBreak(li);
				list.appendChild(li);
				target.remove();
			}
		}

		/* Moved text nodes keep the caret; a removed empty block loses it. */
		if (!selection.anchorNode || !sheet.contains(selection.anchorNode)) {
			const firstItem = list.querySelector('li');
			if (firstItem) {
				const caret = document.createRange();
				caret.setStart(
					firstItem,
					firstItem.querySelector('input[type="checkbox"]') ? 1 : 0
				);
				caret.collapse(true);
				selection.removeAllRanges();
				selection.addRange(caret);
			}
		}
	}

	function currentCell(): HTMLTableCellElement | null {
		if (!sheet) return null;
		const selection = window.getSelection();
		if (!selection || selection.rangeCount === 0) return null;
		let node: Node | null = selection.getRangeAt(0).startContainer;
		if (node.nodeType === 3) node = node.parentNode;
		while (node && node !== sheet) {
			if (node.nodeType === 1) {
				const tag = (node as Element).tagName;
				if (tag === 'TD' || tag === 'TH') return node as HTMLTableCellElement;
			}
			node = node.parentNode;
		}
		return null;
	}

	function placeCaretIn(node: Node | null) {
		const selection = window.getSelection();
		if (!selection || !node) return;
		const range = document.createRange();
		range.selectNodeContents(node);
		range.collapse(true);
		selection.removeAllRanges();
		selection.addRange(range);
	}

	const cellIndex = (cell: HTMLTableCellElement) =>
		Array.prototype.indexOf.call(cell.parentElement!.children, cell);

	function bodyOf(table: HTMLTableElement) {
		if (table.tBodies[0]) return table.tBodies[0];
		const body = document.createElement('tbody');
		table.appendChild(body);
		return body;
	}

	function addRow(cell: HTMLTableCellElement, after: boolean) {
		const table = cell.closest('table')!;
		const row = cell.parentElement as HTMLTableRowElement;
		const width = table.rows[0].cells.length;
		const fresh = document.createElement('tr');
		for (let i = 0; i < width; i++) fresh.appendChild(document.createElement('td'));

		if (table.tHead && row.parentElement === table.tHead) {
			const body = bodyOf(table);
			body.insertBefore(fresh, body.firstChild);
		} else {
			row.parentElement!.insertBefore(fresh, after ? row.nextSibling : row);
		}
		placeCaretIn(fresh.cells[0]);
	}

	function addColumn(cell: HTMLTableCellElement, after: boolean) {
		const table = cell.closest('table')!;
		const at = cellIndex(cell) + (after ? 1 : 0);
		for (const row of Array.from(table.rows)) {
			const heading = Boolean(table.tHead && row.parentElement === table.tHead);
			const fresh = document.createElement(heading ? 'th' : 'td');
			row.insertBefore(fresh, row.cells[at] || null);
		}
		placeCaretIn(table.rows[0].cells[at]);
	}

	function removeRow(cell: HTMLTableCellElement) {
		const table = cell.closest('table')!;
		const row = cell.parentElement as HTMLTableRowElement;

		if (table.tHead && row.parentElement === table.tHead) {
			const first = table.tBodies[0] && table.tBodies[0].rows[0];
			if (!first) {
				table.remove();
				return;
			}
			const promoted = document.createElement('tr');
			for (const source of Array.from(first.cells)) {
				const heading = document.createElement('th');
				while (source.firstChild) heading.appendChild(source.firstChild);
				promoted.appendChild(heading);
			}
			table.tHead.replaceChild(promoted, row);
			first.remove();
			placeCaretIn(promoted.cells[0]);
			return;
		}

		const fallback = row.nextElementSibling || row.previousElementSibling;
		row.remove();
		if (table.rows.length === 0) table.remove();
		else placeCaretIn(((fallback as HTMLTableRowElement) || table.rows[0]).cells[0]);
	}

	function removeColumn(cell: HTMLTableCellElement) {
		const table = cell.closest('table')!;
		const at = cellIndex(cell);
		if (table.rows[0].cells.length <= 1) {
			table.remove();
			return;
		}
		for (const row of Array.from(table.rows)) {
			if (row.cells[at]) row.cells[at].remove();
		}
		placeCaretIn(table.rows[0].cells[Math.max(0, at - 1)]);
	}

	const TABLE_ACTIONS: Record<string, (cell: HTMLTableCellElement) => void> = {
		rowAbove: (cell) => addRow(cell, false),
		rowBelow: (cell) => addRow(cell, true),
		columnLeft: (cell) => addColumn(cell, false),
		columnRight: (cell) => addColumn(cell, true),
		removeRow,
		removeColumn,
		removeTable: (cell) => cell.closest('table')!.remove()
	};

	function insertPageBlock(name: string) {
		if (!sheet) return;
		const html = renderMarkdown(SNIPPETS[name].text);
		const holder = document.createElement('div');
		holder.innerHTML = html; // our own output from our own snippet

		const selection = window.getSelection();
		const block = currentBlock();
		const target = block && block.parentNode === sheet ? block : sheet.lastChild;
		const nodes = Array.from(holder.childNodes);
		if (nodes.length === 0) return;

		for (const node of nodes) {
			if (target && target.parentNode === sheet) sheet.insertBefore(node, target.nextSibling);
			else sheet.appendChild(node);
		}

		const trailing = document.createElement('p');
		trailing.appendChild(document.createElement('br'));
		sheet.insertBefore(trailing, nodes[nodes.length - 1].nextSibling);

		if (selection) {
			const range = document.createRange();
			range.selectNodeContents(nodes[0]);
			range.collapse(true);
			selection.removeAllRanges();
			selection.addRange(range);
		}
	}

	function pageLink() {
		if (ancestorTag('A')) {
			run('unlink');
			return;
		}

		const selection = window.getSelection();
		let address: string | null;
		try {
			address = window.prompt('Link address', 'https://');
		} catch {
			return;
		}
		if (!address) return;
		const href = safeUrl(address);
		if (!href) return;

		if (selection && !selection.isCollapsed) {
			run('createLink', href);
			return;
		}

		let label: string | null;
		try {
			label = window.prompt('Link text', href);
		} catch {
			label = href;
		}
		if (!label || !sheet) return;

		const anchorNode = document.createElement('a');
		anchorNode.href = href;
		anchorNode.textContent = label;

		if (selection && selection.rangeCount > 0) {
			const range = selection.getRangeAt(0);
			range.insertNode(anchorNode);
			range.setStartAfter(anchorNode);
			range.collapse(true);
			selection.removeAllRanges();
			selection.addRange(range);
		} else {
			sheet.appendChild(anchorNode);
		}
	}

	function pageCommand(name: string, argument?: string) {
		const before = pageState();

		if (name === 'bold') run('bold');
		else if (name === 'italic') run('italic');
		else if (name === 'strike') run('strikeThrough');
		else if (name === 'code') toggleTag('CODE');
		else if (name === 'link') pageLink();
		else if (name === 'style') run('formatBlock', '<' + (BLOCK_FOR[argument || ''] || 'p') + '>');
		else if (name === 'quote') run('formatBlock', before.kind === 'quote' ? '<p>' : '<blockquote>');
		else if (name === 'ul') toggleListOnPage('ul');
		else if (name === 'ol') toggleListOnPage('ol');
		else if (name === 'task') toggleListOnPage('task');
		else if (name === 'clear') {
			run('removeFormat');
			run('unlink');
		} else if (TABLE_ACTIONS[name]) {
			const cell = currentCell();
			if (cell) TABLE_ACTIONS[name](cell);
		} else if (SNIPPETS[name]) insertPageBlock(name);

		enableTaskBoxes();
		rememberPage();
		pageChanged();
		updateToolbar();
	}

	/** Every command goes through here so toolbar and keyboard agree. */
	function command(name: string, argument?: string) {
		if (!editor) return;
		restoreSelection();

		if (surface() === 'page') {
			pageCommand(name, argument);
			return;
		}

		const text = editor.value;
		const start = editor.selectionStart;
		const end = editor.selectionEnd;
		let result;

		// Core helpers are behavior-preserving JS ports; call through loosely typed.
		const fmt = {
			toggleMark,
			toggleLink,
			setBlockKind,
			clearFormatting,
			insertBlock,
			toggleBlockKind
		} as {
			toggleMark: (t: string, s: number, e: number, k: string) => FormatResult;
			toggleLink: (t: string, s: number, e: number, p?: string) => FormatResult;
			setBlockKind: (t: string, s: number, e: number, k: string) => FormatResult;
			clearFormatting: (t: string, s: number, e: number) => FormatResult;
			insertBlock: (
				t: string,
				s: number,
				e: number,
				snippet: string,
				caret?: number | null
			) => FormatResult;
			toggleBlockKind: (t: string, s: number, e: number, k: string) => FormatResult;
		};

		if ((MARKS as Record<string, unknown>)[name])
			result = fmt.toggleMark(text, start, end, name);
		else if (name === 'link') result = fmt.toggleLink(text, start, end);
		else if (name === 'style')
			result = fmt.setBlockKind(text, start, end, argument || 'paragraph');
		else if (name === 'clear') result = fmt.clearFormatting(text, start, end);
		else if (SNIPPETS[name])
			result = fmt.insertBlock(
				text,
				start,
				end,
				SNIPPETS[name].text,
				SNIPPETS[name].caret
			);
		else result = fmt.toggleBlockKind(text, start, end, name);

		editor.value = result.text;
		sourceChanged();
		editor.focus();
		editor.setSelectionRange(result.start, result.end);
		rememberSource();
		updateCursor();
		updateToolbar();
	}

	function updateToolbar() {
		if (!editor) return;
		let nextMarks: InlineMarks;
		let kind: string;

		if (surface() === 'source') {
			const text = editor.value;
			nextMarks = inlineMarks(
				text,
				editor.selectionStart,
				editor.selectionEnd
			) as InlineMarks;
			kind = blockKind(text, editor.selectionStart) as string;
		} else {
			const current = pageState();
			nextMarks = current.marks;
			kind = current.kind;
		}

		marks = {
			bold: Boolean(nextMarks.bold),
			italic: Boolean(nextMarks.italic),
			strike: Boolean(nextMarks.strike),
			code: Boolean(nextMarks.code),
			link: Boolean(nextMarks.link)
		};
		activeBlock = kind;
		inTable = surface() === 'page' && Boolean(currentCell());

		const style = STYLES.find((item) => item.kind === kind);
		styleToken = style ? style.token : OTHER_TOKENS[kind] || 'Aa';
		styleName = style ? style.label : OTHER_NAMES[kind] || 'Normal text';

		if (focus) markWritingBlock();
	}

	function markWritingBlock() {
		if (!sheet) return;
		const previous = sheet.querySelector('.is-writing');
		if (previous) previous.classList.remove('is-writing');
		if (!focus) return;

		let block = currentBlock();
		while (block && block.parentNode !== sheet) block = block.parentNode as HTMLElement | null;
		if (block && block.parentNode === sheet) block.classList.add('is-writing');
	}

	function setFocusMode(on: boolean) {
		if (on === focus) return;
		focus = on;
		if (on) {
			viewBeforeFocus = view;
			view = 'page';
		} else if (viewBeforeFocus) {
			view = viewBeforeFocus;
			viewBeforeFocus = null;
		}
		applyView();
		markWritingBlock();
		if (on && sheet) sheet.focus();
		desk.persist();
	}

	function setView(next: ViewMode) {
		view = next;
		applyView();
		enableTaskBoxes(); // boxes follow the view: live in edit views, frozen in read
		syncBackdrop(); // re-entering the source surface re-aligns highlight and scroll
		desk.persist();
	}

	function openShortcuts() {
		closeMenus();
		paletteOpen = false;
		shortcutsOpen = true;
	}

	function setThemeMode(mode: ThemeMode) {
		theme = mode;
		saveThemePrefs(mode);
	}

	function cycleTheme() {
		setThemeMode(nextTheme(theme, systemDark));
	}

	function toggleFootnotes() {
		footnotesOn = !footnotesOn;
		setFootnotesEnabled(footnotesOn);
		renderDocument();
		desk.flashStatus(footnotesOn ? 'Footnotes on' : 'Footnotes off');
	}

	function dismissWelcome() {
		welcomeVisible = false;
		saveOnboarding({ welcomeDismissed: true });
	}

	/** True when the event target is a field that should receive "?" as a character. */
	function isTypingTarget(target: EventTarget | null): boolean {
		if (!(target instanceof HTMLElement)) return false;
		const tag = target.tagName;
		if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return true;
		if (target.isContentEditable) return true;
		return Boolean(target.closest('[contenteditable="true"]'));
	}

	/* ---------- slash palette ------------------------------------------- */

	function refreshSlashFromEditor() {
		if (!editor || slashMode !== 'source') return;
		const detected = detectSlashQuery(editor.value, editor.selectionStart);
		if (!detected) {
			slashOpen = false;
			return;
		}
		slashQuery = detected.query;
		slashItems = filterSlashCommands(detected.query);
		slashIndex = 0;
		slashOpen = true;
		slashAnchor = slashAnchorFromEditor();
	}

	function slashAnchorFromEditor(): { top: number; left: number } {
		if (!editor) return { top: 120, left: 40 };
		const rect = editor.getBoundingClientRect();
		const style = getComputedStyle(editor);
		const lineHeight = parseFloat(style.lineHeight) || 24;
		const paddingTop = parseFloat(style.paddingTop) || 0;
		const line = editor.value.slice(0, editor.selectionStart).split('\n').length;
		const top = Math.min(
			Math.max(8, rect.top + paddingTop + line * lineHeight - editor.scrollTop + 4),
			window.innerHeight - 220
		);
		const left = Math.min(rect.left + 20, window.innerWidth - 300);
		return { top, left };
	}

	function openSlashOnPage() {
		slashMode = 'page';
		slashQuery = '';
		slashItems = filterSlashCommands('');
		slashIndex = 0;
		slashOpen = true;
		if (sheet) {
			const rect = sheet.getBoundingClientRect();
			slashAnchor = {
				top: Math.min(rect.top + 48, window.innerHeight - 220),
				left: Math.min(rect.left + 24, window.innerWidth - 300)
			};
		} else {
			slashAnchor = { top: 120, left: 40 };
		}
	}

	function removeSourceSlashQuery() {
		if (!editor || slashMode !== 'source') return;
		const detected = detectSlashQuery(editor.value, editor.selectionStart);
		if (!detected) return;
		const end = editor.selectionStart;
		const next = editor.value.slice(0, detected.start) + editor.value.slice(end);
		editor.value = next;
		editor.setSelectionRange(detected.start, detected.start);
		sourceChanged();
		rememberSource();
	}

	function closeSlash(removeQuery = false) {
		if (removeQuery) removeSourceSlashQuery();
		slashOpen = false;
		slashQuery = '';
		slashItems = [];
	}

	function applySlashCommand(cmd: SlashCommand) {
		if (slashMode === 'source') removeSourceSlashQuery();
		slashOpen = false;
		slashQuery = '';
		slashItems = [];

		if (cmd.action.type === 'command') {
			command(cmd.action.name, cmd.action.argument);
		} else {
			command(cmd.action.id);
		}
	}

	/* ---------- command palette (⌘K) ------------------------------------- */

	function openPalette() {
		closeMenus();
		closeSlash();
		paletteOpen = true;
	}

	function closePalette() {
		paletteOpen = false;
	}

	/** One bus: palette insert actions reuse the slash command dispatch. */
	function runPaletteCommand(cmd: PaletteCommand) {
		paletteOpen = false;
		if (cmd.action.type === 'slash') {
			const action = cmd.action.command.action;
			if (action.type === 'command') command(action.name, action.argument);
			else command(action.id);
			return;
		}
		switch (cmd.action.name) {
			case 'new':
				newDocument();
				break;
			case 'open':
				fileInput?.click();
				break;
			case 'export-md':
				onExport('md');
				break;
			case 'export-html':
				onExport('html');
				break;
			case 'export-print':
				onExport('print');
				break;
			case 'delete':
				if (desk.activeId) deleteLibraryDoc(desk.activeId);
				break;
			case 'clear':
				clearDesk();
				break;
			case 'view-page':
				setView('page');
				break;
			case 'view-split':
				setView('split');
				break;
			case 'view-source':
				setView('source');
				break;
			case 'view-read':
				setView('read');
				break;
			case 'toggle-library':
				toggleLibrary();
				break;
			case 'toggle-focus':
				setFocusMode(!focus);
				break;
			case 'theme-light':
				setThemeMode('light');
				break;
			case 'theme-dark':
				setThemeMode('dark');
				break;
			case 'theme-system':
				setThemeMode('system');
				break;
			case 'toggle-footnotes':
				toggleFootnotes();
				break;
			case 'find':
				openFind();
				break;
			case 'toggle-truth':
				toggleTruthMode();
				break;
			case 'shortcuts':
				openShortcuts();
				break;
		}
	}

	/* ---------- find ---------------------------------------------------- */

	/**
	 * Live find (browser-style): as you type, highlights update on the page.
	 * Focus stays in the find field. Enter / ↑↓ step through matches.
	 */
	function openFind() {
		closeMenus();
		closeSlash();
		paletteOpen = false;
		// Prefer the typeset page — that's where highlights belong.
		if (view === 'source') {
			view = 'page';
			applyView();
			desk.persist();
		}
		findOpen = true;
		findFocusToken += 1;
		// Restore live results if a query is already there.
		runFindSearch({ resetIndex: false, immediate: true });
	}

	function closeFind() {
		findOpen = false;
		clearTimeout(findPaintTimer);
		clearFindHighlights(sheet);
	}

	/** Live as you type — debounce paint slightly for smooth keystrokes. */
	function updateFindMatches(q: string) {
		findQuery = q;
		runFindSearch({ resetIndex: true, immediate: false });
	}

	function runFindSearch(opts: { resetIndex?: boolean; immediate?: boolean } = {}) {
		const q = findQuery;
		if (q.trim().length < FIND_MIN_LENGTH) {
			clearTimeout(findPaintTimer);
			findMatchesList = [];
			findIndex = 0;
			clearFindHighlights(sheet);
			return;
		}

		const apply = () => {
			// Prefer page plain text so highlights match what the writer sees.
			const haystack =
				sheet && view !== 'source'
					? sheet.innerText || sheet.textContent || desk.doc
					: desk.doc;
			findMatchesList = findMatches(haystack, q);
			if (opts.resetIndex !== false) findIndex = 0;
			if (findIndex >= findMatchesList.length) findIndex = Math.max(0, findMatchesList.length - 1);
			// While typing, only nudge scroll if the hit is off-screen — never jump to center.
			revealFindMatch(findIndex, { scroll: true });
		};

		clearTimeout(findPaintTimer);
		if (opts.immediate) {
			apply();
		} else {
			// ~40ms feels instant; Highlight API is cheap (no DOM writes).
			findPaintTimer = window.setTimeout(apply, 40);
		}
	}

	function revealFindMatch(index: number, opts: { scroll?: boolean } = {}) {
		if (findQuery.trim().length < FIND_MIN_LENGTH) {
			clearFindHighlights(sheet);
			findMatchesList = [];
			findIndex = 0;
			return;
		}

		// Page highlights are the product surface (CSS Highlight API — no layout shift).
		if (sheet && view !== 'source') {
			const painted = paintFindHighlights(sheet, findQuery, index, {
				scroll: opts.scroll !== false
			});
			if (painted > 0) {
				findIndex = ((index % painted) + painted) % painted;
				if (findMatchesList.length !== painted) {
					findMatchesList = Array.from({ length: painted }, (_, i) => ({
						index: i,
						line: 0,
						column: 0,
						preview: ''
					}));
				}
				return;
			}
			// Query only hits Markdown chrome, not page text.
			findMatchesList = [];
			findIndex = 0;
			return;
		}

		// Source-only fallback: select in the Markdown textarea (no focus steal).
		if (!findMatchesList.length || !editor) {
			findIndex = 0;
			return;
		}
		const i = ((index % findMatchesList.length) + findMatchesList.length) % findMatchesList.length;
		findIndex = i;
		const match = findMatchesList[i];
		const end = match.index + Math.max(FIND_MIN_LENGTH, findQuery.trim().length);
		const ratio = match.index / Math.max(1, editor.value.length);
		editor.scrollTop = Math.max(0, ratio * editor.scrollHeight - editor.clientHeight / 3);
		try {
			editor.setSelectionRange(match.index, end);
		} catch {
			/* ignore */
		}
		updateCursor();
	}

	function findNext() {
		if (findQuery.trim().length < FIND_MIN_LENGTH) return;
		if (!findMatchesList.length) {
			runFindSearch({ resetIndex: true, immediate: true });
			return;
		}
		revealFindMatch(findIndex + 1, { scroll: true });
	}

	function findPrev() {
		if (findQuery.trim().length < FIND_MIN_LENGTH) return;
		if (!findMatchesList.length) {
			runFindSearch({ resetIndex: true, immediate: true });
			return;
		}
		revealFindMatch(findIndex - 1, { scroll: true });
	}

	/* ---------- outline drag-to-reorder ------------------------------------ */

	let outlineDragFrom = $state<number | null>(null);
	let outlineDropTarget = $state<{ index: number; before: boolean } | null>(null);

	function applyOutlineReorder(from: number, to: number) {
		if (from === to) return;
		const next = reorderOutlineSections(desk.doc, from, to);
		if (next === desk.doc) return;
		setDoc(next);
		rebuildOutline();
	}

	function onOutlineDragStart(event: DragEvent, index: number) {
		outlineDragFrom = index;
		if (!event.dataTransfer) return;
		event.dataTransfer.effectAllowed = 'move';
		event.dataTransfer.setData('text/plain', String(index));
		const row = (event.currentTarget as HTMLElement).closest('li');
		if (row) event.dataTransfer.setDragImage(row as HTMLElement, 12, 12);
	}

	function onOutlineDragOver(event: DragEvent, index: number) {
		if (outlineDragFrom === null) return;
		event.preventDefault();
		if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
		const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
		outlineDropTarget = { index, before: event.clientY < rect.top + rect.height / 2 };
	}

	function onOutlineDrop(event: DragEvent) {
		event.preventDefault();
		if (outlineDragFrom !== null && outlineDropTarget) {
			let to = outlineDropTarget.index + (outlineDropTarget.before ? 0 : 1);
			if (to > outlineDragFrom) to -= 1;
			applyOutlineReorder(outlineDragFrom, to);
		}
		outlineDragFrom = null;
		outlineDropTarget = null;
	}

	function onOutlineDragEnd() {
		outlineDragFrom = null;
		outlineDropTarget = null;
	}

	/* Keyboard parity: Alt+Arrow moves a section without the mouse. The
	   rebuild after a reorder replaces every row (keys are line-based), so
	   focus would fall to <body> and the second keypress would die — put it
	   back on the moved section, on the same kind of control that had it. */
	async function onOutlineGripKey(event: KeyboardEvent, index: number) {
		if (!event.altKey) return;
		const to =
			event.key === 'ArrowUp' ? index - 1 : event.key === 'ArrowDown' ? index + 1 : index;
		if (to === index || to < 0 || to >= outlineItems.length) return;
		event.preventDefault();
		const wasGrip = (event.currentTarget as HTMLElement).classList.contains('outline-grip');
		applyOutlineReorder(index, to);
		await tick();
		const row = outlineMenuEl?.querySelectorAll('.outline-row')[to];
		const target = row?.querySelector(wasGrip ? '.outline-grip' : '.outline-jump');
		(target as HTMLElement | undefined)?.focus();
	}

	/* ---------- file / export ------------------------------------------- */

	function openFile(file: File) {
		const reader = new FileReader();
		reader.addEventListener('load', () => {
			const text = String(reader.result);
			if (!desk.library) {
				setDoc(text);
				editor?.focus();
				return;
			}
			// Import as a new library document — never overwrites without intent.
			const baseName = file.name.replace(/\.(md|markdown|txt)$/i, '').trim();
			if (!libraryOpen) libraryOpen = true;
			desk.importDocument(text, baseName || undefined);
			loadActiveIntoEditor();
			editor?.focus();
		});
		reader.readAsText(file);
	}

	function onExport(kind: string) {
		if (kind === 'md') download(desk.doc, documentName(desk.doc) + '.md', 'text/markdown');
		else if (kind === 'html') {
			// Standalone file: swap stored-asset refs for inline data URLs.
			void inlineAssetDataUrls(desk.doc, async (id) => {
				const blob = await getAsset(id);
				return blob ? blobToDataUrl(blob) : null;
			}).then((doc) => exportStandaloneHtml(doc, { footnotes: footnotesOn }));
		} else if (kind === 'print') setTimeout(() => window.print(), 60);
	}

	function clearDesk() {
		if (desk.doc.trim() !== '' && !confirm('Clear the desk? This cannot be undone.')) return;
		setDoc('');
		editor?.focus();
	}

	/* ---------- event handlers ------------------------------------------ */

	function onToolbarPointer(event: Event) {
		const t = event.target as HTMLElement;
		if (t.closest('button')) event.preventDefault();
	}

	function onToolbarClick(event: MouseEvent) {
		const button = (event.target as HTMLElement).closest('button');
		if (!button || button.id === 'styleBtn' || button.id === 'moreBtn') return;
		const ds = (button as HTMLElement).dataset;
		if (ds.mark) command(ds.mark);
		else if (ds.block) command(ds.block);
		else if (ds.insert) command(ds.insert);
		else if (ds.action) command(ds.action);
	}

	function onMoreMenuClick(event: MouseEvent) {
		const button = (event.target as HTMLElement).closest('button');
		if (!button) return;
		const ds = (button as HTMLElement).dataset;
		if (ds.mark) command(ds.mark);
		else if (ds.table) command(ds.table);
		else if (ds.block) command(ds.block);
		else if (ds.insert) command(ds.insert);
		else if (ds.action) command(ds.action);
		closeMenus();
	}

	function onSheetKeydown(event: KeyboardEvent) {
		if (view === 'read') return;
		/* Slash on an empty paragraph → structure palette (page surface). */
		if (event.key === '/' && !event.metaKey && !event.ctrlKey && !event.altKey) {
			const block = currentBlock();
			const empty =
				block &&
				/^(P|DIV)$/.test(block.tagName) &&
				!(block.textContent || '').replace(/\u00a0/g, ' ').trim();
			if (empty || (!block && sheet && !(sheet.textContent || '').trim())) {
				event.preventDefault();
				openSlashOnPage();
				return;
			}
		}

		if (slashOpen && slashMode === 'page') {
			if (event.key === 'Escape') {
				event.preventDefault();
				closeSlash();
				return;
			}
			if (event.key === 'ArrowDown') {
				event.preventDefault();
				slashIndex = Math.min(slashItems.length - 1, slashIndex + 1);
				return;
			}
			if (event.key === 'ArrowUp') {
				event.preventDefault();
				slashIndex = Math.max(0, slashIndex - 1);
				return;
			}
			if (event.key === 'Enter' && slashItems[slashIndex]) {
				event.preventDefault();
				applySlashCommand(slashItems[slashIndex]);
				return;
			}
		}

		/* Enter inside a task item continues the task list. The native split
		   clones the <li> but not its checkbox, so the new line would degrade
		   to a plain bullet on the next round-trip — do the split by hand. */
		if (
			event.key === 'Enter' &&
			!event.shiftKey &&
			!event.metaKey &&
			!event.ctrlKey &&
			!event.altKey
		) {
			const block = currentBlock();
			if (block && block.tagName === 'LI' && block.classList.contains('task')) {
				const selection = window.getSelection();
				if (selection && selection.rangeCount && selection.isCollapsed) {
					event.preventDefault();
					const li = block as HTMLElement;
					const tail = selection.getRangeAt(0).cloneRange();
					tail.selectNodeContents(li);
					tail.setStart(selection.getRangeAt(0).endContainer, selection.getRangeAt(0).endOffset);
					const next = document.createElement('li');
					next.className = 'task';
					const box = document.createElement('input');
					box.type = 'checkbox';
					box.setAttribute('contenteditable', 'false');
					next.appendChild(box);
					next.appendChild(tail.extractContents());
					li.after(next);
					const caret = document.createRange();
					caret.setStart(next, 1);
					caret.collapse(true);
					selection.removeAllRanges();
					selection.addRange(caret);
					rememberPage();
					pageChanged();
					updateToolbar();
					return;
				}
			}
		}

		if (event.key !== 'Tab') return;
		const cell = currentCell();
		if (!cell) return;
		event.preventDefault();
		const cells = Array.from(cell.closest('table')!.querySelectorAll('th, td'));
		const next = cells[cells.indexOf(cell) + (event.shiftKey ? -1 : 1)] as HTMLElement | undefined;
		if (next) placeCaretIn(next);
		else if (!event.shiftKey) addRow(cell, true);
		rememberPage();
		pageChanged();
		updateToolbar();
	}

	function imageFileFrom(data: DataTransfer | null): File | null {
		if (!data) return null;
		for (const file of Array.from(data.files ?? [])) {
			if (/^image\//.test(file.type)) return file;
		}
		return null;
	}

	/**
	 * One path for paste and drop, both surfaces: store the blob in IndexedDB,
	 * then reference it. Page gets an <img> at the selection; source gets the
	 * Markdown reference at the caret.
	 */
	async function insertImageFile(file: File) {
		if (view === 'read') return; // the page is hands-off in read view
		const meta = await putAsset(file);
		const ref = assetRef(meta.id);
		const alt = altFromFileName(file.name);
		restoreSelection();
		if (surface() === 'page' && sheet) {
			// Manual Range insertion — deterministic whether the caret is current
			// (paste) or only remembered (drop). The URL is minted immediately:
			// the image shows at once, and data-asset keeps serialise honest.
			const img = document.createElement('img');
			img.setAttribute('data-asset', meta.id);
			img.setAttribute('alt', alt);
			const url = URL.createObjectURL(file);
			assetUrls.set(meta.id, url);
			img.src = url;
			const selection = window.getSelection();
			let range = selection && selection.rangeCount > 0 ? selection.getRangeAt(0) : null;
			if (!range || !sheet.contains(range.commonAncestorContainer)) {
				// No caret on the page — append a fresh paragraph holding the image
				// (a bare <img> at the sheet root would not serialise).
				const p = document.createElement('p');
				p.appendChild(img);
				sheet.appendChild(p);
				range = document.createRange();
				range.setStartAfter(p);
				range.collapse(true);
			} else {
				range.deleteContents();
				range.insertNode(img);
				range.setStartAfter(img);
				range.collapse(true);
			}
			selection?.removeAllRanges();
			selection?.addRange(range);
			rememberPage();
			pageChanged();
			void resolveAssetImages(sheet);
			return;
		}
		if (!editor) return;
		const edit = insertImageRef(editor.value, editor.selectionStart, editor.selectionEnd, ref, alt);
		setDoc(edit.text);
		editor.setSelectionRange(edit.selectionStart, edit.selectionEnd);
		rememberSource();
	}

	function onEditorPaste(event: ClipboardEvent) {
		if (!editor || !event.clipboardData) return;
		const file = imageFileFrom(event.clipboardData);
		if (!file) return; // plain text — let the default paste happen
		event.preventDefault();
		void insertImageFile(file);
	}

	function onSheetPaste(event: ClipboardEvent) {
		if (!event.clipboardData) return;
		const file = imageFileFrom(event.clipboardData);
		if (file) {
			event.preventDefault();
			void insertImageFile(file);
			return;
		}
		event.preventDefault();
		run('insertText', event.clipboardData.getData('text/plain'));
		pageChanged();
	}

	function onReadingPaneMouseDown(event: MouseEvent) {
		if (view === 'read' || event.target !== readingPane || !sheet) return;
		event.preventDefault();
		sheet.focus();
		const last = sheet.lastElementChild;
		const selection = window.getSelection();
		if (!last || !selection) return;
		const range = document.createRange();
		range.selectNodeContents(last);
		range.collapse(false);
		selection.removeAllRanges();
		selection.addRange(range);
	}

	function onEditorKeydown(event: KeyboardEvent) {
		if (!editor) return;
		const meta = event.metaKey || event.ctrlKey;

		/* Slash palette navigation while open */
		if (slashOpen && slashMode === 'source') {
			if (event.key === 'Escape') {
				event.preventDefault();
				closeSlash(true);
				return;
			}
			if (event.key === 'ArrowDown') {
				event.preventDefault();
				slashIndex = Math.min(slashItems.length - 1, slashIndex + 1);
				return;
			}
			if (event.key === 'ArrowUp') {
				event.preventDefault();
				slashIndex = Math.max(0, slashIndex - 1);
				return;
			}
			if (event.key === 'Enter' && !event.shiftKey && slashItems[slashIndex]) {
				event.preventDefault();
				applySlashCommand(slashItems[slashIndex]);
				return;
			}
			if (event.key === 'Tab' && slashItems[slashIndex]) {
				event.preventDefault();
				applySlashCommand(slashItems[slashIndex]);
				return;
			}
		}

		if (meta) {
			const key = event.key.toLowerCase();
			if (key === 'f' && !event.altKey && !event.shiftKey) {
				event.preventDefault();
				openFind();
				return;
			}
			if (event.altKey && '0123'.indexOf(key) !== -1) {
				event.preventDefault();
				command('style', key === '0' ? 'paragraph' : 'h' + key);
				return;
			}
			if (!event.altKey) {
				if (key === 'b') {
					event.preventDefault();
					command('bold');
					return;
				}
				if (key === 'i') {
					event.preventDefault();
					command('italic');
					return;
				}
				if (key === 'k' && event.shiftKey) {
					event.preventDefault();
					command('link');
					return;
				}
				if (key === 'e') {
					event.preventDefault();
					command('code');
					return;
				}
				if (key === 'x' && event.shiftKey) {
					event.preventDefault();
					command('strike');
					return;
				}
				if (key === '7' && event.shiftKey) {
					event.preventDefault();
					command('ol');
					return;
				}
				if (key === '8' && event.shiftKey) {
					event.preventDefault();
					command('ul');
					return;
				}
			}
		}

		if (event.key === 'Tab') {
			event.preventDefault();
			const tabEdit = indentOnTab(
				editor.value,
				editor.selectionStart,
				editor.selectionEnd,
				event.shiftKey
			);
			setDoc(tabEdit.text);
			editor.setSelectionRange(tabEdit.selectionStart, tabEdit.selectionEnd);
			return;
		}

		/* Enter continues lists / tasks / quotes; Shift+Enter writes a hard break. */
		if (event.key === 'Enter') {
			const start = editor.selectionStart;
			if (start !== editor.selectionEnd) return;
			const edit = event.shiftKey
				? hardBreak(editor.value, start)
				: continueOnEnter(editor.value, start);
			if (!edit) return;
			event.preventDefault();
			setDoc(edit.text);
			editor.setSelectionRange(edit.selectionStart, edit.selectionEnd);
		}
	}

	function onEditorScroll() {
		if (backdrop && editor) backdrop.scrollTop = editor.scrollTop;
		if (!editor || !readingPane || view !== 'split') return;
		const range = editor.scrollHeight - editor.clientHeight;
		if (range <= 0) return;
		const ratio = editor.scrollTop / range;
		readingPane.scrollTop = ratio * (readingPane.scrollHeight - readingPane.clientHeight);
	}

	/* ---------- lifecycle ----------------------------------------------- */

	onMount(() => {
		try {
			document.execCommand('styleWithCSS', false, 'false');
			document.execCommand('defaultParagraphSeparator', false, 'p');
		} catch {
			/* older engines */
		}

		// First-run orientation (independent of document state).
		const onboarding = loadOnboarding();
		welcomeVisible = !onboarding.welcomeDismissed;

		// Multi-doc library (migrates legacy single-doc storage automatically).
		const ui = desk.init(SAMPLE);
		desk.uiSnapshot = () => ({ libraryOpen, view, focus });
		libraryOpen = ui.libraryOpen;
		// Narrow viewports: library as overlay would dominate — start closed.
		if (isNarrow()) libraryOpen = false;
		view = ui.view;
		focus = ui.focus;
		applyView();
		if (editor) editor.value = desk.doc;
		// Opt-in dialect packs — before the first render, so they apply to it.
		footnotesOn = loadDialectPrefs().footnotes;
		renderDocument();
		updateCursor();
		updateToolbar();

		// Truth: restore on/off + per-note baseline (do not reset baseline to body).
		const truthPrefs = loadTruthPrefs();
		truthEnabled = truthPrefs.enabled;
		restoreTruthForActiveDoc();
		pruneTruthBaselines(desk.library?.documents.map((d) => d.id) ?? []);

		// Theme: restore the saved mode, then follow the OS while in "system".
		theme = loadThemePrefs();
		const scheme = window.matchMedia('(prefers-color-scheme: dark)');
		const onScheme = () => {
			systemDark = scheme.matches;
		};
		onScheme();
		scheme.addEventListener('change', onScheme);

		ready = true;

		const onDocClick = () => {
			closeMenus();
			if (slashOpen && slashMode === 'page') closeSlash();
		};
		const onKey = (event: KeyboardEvent) => {
			const meta = event.metaKey || event.ctrlKey;

			// Global command palette — every action, fuzzy-findable. Toggles.
			if (meta && event.key.toLowerCase() === 'k' && !event.altKey && !event.shiftKey) {
				event.preventDefault();
				if (paletteOpen) closePalette();
				else openPalette();
				return;
			}

			// Global find — always our find bar (not the browser's), including when
			// focus is already in the find field (re-focus / select query).
			if (meta && event.key.toLowerCase() === 'f' && !event.altKey && !event.shiftKey) {
				event.preventDefault();
				openFind();
				return;
			}

			// Shortcuts: "?" when not typing into an input/textarea/contenteditable field with modifiers
			if (
				event.key === '?' &&
				!event.metaKey &&
				!event.ctrlKey &&
				!event.altKey &&
				!isTypingTarget(event.target)
			) {
				event.preventDefault();
				closeMenus();
				shortcutsOpen = true;
				return;
			}

			if (event.key === 'Escape') {
				if (paletteOpen) {
					closePalette();
					return;
				}
				if (shortcutsOpen) {
					shortcutsOpen = false;
					return;
				}
				if (truthStripOpen) {
					dismissTruthStrip();
					return;
				}
				if (findOpen) {
					closeFind();
					return;
				}
				if (slashOpen) {
					closeSlash(slashMode === 'source');
					return;
				}
				if (openMenu) closeMenus();
				else if (focus) setFocusMode(false);
			}
		};
		const onSelChange = () => {
			if (onPage()) {
				rememberPage();
				updateToolbar();
			}
		};
		const onResize = () => {
			if (isNarrow() && view === 'split') {
				applyView();
				desk.persist();
			}
		};

		const onDragEnter = (event: DragEvent) => {
			if (!event.dataTransfer || !Array.from(event.dataTransfer.types).includes('Files')) return;
			dragDepth++;
			dragging = true;
		};
		const onDragOver = (event: DragEvent) => event.preventDefault();
		const onDragLeave = () => {
			dragDepth = Math.max(0, dragDepth - 1);
			if (dragDepth === 0) dragging = false;
		};
		const onDrop = (event: DragEvent) => {
			event.preventDefault();
			dragDepth = 0;
			dragging = false;
			const file = event.dataTransfer?.files?.[0];
			if (!file) return;
			if (/^image\//.test(file.type)) {
				void insertImageFile(file);
				return;
			}
			openFile(file);
		};

		document.addEventListener('click', onDocClick);
		document.addEventListener('keydown', onKey);
		document.addEventListener('selectionchange', onSelChange);
		window.addEventListener('resize', onResize);
		window.addEventListener('dragenter', onDragEnter);
		window.addEventListener('dragover', onDragOver);
		window.addEventListener('dragleave', onDragLeave);
		window.addEventListener('drop', onDrop);

		const viewport = window.visualViewport;
		const followKeyboard = () => {
			if (!viewport) return;
			const overlap = Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop);
			keyboardUp = overlap > 120;
			document.documentElement.style.setProperty(
				'--keyboard-offset',
				-Math.round(overlap) + 'px'
			);
		};
		if (viewport) {
			viewport.addEventListener('resize', followKeyboard);
			viewport.addEventListener('scroll', followKeyboard);
			followKeyboard();
		}

		return () => {
			document.removeEventListener('click', onDocClick);
			document.removeEventListener('keydown', onKey);
			document.removeEventListener('selectionchange', onSelChange);
			window.removeEventListener('resize', onResize);
			window.removeEventListener('dragenter', onDragEnter);
			window.removeEventListener('dragover', onDragOver);
			window.removeEventListener('dragleave', onDragLeave);
			window.removeEventListener('drop', onDrop);
			scheme.removeEventListener('change', onScheme);
			// Minted object URLs die with the editor.
			for (const url of assetUrls.values()) URL.revokeObjectURL(url);
			assetUrls.clear();
			if (viewport) {
				viewport.removeEventListener('resize', followKeyboard);
				viewport.removeEventListener('scroll', followKeyboard);
			}
			// Return menus to the component tree if we ported them
			for (const el of [outlineMenuEl, fileMenuEl, exportMenuEl, styleMenuEl, moreMenuEl]) {
				if (el && el.parentNode === document.body) el.remove();
			}
		};
	});
</script>

<!--
  Root shell. data-view / focus-mode / dragging / keyboard-up drive CSS.
  All chrome lives here so print styles can hide it cleanly.
-->
<div
	class="desk"
	class:focus-mode={focus}
	class:dragging
	class:keyboard-up={keyboardUp}
	class:library-open={libraryOpen}
	data-view={view}
	bind:this={deskEl}
>
	<div class="desk-body">
		{#if lib}
			<LibrarySidebar
				open={libraryOpen}
				activeId={lib.activeId}
				hits={libraryHits()}
				bind:query={libraryQuery}
				trash={lib.trash}
				onSelect={switchDocument}
				onNew={newDocument}
				onRename={renameActiveLibraryDoc}
				onDelete={deleteLibraryDoc}
				onUndo={undoLibraryDelete}
				onClose={() => {
					libraryOpen = false;
					desk.persistImmediate();
				}}
				onQueryChange={(q) => {
					libraryQuery = q;
				}}
			/>
		{/if}

		<div class="desk-main">
	<header class="app-bar">
		<div class="brand">
			<button
				type="button"
				class="btn btn-quiet library-toggle"
				title={libraryOpen ? 'Collapse sidebar' : 'Expand sidebar'}
				aria-label={libraryOpen ? 'Collapse sidebar' : 'Expand sidebar'}
				aria-pressed={libraryOpen}
				onclick={toggleLibrary}
			>
				<Icon name="sidebar" />
			</button>
			<div class="menu-wrap brand-wrap">
				<button
					type="button"
					class="brand-trigger"
					bind:this={fileBtnEl}
					aria-haspopup="true"
					aria-expanded={openMenu === 'file'}
					aria-label="File menu"
					title="File"
					onclick={(e) => {
						e.stopPropagation();
						toggleMenu('file');
					}}
				>
					<BrandMark />
					<span class="brand-caret"><Icon name="chevron-down" size={12} /></span>
				</button>
				<span class="brand-name">Writing Desk</span>
				<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_noninteractive_element_interactions -->
				<ul
					class="menu menu--left"
					bind:this={fileMenuEl}
					hidden
					onmousedown={(e) => {
						if ((e.target as HTMLElement).closest('button')) e.preventDefault();
					}}
					onclick={() => closeMenus()}
				>
					<li>
						<button type="button" onclick={newDocument}><Icon name="plus" />New document</button>
					</li>
					<li>
						<button type="button" onclick={() => fileInput?.click()}
							><Icon name="folder" />Open a .md file…</button
						>
					</li>
					<li>
						<button
							type="button"
							onclick={() => {
								setDoc(SAMPLE);
								editor?.focus();
							}}><Icon name="page" />Load the sample document</button
						>
					</li>
					<li>
						<button type="button" class="danger" onclick={clearDesk}
							><Icon name="trash" />Clear the desk</button
						>
					</li>
					<li class="menu-note">Documents stay in this browser. Drop a .md file to import.</li>
				</ul>
			</div>
		</div>

		<span class="save-status" class:on={desk.saveOn} role="status" aria-live="polite">{desk.saveLabel}</span>

		<div class="views" role="group" aria-label="View">
			<button
				type="button"
				data-view-btn="page"
				aria-pressed={view === 'page'}
				title="Page"
				aria-label="Page"
				onclick={() => setView('page')}
			>
				<Icon name="page" />
			</button>
			<button
				type="button"
				data-view-btn="split"
				aria-pressed={view === 'split'}
				title="Page and Markdown side by side"
				aria-label="Split"
				onclick={() => setView('split')}
			>
				<Icon name="split" />
			</button>
			<button
				type="button"
				data-view-btn="source"
				aria-pressed={view === 'source'}
				title="Markdown"
				aria-label="Markdown"
				onclick={() => setView('source')}
			>
				<Icon name="code" />
			</button>
			<button
				type="button"
				data-view-btn="read"
				aria-pressed={view === 'read'}
				title="Read — the typeset page, hands off"
				aria-label="Read"
				onclick={() => setView('read')}
			>
				<Icon name="read" />
			</button>
		</div>

		<div class="menu-wrap">
			<button
				type="button"
				class="btn btn-quiet"
				bind:this={outlineBtnEl}
				aria-haspopup="true"
				aria-expanded={openMenu === 'outline'}
				onclick={(e) => {
					e.stopPropagation();
					toggleMenu('outline', rebuildOutline);
				}}
			>
				Outline
			</button>
			<ul class="menu menu-outline" bind:this={outlineMenuEl} hidden>
				{#if outlineItems.length === 0}
					<li class="empty">No headings yet. Use /h1 in Markdown or the style menu.</li>
				{:else}
					{#each outlineItems as heading, index (heading.line + ':' + index)}
						<li
							class="outline-row"
							class:dragging={outlineDragFrom === index}
							class:drop-before={outlineDropTarget?.index === index && outlineDropTarget.before}
							class:drop-after={outlineDropTarget?.index === index && !outlineDropTarget.before}
							ondragover={(e) => onOutlineDragOver(e, index)}
							ondrop={onOutlineDrop}
						>
							<span
								class="outline-grip"
								role="button"
								tabindex="0"
								title="Drag to reorder section (⌥↑↓)"
								aria-label="Reorder section — drag, or Alt with arrow keys"
								draggable="true"
								ondragstart={(e) => onOutlineDragStart(e, index)}
								ondragend={onOutlineDragEnd}
								onkeydown={(e) => onOutlineGripKey(e, index)}
							>
								<Icon name="grip" size={14} />
							</span>
							<button
								type="button"
								class="lv{heading.level} outline-jump"
								onclick={() => jumpToHeading(heading, index)}
								onkeydown={(e) => onOutlineGripKey(e, index)}
							>
								{heading.text || '(untitled)'}
							</button>
						</li>
					{/each}
					<li class="menu-note">Drag the dots to reorder whole sections · ⌥↑↓ too</li>
				{/if}
			</ul>
		</div>

		<button
			type="button"
			class="btn btn-quiet"
			aria-pressed={focus}
			title="Dim everything but the paragraph you are writing. Escape leaves."
			onclick={() => setFocusMode(!focus)}
		>
			Focus
		</button>

		<button
			type="button"
			class="btn btn-quiet"
			title="Find in document (⌘F)"
			aria-label="Find in document"
			aria-pressed={findOpen}
			onclick={(e) => {
				e.stopPropagation();
				if (findOpen) closeFind();
				else openFind();
			}}
		>
			Find
		</button>

		<button
			type="button"
			class="btn btn-quiet theme-toggle"
			title={themeLabel}
			aria-label={themeLabel}
			onclick={cycleTheme}
		>
			<Icon name={theme === 'light' ? 'sun' : theme === 'dark' ? 'moon' : 'auto'} />
		</button>

		<button
			type="button"
			class="btn btn-quiet app-bar__help"
			title="Keyboard shortcuts (?)"
			aria-label="Keyboard shortcuts"
			aria-haspopup="dialog"
			aria-expanded={shortcutsOpen}
			onclick={(e) => {
				e.stopPropagation();
				openShortcuts();
			}}
		>
			<Icon name="question" />
		</button>

		<div class="menu-wrap">
			<button
				type="button"
				class="btn btn-primary"
				bind:this={exportBtnEl}
				aria-haspopup="true"
				aria-expanded={openMenu === 'export'}
				onclick={(e) => {
					e.stopPropagation();
					toggleMenu('export');
				}}
			>
				Export
			</button>
			<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_noninteractive_element_interactions -->
			<ul
				class="menu"
				bind:this={exportMenuEl}
				hidden
				onmousedown={(e) => {
					if ((e.target as HTMLElement).closest('button')) e.preventDefault();
				}}
				onclick={() => closeMenus()}
			>
				<li>
					<button type="button" onclick={() => onExport('md')}
						><Icon name="download" />Markdown (.md)</button
					>
				</li>
				<li>
					<button type="button" onclick={() => onExport('html')}
						><Icon name="globe" />Standalone HTML</button
					>
				</li>
				<li>
					<button type="button" onclick={() => onExport('print')}
						><Icon name="print" />Print / save as PDF…</button
					>
				</li>
				<li class="menu-note">
					The HTML export carries its own styles and needs nothing else to open.
				</li>
			</ul>
		</div>

		<input
			type="file"
			bind:this={fileInput}
			accept=".md,.markdown,.txt,text/markdown,text/plain"
			hidden
			onchange={(event) => {
				const input = event.currentTarget;
				const file = input.files?.[0];
				if (file) openFile(file);
				input.value = '';
			}}
		/>
	</header>

	<WelcomeStrip
		bind:visible={welcomeVisible}
		onOpenShortcuts={openShortcuts}
		onDismiss={dismissWelcome}
	/>

	<FindBar
		bind:open={findOpen}
		bind:query={findQuery}
		matchCount={findMatchesList.length}
		activeIndex={findIndex}
		focusToken={findFocusToken}
		onQueryChange={updateFindMatches}
		onNext={findNext}
		onPrev={findPrev}
		onClose={closeFind}
	/>

	<!-- Floating format bar: never steals selection (pointerdown preventDefault). -->
	<!-- svelte-ignore a11y_interactive_supports_focus a11y_click_events_have_key_events a11y_no_static_element_interactions -->
	<div
		class="toolbar"
		bind:this={toolbarEl}
		role="toolbar"
		aria-label="Formatting"
		aria-controls="editor"
		tabindex="-1"
		onmousedown={onToolbarPointer}
		onpointerdown={onToolbarPointer}
		onclick={onToolbarClick}
	>
		<div class="menu-wrap">
			<button
				type="button"
				class="tool tool--style"
				id="styleBtn"
				bind:this={styleBtnEl}
				aria-haspopup="true"
				aria-expanded={openMenu === 'style'}
				title={styleName}
				aria-label={'Paragraph style: ' + styleName}
				onclick={(e) => {
					e.stopPropagation();
					toggleMenu('style');
				}}
			>
				<span>{styleToken}</span>
				<Icon name="chevron-down" size={13} />
			</button>
			<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
			<ul
				class="menu menu-style"
				bind:this={styleMenuEl}
				hidden
				onmousedown={(e) => {
					if ((e.target as HTMLElement).closest('button')) e.preventDefault();
				}}
			>
				{#each STYLES as style (style.kind)}
					<li>
						<button
							type="button"
							onclick={() => {
								command('style', style.kind);
								closeMenus();
							}}
						>
							<span class="tick">{activeBlock === style.kind ? '✓' : ''}</span>
							<span class="style-token">{style.token}</span>
							<span class={style.menu}>{style.label}</span>
							<span class="hint">{style.hint}</span>
						</button>
					</li>
				{/each}
			</ul>
		</div>

		<span class="tool-sep"></span>

		<button
			type="button"
			class="tool"
			data-mark="bold"
			aria-pressed={marks.bold}
			title="Bold (⌘B)"
			aria-label="Bold"
		>
			<Icon name="bold" />
		</button>
		<button
			type="button"
			class="tool"
			data-mark="italic"
			aria-pressed={marks.italic}
			title="Italic (⌘I)"
			aria-label="Italic"
		>
			<Icon name="italic" />
		</button>
		<button
			type="button"
			class="tool tool--secondary"
			data-mark="strike"
			aria-pressed={marks.strike}
			title="Strikethrough (⌘⇧X)"
			aria-label="Strikethrough"
		>
			<Icon name="strike" />
		</button>
		<button
			type="button"
			class="tool tool--secondary"
			data-mark="code"
			aria-pressed={marks.code}
			title="Code (⌘E)"
			aria-label="Inline code"
		>
			<Icon name="code" />
		</button>
		<button
			type="button"
			class="tool"
			data-action="link"
			aria-pressed={marks.link}
			title="Link (⌘K)"
			aria-label="Link"
		>
			<Icon name="link" />
		</button>

		<span class="tool-sep"></span>

		<button
			type="button"
			class="tool"
			data-block="ul"
			aria-pressed={activeBlock === 'ul'}
			title="Bulleted list"
			aria-label="Bulleted list"
		>
			<Icon name="list" />
		</button>
		<button
			type="button"
			class="tool tool--secondary"
			data-block="ol"
			aria-pressed={activeBlock === 'ol'}
			title="Numbered list"
			aria-label="Numbered list"
		>
			<Icon name="ordered" />
		</button>
		<button
			type="button"
			class="tool tool--secondary"
			data-block="task"
			aria-pressed={activeBlock === 'task'}
			title="Task list"
			aria-label="Task list"
		>
			<Icon name="task" />
		</button>
		<button
			type="button"
			class="tool tool--secondary"
			data-block="quote"
			aria-pressed={activeBlock === 'quote'}
			title="Quote"
			aria-label="Quote"
		>
			<Icon name="quote" />
		</button>
		<button
			type="button"
			class="tool tool--secondary"
			data-insert="codeblock"
			title="Code block"
			aria-label="Code block"
		>
			<Icon name="codeblock" />
		</button>

		<span class="tool-spacer"></span>

		<div class="menu-wrap">
			<button
				type="button"
				class="tool"
				id="moreBtn"
				bind:this={moreBtnEl}
				aria-haspopup="true"
				aria-expanded={openMenu === 'more'}
				title="More formatting"
				aria-label="More formatting"
				onclick={(e) => {
					e.stopPropagation();
					toggleMenu('more', () => {
						inTable = surface() === 'page' && Boolean(currentCell());
					});
				}}
			>
				<Icon name="more" />
			</button>
			<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_noninteractive_element_interactions -->
			<ul
				class="menu menu-more"
				bind:this={moreMenuEl}
				hidden
				onmousedown={(e) => {
					if ((e.target as HTMLElement).closest('button')) e.preventDefault();
				}}
				onclick={onMoreMenuClick}
			>
				<li class="only-narrow">
					<button type="button" data-mark="strike" class:on={marks.strike}
						><Icon name="strike" />Strikethrough<span class="hint">⌘⇧X</span></button
					>
				</li>
				<li class="only-narrow">
					<button type="button" data-mark="code" class:on={marks.code}
						><Icon name="code" />Inline code<span class="hint">⌘E</span></button
					>
				</li>
				<li class="only-narrow">
					<button type="button" data-block="ol" class:on={activeBlock === 'ol'}
						><Icon name="ordered" />Numbered list</button
					>
				</li>
				<li class="only-narrow separator"></li>
				<li>
					<button type="button" data-block="task" class:on={activeBlock === 'task'}
						><Icon name="task" />Task list</button
					>
				</li>
				<li>
					<button type="button" data-block="quote" class:on={activeBlock === 'quote'}
						><Icon name="quote" />Quote</button
					>
				</li>
				<li>
					<button type="button" data-insert="codeblock"
						><Icon name="codeblock" />Code block<span class="hint">```</span></button
					>
				</li>
				<li>
					<button type="button" data-insert="table"><Icon name="table" />Table</button>
				</li>
				<li>
					<button type="button" data-insert="rule"
						><Icon name="rule" />Divider<span class="hint">---</span></button
					>
				</li>
				<li>
					<button type="button" data-insert="image"><Icon name="image" />Image</button>
				</li>
				<li>
					<button type="button" data-action="clear"
						><Icon name="eraser" />Clear formatting</button
					>
				</li>
				{#if inTable}
					<li class="only-table separator"></li>
					<li class="only-table">
						<button type="button" data-table="rowAbove">Insert row above</button>
					</li>
					<li class="only-table">
						<button type="button" data-table="rowBelow"
							>Insert row below<span class="hint">Tab</span></button
						>
					</li>
					<li class="only-table">
						<button type="button" data-table="columnLeft">Insert column left</button>
					</li>
					<li class="only-table">
						<button type="button" data-table="columnRight">Insert column right</button>
					</li>
					<li class="only-table">
						<button type="button" data-table="removeRow">Delete row</button>
					</li>
					<li class="only-table">
						<button type="button" data-table="removeColumn">Delete column</button>
					</li>
					<li class="only-table">
						<button type="button" data-table="removeTable">Delete table</button>
					</li>
				{/if}
			</ul>
		</div>
	</div>

	<main class="workspace">
		<div class="editor-pane">
			<!-- highlight backdrop: mirrors #editor byte-for-byte; the textarea above
			     paints only the caret and the selection tint -->
			<pre class="editor-backdrop" aria-hidden="true" bind:this={backdrop}></pre>
			<textarea
				id="editor"
				bind:this={editor}
				spellcheck="true"
				autocapitalize="sentences"
				autocomplete="off"
				aria-label="Markdown source"
				placeholder="# Start writing&#10;&#10;Markdown on the left, the page on the right."
				onfocus={rememberSource}
				oninput={() => {
					sourceChanged();
					updateCursor();
					updateToolbar();
					rememberSource();
					// Slash menu follows typing in the Markdown surface
					slashMode = 'source';
					queueMicrotask(() => refreshSlashFromEditor());
				}}
				onclick={() => {
					rememberSource();
					updateCursor();
					updateToolbar();
				}}
				onkeyup={() => {
					rememberSource();
					updateCursor();
					updateToolbar();
				}}
				onselect={() => {
					rememberSource();
					updateCursor();
					updateToolbar();
				}}
				onmouseup={rememberSource}
				onkeydown={onEditorKeydown}
				onpaste={onEditorPaste}
				onscroll={onEditorScroll}
			></textarea>
		</div>
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div class="reading-pane" bind:this={readingPane} onmousedown={onReadingPaneMouseDown}>
			<!-- contenteditable sheet: HTML is set via renderDocument() only (never reactive {@html}) -->
			<!-- svelte-ignore a11y_no_noninteractive_element_to_interactive_role -->
			<article
				class="sheet"
				bind:this={sheet}
				contenteditable={view === 'read' ? 'false' : 'true'}
				aria-readonly={view === 'read'}
				spellcheck="true"
				role="textbox"
				aria-multiline="true"
				aria-label="Document"
				data-placeholder="Start writing…"
				onfocus={() => {
					rememberPage();
					updateToolbar();
				}}
				oninput={() => {
					rememberPage();
					pageChanged();
				}}
				onblur={pageChanged}
				onchange={(event) => {
					if ((event.target as HTMLInputElement).type === 'checkbox') pageChanged();
				}}
				onkeyup={() => {
					rememberPage();
					updateToolbar();
				}}
				onmouseup={() => {
					rememberPage();
					updateToolbar();
				}}
				onkeydown={onSheetKeydown}
				onpaste={onSheetPaste}
			></article>
		</div>
	</main>

	<TruthStrip
		report={truthReport}
		open={truthEnabled && truthStripOpen}
		onDismiss={dismissTruthStrip}
		onRestoreBaseline={restoreTruthBaseline}
		onRestoreChange={restoreTruthChangeAt}
		onAcceptBaseline={acceptTruthBaseline}
	/>

	<StatusBar
		wordCount={desk.wordCount}
		charCount={desk.charCount}
		readTime={desk.readTime}
		{cursorPos}
		{truthEnabled}
		{footnotesOn}
		truthStatus={truthReport?.status ?? null}
		truthChangeCount={
			truthEnabled && truthReport && truthReport.status !== 'identical'
				? groupTruthChanges(truthReport.hunks).length
				: 0
		}
		onToggleTruth={toggleTruthMode}
		onOpenShortcuts={openShortcuts}
	/>

	<div class="drop-hint" aria-hidden="true">Drop a Markdown file to open it</div>

	<SlashPalette
		open={slashOpen}
		query={slashQuery}
		items={slashItems}
		bind:activeIndex={slashIndex}
		anchor={slashAnchor}
		onSelect={applySlashCommand}
		onClose={() => closeSlash(slashMode === 'source')}
	/>

	<CommandPalette
		open={paletteOpen}
		items={paletteItems}
		bind:query={paletteQuery}
		bind:activeIndex={paletteIndex}
		onSelect={runPaletteCommand}
		onClose={closePalette}
	/>

	<ShortcutsOverlay bind:open={shortcutsOpen} />
		</div><!-- .desk-main -->
	</div><!-- .desk-body -->
</div>
