<script lang="ts">
	/**
	 * Draft First Screenwriting editor surface.
	 *
	 * The DOM provides the contenteditable surface. Document parsing, pagination,
	 * analysis, prediction, and keyboard policies come from the framework-free
	 * engine package.
	 */
	import { onMount, onDestroy } from 'svelte';
	import { isPrinting, type AnyElementType, type ScreenplayElement, type TitlePageEntry } from '@draftfirst/core';
	import {
		looksLikeCue,
		normalizeElementText,
		parseFountain,
		SCENE_DETECT,
		serialiseFountain,
		TRANSITION_DETECT
	} from '@draftfirst/core/fountain';
	import { parseFdx, writeFdxWithDiagnostics } from '@draftfirst/core/fdx';
	import { finalizeImport, extractPdfPayload, importDocx, importPlainText, writeDocx } from '@draftfirst/core/import';
	import type { ClassifiedLine, ImportResult } from '@draftfirst/core/import';
	import { estimateRuntime, paginate } from '@draftfirst/core/layout';
	import {
		detachStructural,
		emptyEnterOutcome,
		ghostSuffix,
		ghostTabBehavior,
		isSummonNeutralKey,
		newSummonState,
		nextElement,
		nextWord,
		predict,
		reattachStructural,
		resetSummon,
		slashSummons,
		tabCycle,
		type Prediction,
		type StructuralAnchor
	} from '@draftfirst/core/editor';
	import { continuityReport, type ContinuityNote } from '@draftfirst/core/analysis';
	import { SAMPLE_FOUNTAIN } from '$lib/screenplay/sample';
	import { scriptToPdf } from '$lib/screenplay/pdf';
	import { download, downloadBytes } from '$lib/utils/download';

	/* ---- element metadata ------------------------------------------------ */

	type EType = Extract<AnyElementType, 'scene' | 'action' | 'character' | 'dialogue' | 'parenthetical' | 'transition' | 'shot' | 'general' | 'centered'>;

	const LABEL: Record<EType, string> = {
		scene: 'Scene Heading', action: 'Action', character: 'Character',
		dialogue: 'Dialogue', parenthetical: 'Parenthetical', transition: 'Transition',
		shot: 'Shot', general: 'General', centered: 'Centered'
	};
	const TYPE_ORDER: EType[] = ['scene', 'action', 'character', 'parenthetical', 'dialogue', 'transition', 'shot', 'general', 'centered'];

	/** Element types normalized to uppercase by every commit path. */
	const CANONICAL_UPPER: ReadonlySet<string> = new Set(['scene', 'character', 'transition', 'shot']);

	/* Read the legacy autosave key as a non-destructive migration fallback. */
	const STORAGE_KEY = 'screenplay.draft.v1';
	const LEGACY_STORAGE_KEY = 'screenplay.fountain.v1';
	const THEME_KEY = 'screenplay.theme';
	const WELCOMED_KEY = 'screenplay.welcomed';

	/* ---- state ------------------------------------------------------------ */

	let sheet: HTMLElement;
	let titleEntries = $state<TitlePageEntry[]>([]);
	let pageCount = $state(1);
	let runtime = $state('~1 minute');
	let wordCount = $state(0);
	let sceneRows = $state<Array<{ text: string; page: number; idx: number }>>([]);
	let castRows = $state<Array<{ name: string; count: number }>>([]);
	let checkRows = $state<ContinuityNote[]>([]);
	let curType = $state<EType>('action');
	let focusMode = $state(false);
	let showSide = $state(false);
	let sideTab = $state<'scenes' | 'cast' | 'check'>('scenes');
	let helpOn = $state(false);
	let sourceMode = $state(false);
	let sourceText = $state('');
	let theme = $state<'light' | 'dark'>('light');
	let exportMenuOn = $state(false);
	let elementMenuOn = $state(false);
	/** True when the current block carries a "page break before" marker. */
	let curPb = $state(false);
	/** Element menu opened by Enter×3 on empty blocks or by `/`. */
	let summonMenuOn = $state(false);
	let summonIndex = $state(0);
	let summonPos = $state({ top: 0, left: 0 });
	let summonPb = $state(false);
	const summon = newSummonState();
	let titleModalOn = $state(false);
	let tpTitle = $state(''), tpAuthor = $state(''), tpCredit = $state(''), tpContact = $state('');
	let toast = $state<{ type: 'success' | 'caution' | 'info' | 'error'; msg: string } | null>(null);
	/** Sticky ghost dismissal: Esc means "not here" until the caret leaves the element. */
	let ghostDismissedIn: HTMLElement | null = null;
	let welcomeOn = $state(false);
	let welcomeTitle = $state('');
	let predictOn = $state(true);
	let fileInput: HTMLInputElement | undefined = $state(undefined);

	/* ---- import review: what the engine read, and where it needs your eye ---- */
	let importReview = $state<{
		name: string;
		format: string;
		warnings: string[];
		classified: ClassifiedLine[];
	} | null>(null);
	/** Re-derived on every override — the sheet always shows the current read. */
	const reviewResult = $derived(
		importReview ? finalizeImport(importReview.classified, importReview.format, importReview.warnings) : null
	);
	/** True while a file hovers over the window, ready to drop-import. */
	let dropOn = $state(false);

	const scriptTitle = $derived(
		titleEntries.find((e) => e.key.toLowerCase() === 'title')?.values[0] ?? 'Untitled'
	);

	let toastTimer: ReturnType<typeof setTimeout> | null = null;
	function showToast(type: 'success' | 'caution' | 'info' | 'error', msg: string) {
		if (toastTimer) clearTimeout(toastTimer);
		toast = { type, msg };
		toastTimer = setTimeout(() => (toast = null), 3000);
	}
	const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`;

	/* ---- block helpers ---------------------------------------------------- */

	/* ---- model <-> DOM ------------------------------------------------------
	   Structure (notes/sections/page breaks) and per-block metadata (scene
	   numbers, dual dialogue) must survive round trips through the surface. */

	let structuralAnchors: StructuralAnchor[] = [];

	function mkBlock(type: EType, text: string, el?: ScreenplayElement): HTMLElement {
		const d = document.createElement('div');
		d.className = 'b el-' + type;
		if (el?.sceneNumber) d.dataset.sn = el.sceneNumber;
		if (el?.dual) d.dataset.dual = '1';
		if (text) d.textContent = text;
		else d.appendChild(document.createElement('br'));
		return d;
	}
	function blocks(): HTMLElement[] {
		return Array.from(sheet.children).filter((n): n is HTMLElement => n instanceof HTMLElement && n.classList.contains('b'));
	}
	function typeOf(el: HTMLElement): EType {
		for (const t of TYPE_ORDER) if (el.classList.contains('el-' + t)) return t;
		return 'action';
	}
	function setType(el: HTMLElement, t: EType) {
		for (const k of TYPE_ORDER) el.classList.remove('el-' + k);
		el.classList.add('el-' + t);
	}
	function textOf(el: HTMLElement): string {
		/* contenteditable emits non-breaking spaces for some whitespace runs. */
		return (el.textContent ?? '').replace(/\u00A0/g, ' ');
	}
	function isEmpty(el: HTMLElement): boolean {
		return textOf(el).trim() === '';
	}
	function currentBlock(): HTMLElement | null {
		const s = getSelection();
		if (!s || !s.rangeCount) return null;
		let n: Node | null = s.anchorNode;
		if (!n) return null;
		if (n.nodeType === 3) n = n.parentNode;
		if (n === sheet) return blocks()[0] ?? null;
		return n instanceof HTMLElement ? (n.closest('.b') as HTMLElement | null) : null;
	}
	function caretOffset(el: HTMLElement): number {
		const s = getSelection();
		if (!s || !s.rangeCount) return 0;
		const r = s.getRangeAt(0).cloneRange();
		const pre = document.createRange();
		pre.selectNodeContents(el);
		try { pre.setEnd(r.endContainer, r.endOffset); } catch { return 0; }
		return pre.toString().length;
	}
	function setCaret(el: HTMLElement, off: number) {
		const r = document.createRange();
		const s = getSelection();
		if (!s) return;
		const walk = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
		let node: Text | null = null;
		let rem = off;
		let n: Text | null;
		while ((n = walk.nextNode() as Text | null)) {
			if (rem <= n.nodeValue!.length) { node = n; break; }
			rem -= n.nodeValue!.length;
		}
		if (node) r.setStart(node, rem);
		else { r.selectNodeContents(el); r.collapse(false); }
		r.collapse(true);
		s.removeAllRanges();
		s.addRange(r);
		el.scrollIntoView({ block: 'nearest' });
	}
	function focusBlock(el: HTMLElement, atEnd: boolean) {
		setCaret(el, atEnd ? textOf(el).length : 0);
		onCaretMove();
	}
	function tidy(el: HTMLElement) {
		const hasText = textOf(el).length > 0;
		const br = el.querySelector('br');
		if (hasText && br) br.remove();
		if (!hasText && !br) el.appendChild(document.createElement('br'));
	}

	/* ---- bracket normalization ---------------------------------------------
	   Normalize parentheticals and cue extensions only when a block is committed. */

	function isEmptyParen(el: HTMLElement): boolean {
		return typeOf(el) === 'parenthetical' && textOf(el).trim() === '';
	}

	function discardParen(el: HTMLElement) {
		el.textContent = '';
		tidy(el);
		const prev = el.previousElementSibling;
		setType(el, prev && typeOf(prev as HTMLElement) === 'character' ? 'dialogue' : 'action');
	}

	function normalizeBlock(el: HTMLElement): boolean {
		const fixed = normalizeElementText(typeOf(el), textOf(el));
		if (fixed === textOf(el)) return false;
		el.textContent = fixed;
		tidy(el);
		return true;
	}

	/** Promote an uppercase name entered as a parenthetical to a character cue. */
	function promoteMiscastCue(el: HTMLElement) {
		if (typeOf(el) === 'parenthetical' && looksLikeCue(textOf(el))) setType(el, 'character');
	}

	/** Apply the same uppercase convention across all commit paths. */
	function applyCanonicalCase(el: HTMLElement) {
		if (!CANONICAL_UPPER.has(typeOf(el))) return;
		const up = textOf(el).toUpperCase();
		if (up === textOf(el)) return;
		const off = caretOffset(el);
		el.textContent = up;
		tidy(el);
		setCaret(el, Math.min(off, up.length));
	}

	/* ---- model <-> DOM ---------------------------------------------------- */

	/** Page breaks are carried as a block property — "break before" — so the
	   marker can never drift from the paragraph it belongs to. */
	function modelFromDOM(): ScreenplayElement[] {
		const out: ScreenplayElement[] = [];
		for (const b of blocks()) {
			if (b.dataset.pb === '1') out.push({ type: 'pagebreak', text: '' });
			const el: ScreenplayElement = { type: typeOf(b), text: textOf(b) };
			if (b.dataset.sn) el.sceneNumber = b.dataset.sn;
			if (b.dataset.dual === '1') el.dual = true;
			out.push(el);
		}
		return out;
	}

	/** Locate a visible block in the full model, including page-break markers. */
	function modelIndexForBlock(target: HTMLElement): number {
		let modelIndex = 0;
		for (const block of blocks()) {
			if (block.dataset.pb === '1') modelIndex++;
			if (block === target) return modelIndex;
			modelIndex++;
		}
		return modelIndex;
	}

	/** Rebuild the sheet from a printing stream; inline pagebreaks fold onto
	   the block that follows them (a trailing break never appears here — it
	   stays anchored, see loadModel). */
	function appendElements(els: ScreenplayElement[]) {
		let pendingPb = false;
		for (const e of els) {
			if (e.type === 'pagebreak') { pendingPb = true; continue; }
			/* Preserve lyrics as general text until the editor exposes a lyric lane. */
			const t = e.type === 'lyrics' ? 'general' : e.type;
			if (!TYPE_ORDER.includes(t as EType)) continue;
			const b = mkBlock(t as EType, e.text, e);
			if (pendingPb) { b.dataset.pb = '1'; pendingPb = false; }
			sheet.appendChild(b);
		}
	}

	function loadModel(elements: ScreenplayElement[], tp: TitlePageEntry[]) {
		titleEntries = tp;
		sheet.innerHTML = '';
		/* Preserve structural elements separately; page breaks remain block markers. */
		const detached = detachStructural(elements);
		structuralAnchors = detached.anchors.filter(
			(a) => a.item.type !== 'pagebreak' || a.anchorType == null
		);
		const stream = elements.filter((e) => isPrinting(e.type) || e.type === 'pagebreak');
		appendElements(stream.length ? stream : [{ type: 'scene', text: '' }]);
		undoStack.length = 0;
		redoStack.length = 0;
		lastSnap = '';
		refreshSoon(0);
		const first = blocks()[0];
		if (first) focusBlock(first, true);
	}
	function currentScript() {
		return {
			titlePage: titleEntries,
			elements: reattachStructural(modelFromDOM(), structuralAnchors)
		};
	}

	/* ---- undo / redo --------------------------------------------------------
	   Store model snapshots before mutations. Consecutive typing is grouped into
	   one undo entry and snapshots never depend on editable HTML. */

	interface Snap { els: ScreenplayElement[]; idx: number; off: number }
	const undoStack: Snap[] = [];
	const redoStack: Snap[] = [];
	let snapTimer: ReturnType<typeof setTimeout> | null = null;
	let lastSnap = '';
	let typingBurst = false;

	function takeSnap() {
		const els = modelFromDOM();
		const key = JSON.stringify(els);
		if (key === lastSnap) return;
		const b = currentBlock();
		undoStack.push({ els, idx: b ? blocks().indexOf(b) : 0, off: b ? caretOffset(b) : 0 });
		if (undoStack.length > 200) undoStack.shift();
		redoStack.length = 0;
		lastSnap = key;
	}
	/** Fires before any DOM mutation (typing, paste, drop, deletion). */
	function onBeforeInput() {
		if (!typingBurst) { takeSnap(); typingBurst = true; }
	}
	/** A burst ends after a short silence; the next keystroke snapshots anew. */
	function snapSoon() {
		if (snapTimer) clearTimeout(snapTimer);
		snapTimer = setTimeout(() => { typingBurst = false; }, 800);
	}
	function restoreSnap(s: Snap) {
		sheet.innerHTML = '';
		appendElements(s.els);
		lastSnap = JSON.stringify(modelFromDOM());
		const bs = blocks();
		const el = bs[Math.min(s.idx, bs.length - 1)];
		if (el) {
			setCaret(el, Math.min(s.off, textOf(el).length));
			onCaretMove();
		}
		refreshSoon(0);
	}
	function undo() {
		if (snapTimer) { clearTimeout(snapTimer); snapTimer = null; }
		typingBurst = false;
		const prev = undoStack.pop();
		if (!prev) return;
		const b = currentBlock();
		redoStack.push({ els: modelFromDOM(), idx: b ? blocks().indexOf(b) : 0, off: b ? caretOffset(b) : 0 });
		restoreSnap(prev);
	}
	function redo() {
		const next = redoStack.pop();
		if (!next) return;
		typingBurst = false;
		const b = currentBlock();
		undoStack.push({ els: modelFromDOM(), idx: b ? blocks().indexOf(b) : 0, off: b ? caretOffset(b) : 0 });
		restoreSnap(next);
	}

	/* ---- typing rules ----------------------------------------------------- */

	function onKeydown(e: KeyboardEvent) {
		const el = currentBlock();
		if (!el) return;
		/* The open element menu handles navigation keys and dismisses on other input. */
		if (summonMenuOn && summonMenuKey(e)) return;
		if (e.key !== 'Enter' && !isSummonNeutralKey(e.key)) resetSummon(summon);
		if (e.key.length > 1 && !isSummonNeutralKey(e.key)) typingBurst = false;
		/* Capture key-driven edits here; `beforeinput` covers paste, drop, and IME. */
		if (e.key.length === 1 && !(e.metaKey || e.ctrlKey) && !typingBurst) {
			takeSnap();
			typingBurst = true;
		}
		if (ghostKey(e)) return;

		const mod = e.metaKey || e.ctrlKey;

		if (mod && e.key.toLowerCase() === 'z') {
			e.preventDefault();
			if (e.shiftKey) redo(); else undo();
			return;
		}
		if (mod && e.key >= '1' && e.key <= '9') {
			const t = TYPE_ORDER[+e.key - 1];
			if (t) {
				e.preventDefault();
				takeSnap();
				setType(el, t);
				syncAfterEdit();
			}
			return;
		}
		if (mod && e.key.toLowerCase() === 's') {
			e.preventDefault();
			saveDraft();
			return;
		}

		if (e.key === 'Tab') {
			e.preventDefault();
			takeSnap();
			/* At line end, Tab commits and advances. Within text or on an empty block,
			   Tab cycles through element types allowed by the preceding block. */
			const tabText = textOf(el);
			const tabAtEnd = caretOffset(el) === tabText.length;
			if (!e.shiftKey && tabText.trim() !== '' && tabAtEnd) {
				promoteMiscastCue(el);
				if (normalizeBlock(el)) setCaret(el, textOf(el).length);
				applyCanonicalCase(el);
				const follower = nextElement(typeOf(el), 'enter', textOf(el)) as EType;
				const next = el.nextElementSibling as HTMLElement | null;
				if (next && next.classList.contains('b')) focusBlock(next, true);
				else { const nb = mkBlock(follower, ''); el.after(nb); focusBlock(nb, false); }
				syncAfterEdit();
				return;
			}
			/* The page-break marker belongs before a real block; that block remains
			   the grammatical predecessor and must never be skipped. */
			let prevEl = el.previousElementSibling as HTMLElement | null;
			while (prevEl && !prevEl.classList.contains('b'))
				prevEl = prevEl.previousElementSibling as HTMLElement | null;
			const t = tabCycle(typeOf(el), prevEl ? typeOf(prevEl) : null, e.shiftKey) as EType;
			setType(el, t);
			syncAfterEdit();
			return;
		}

		if (e.key === 'Enter') {
			e.preventDefault();
			if (e.shiftKey) {
				resetSummon(summon);
				takeSnap();
				handleEnter(el, true);
				return;
			}
			/* The third consecutive Enter on empty blocks opens the element menu. */
			if (emptyEnterOutcome(summon, isEmpty(el)) === 'menu') {
				openSummonMenu();
				return;
			}
			takeSnap();
			handleEnter(el, false);
			return;
		}

		if (e.key === '/' && !mod && slashSummons(textOf(el))) {
			e.preventDefault();
			resetSummon(summon);
			openSummonMenu();
			return;
		}

		if (e.key === 'Backspace') {
			const off = caretOffset(el);
			const s = getSelection();
			if (off === 0 && s?.isCollapsed) {
				/* a page break before this block lifts first — Backspace never
				   swallows a break invisibly into a merge */
				if (el.dataset.pb === '1') {
					e.preventDefault();
					takeSnap();
					delete el.dataset.pb;
					curPb = false;
					syncAfterEdit();
					return;
				}
				const t = typeOf(el);
				if (isEmpty(el) && t !== 'action') {
					e.preventDefault();
					takeSnap();
					setType(el, 'action');
					syncAfterEdit();
					return;
				}
				const prev = el.previousElementSibling as HTMLElement | null;
				if (!prev) { e.preventDefault(); return; }
				e.preventDefault();
				takeSnap();
				const at = textOf(prev).length;
				prev.textContent = textOf(prev) + textOf(el);
				tidy(prev);
				el.remove();
				focusBlock(prev, false);
				setCaret(prev, at);
				syncAfterEdit();
			}
		}
	}

	function handleEnter(el: HTMLElement, shift: boolean) {
		if (shift) {
			/* ⇧Enter is a same-type sibling line — the model's honest "line break".
			   One element per line keeps the native round trip exact; a same-type
			   block stacks with no gap, so it reads as one continuous passage.
			   (The deprecated execCommand('insertLineBreak') path was also a lie:
			   tidy() removed the <br> on the next keystroke.) */
			const nb = mkBlock(typeOf(el), '');
			el.after(nb);
			focusBlock(nb, false);
			syncAfterEdit();
			return;
		}

		/* Do not create a second block from an empty parenthetical. */
		if (isEmptyParen(el)) {
			discardParen(el);
			focusBlock(el, true);
			syncAfterEdit();
			return;
		}

		promoteMiscastCue(el);

		/* Enter is a commit gesture: supply the brackets the writer meant —
		   only safe when the caret is at line end */
		if (caretOffset(el) === textOf(el).length && normalizeBlock(el)) {
			setCaret(el, textOf(el).length);
		}

		/* Read text and caret position after normalization. */
		const off = caretOffset(el);
		const text = textOf(el);
		const t = typeOf(el);

		if (text.trim() === '' && t !== 'action') {
			setType(el, 'action');
			syncAfterEdit();
			return;
		}

		const head = text.slice(0, off);
		const tail = text.slice(off);

		let finalType = t;
		if ((t === 'action' || t === 'general') && SCENE_DETECT.test(head)) finalType = 'scene';
		else if ((t === 'action' || t === 'general') && TRANSITION_DETECT.test(head.trim())) finalType = 'transition';
		if (finalType !== t) setType(el, finalType);

		let finalHead = head;
		if (CANONICAL_UPPER.has(finalType)) finalHead = head.toUpperCase();
		el.textContent = finalHead;
		tidy(el);

		let nt = nextElement(finalType, 'enter', finalHead) as EType;
		if (finalType === 'character' && tail.startsWith('(')) nt = 'parenthetical';

		const nb = mkBlock(nt, tail);
		el.after(nb);
		focusBlock(nb, false);
		syncAfterEdit();
	}

	function onInput() {
		const el = currentBlock();
		if (el) {
			tidy(el);
			if (typeOf(el) === 'action' && SCENE_DETECT.test(textOf(el))) {
				const off = caretOffset(el);
				setType(el, 'scene');
				setCaret(el, off);
			}
		}
		Array.from(sheet.childNodes).forEach((n) => {
			if (n.nodeType === 3 && (n.nodeValue ?? '').trim()) {
				sheet.replaceChild(mkBlock('action', n.nodeValue ?? ''), n);
			} else if (n instanceof HTMLElement && !n.classList.contains('b')) {
				sheet.replaceChild(mkBlock('action', n.textContent ?? ''), n);
			}
		});
		if (!sheet.children.length) sheet.appendChild(mkBlock('scene', ''));
		snapSoon();
		syncAfterEdit();
	}

	/* Paste is classified by the Fountain parser itself: a pasted cue lands as
	   a cue, a transition as a transition — never as prose that merely looks
	   like one. A paste landing on an EMPTY line hands the whole clipboard to
	   the parser; a paste into written text merges the first line at the caret
	   and parses the remainder. Nothing in the clipboard is ever dropped:
	   title keys re-emerge as plain lines (a fragment is not a document),
	   notes/sections anchor into the structural store, page breaks fold onto
	   the block that follows them, lyrics keep their words as general text. */

	/** Insert a parsed fragment after `afterEl`; returns the last block inserted
	   (or `afterEl` itself when the fragment held nothing printable). */
	function insertFragment(src: string, afterEl: HTMLElement): HTMLElement {
		const parsed = parseFountain(src);
		const frag: ScreenplayElement[] = [
			...parsed.titlePage.map((tp) => ({
				type: 'action' as const,
				text: tp.key + ':' + (tp.values.length ? ' ' + tp.values.join(' ') : '')
			})),
			...parsed.elements
		];
		let anchor = afterEl;
		let pendingPb = false;
		let pendingStructural: ScreenplayElement[] = [];
		const anchorStructuralTo = (b: HTMLElement) => {
			for (const item of pendingStructural)
				structuralAnchors.push({ item, anchorType: typeOf(b), anchorText: textOf(b) });
			pendingStructural = [];
		};
		for (const fe of frag) {
			if (fe.type === 'pagebreak') { pendingPb = true; continue; }
			if (!isPrinting(fe.type)) { pendingStructural.push(fe); continue; }
			/* lyrics keep their words on the page (no lyric lane yet) */
			const ft = fe.type === 'lyrics' ? 'general' : fe.type;
			if (!TYPE_ORDER.includes(ft as EType)) continue;
			const b = mkBlock(ft as EType, fe.text, fe);
			if (pendingPb) { b.dataset.pb = '1'; pendingPb = false; }
			anchor.after(b);
			anchor = b;
			anchorStructuralTo(b);
		}
		/* structure with nothing printable after it anchors loose — the export
		   pass appends it to the document rather than dropping it */
		for (const item of pendingStructural)
			structuralAnchors.push({ item, anchorType: null, anchorText: null });
		return anchor;
	}

	function onPaste(e: ClipboardEvent) {
		e.preventDefault();
		takeSnap();
		const txt = (e.clipboardData ?? (window as unknown as { clipboardData: DataTransfer }).clipboardData).getData('text/plain');
		const el = currentBlock();
		if (!el) return;
		const lines = txt.split(/\r?\n/);
		const off = caretOffset(el);
		const full = textOf(el);
		const whole = lines.length > 1 && full.trim() === '';
		if (!whole) {
			el.textContent = full.slice(0, off) + lines[0];
			tidy(el);
			/* a pasted slugline earns its heading immediately, as typing would */
			if (typeOf(el) === 'action' && SCENE_DETECT.test(textOf(el))) setType(el, 'scene');
		}
		const anchor = whole ? insertFragment(txt, el) : insertFragment(lines.slice(1).join('\n'), el);
		if (whole) {
			if (anchor !== el) el.remove();
		} else if (lines.length > 1) {
			anchor.textContent = textOf(anchor) + full.slice(off);
			tidy(anchor);
		}
		focusBlock(anchor, true);
		syncAfterEdit();
	}

	function onCaretMove() {
		const el = currentBlock();
		if (!el) return;
		if (el !== ghostDismissedIn) ghostDismissedIn = null;
		curType = typeOf(el);
		curPb = el.dataset.pb === '1';
		sheet.querySelectorAll('.b.here').forEach((n) => n.classList.remove('here'));
		el.classList.add('here');
		scheduleGhost();
	}

	function chooseElement(t: EType) {
		const el = currentBlock();
		elementMenuOn = false;
		if (!el) return;
		takeSnap();
		setType(el, t);
		sheet.focus();
		syncAfterEdit();
	}

	/* ---- the summon menu ------------------------------------------------------
	   "Show me my options": summoned by Enter×3 on empty lines, or `/` on an
	   empty line for those who know. It interprets a gesture — it can never
	   manufacture, move, or delete content on its own. */

	type SummonChoice = EType | 'pagebreak';
	const SUMMON_ITEMS: SummonChoice[] = [...TYPE_ORDER, 'pagebreak'];

	function openSummonMenu() {
		const el = currentBlock();
		if (!el) return;
		dismissGhost();
		summonPb = el.dataset.pb === '1';
		summonIndex = TYPE_ORDER.indexOf(typeOf(el));
		/* anchored at the block's own left edge, just beneath the line */
		let top = el.offsetTop + el.offsetHeight + 6;
		const left = Math.max(8, el.offsetLeft);
		/* near the page's foot the card opens upward instead of overflowing */
		const estHeight = SUMMON_ITEMS.length * 34 + 20;
		if (top + estHeight > sheet.scrollHeight) top = Math.max(8, el.offsetTop - estHeight - 6);
		summonPos = { top, left };
		summonMenuOn = true;
	}

	function applySummon(choice: SummonChoice) {
		const el = currentBlock();
		summonMenuOn = false;
		elementMenuOn = false;
		if (!el) return;
		takeSnap();
		if (choice === 'pagebreak') {
			/* "break before" is a property of the block — choose again to lift it */
			if (el.dataset.pb === '1') delete el.dataset.pb;
			else el.dataset.pb = '1';
			curPb = el.dataset.pb === '1';
		} else {
			setType(el, choice);
		}
		sheet.focus();
		syncAfterEdit();
	}

	/** While summoned, the menu owns ↑↓/Enter/Esc; anything else closes it and
	   falls through so a changed mind can simply keep typing. */
	function summonMenuKey(e: KeyboardEvent): boolean {
		if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
			e.preventDefault();
			const d = e.key === 'ArrowDown' ? 1 : -1;
			summonIndex = (summonIndex + d + SUMMON_ITEMS.length) % SUMMON_ITEMS.length;
			return true;
		}
		if (e.key === 'Enter') {
			e.preventDefault();
			applySummon(SUMMON_ITEMS[summonIndex]);
			return true;
		}
		if (e.key === 'Escape') {
			e.preventDefault();
			summonMenuOn = false;
			return true;
		}
		summonMenuOn = false;
		return false;
	}

	/* ---- pagination + sidebar (ALL numbers from the paginator core) ------- */

	let refreshTimer: ReturnType<typeof setTimeout> | null = null;
	function syncAfterEdit() {
		onCaretMove();
		refreshSoon(140);
		scheduleGhost();
	}
	function refreshSoon(ms: number) {
		if (refreshTimer) clearTimeout(refreshTimer);
		refreshTimer = setTimeout(doRefresh, ms);
	}

	function doRefresh() {
		/* paginate the PRINTING stream — DOM block indices must align with
		   model indices, so structure (reattached at export) stays out here.
		   Page breaks are the one exception: they ride the model as elements
		   but live on the page as block markers, so indices past one drift.
		   The maps below translate between the two coordinate systems. */
		const printable = modelFromDOM();
		const script = { titlePage: titleEntries, elements: printable };
		const pages = paginate(script);
		pageCount = pages.length;
		runtime = estimateRuntime(pages);

		const m2b = new Map<number, number>(); /* model index → block index */
		const b2m = new Map<number, number>(); /* block index → model index */
		{
			let bi = 0;
			printable.forEach((e, mi) => {
				if (e.type === 'pagebreak') return;
				m2b.set(mi, bi);
				b2m.set(bi, mi);
				bi++;
			});
		}

		const pageOf = new Map<number, number>();
		const breakAt = new Map<number, number>();
		for (const p of pages) {
			for (const l of p.lines) {
				if (l.element >= 0 && !pageOf.has(l.element)) pageOf.set(l.element, p.number);
			}
			if (p.number > 1) {
				const first = p.lines.find((l) => l.element >= 0);
				if (first) breakAt.set(first.element, p.number);
			}
		}

		const bs = blocks();
		bs.forEach((b, i) => {
			const pg = breakAt.get(b2m.get(i) ?? i);
			b.classList.toggle('pgb', pg !== undefined && i > 0);
			if (pg !== undefined && i > 0) b.dataset.page = String(pg);
			else delete b.dataset.page;
			delete b.dataset.contd;
			delete b.dataset.contdb;
		});

		/* scene-continued markers: (CONTINUED) in the bottom margin of the page
		   that ends mid-scene, CONTINUED: atop the page that opens mid-scene.
		   Rendered as CSS pseudo-elements on the boundary blocks — no extra DOM,
		   so nothing can ever leak into the document model. */
		for (const p of pages) {
			if (p.continuedBottom) {
				for (let i = p.lines.length - 1; i >= 0; i--) {
					const bi2 = m2b.get(p.lines[i].element);
					if (bi2 !== undefined && bs[bi2]) { bs[bi2].dataset.contdb = '1'; break; }
				}
			}
			if (p.continuedTop) {
				const first = p.lines.find((l) => l.element >= 0);
				const bi2 = first ? m2b.get(first.element) : undefined;
				if (bi2 !== undefined && bs[bi2]) bs[bi2].dataset.contd = '1';
			}
		}

		wordCount = script.elements.reduce(
			(a, e) => a + (e.text.trim() ? e.text.trim().split(/\s+/).length : 0), 0
		);
		sceneRows = script.elements
			.map((e, idx) => ({ e, idx }))
			.filter(({ e }) => e.type === 'scene' && e.text.trim() !== '')
			.map(({ e, idx }) => ({ text: e.text, page: pageOf.get(idx) ?? 1, idx: m2b.get(idx) ?? idx }));

		const counts = new Map<string, number>();
		for (const e of script.elements) {
			if (e.type === 'character' && e.text.trim()) {
				const name = e.text.trim().toUpperCase().replace(/\s*\(.*\)$/, '');
				counts.set(name, (counts.get(name) ?? 0) + 1);
			}
		}
		castRows = [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([name, count]) => ({ name, count }));

		checkRows = continuityReport(script);

		autosave(script);
	}

	function jumpToScene(idx: number) {
		const b = blocks()[idx];
		if (!b) return;
		b.scrollIntoView({ behavior: 'smooth', block: 'center' });
		focusBlock(b, true);
		sheet.focus();
	}

	/* Prediction text continues the current line without mutating the document. */

	interface GhostState {
		suffix: string;
		items: Prediction[];
		index: number;
		blockText: string;
		top: number;
		takeOver: boolean;
		type: string;
		hint: boolean;
	}
	let ghost = $state<GhostState | null>(null);

	/* Right-aligned suggestions render the complete line so acceptance does not
	   change its alignment. */
	let ghostedEl: HTMLElement | null = null;
	function unmarkGhosted() {
		ghostedEl?.classList.remove('ghosted');
		ghostedEl = null;
	}

	function dismissGhost() {
		if (ghost) ghost = null;
		unmarkGhosted();
	}

	let ghostTimer: ReturnType<typeof setTimeout> | null = null;
	function scheduleGhost() {
		if (ghostTimer) clearTimeout(ghostTimer);
		ghostTimer = setTimeout(computeGhost, 70);
	}

	const PREDICTABLE = new Set(['character', 'scene', 'transition', 'parenthetical', 'shot', 'action']);

	function computeGhost() {
		if (!predictOn) return dismissGhost();
		const el = currentBlock();
		if (!el) return dismissGhost();
		/* a dismissed suggestion stays dismissed until the caret leaves */
		if (el === ghostDismissedIn) return dismissGhost();
		const t = typeOf(el);
		if (!PREDICTABLE.has(t)) return dismissGhost();
		const text = textOf(el);
		/* prediction continues a line — it never edits mid-line */
		if (caretOffset(el) !== text.length) return dismissGhost();

		const items = predict(
			{ titlePage: [], elements: modelFromDOM() },
			{ type: t, text, index: modelIndexForBlock(el) }
		);
		if (items.length === 0) return dismissGhost();

		const index = ghost && ghost.items.map((p) => p.text).join('') === items.map((p) => p.text).join('') ? Math.min(ghost.index, items.length - 1) : 0;
		const suffix = ghostSuffix(items[index].text, text, !!items[index].hint);
		if (suffix === '') return dismissGhost();

		const takeOver = t === 'transition';
		ghost = { suffix, items, index, blockText: text, top: ghostTop(el), takeOver, type: t, hint: !!items[index].hint };
		unmarkGhosted();
		if (takeOver) {
			ghostedEl = el;
			el.classList.add('ghosted');
		}
	}

	/* offsetTop lands on the border box; a page-break block's text starts one
	   line lower (its padding-top), so the ghost must step down with it */
	function ghostTop(el: HTMLElement): number {
		const LINE = (96 * 9) / 55;
		return el.offsetTop + (el.classList.contains('pgb') ? LINE : 0);
	}

	function cycleGhost(dir: number) {
		if (!ghost) return;
		const index = (ghost.index + dir + ghost.items.length) % ghost.items.length;
		const suffix = ghostSuffix(ghost.items[index].text, ghost.blockText, !!ghost.items[index].hint);
		ghost = { ...ghost, index, suffix, hint: !!ghost.items[index].hint };
	}

	function acceptGhost() {
		const el = currentBlock();
		if (!el || !ghost) return;
		takeSnap();
		const cand = ghost.items[ghost.index];
		let value = ghost.blockText + ghost.suffix;
		/* accepting a slugline prediction in an action line promotes the element */
		if (cand.becomes) setType(el, cand.becomes as EType);
		/* canonical case follows the element the text will BE — and only the
		   uppercase-convention elements; prose is never SHOUTED */
		if (CANONICAL_UPPER.has(cand.becomes ?? ghost.type)) value = value.toUpperCase();
		el.textContent = value;
		tidy(el);
		setCaret(el, value.length);
		dismissGhost();
		syncAfterEdit();
	}

	/** Partial accept (Copilot's ⌘→): take just the next word of the whisper. */
	function acceptGhostWord() {
		const el = currentBlock();
		if (!el || !ghost) return;
		takeSnap();
		const cand = ghost.items[ghost.index];
		let value = ghost.blockText + nextWord(ghost.suffix);
		if (cand.becomes) setType(el, cand.becomes as EType);
		if (CANONICAL_UPPER.has(cand.becomes ?? ghost.type)) value = value.toUpperCase();
		el.textContent = value;
		tidy(el);
		setCaret(el, value.length);
		dismissGhost();
		syncAfterEdit();
	}

	/** Ghost owns these keys while visible; returns true when consumed. */
	function ghostKey(e: KeyboardEvent): boolean {
		if (!ghost) return false;
		if ((e.metaKey || e.ctrlKey) && e.key === 'ArrowRight') {
			e.preventDefault();
			if (ghost.hint) dismissGhost();
			else acceptGhostWord();
			return true;
		}
		if (e.altKey && (e.key === ']' || e.key === '[')) {
			e.preventDefault();
			cycleGhost(e.key === ']' ? 1 : -1);
			return true;
		}
		if (e.key === 'Tab' || e.key === 'ArrowRight') {
			/* on an empty line, Tab belongs to the choreography, not the ghost */
			if (e.key === 'Tab' && ghostTabBehavior(ghost.blockText) === 'jump') {
				dismissGhost();
				return false;
			}
			e.preventDefault();
			/* a shape hint is never committed — it teaches, then steps aside */
			if (ghost.hint) dismissGhost();
			else acceptGhost();
			return true;
		}
		if (e.key === 'ArrowDown') {
			e.preventDefault();
			cycleGhost(1);
			return true;
		}
		if (e.key === 'ArrowUp') {
			e.preventDefault();
			cycleGhost(-1);
			return true;
		}
		if (e.key === 'Escape') {
			e.preventDefault();
			/* Esc means "not here" — and it has to stick, or the next keystroke
			   brings the same rejected suggestion straight back. It lifts when
			   the caret leaves this element (see onCaretMove). */
			const holder = currentBlock();
			if (holder) ghostDismissedIn = holder;
			dismissGhost();
			return true;
		}
		return false;
	}

	/* ---- files ------------------------------------------------------------ */

	function baseName() {
		return scriptTitle.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'screenplay';
	}
	/* .draft — our native format. Plain Fountain text under our own name:
	   openable by any editor on earth, today and in thirty years. ⌘S. */
	function saveDraft() {
		exportMenuOn = false;
		download(serialiseFountain(currentScript()), baseName() + '.draft', 'text/plain');
		showToast('success', 'Saved ' + baseName() + '.draft');
	}
	function exportFdx() {
		exportMenuOn = false;
		const result = writeFdxWithDiagnostics(currentScript());
		download(result.xml, baseName() + '.fdx', 'text/xml');
		showToast(
			result.diagnostics.length > 0 ? 'caution' : 'success',
			result.diagnostics.length > 0
				? `Exported ${baseName()}.fdx — ${result.diagnostics.length} compatibility note${result.diagnostics.length === 1 ? '' : 's'}`
				: `Exported ${baseName()}.fdx`
		);
	}
	function exportFountain() {
		exportMenuOn = false;
		download(serialiseFountain(currentScript()), baseName() + '.fountain', 'text/plain');
		showToast('success', 'Exported ' + baseName() + '.fountain');
	}
	function exportTxt() {
		exportMenuOn = false;
		const pages = paginate(currentScript());
		const out = pages
			.map((p) => {
				const lines = p.lines.map((l) => ' '.repeat(l.indent) + l.text);
				if (p.continuedTop) lines.unshift('CONTINUED:');
				if (p.continuedBottom) lines.push(' '.repeat(49) + '(CONTINUED)');
				return lines.join('\n');
			})
			.join('\n\f\n');
		download(out + '\n', baseName() + '.txt', 'text/plain');
		showToast('success', 'Exported ' + baseName() + '.txt');
	}
	function exportPdf() {
		exportMenuOn = false;
		downloadBytes(scriptToPdf(currentScript()), baseName() + '.pdf', 'application/pdf');
		showToast('success', 'Exported ' + baseName() + '.pdf');
	}
	function exportDocx() {
		exportMenuOn = false;
		downloadBytes(
			writeDocx(currentScript()),
			baseName() + '.docx',
			'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
		);
		showToast('success', 'Exported ' + baseName() + '.docx');
	}
	function importFile(e: Event) {
		const input = e.target as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (file) void importFileObject(file);
	}
	/**
	 * One pipeline for every path a file can arrive by — the open button or a
	 * drop anywhere on the window. Exact formats (.fdx, .fountain, .draft)
	 * commit straight away; inferred formats (.docx, .txt) pass through the
	 * import review whenever the engine has anything to confess.
	 */
	async function importFileObject(file: File) {
		try {
			if (/\.fdx$/i.test(file.name) || /\.xml$/i.test(file.name)) {
				const res = parseFdx(await file.text());
				loadModel(res.script.elements, res.script.titlePage);
				showToast(
					res.warnings.length ? 'caution' : 'success',
					res.warnings.length
						? `Opened ${file.name} — ${res.warnings.length} note${res.warnings.length === 1 ? '' : 's'}, best effort`
						: 'Opened ' + file.name
				);
			} else if (/\.docx$/i.test(file.name)) {
				offerImportReview(file.name, await importDocx(new Uint8Array(await file.arrayBuffer())));
			} else if (/\.txt$/i.test(file.name)) {
				offerImportReview(file.name, importPlainText(await file.text()));
			} else if (/\.pdf$/i.test(file.name)) {
				/* a PDF we exported carries its own source home; a foreign one gets
				   a kind refusal — parsing arbitrary PDFs is a road we do not travel */
				const fountain = extractPdfPayload(new Uint8Array(await file.arrayBuffer()));
				if (fountain === null) {
					showToast('caution', `${file.name} carries no Draft First source — try .fdx, .docx, or .txt instead`);
					return;
				}
				const script = parseFountain(fountain);
				loadModel(script.elements, script.titlePage);
				showToast('success', `Recovered ${file.name} — its source was embedded at export`);
			} else {
				const script = parseFountain(await file.text());
				loadModel(script.elements, script.titlePage);
				showToast('success', 'Opened ' + file.name);
			}
		} catch (err) {
			showToast('error', 'Import failed: ' + (err instanceof Error ? err.message : String(err)));
		}
	}
	function offerImportReview(name: string, result: ImportResult) {
		/* The editor has no lyric lane — present lyrics as the general text they
		   become on the page, so the review never shows a type it cannot hold. */
		for (const line of result.classified) {
			if ((line.type as string) === 'lyrics') {
				line.type = 'general';
				line.why += ' — lyrics print as general text here';
			}
		}
		/* nothing to weigh — the engine read every line cleanly */
		if (result.report.flagged.length === 0 && result.report.warnings.length === 0) {
			loadModel(result.script.elements, result.script.titlePage);
			showToast('success', 'Opened ' + name);
			return;
		}
		importReview = {
			name,
			format: result.report.format,
			warnings: result.report.warnings,
			classified: result.classified
		};
	}
	function overrideImportLine(lineIndex: number, type: EType) {
		const line = importReview?.classified[lineIndex];
		if (!line) return;
		line.type = type;
		line.confidence = 'high';
		line.why = 'you chose this';
	}
	function commitImportReview() {
		if (!importReview || !reviewResult) return;
		loadModel(reviewResult.script.elements, reviewResult.script.titlePage);
		showToast(
			'success',
			`Opened ${importReview.name} — ${plural(reviewResult.report.lines, 'line')}, ${plural(reviewResult.report.scenes, 'scene')}`
		);
		importReview = null;
	}
	function onDropFile(e: DragEvent) {
		e.preventDefault();
		dropOn = false;
		const file = e.dataTransfer?.files?.[0];
		if (file) void importFileObject(file);
	}
	function newScript() {
		if (!confirm('Start a new screenplay? Export first if you want to keep this one.')) return;
		loadModel([{ type: 'scene', text: '' }], []);
		sheet.focus();
	}

	/* ---- title page modal --------------------------------------------------- */

	function openTitleModal() {
		const get = (k: string) => titleEntries.find((e) => e.key.toLowerCase() === k)?.values.join('\n') ?? '';
		tpTitle = get('title');
		tpCredit = get('credit') || 'written by';
		tpAuthor = get('author');
		tpContact = get('contact');
		titleModalOn = true;
	}
	function saveTitleModal() {
		const entries: TitlePageEntry[] = [];
		if (tpTitle.trim()) entries.push({ key: 'Title', values: [tpTitle.trim()] });
		if (tpCredit.trim()) entries.push({ key: 'Credit', values: [tpCredit.trim()] });
		if (tpAuthor.trim()) entries.push({ key: 'Author', values: [tpAuthor.trim()] });
		if (tpContact.trim()) entries.push({ key: 'Contact', values: [tpContact.trim()] });
		titleEntries = entries;
		titleModalOn = false;
		refreshSoon(0);
		showToast('success', 'Title page saved');
	}

	/* ---- source view -------------------------------------------------------- */

	function openSource() {
		sourceText = serialiseFountain(currentScript());
		sourceMode = true;
	}
	function closeSource() {
		const script = parseFountain(sourceText);
		loadModel(script.elements, script.titlePage);
		sourceMode = false;
	}

	/* ---- theme -------------------------------------------------------------- */

	function toggleTheme() {
		theme = theme === 'light' ? 'dark' : 'light';
		try { localStorage.setItem(THEME_KEY, theme); } catch { /* ignore */ }
	}

	/* ---- autosave + boot ---------------------------------------------------- */

	let saveTimer: ReturnType<typeof setTimeout> | null = null;
	function autosave(script: ReturnType<typeof currentScript>) {
		if (saveTimer) clearTimeout(saveTimer);
		saveTimer = setTimeout(() => {
			try { localStorage.setItem(STORAGE_KEY, serialiseFountain(script)); } catch { /* keep typing */ }
		}, 800);
	}

	/** The last 800ms of writing must survive a closed tab or a route change.
	   Fires on beforeunload and on component destroy — never lose their work. */
	function flushSave() {
		if (!sheet) return;
		if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; }
		try { localStorage.setItem(STORAGE_KEY, serialiseFountain(currentScript())); } catch { /* leaving anyway */ }
	}

	onDestroy(() => {
		flushSave();
		for (const t of [toastTimer, snapTimer, refreshTimer, ghostTimer, saveTimer]) if (t) clearTimeout(t);
	});

	function onWindowDown(e: MouseEvent) {
		const t = e.target as HTMLElement;
		if (!t.closest('.menu-pop') && !t.closest('[data-menu-trigger]')) {
			exportMenuOn = false;
			elementMenuOn = false;
			summonMenuOn = false;
		}
	}

	function onGlobalKey(e: KeyboardEvent) {
		const t = e.target as HTMLElement | null;
		const typing = !!t?.closest('[contenteditable="true"], input, textarea, select');
		/* ⌘S belongs to the draft from anywhere — the page handles its own
		   keystroke; this catches modals, the drawer, and the source view */
		if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's' && !t?.closest('.sppage')) {
			e.preventDefault();
			/* In the source view the textarea IS the document — commit it before
			   saving, or ⌘S would download the stale pre-edit model. */
			if (sourceMode) {
				try {
					const script = parseFountain(sourceText);
					loadModel(script.elements, script.titlePage);
				} catch (err) {
					showToast('error', 'Source could not be parsed: ' + (err instanceof Error ? err.message : String(err)));
					return;
				}
			}
			saveDraft();
			return;
		}
		if (e.key === '?' && !typing) {
			e.preventDefault();
			helpOn = !helpOn;
			return;
		}
		if (e.key === 'Escape') {
			if (importReview) importReview = null;
			else if (helpOn) helpOn = false;
			else if (titleModalOn) titleModalOn = false;
			else if (sourceMode) closeSource();
			else {
				exportMenuOn = false;
				elementMenuOn = false;
			}
		}
	}

	function togglePredict() {
		predictOn = !predictOn;
		try { localStorage.setItem('screenplay.predict', predictOn ? '1' : '0'); } catch { /* ignore */ }
		if (!predictOn) dismissGhost();
		showToast('info', predictOn ? 'Prediction on — suggestions appear as you write' : 'Prediction off');
	}

	onMount(() => {
		try {
			const storedTheme = localStorage.getItem(THEME_KEY);
			if (storedTheme === 'dark' || storedTheme === 'light') theme = storedTheme;
			else if (window.matchMedia?.('(prefers-color-scheme: dark)').matches) theme = 'dark';
			if (localStorage.getItem('screenplay.predict') === '0') predictOn = false;
		} catch { /* default light */ }
		let boot: string | null = null;
		let welcomed = false;
		try {
			boot = localStorage.getItem(STORAGE_KEY) ?? localStorage.getItem(LEGACY_STORAGE_KEY);
			welcomed = localStorage.getItem(WELCOMED_KEY) === '1';
		} catch { boot = null; }
		const script = parseFountain(boot ?? SAMPLE_FOUNTAIN);
		loadModel(script.elements, script.titlePage);
		/* first visit: a centered moment of intent, not a sample dump */
		if (!boot && !welcomed) {
			welcomeOn = true;
		} else {
			try {
				if (new URLSearchParams(window.location.search).has('help')) helpOn = true;
			} catch { /* ignore */ }
			sheet.focus();
		}
	});

	function beginFresh() {
		const entries: TitlePageEntry[] = [];
		if (welcomeTitle.trim()) {
			entries.push({ key: 'Title', values: [welcomeTitle.trim().toUpperCase()] });
			entries.push({ key: 'Credit', values: ['written by'] });
		}
		try { localStorage.setItem(WELCOMED_KEY, '1'); } catch { /* ignore */ }
		welcomeOn = false;
		loadModel([{ type: 'scene', text: '' }, { type: 'action', text: '' }], entries);
		sheet.focus();
	}
	function exploreSample() {
		try { localStorage.setItem(WELCOMED_KEY, '1'); } catch { /* ignore */ }
		welcomeOn = false;
		const script = parseFountain(SAMPLE_FOUNTAIN);
		loadModel(script.elements, script.titlePage);
		sheet.focus();
	}
</script>

<svelte:window
	onmousedown={onWindowDown}
	onkeydown={onGlobalKey}
	onbeforeunload={flushSave}
	ondragover={(e) => {
		if (e.dataTransfer?.types.includes('Files')) e.preventDefault();
	}}
	ondragenter={(e) => {
		if (e.dataTransfer?.types.includes('Files')) dropOn = true;
	}}
	ondragleave={(e) => {
		if (e.relatedTarget === null) dropOn = false;
	}}
	ondrop={onDropFile}
/>

<div class="stage" class:dark={theme === 'dark'}>
	<!-- floating chrome: always present, never receding -->
	<header class="chrome">
		<div class="pill">
			<span class="doctitle">{scriptTitle}</span>
			<span class="vsep"></span>

			<button type="button" class="iconbtn" data-tip="New screenplay" aria-label="New screenplay" onclick={newScript}>
				<svg viewBox="0 0 16 16"><path d="M8 3v10M3 8h10"/></svg>
			</button>
			<button type="button" class="iconbtn" data-tip="Open .draft / .fdx / .docx / .txt" aria-label="Open file" onclick={() => fileInput?.click()}>
				<svg viewBox="0 0 16 16"><path d="M2 5.5A1.5 1.5 0 0 1 3.5 4h3l1.5 2h4.5A1.5 1.5 0 0 1 14 7.5v4A1.5 1.5 0 0 1 12.5 13h-9A1.5 1.5 0 0 1 2 11.5v-6z"/></svg>
			</button>

			<span class="menu-anchor">
				<button type="button" class="iconbtn" class:on={exportMenuOn} data-menu-trigger data-tip="Save / export" aria-label="Save or export" onclick={() => { exportMenuOn = !exportMenuOn; elementMenuOn = false; }}>
					<svg viewBox="0 0 16 16"><path d="M8 2v8m0 0L5 7m3 3 3-3M3 12.5h10"/></svg>
				</button>
				{#if exportMenuOn}
					<div class="menu-pop" role="menu">
						<button type="button" role="menuitem" onclick={saveDraft}><span>Save draft</span><span class="trail">⌘S .draft</span></button>
						<button type="button" role="menuitem" onclick={exportPdf}><span>PDF document</span><span class="trail">.pdf</span></button>
						<button type="button" role="menuitem" onclick={exportDocx}><span>Word document</span><span class="trail">.docx</span></button>
						<button type="button" role="menuitem" onclick={exportFdx}><span>Final Draft</span><span class="trail">.fdx</span></button>
						<button type="button" role="menuitem" onclick={exportFountain}><span>Fountain</span><span class="trail">.fountain</span></button>
						<button type="button" role="menuitem" onclick={exportTxt}><span>Plain text</span><span class="trail">.txt</span></button>
						<button type="button" role="menuitem" onclick={() => { exportMenuOn = false; window.print(); }}><span>Print</span><span class="trail">⌘P</span></button>
					</div>
				{/if}
			</span>

			<span class="vsep"></span>

			<button type="button" class="iconbtn" data-tip="Title page" aria-label="Title page" onclick={openTitleModal}>
				<svg viewBox="0 0 16 16"><path d="M4 2.5h8A1.5 1.5 0 0 1 13.5 4v8a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 12V4A1.5 1.5 0 0 1 4 2.5zM5.5 5.5h5M5.5 8h5M5.5 10.5h3"/></svg>
			</button>
			<button type="button" class="iconbtn" data-tip="Fountain source" aria-label="Fountain source" onclick={openSource}>
				<svg viewBox="0 0 16 16"><path d="M5.5 4.5 2 8l3.5 3.5M10.5 4.5 14 8l-3.5 3.5"/></svg>
			</button>
			<button type="button" class="iconbtn" class:on={focusMode} data-tip="Focus mode" aria-label="Focus mode" onclick={() => (focusMode = !focusMode)}>
				<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="3.2"/><path d="M8 1.8v1.6M8 12.6v1.6M1.8 8h1.6M12.6 8h1.6"/></svg>
			</button>
			<button type="button" class="iconbtn" class:on={showSide} data-tip="Scenes panel" aria-label="Scenes panel" onclick={() => (showSide = !showSide)}>
				<svg viewBox="0 0 16 16"><rect x="2" y="2.5" width="12" height="11" rx="1.5"/><path d="M6.2 2.5v11"/></svg>
			</button>
			<button type="button" class="iconbtn" data-tip="Keyboard shortcuts (?)" aria-label="Keyboard shortcuts" onclick={() => (helpOn = !helpOn)}>
				<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.2"/><path d="M6.2 6.2c0-1 .8-1.8 1.8-1.8s1.8.8 1.8 1.8c0 1.2-1.8 1.4-1.8 2.6M8 11.4v.1"/></svg>
			</button>
			<button type="button" class="iconbtn" data-tip={theme === 'dark' ? 'Light mode' : 'Dark mode'} aria-label="Toggle theme" onclick={toggleTheme}>
				{#if theme === 'dark'}
					<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="3"/><path d="M8 1.5v1.4M8 13.1v1.4M1.5 8h1.4M13.1 8h1.4M3.4 3.4l1 1M11.6 11.6l1 1M12.6 3.4l-1 1M4.4 11.6l-1 1"/></svg>
				{:else}
					<svg viewBox="0 0 16 16"><path d="M13.5 9.5A5.5 5.5 0 0 1 6.5 2.5a5.5 5.5 0 1 0 7 7z"/></svg>
				{/if}
			</button>
			<input bind:this={fileInput} type="file" accept=".draft,.fdx,.xml,.fountain,.txt,.docx,.pdf" onchange={importFile} hidden />
		</div>
	</header>

	<div class="main">
		<!-- drawer: scenes / cast / keys -->
		<aside class="drawer" class:closed={!showSide} aria-hidden={!showSide}>
			<div class="seg" role="radiogroup" aria-label="Panel view">
				{#each ['scenes', 'cast', 'check'] as tab (tab)}
					<button type="button" role="radio" aria-checked={sideTab === tab} class:sel={sideTab === tab}
						onclick={() => (sideTab = tab as typeof sideTab)}>{tab[0].toUpperCase() + tab.slice(1)}{#if tab === 'check' && checkRows.length > 0}<span class="cbadge">{checkRows.length}</span>{/if}</button>
				{/each}
			</div>
			<div class="sidebody">
				{#if sideTab === 'scenes'}
					{#if sceneRows.length === 0}
						<div class="empty">Scene headings appear here.<br />Start a line with <b>INT.</b> or <b>EXT.</b></div>
					{:else}
						{#each sceneRows as row, i (row.idx)}
							<button type="button" class="row" onclick={() => jumpToScene(row.idx)}>
								<span class="num">{i + 1}</span><span class="txt">{row.text}</span><span class="pg">{row.page}</span>
							</button>
						{/each}
					{/if}
				{:else if sideTab === 'cast'}
					{#if castRows.length === 0}
						<div class="empty">Characters appear here as you write dialogue.</div>
					{:else}
						{#each castRows as row (row.name)}
							<div class="row static"><span class="txt">{row.name}</span><span class="pg">{row.count}</span></div>
						{/each}
					{/if}
				{:else}
					{#if checkRows.length === 0}
						<div class="empty">Nothing inconsistent found.<br /><br />This is the pass a script coordinator makes: names and locations spelled one way throughout, sequences you opened closed again, every heading carrying a time of day.</div>
					{:else}
						{#each checkRows as note, i (i)}
							<div class="cnote">
								<div class="ck">{note.kind}</div>
								<div class="cd">{note.detail}</div>
								<div class="cw">{note.why}</div>
							</div>
						{/each}
					{/if}
				{/if}
			</div>
		</aside>

		<!-- the page -->
		<div class="scroll">
			<div class="page-wrap">
				<div
					bind:this={sheet}
					class="sppage"
					class:focusmode={focusMode}
					contenteditable="true"
					spellcheck="true"
					role="textbox"
					aria-multiline="true"
					aria-label="Screenplay page editor"
					tabindex="0"
					onkeydown={onKeydown}
					oninput={onInput}
					onbeforeinput={onBeforeInput}
					onpaste={onPaste}
					onkeyup={(e) => { if (e.key.startsWith('Arrow')) onCaretMove(); }}
					onclick={() => { resetSummon(summon); typingBurst = false; onCaretMove(); }}
					onblur={() => setTimeout(dismissGhost, 120)}
				></div>
				{#if ghost}
					<div class="ghost-layer" aria-hidden="true">
						<div class="gline el-{ghost.type}" class:hint={ghost.hint} class:takeover={ghost.takeOver} style:top="{ghost.top}px">{#if ghost.takeOver && ghost.items.length > 1}<span class="gmore">+{ghost.items.length - 1}</span>{/if}<span class="gpref">{ghost.blockText}</span><span class="gsuf">{ghost.suffix}</span>{#if !ghost.takeOver && ghost.items.length > 1}<span class="gmore">+{ghost.items.length - 1}</span>{/if}
						</div>
					</div>
				{/if}
				{#if summonMenuOn}
					<!-- the "show me my options" card — anchored to the block, never part of the document -->
					<div
						class="menu-pop summon"
						role="menu"
						aria-label="Choose element"
						tabindex="-1"
						style:top="{summonPos.top}px"
						style:left="{summonPos.left}px"
						onmousedown={(e) => e.preventDefault()}
					>
						{#each TYPE_ORDER as t, i (t)}
							<button type="button" role="menuitem" class:sel={i === summonIndex} onclick={() => applySummon(t)}>
								<span>{LABEL[t]}</span>
								<span class="trail">⌘{i + 1}</span>
							</button>
						{/each}
						<div class="menu-sep"></div>
						<button
							type="button"
							role="menuitemcheckbox"
							aria-checked={summonPb}
							class:sel={summonIndex === TYPE_ORDER.length}
							onclick={() => applySummon('pagebreak')}
						>
							<span>Page Break</span>
							<span class="trail">{summonPb ? '✓' : ''}</span>
						</button>
					</div>
				{/if}
			</div>
		</div>
	</div>

	<!-- status pill: always present -->
	<footer class="statuspill">
		<span class="menu-anchor">
			<button type="button" class="etype" data-menu-trigger onclick={() => { elementMenuOn = !elementMenuOn; exportMenuOn = false; }}>
				{LABEL[curType]}
				<svg viewBox="0 0 16 16" class="chev"><path d="M4 6.5 8 10.5 12 6.5"/></svg>
			</button>
			{#if elementMenuOn}
				<div class="menu-pop up" role="menu">
					{#each TYPE_ORDER as t, i (t)}
						<button type="button" role="menuitem" class:sel={t === curType} onclick={() => chooseElement(t)}>
							<span>{LABEL[t]}</span>
							<span class="trail">{i < 9 ? '⌘' + (i + 1) : ''}</span>
						</button>
					{/each}
					<div class="menu-sep"></div>
					<button type="button" role="menuitemcheckbox" aria-checked={curPb} onclick={() => applySummon('pagebreak')}>
						<span>Page Break</span>
						<span class="trail">{curPb ? '✓' : ''}</span>
					</button>
					<button type="button" role="menuitemcheckbox" aria-checked={predictOn} onclick={togglePredict}>
						<span>Prediction</span>
						<span class="trail">{predictOn ? '✓' : ''}</span>
					</button>
				</div>
			{/if}
		</span>
		<span class="sep-dot"></span>
		<span><b>{pageCount}</b> {pageCount === 1 ? 'page' : 'pages'}</span>
		<span class="sep-dot"></span>
		<span>{runtime}</span>
		<span class="sep-dot"></span>
		<span><b>{wordCount.toLocaleString()}</b> words</span>
		{#if ghost}
			<span class="sep-dot"></span>
			<span class="gwhy">{ghost.items[ghost.index].why}</span>
		{/if}
	</footer>

	<!-- toast -->
	{#if toast}
		<div class="toast" role={toast.type === 'error' ? 'alert' : 'status'}>
			{#if toast.type === 'success'}<svg viewBox="0 0 16 16" class="ticon ok"><path d="M3 8.5 6.5 12 13 4.5"/></svg>
			{:else if toast.type === 'caution'}<svg viewBox="0 0 16 16" class="ticon warn"><path d="M8 2.5 14.5 13h-13L8 2.5zM8 6.5v3.2M8 11.4v.1"/></svg>
			{:else if toast.type === 'info'}<svg viewBox="0 0 16 16" class="ticon inf"><circle cx="8" cy="8" r="6.2"/><path d="M8 7.4v3.4M8 4.6v.1"/></svg>
			{:else if toast.type === 'error'}<svg viewBox="0 0 16 16" class="ticon err"><circle cx="8" cy="8" r="6"/><path d="M5.5 5.5l5 5M10.5 5.5l-5 5"/></svg>
			{/if}
			<span>{toast.msg}</span>
		</div>
	{/if}

	<!-- Fountain source modal -->
	{#if sourceMode}
		<div class="overlay" role="dialog" aria-modal="true" aria-label="Fountain source">
			<div class="modal-card source-card">
				<div class="modal-head">
					<span class="modal-title">Fountain source</span>
					<span class="modal-sub">The honest file underneath — edits re-parse when you return</span>
					<button type="button" class="iconbtn" aria-label="Close" onclick={closeSource}>
						<svg viewBox="0 0 16 16"><path d="M4 4l8 8M12 4l-8 8"/></svg>
					</button>
				</div>
				<textarea bind:value={sourceText} spellcheck="false" aria-label="Fountain source"></textarea>
				<div class="modal-foot">
					<button type="button" class="spbtn secondary" onclick={closeSource}>Back to the page</button>
					<button type="button" class="spbtn primary" onclick={closeSource}>Done</button>
				</div>
			</div>
		</div>
	{/if}

	<!-- first run: a centered moment of intent -->
	{#if welcomeOn}
		<div class="overlay welcome" role="dialog" aria-modal="true" aria-labelledby="welcome-heading">
			<div class="welcome-inner">
				<h1 class="welcome-title" id="welcome-heading">Name your screenplay</h1>
				<input
					class="welcome-input"
					bind:value={welcomeTitle}
					placeholder="UNTITLED"
					aria-label="Screenplay title"
					onkeydown={(e) => { if (e.key === 'Enter') beginFresh(); }}
				/>
				<div class="welcome-actions">
					<button type="button" class="spbtn primary" onclick={beginFresh}>Begin writing</button>
					<button type="button" class="welcome-link" onclick={exploreSample}>or explore a sample script</button>
				</div>
			</div>
		</div>
	{/if}

	<!-- keyboard shortcuts overlay — '?' like Writing Desk -->
	{#if helpOn}
		<div class="overlay" role="dialog" aria-modal="true" aria-labelledby="keys-heading" tabindex="-1">
			<div class="modal-card keys-card">
				<div class="modal-head">
					<span class="modal-title" id="keys-heading">Keyboard shortcuts</span>
					<button type="button" class="iconbtn" aria-label="Close" onclick={() => (helpOn = false)}>
						<svg viewBox="0 0 16 16"><path d="M4 4l8 8M12 4l-8 8"/></svg>
					</button>
				</div>
				<div class="keys-grid">
					<h4>Writing</h4>
					<div class="krow"><span><kbd>Tab</kbd></span><span>at line end: commit &amp; move on · inside text / empty: change element</span></div>
					<div class="krow"><span><kbd>⌘ →</kbd></span><span>accept next word of suggestion</span></div>
					<div class="krow"><span><kbd>⌥ ]</kbd> <kbd>⌥ [</kbd></span><span>cycle suggestions</span></div>
					<div class="krow"><span><kbd>⇧ Tab</kbd></span><span>cycle elements back</span></div>
					<div class="krow"><span><kbd>Enter</kbd></span><span>next logical element</span></div>
					<div class="krow"><span><kbd>⇧ Enter</kbd></span><span>new line, same element</span></div>
					<div class="krow"><span><kbd>⌫</kbd></span><span>at line start: lift page break, else back to Action</span></div>
					<div class="krow"><span><kbd>/</kbd></span><span>on empty line: element menu</span></div>
					<div class="krow"><span><kbd>Enter</kbd> <kbd>Enter</kbd> <kbd>Enter</kbd></span><span>on empty lines: element menu</span></div>
					<h4>Set element directly</h4>
					<div class="krow"><span><kbd>⌘1</kbd></span><span>Scene Heading</span></div>
					<div class="krow"><span><kbd>⌘2</kbd></span><span>Action</span></div>
					<div class="krow"><span><kbd>⌘3</kbd></span><span>Character</span></div>
					<div class="krow"><span><kbd>⌘4</kbd></span><span>Parenthetical</span></div>
					<div class="krow"><span><kbd>⌘5</kbd></span><span>Dialogue</span></div>
					<div class="krow"><span><kbd>⌘6</kbd></span><span>Transition</span></div>
					<div class="krow"><span><kbd>⌘7</kbd></span><span>Shot</span></div>
					<div class="krow"><span><kbd>⌘8</kbd></span><span>General</span></div>
					<div class="krow"><span><kbd>⌘9</kbd></span><span>Centered</span></div>
					<h4>App</h4>
					<div class="krow"><span><kbd>⌘S</kbd></span><span>save .draft</span></div>
					<div class="krow"><span><kbd>⌘Z</kbd> <kbd>⇧⌘Z</kbd></span><span>undo / redo</span></div>
					<div class="krow"><span><kbd>?</kbd></span><span>this overlay</span></div>
					<div class="krow"><span><kbd>Esc</kbd></span><span>close menus & overlays</span></div>
					<h4>Automatic</h4>
					<p class="keys-note">Typing <b>INT.</b> or <b>EXT.</b> promotes the line to a Scene Heading. The prediction engine suggests likely dialogue partners, document locations, and extensions such as (V.O.); accept a suggestion or keep typing. Page breaks come from the pagination engine rather than screen pixels. To force one, choose <b>Page Break</b> in the element menu.</p>
					<p class="keys-note">Drop a <b>.docx</b>, <b>.txt</b>, <b>.fdx</b>, or <b>.fountain</b> file anywhere on the window to import it. Word and plain-text files pass through an import review first — the engine shows exactly which lines it was unsure about, and you can correct them before anything joins your draft. A <b>.pdf</b> exported here carries its own source: drop it back in to recover the script exactly as you left it.</p>
				</div>
			</div>
		</div>
	{/if}

	<!-- title page modal -->
	{#if titleModalOn}
		<div class="overlay" role="dialog" aria-modal="true" aria-labelledby="tp-heading">
			<div class="modal-card">
				<div class="modal-head">
					<span class="modal-title" id="tp-heading">Title page</span>
					<button type="button" class="iconbtn" aria-label="Close" onclick={() => (titleModalOn = false)}>
						<svg viewBox="0 0 16 16"><path d="M4 4l8 8M12 4l-8 8"/></svg>
					</button>
				</div>
				<div class="form">
					<label>Title<input bind:value={tpTitle} placeholder="THE EMPTY CINEMA" /></label>
					<label>Credit<input bind:value={tpCredit} placeholder="written by" /></label>
					<label>Author<input bind:value={tpAuthor} placeholder="Your name" /></label>
					<label>Contact<input bind:value={tpContact} placeholder="email / phone" /></label>
				</div>
				<div class="modal-foot">
					<button type="button" class="spbtn secondary" onclick={() => (titleModalOn = false)}>Cancel</button>
					<button type="button" class="spbtn primary" onclick={saveTitleModal}>Save</button>
				</div>
			</div>
		</div>
	{/if}

	<!-- import review: the engine shows its read before anything joins the draft -->
	{#if importReview && reviewResult}
		<div class="overlay" role="dialog" aria-modal="true" aria-labelledby="ir-heading">
			<div class="modal-card review-card">
				<div class="modal-head">
					<span class="modal-title" id="ir-heading">Import review</span>
					<span class="modal-sub">
						{importReview.name} · {plural(reviewResult.report.lines, 'line')} · {plural(reviewResult.report.scenes, 'scene')} · {plural(reviewResult.report.characters.length, 'character')}
					</span>
					<button type="button" class="iconbtn" aria-label="Close" onclick={() => (importReview = null)}>
						<svg viewBox="0 0 16 16"><path d="M4 4l8 8M12 4l-8 8"/></svg>
					</button>
				</div>
				{#if reviewResult.report.warnings.length > 0}
					<div class="review-notes">
						{#each reviewResult.report.warnings as warning (warning)}
							<div class="review-note">{warning}</div>
						{/each}
					</div>
				{/if}
				{#if reviewResult.report.flagged.length > 0}
					<div class="review-flaghead">Needs your eye — {reviewResult.report.flagged.length}</div>
					<div class="review-list">
						{#each reviewResult.report.flagged as flag (flag.lineIndex)}
							<div class="review-row">
								<div class="review-text">{flag.text}</div>
								<div class="review-meta">
									<select
										class="review-type"
										value={flag.type}
										aria-label="Element type for this line"
										onchange={(e) => overrideImportLine(flag.lineIndex, (e.target as HTMLSelectElement).value as EType)}
									>
										{#each TYPE_ORDER as t (t)}
											<option value={t}>{LABEL[t]}</option>
										{/each}
									</select>
									<span class="review-why">{flag.why}</span>
								</div>
							</div>
						{/each}
					</div>
				{:else}
					<div class="review-clear">Every line reads cleanly — nothing left to weigh.</div>
				{/if}
				<div class="modal-foot">
					<button type="button" class="spbtn secondary" onclick={() => (importReview = null)}>Leave it</button>
					<button type="button" class="spbtn primary" onclick={commitImportReview}>Bring it in</button>
				</div>
			</div>
		</div>
	{/if}

	<!-- drop a file anywhere: one calm veil, no chrome -->
	{#if dropOn}
		<div class="dropveil" aria-hidden="true">
			<span>Drop it — we will read it with care</span>
		</div>
	{/if}
</div>

<style>
	/* ---- design tokens ---------------------------------------------------- */
	.stage {
		--bg: #f0f1f3;
		--panel: rgba(255, 255, 255, 0.9);
		--panel-solid: #ffffff;
		--menu-bg: #ffffff;
		--ink: rgba(0, 0, 0, 0.9);
		--ink-2: rgba(0, 0, 0, 0.6);
		--ink-3: rgba(0, 0, 0, 0.45);
		--ink-4: rgba(0, 0, 0, 0.3);
		--f1: rgba(0, 0, 0, 0.03);
		--f2: rgba(0, 0, 0, 0.05);
		--f3: rgba(0, 0, 0, 0.15);
		--sep: rgba(0, 0, 0, 0.13);
		--accent: #1783ff;
		--green: #16c456;
		--orange: #ff9500;
		--danger: #ff3849;
		--mask: rgba(0, 0, 0, 0.4);
		--toast-bg: #2b2b2b;
		--paper: #ffffff;
		--paper-ink: #141414;
		--paper-edge: rgba(0, 0, 0, 0.05);
		--shadow-pill: 0 1px 2px rgba(16, 24, 32, 0.06), 0 8px 28px rgba(16, 24, 32, 0.1);
		--shadow-sheet: 0 1px 2px rgba(16, 24, 32, 0.05), 0 20px 56px rgba(16, 24, 32, 0.14);
		--ease-out: cubic-bezier(0.23, 1, 0.32, 1);
		--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1);

		display: flex;
		flex-direction: column;
		height: 100vh;
		background: var(--bg);
		color: var(--ink);
		font-family: -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Segoe UI', Roboto, sans-serif;
		font-size: 14px;
		line-height: 20px;
		overflow: hidden;
	}
	.stage.dark {
		--bg: #131313;
		--panel: rgba(18, 18, 18, 0.9);
		--panel-solid: #121212;
		--menu-bg: #292929;
		--ink: rgba(255, 255, 255, 0.84);
		--ink-2: rgba(255, 255, 255, 0.56);
		--ink-3: rgba(255, 255, 255, 0.42);
		--ink-4: rgba(255, 255, 255, 0.26);
		--f1: rgba(255, 255, 255, 0.05);
		--f2: rgba(255, 255, 255, 0.1);
		--f3: rgba(255, 255, 255, 0.18);
		--sep: rgba(255, 255, 255, 0.12);
		--accent: #1a88ff;
		--mask: rgba(0, 0, 0, 0.6);
		--toast-bg: #404040;
		--paper: #2a2a29;
		--paper-ink: rgba(255, 255, 255, 0.85);
		--paper-edge: rgba(255, 255, 255, 0.09);
		--shadow-pill: 0 1px 2px rgba(0, 0, 0, 0.4), 0 8px 28px rgba(0, 0, 0, 0.45);
		--shadow-sheet: 0 1px 2px rgba(0, 0, 0, 0.5), 0 20px 60px rgba(0, 0, 0, 0.6);
	}

	/* ---- floating chrome -------------------------------------------------- */
	.chrome {
		position: absolute;
		top: 12px;
		left: 0;
		right: 0;
		display: flex;
		justify-content: center;
		z-index: 500;
		pointer-events: none;
	}
	.pill {
		pointer-events: auto;
		display: flex;
		align-items: center;
		gap: 2px;
		padding: 5px 8px;
		background: var(--panel);
		backdrop-filter: blur(20px);
		-webkit-backdrop-filter: blur(20px);
		border: 0.5px solid var(--sep);
		border-radius: 12px;
		box-shadow: var(--shadow-pill);
	}
	.doctitle {
		font-size: 13px;
		font-weight: 500;
		color: var(--ink-2);
		max-width: 180px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.vsep { width: 0.5px; height: 18px; background: var(--sep); margin: 0 6px; }

	.iconbtn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 30px;
		height: 30px;
		border: 0;
		border-radius: 8px;
		background: transparent;
		color: var(--ink-2);
		cursor: pointer;
		transition: background-color 150ms ease, color 150ms ease, transform 120ms ease;
	}
	.iconbtn svg { width: 16px; height: 16px; fill: none; stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; }
	.iconbtn:hover { background: var(--f1); color: var(--ink); }
	.iconbtn:active { transform: scale(0.96); }
	.iconbtn.on { background: var(--f2); color: var(--ink); }
	.iconbtn:focus-visible, .spbtn:focus-visible, .etype:focus-visible, .seg button:focus-visible, .menu-pop button:focus-visible {
		outline: none;
		box-shadow: 0 0 0 2px var(--accent);
	}

	/* ---- menus ------------------------------------------------------------ */
	.menu-anchor { position: relative; display: inline-flex; }
	.menu-pop {
		position: absolute;
		top: calc(100% + 6px);
		left: 50%;
		transform: translateX(-50%);
		min-width: 168px;
		max-width: 240px;
		padding: 6px;
		background: var(--menu-bg);
		border: 0.5px solid var(--sep);
		border-radius: 12px;
		box-shadow: var(--shadow-pill);
		z-index: 900;
		display: flex;
		flex-direction: column;
		animation: pop 160ms var(--ease-out);
	}
	.menu-pop.up { top: auto; bottom: calc(100% + 8px); }
	/* the summon card anchors to a page coordinate (inline top/left), not to a
	   trigger button — so the base menu's centering must not apply */
	.menu-pop.summon {
		transform: none;
		min-width: 200px;
		animation: pop-summon 160ms var(--ease-out);
	}
	@keyframes pop-summon {
		from { opacity: 0; transform: translateY(-4px) scale(0.98); }
		to { opacity: 1; transform: none; }
	}
	.menu-pop button {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		height: 34px;
		padding: 0 10px;
		border: 0;
		border-radius: 8px;
		background: transparent;
		color: var(--ink);
		font: inherit;
		font-size: 13px;
		cursor: pointer;
		white-space: nowrap;
	}
	.menu-pop button:hover { background: var(--f1); }
	.menu-pop button.sel { background: var(--f2); }
	.menu-pop .trail { color: var(--ink-3); font-size: 12px; }
	@keyframes pop {
		from { opacity: 0; transform: translateX(-50%) scale(0.96); }
		to { opacity: 1; transform: translateX(-50%) scale(1); }
	}

	/* ---- layout ------------------------------------------------------------ */
	.main { display: flex; flex: 1; min-height: 0; }

	.drawer {
		width: 264px;
		flex: 0 0 264px;
		background: var(--panel-solid);
		border-right: 0.5px solid var(--sep);
		display: flex;
		flex-direction: column;
		min-height: 0;
		transition: margin-left 300ms var(--ease-drawer);
	}
	.drawer.closed { margin-left: -264px; }

	.seg {
		display: flex;
		gap: 4px;
		margin: 12px;
		padding: 2px;
		background: var(--f2);
		border-radius: 10px;
	}
	.seg button {
		flex: 1;
		height: 28px;
		border: 0;
		border-radius: 8px;
		background: transparent;
		color: var(--ink);
		font: inherit;
		font-size: 13px;
		cursor: pointer;
		transition: background-color 150ms ease;
	}
	.seg button.sel { background: var(--panel-solid); box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08); }
	.stage.dark .seg button.sel { background: #4d4d4d; box-shadow: none; }

	.sidebody { flex: 1; overflow: auto; padding: 0 8px 16px; }
	.sidebody .row {
		display: flex;
		gap: 8px;
		align-items: baseline;
		width: 100%;
		text-align: left;
		padding: 7px 8px;
		border: 0;
		border-radius: 8px;
		font-size: 13px;
		background: transparent;
		color: var(--ink);
		cursor: pointer;
		font-family: inherit;
		transition: background-color 150ms ease;
	}
	.sidebody .row:not(.static):hover { background: var(--f1); }
	.sidebody .num { color: var(--ink-3); min-width: 1.6em; font-variant-numeric: tabular-nums; font-size: 12px; }
	.sidebody .txt { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.sidebody .pg { margin-left: auto; color: var(--ink-3); font-size: 12px; }
	.sidebody .empty { color: var(--ink-3); padding: 14px 8px; font-size: 13px; line-height: 1.6; }
	.sidebody .cnote { padding: 10px 8px; border-radius: 8px; }
	.sidebody .cnote:hover { background: var(--f1); }
	.sidebody .cnote + .cnote { border-top: 0.5px solid var(--sep); border-radius: 0; }
	.sidebody .ck { font-size: 13px; font-weight: 600; color: var(--ink); line-height: 1.4; }
	.sidebody .cd { font-size: 12px; color: var(--ink-2); margin-top: 3px; line-height: 1.5; overflow-wrap: anywhere; }
	.sidebody .cw { font-size: 12px; color: var(--ink-3); margin-top: 3px; line-height: 1.5; }
	.cbadge {
		display: inline-block;
		min-width: 15px;
		margin-left: 5px;
		padding: 1px 4px;
		border-radius: 8px;
		background: var(--ink);
		color: var(--panel-solid);
		font-size: 10px;
		font-weight: 600;
		line-height: 1.3;
		text-align: center;
		vertical-align: 1px;
	}
	kbd {
		font: 11px/1 ui-monospace, 'SF Mono', Menlo, monospace;
		border: 0.5px solid var(--sep);
		border-bottom-width: 1.5px;
		border-radius: 4px;
		padding: 2px 5px;
		background: var(--f1);
		color: var(--ink-2);
	}

	.scroll { flex: 1; overflow: auto; padding: 72px 0 30vh; min-width: 0; }

	/* ---- the paper ---------------------------------------------------------
	   Geometry matches the paginator core exactly: Courier 12pt ≈ 16px,
	   9.6px per character, line-height 9in/55 — the engine's 55-line page.
	   Font metrics live on the wrapper so the ghost layer inherits them. */
	.page-wrap {
		position: relative;
		width: 8.5in;
		margin: 0 auto;
		font-family: 'Courier Prime', 'Courier New', Courier, monospace;
		font-size: 16px;
		line-height: calc(9in / 55);
		color: var(--paper-ink);
	}
	.sppage {
		width: 8.5in;
		min-height: 11in;
		margin: 0 auto;
		background: var(--paper);
		color: var(--paper-ink);
		padding: 1in 1in 1in 1.5in;
		border: 0.5px solid var(--paper-edge);
		border-radius: 2px;
		box-shadow: var(--shadow-sheet);
		outline: none;
		transition: box-shadow 200ms ease;
		box-sizing: border-box;
	}
	.sppage.focusmode :global(.b) { opacity: 0.24; transition: opacity 180ms ease; }
	.sppage.focusmode :global(.b.here) { opacity: 1; }

	:global(.b) { width: 6in; min-height: calc(9in / 55); white-space: pre-wrap; overflow-wrap: break-word; margin: 0; outline: none; position: relative; }
	:global(.b.el-scene) { text-transform: uppercase; margin-top: calc((9in / 55) * 2); }
	:global(.b.el-action), :global(.b.el-shot), :global(.b.el-general), :global(.b.el-centered), :global(.b.el-transition) { margin-top: calc(9in / 55); }
	:global(.b.el-character) { text-transform: uppercase; margin-left: 2.2in; width: 3in; margin-top: calc(9in / 55); }
	:global(.b.el-parenthetical) { margin-left: 1.6in; width: 2.2in; }
	:global(.b.el-dialogue) { margin-left: 1in; width: 3.5in; }
	:global(.b.el-transition) { text-transform: uppercase; text-align: right; }
	:global(.b.el-shot) { text-transform: uppercase; }
	:global(.b.el-centered) { text-align: center; }
	:global(.b:first-child) { margin-top: 0; }

	:global(.b.pgb) {
		margin-top: 1in;
		border-top: 0.5px dashed var(--sep);
		padding-top: calc(9in / 55);
		position: relative;
	}
	:global(.b.pgb)::after {
		content: attr(data-page) '.';
		position: absolute;
		right: 0;
		top: -0.7in;
		color: var(--ink-4);
	}
	/* scene continuation: (CONTINUED) hangs in the bottom margin under the page's
	   last line; CONTINUED: sits atop the new page — gray margin annotations,
	   pseudo-elements only, never document text */
	:global(.b.pgb[data-contd])::before {
		content: 'CONTINUED:';
		position: absolute;
		left: 0;
		top: 0.015in;
		font-size: 12px;
		color: var(--ink-4);
	}
	:global(.b[data-contdb])::after {
		content: '(CONTINUED)';
		position: absolute;
		right: 0;
		top: calc(100% + 0.2in);
		font-size: 12px;
		color: var(--ink-4);
		white-space: nowrap;
	}

	/* ---- ghost text ---------------------------------------------------------
	   The prediction, rendered as gray continuation of your line. The prefix
	   span keeps alignment by invisibly mirroring what you already typed. */
	.ghost-layer {
		position: absolute;
		top: 0;
		left: 1.5in;
		width: 6in;
		bottom: 0;
		pointer-events: none;
		overflow: hidden;
	}
	.gline { position: absolute; left: 0; width: 6in; white-space: pre-wrap; overflow-wrap: break-word; }
	/* takeover ghosts (right-aligned elements) render the whole line: the
	   typed part in ink, the whisper in gray — the string ends exactly at
	   the margin, so accepting it moves nothing but the color */
	.gline.takeover .gpref { visibility: visible; }
	:global(.b.ghosted) { color: transparent; caret-color: var(--ink); }
	.gline.el-character { margin-left: 2.2in; width: 3in; text-transform: uppercase; }
	.gline.el-parenthetical { margin-left: 1.6in; width: 2.2in; }
	.gline.el-transition { text-transform: uppercase; text-align: right; }
	.gline.el-scene { text-transform: uppercase; }
	.gpref { visibility: hidden; }
	.gsuf { color: color-mix(in srgb, currentColor 34%, transparent); }
	/* a shape hint teaches the form of the element — one-third the weight,
	   never commitable, never confused with a real suggestion */
	.gline.hint .gsuf { color: color-mix(in srgb, currentColor 16%, transparent); font-style: normal; }
	.gmore {
		color: color-mix(in srgb, currentColor 18%, transparent);
		font-size: 0.78em;
		padding-left: 1.2ch;
		letter-spacing: 0.04em;
	}
	.menu-sep { height: 0.5px; background: var(--sep); margin: 5px 8px; }

	/* ---- shape hints ride the ghost channel ----------------------------------
	   No per-block placeholders anywhere. A hint is a ghost that cannot be
	   committed: same font, same flow, one-third the weight. */

	/* ---- status pill -------------------------------------------------------- */
	.statuspill {
		position: absolute;
		bottom: 14px;
		left: 50%;
		transform: translateX(-50%);
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 7px 14px;
		background: var(--panel);
		backdrop-filter: blur(20px);
		-webkit-backdrop-filter: blur(20px);
		border: 0.5px solid var(--sep);
		border-radius: 12px;
		box-shadow: var(--shadow-pill);
		font-size: 12px;
		color: var(--ink-3);
		z-index: 500;
		white-space: nowrap;
	}
	.statuspill b { color: var(--ink-2); font-weight: 600; }
	.sep-dot { width: 3px; height: 3px; border-radius: 50%; background: var(--ink-4); }
	.etype {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		border: 0;
		background: transparent;
		color: var(--ink);
		font: inherit;
		font-size: 12px;
		font-weight: 600;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		cursor: pointer;
		padding: 2px 4px;
		border-radius: 6px;
	}
	.etype:hover { background: var(--f1); }
	.etype .chev { width: 12px; height: 12px; fill: none; stroke: var(--ink-3); stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; }
	.gwhy { color: var(--ink-3); font-style: italic; max-width: 260px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

	/* ---- toast --------------------------------------------------------------- */
	.toast {
		position: fixed;
		top: 16px;
		left: 50%;
		transform: translateX(-50%);
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 10px 14px;
		background: var(--toast-bg);
		color: #fff;
		border-radius: 12px;
		font-size: 13px;
		z-index: 1000;
		animation: toastin 350ms var(--ease-out);
		max-width: 360px;
	}
	@keyframes toastin {
		from { opacity: 0; transform: translate(-50%, -16px) scale(0.96); }
		to { opacity: 1; transform: translate(-50%, 0) scale(1); }
	}
	.ticon { width: 16px; height: 16px; fill: none; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; flex: 0 0 auto; }
	.ticon.ok { stroke: var(--green); }
	.ticon.warn { stroke: var(--orange); }
	.ticon.err { stroke: var(--danger); }
	.ticon.inf { stroke: var(--accent); }

	/* ---- modals -------------------------------------------------------------- */
	.overlay {
		position: fixed;
		inset: 0;
		background: var(--mask);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 810;
		animation: fadein 180ms var(--ease-out);
	}
	@keyframes fadein { from { opacity: 0; } to { opacity: 1; } }
	.modal-card {
		width: min(420px, calc(100vw - 32px));
		background: var(--menu-bg);
		border-radius: 16px;
		padding: 24px;
		display: flex;
		flex-direction: column;
		gap: 16px;
		animation: modalin 180ms var(--ease-out);
	}
	.source-card { width: min(680px, calc(100vw - 32px)); height: min(560px, calc(100vh - 64px)); }
	@keyframes modalin {
		from { opacity: 0; transform: scale(0.96); }
		to { opacity: 1; transform: scale(1); }
	}
	.modal-head { display: flex; align-items: baseline; gap: 10px; }
	.modal-title { font-size: 16px; font-weight: 500; color: var(--ink); }
	.modal-sub { font-size: 12px; color: var(--ink-3); flex: 1; }
	.modal-head .iconbtn { margin-left: auto; flex: 0 0 auto; }
	.modal-foot { display: flex; justify-content: flex-end; gap: 8px; }

	.spbtn {
		height: 32px;
		padding: 0 14px;
		border: 0;
		border-radius: 10px;
		font: inherit;
		font-size: 14px;
		font-weight: 500;
		cursor: pointer;
		transition: background-color 150ms ease, transform 120ms ease;
	}
	.spbtn:active { transform: scale(0.97); }
	.spbtn.primary { background: var(--ink); color: var(--panel-solid); }
	.stage.dark .spbtn.primary { color: #121212; }
	.spbtn.secondary { background: var(--f1); color: var(--ink); }
	.spbtn.secondary:hover { background: var(--f2); }

	/* ---- import review ---------------------------------------------------- */
	.review-card { width: min(560px, calc(100vw - 32px)); max-height: min(600px, calc(100vh - 64px)); }
	.review-notes { display: flex; flex-direction: column; gap: 6px; }
	.review-note {
		font-size: 12px;
		line-height: 1.45;
		color: var(--ink-2);
		background: var(--f1);
		border-radius: 8px;
		padding: 7px 10px;
	}
	.review-flaghead { font-size: 12px; font-weight: 600; letter-spacing: 0.02em; color: var(--ink-3); }
	.review-list {
		display: flex;
		flex-direction: column;
		gap: 8px;
		overflow-y: auto;
		min-height: 0;
		margin: -4px;
		padding: 4px;
	}
	.review-row {
		background: var(--f1);
		border-radius: 10px;
		padding: 10px 12px;
		display: flex;
		flex-direction: column;
		gap: 7px;
	}
	.review-text {
		font-size: 13px;
		line-height: 1.4;
		color: var(--ink);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.review-meta { display: flex; align-items: center; gap: 8px; }
	.review-type {
		font: inherit;
		font-size: 12px;
		font-weight: 500;
		color: var(--ink);
		background: var(--f2);
		border: 0;
		border-radius: 7px;
		padding: 3px 6px;
		cursor: pointer;
	}
	.review-why { font-size: 11px; line-height: 1.35; color: var(--ink-3); flex: 1; }
	.review-clear { font-size: 13px; color: var(--ink-3); }

	/* ---- drop veil -------------------------------------------------------- */
	.dropveil {
		position: fixed;
		inset: 0;
		z-index: 900;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--mask);
		pointer-events: none;
		animation: fadein 150ms var(--ease-out);
	}
	.dropveil span {
		font-size: 15px;
		font-weight: 500;
		color: #fff;
		background: rgba(20, 20, 20, 0.72);
		border-radius: 12px;
		padding: 12px 20px;
	}

	.form { display: flex; flex-direction: column; gap: 12px; }
	.form label { display: block; font-size: 12px; font-weight: 500; color: var(--ink-3); text-transform: uppercase; letter-spacing: 0.06em; }
	.form input {
		width: 100%;
		margin-top: 4px;
		font: inherit;
		font-size: 14px;
		padding: 8px 10px;
		border: 0.5px solid var(--sep);
		border-radius: 10px;
		background: var(--panel-solid);
		color: var(--ink);
		box-sizing: border-box;
		outline: none;
		transition: box-shadow 150ms ease;
	}
	.form input:focus { box-shadow: 0 0 0 2px var(--accent); border-color: transparent; }

	.source-card textarea {
		flex: 1;
		border: 0.5px solid var(--sep);
		border-radius: 10px;
		outline: none;
		resize: none;
		padding: 14px;
		background: var(--panel-solid);
		color: var(--ink);
		font-family: ui-monospace, 'SF Mono', Menlo, monospace;
		font-size: 13px;
		line-height: 1.6;
		white-space: pre;
	}

	.keys-card { width: min(440px, calc(100vw - 32px)); }
	.keys-grid { display: flex; flex-direction: column; gap: 6px; }
	.keys-grid h4 {
		margin: 10px 0 2px;
		font-size: 11px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--ink-3);
	}
	.keys-grid h4:first-child { margin-top: 0; }
	.krow {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 16px;
		font-size: 13px;
		color: var(--ink);
	}
	.keys-note { margin: 2px 0 0; font-size: 13px; line-height: 1.6; color: var(--ink-3); }

	/* ---- custom tooltips (125ms ease-out, 350ms delay, dark pill) --------- */
	[data-tip] { position: relative; }
	[data-tip]::after {
		content: attr(data-tip);
		position: absolute;
		top: calc(100% + 8px);
		left: 50%;
		transform: translateX(-50%) scale(0.97);
		background: var(--toast-bg);
		color: #fff;
		font-size: 11px;
		font-weight: 400;
		padding: 4px 8px;
		border-radius: 6px;
		white-space: nowrap;
		opacity: 0;
		pointer-events: none;
		transition: opacity 125ms var(--ease-out) 350ms, transform 125ms var(--ease-out) 350ms;
		z-index: 900;
	}
	@media (hover: hover) and (pointer: fine) {
		[data-tip]:hover::after { opacity: 1; transform: translateX(-50%) scale(1); }
	}

	/* ---- welcome (first run) ----------------------------------------------- */
	.overlay.welcome { background: var(--bg); }
	.welcome-inner {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 24px;
		width: min(440px, calc(100vw - 32px));
		text-align: center;
		animation: modalin 300ms var(--ease-out);
	}
	.welcome-title { margin: 0; font-size: 36px; font-weight: 300; letter-spacing: 0.02em; color: var(--ink); }
	.welcome-input {
		width: 100%;
		font: inherit;
		font-size: 20px;
		text-align: center;
		letter-spacing: 0.06em;
		padding: 8px 0;
		border: none;
		border-bottom: 1px solid var(--sep);
		border-radius: 0;
		background: transparent;
		color: var(--ink);
		outline: none;
		transition: border-color 200ms ease;
	}
	.welcome-input:focus { border-color: var(--ink); box-shadow: none; }
	.welcome-actions { display: flex; flex-direction: column; align-items: center; gap: 16px; margin-top: 12px; }
	.welcome-link {
		border: 0;
		background: transparent;
		color: var(--ink-3);
		font: inherit;
		font-size: 13px;
		cursor: pointer;
		padding: 4px 8px;
		border-radius: 6px;
	}
	.welcome-link:hover { color: var(--ink); background: var(--f1); }

	/* ---- motion accessibility ------------------------------------------------- */
	@media (prefers-reduced-motion: reduce) {
		*, *::before, *::after {
			animation-duration: 0.01ms !important;
			animation-iteration-count: 1 !important;
			transition-duration: 0.01ms !important;
		}
	}

	/* ---- print ----------------------------------------------------------------- */
	@media print {
		.chrome, .drawer, .statuspill, .menu-pop, .toast, .ghost-layer, .overlay { display: none !important; }
		.stage { height: auto; background: #fff; overflow: visible; }
		.main, .scroll { display: block; overflow: visible; padding: 0; }
		.sppage { width: auto; margin: 0; padding: 0; box-shadow: none; background: #fff; color: #000; border-radius: 0; }
		:global(.b.pgb) { break-before: page; margin-top: 0; border: 0; padding-top: 0; }
		:global(.b.pgb)::after { content: none; }
		:global(.b.pgb[data-contd])::before { position: static; font-size: inherit; display: block; }
		:global(.b[data-contdb])::after { position: static; display: block; text-align: right; font-size: inherit; }
		:global(.b.el-scene), :global(.b.el-character) { break-after: avoid; }
		:global(.b.el-dialogue), :global(.b.el-parenthetical) { break-inside: avoid; }
	}
	@page { size: letter; margin: 1in 1in 1in 1.5in; }
</style>
