/**
 * eDraft Screenwriting Engine paginator.
 *
 * Applies deterministic screenplay pagination constraints:
 *
 *   · 55 lines per US Letter page (Courier 12pt, 1.5″/1″ margins)
 *   · a scene heading never sits alone at a page bottom (keeps with content)
 *   · a character cue never separates from its dialogue
 *   · split dialogue closes with (MORE) and reopens with NAME (CONT'D)
 *   · action blocks split with at least 2 lines on each side (widow/orphan)
 *   · page 1 carries no number; numbering starts at 2
 *
 * Element geometry in Courier characters from the left margin (6.0″ = 60ch):
 *   scene/action/shot/general  indent 0,  width 60
 *   character                  indent 22, width 38   (3.7″ from page edge)
 *   dialogue                   indent 10, width 35   (2.5″ from page edge)
 *   parenthetical              indent 16, width 26   (3.1″ from page edge)
 *   transition                 flush right (ends at column 60)
 *   centered                   centered within 60
 *
 * The module is deterministic and independent of the DOM and font loading.
 */

import type { AnyElementType, Screenplay } from './types.js';
import { isPrinting } from './types.js';
import { stripCueExtensions } from './smarttype.js';

export const LINES_PER_PAGE = 55;
export const PAGE_WIDTH_CHARS = 60;
const MIN_LINES_PER_PAGE = 10;
const MAX_LINES_PER_PAGE = 10_000;

interface Geometry {
	indent: number;
	width: number;
	before: number;
}

export const GEOMETRY: Readonly<Record<string, Geometry>> = {
	scene: { indent: 0, width: 60, before: 2 },
	action: { indent: 0, width: 60, before: 1 },
	character: { indent: 22, width: 38, before: 1 },
	dialogue: { indent: 10, width: 35, before: 0 },
	parenthetical: { indent: 16, width: 26, before: 0 },
	transition: { indent: 0, width: 60, before: 1 },
	shot: { indent: 0, width: 60, before: 1 },
	general: { indent: 0, width: 60, before: 1 },
	centered: { indent: 0, width: 60, before: 1 },
	lyrics: { indent: 10, width: 35, before: 0 }
};

/* ---- output model ------------------------------------------------------ */

export interface PageLine {
	text: string;
	/** 'blank' = spacing line; 'more' = generated (MORE); otherwise element type. */
	type: AnyElementType | 'blank' | 'more';
	indent: number;
	/** Index into script.elements for provenance; -1 for generated lines. */
	element: number;
}

export interface ScriptPage {
	number: number;
	lines: PageLine[];
	/** This page opens mid-scene — print CONTINUED: at the top margin. */
	continuedTop: boolean;
	/** This page ends mid-scene — print (CONTINUED) at the bottom margin. */
	continuedBottom: boolean;
}

export interface PaginateOptions {
	linesPerPage?: number;
}

/* ---- text wrapping ----------------------------------------------------- */

function assertFiniteInteger(value: number, name: string, min: number, max: number): void {
	if (!Number.isFinite(value) || !Number.isInteger(value) || value < min || value > max) {
		throw new RangeError(`${name} must be an integer between ${min} and ${max}.`);
	}
}

/** Greedy word wrap at `width` characters, hard-splitting tokens that cannot fit. */
export function wrapText(text: string, width: number): string[] {
	assertFiniteInteger(width, 'width', 1, PAGE_WIDTH_CHARS);
	const words = text
		.split(/\s+/)
		.filter((w) => w !== '')
		.flatMap((word) => {
			if (word.length <= width) return [word];
			const chunks: string[] = [];
			for (let i = 0; i < word.length; i += width) chunks.push(word.slice(i, i + width));
			return chunks;
		});
	if (words.length === 0) return [''];
	const lines: string[] = [];
	let cur = words[0];
	for (let i = 1; i < words.length; i++) {
		if (cur.length + 1 + words[i].length <= width) {
			cur += ' ' + words[i];
		} else {
			lines.push(cur);
			cur = words[i];
		}
	}
	lines.push(cur);
	return lines;
}

function alignedLine(text: string, align: 'right' | 'center'): { text: string; indent: number } {
	const len = text.length;
	if (align === 'right') return { text, indent: Math.max(0, PAGE_WIDTH_CHARS - len) };
	return { text, indent: Math.max(0, Math.floor((PAGE_WIDTH_CHARS - len) / 2)) };
}

/* ---- block building ---------------------------------------------------- */

interface FlowLine {
	text: string;
	type: AnyElementType;
	indent: number;
	element: number;
}

interface Block {
	kind: 'scene' | 'flow' | 'simple';
	before: number;
	lines: FlowLine[];
	/** Base cue name for (CONT'D) regeneration — flow blocks only. */
	cueName?: string | undefined;
	/** Lyrics and cue-less dialogue must never acquire synthetic dialogue markers. */
	continuationEligible?: boolean | undefined;
}

const FLOW_TYPES = new Set<AnyElementType>(['character', 'parenthetical', 'dialogue', 'lyrics']);

/**
 * Blocks built as the fold consumes them.
 *
 * `buildBlocks` wrapped the whole document up front — fine while pagination
 * was always whole-document, but the incremental pass stops at the first
 * page that matches its cache, and building blocks for the unread tail cost
 * more than the fold saved: measured 37ms of wrap work per keystroke after
 * the fold itself had already answered. The source produces the same stream
 * as eagerly as the fold asks — a flow block is complete when its successor
 * starts — so an early stop pays for the pages it read and no more.
 */
class BlockSource {
	private index: number;
	private flow: Block | null = null;
	private buffered: Array<Block | 'pagebreak'> = [];

	constructor(
		private readonly script: Screenplay,
		startIndex: number
	) {
		this.index = startIndex;
	}

	/** The head of the stream, unconsumed — the fold's current block. */
	current(): Block | 'pagebreak' | undefined {
		this.fill(1);
		return this.buffered[0];
	}

	/** The block after the head — the scene keep rule's one lookahead. */
	next(): Block | 'pagebreak' | undefined {
		this.fill(2);
		return this.buffered[1];
	}

	/** Consume the head. */
	advance(): void {
		this.fill(1);
		this.buffered.shift();
	}

	private fill(count: number): void {
		while (this.buffered.length < count && !this.atEnd) {
			this.step();
		}
		/* End of input completes any open flow block. */
		if (this.atEnd) this.flushFlow();
	}

	private get atEnd(): boolean {
		return this.index >= this.script.elements.length;
	}

	/* One element in. A block leaves the buffer only when complete: a flow
	   block completes when its successor starts (or the document ends). */
	private step(): void {
		const el = this.script.elements[this.index];
		this.index++;

		if (el.type === 'pagebreak') {
			this.flushFlow();
			this.buffered.push('pagebreak');
			return;
		}
		if (!isPrinting(el.type)) return;

		const geo = GEOMETRY[el.type] ?? GEOMETRY.action;

		if (FLOW_TYPES.has(el.type)) {
			if (el.type === 'character' || !this.flow) {
				this.flushFlow();
				this.flow = {
					kind: 'flow',
					before: GEOMETRY.character.before,
					lines: [],
					cueName: el.type === 'character' ? el.text : undefined,
					continuationEligible: el.type === 'character'
				};
			}
			const activeFlow = this.flow;
			if (!activeFlow) throw new Error('Dialogue flow could not be initialized.');
			if (el.type === 'lyrics') activeFlow.continuationEligible = false;
			const wrapped =
				el.type === 'character'
					? wrapText(el.text + (el.dual ? ' ^' : ''), GEOMETRY.character.width)
					: wrapText(el.text, geo.width);
			for (const text of wrapped) {
				activeFlow.lines.push({ text, type: el.type, indent: geo.indent, element: this.index - 1 });
			}
			return;
		}

		this.flushFlow();

		if (el.type === 'transition' || el.type === 'centered') {
			const align = el.type === 'transition' ? 'right' : 'center';
			this.buffered.push({
				kind: 'simple',
				before: geo.before,
				lines: wrapText(el.text, PAGE_WIDTH_CHARS).map((text) => {
					const a = alignedLine(text, align);
					return { text: a.text, type: el.type, indent: a.indent, element: this.index - 1 };
				})
			});
			return;
		}

		this.buffered.push({
			kind: el.type === 'scene' ? 'scene' : 'simple',
			before: geo.before,
			lines: wrapText(el.text, geo.width).map((text) => ({
				text,
				type: el.type,
				indent: geo.indent,
				element: this.index - 1
			}))
		});
	}

	private flushFlow(): void {
		if (this.flow) {
			this.buffered.push(this.flow);
			this.flow = null;
		}
	}

}

/* ---- pagination -------------------------------------------------------- */

const MORE_INDENT = GEOMETRY.dialogue.indent;

interface FoldOutcome {
	/** Pages the fold completed, numbered absolutely. */
	pages: ScriptPage[];
	/** The open page's lines when the fold ended — empty after a page closed. */
	trailing: PageLine[];
	/** Absolute number of the page the fold stopped after, or 0 for "ran to the end". */
	stoppedAfter: number;
}

/**
 * The pagination fold, shared by the full pass and the incremental one.
 *
 * Everything a page decision reads from the past is in the arguments:
 * `startNumber` (the page being built) and `current0` (the lines already on
 * it). `stopAfter` is consulted as each page closes; the current block still
 * finishes, so a stop never lands mid-block. The rules below are unchanged
 * from the pass that was measured and pinned — this is the same fold, made
 * resumable, not a second paginator.
 */
function runFold(
	source: BlockSource,
	limit: number,
	startNumber: number,
	current0: PageLine[],
	stopAfter?: (completed: ScriptPage) => boolean
): FoldOutcome {
	const pages: ScriptPage[] = [];
	let current = current0.slice();
	let stoppedAfter = 0;

	const newPage = (allowEmpty = false) => {
		if (stoppedAfter > 0) return;
		if (current.length === 0 && !allowEmpty) return;
		const completed: ScriptPage = {
			number: startNumber + pages.length,
			lines: current,
			continuedTop: false,
			continuedBottom: false
		};
		pages.push(completed);
		current = [];
		if (stopAfter?.(completed)) stoppedAfter = completed.number;
	};

	const blanks = (n: number, element: number) => {
		for (let i = 0; i < n; i++) current.push({ text: '', type: 'blank', indent: 0, element });
	};

	const emit = (line: FlowLine) => current.push({ ...line });
	const emitRange = (lines: FlowLine[], start: number, end: number) => {
		for (let i = start; i < end; i++) emit(lines[i]);
	};

	const spaceLeft = () => limit - current.length;

	/** Largest honourable chunk: at least two lines here and two left over. */
	const splitSize = (remaining: number, capacity: number): number => {
		if (capacity < 2 || remaining < 4) return 0;
		const take = Math.min(capacity, remaining - 2);
		return take >= 2 ? take : 0;
	};

	const emitSimpleBlock = (block: Block, initialBefore: number): void => {
		let cursor = 0;
		let pre = initialBefore;
		while (cursor < block.lines.length) {
			const remaining = block.lines.length - cursor;
			const capacity = spaceLeft() - pre;
			if (remaining <= capacity) {
				blanks(pre, block.lines[cursor]?.element ?? -1);
				emitRange(block.lines, cursor, block.lines.length);
				return;
			}

			const take = splitSize(remaining, capacity);
			if (take > 0) {
				blanks(pre, block.lines[cursor]?.element ?? -1);
				emitRange(block.lines, cursor, cursor + take);
				cursor += take;
				newPage();
				pre = 0;
				continue;
			}

			if (current.length > 0) {
				newPage();
				pre = 0;
				continue;
			}

			/* A fresh page can always advance because limit >= 10. This path is
			   reserved for pathological blocks whose shape cannot satisfy the
			   two-line widow/orphan rule. */
			const hardTake = Math.min(capacity, remaining);
			if (hardTake <= 0) throw new Error('Paginator could not make forward progress.');
			emitRange(block.lines, cursor, cursor + hardTake);
			cursor += hardTake;
			if (cursor < block.lines.length) newPage();
			pre = 0;
		}
	};

	const flowHeadLength = (lines: FlowLine[]): number => {
		if (lines[0]?.type !== 'character') return Math.min(2, lines.length);
		let head = 1;
		while (head < lines.length && lines[head].type === 'parenthetical') head++;
		/* A cue and its parentheticals must retain at least one spoken line. */
		return Math.min(lines.length, head + 1);
	};

	const stepBlock = (block: Block, next: Block | 'pagebreak' | undefined): void => {
		const before = current.length === 0 ? 0 : block.before;

		/* -- scene heading: keep with at least 2 lines of following content -- */
		if (block.kind === 'scene') {
			const followLines =
				next && next !== 'pagebreak'
					? next.kind === 'flow'
						? flowHeadLength(next.lines)
						: Math.min(2, next.lines.length)
					: 0;
			const followNeed = next && next !== 'pagebreak' ? next.before + followLines : 0;
			if (current.length > 0 && before + block.lines.length + followNeed > spaceLeft()) {
				newPage();
			}
			emitSimpleBlock(block, current.length === 0 ? 0 : block.before);
			return;
		}

		/* -- dialogue flow: cue keep-together + (MORE)/(CONT'D) splitting ----
		   Continuation LOOPS: a monologue longer than a page must chain
		   (MORE)/NAME (CONT'D) across as many pages as it needs — silently
		   overflowing the page is a correctness failure. */
		if (block.kind === 'flow') {
			const lines = block.lines;
			const head = flowHeadLength(lines);
			const base = stripCueExtensions(block.cueName ?? '').trim();
			const continuationEligible =
				block.continuationEligible === true &&
				base !== '' &&
				lines.some((line) => line.type === 'dialogue') &&
				!lines.some((line) => line.type === 'lyrics');

			if (before + lines.length <= spaceLeft()) {
				blanks(before, lines[0].element);
				emitRange(lines, 0, lines.length);
				return;
			}

			if (!continuationEligible) {
				/* Preserve content and page bounds without inventing a speaker or
				   dialogue continuation for lyrics/cue-less imported material. */
				if (current.length > 0 && spaceLeft() - before < head) newPage();
				emitSimpleBlock(block, current.length === 0 ? 0 : before);
				return;
			}

			const contd = base === '' ? "(CONT'D)" : `${base} (CONT'D)`;
			const contdLines = wrapText(contd, GEOMETRY.character.width);
			let cursor = 0;
			let firstChunk = true;

			while (cursor < lines.length) {
				const pre = firstChunk ? (current.length === 0 ? 0 : block.before) : 0;
				const remaining = lines.length - cursor;

				if (pre + remaining <= spaceLeft()) {
					blanks(pre, lines[cursor].element);
					emitRange(lines, cursor, lines.length);
					break;
				}

				const avail = spaceLeft() - pre - 1; /* reserve (MORE) */
				let take = Math.min(avail, remaining - 1);
				while (take > 0 && lines[cursor + take - 1].type === 'parenthetical') take--;
				const minimum = firstChunk ? head : 1;

				if (take < minimum) {
					if (current.length > 0) {
						/* cannot split honourably here — move to a fresh page and retry */
						newPage();
						continue;
					}
					/* An extreme run of parentheticals cannot be split as dialogue.
					   Preserve it without fabricating markers or overflowing. */
					emitSimpleBlock(
						{ ...block, lines: lines.slice(cursor), continuationEligible: false },
						0
					);
					break;
				}

				blanks(pre, lines[cursor].element);
				emitRange(lines, cursor, cursor + take);
				cursor += take;
				current.push({ text: '(MORE)', type: 'more', indent: MORE_INDENT, element: -1 });
				newPage();
				for (const text of contdLines) {
					current.push({
						text,
						type: 'character',
						indent: GEOMETRY.character.indent,
						element: -1
					});
				}
				firstChunk = false;
			}
			return;
		}

		/* -- simple block: whole, or split with widow/orphan control; a block
		      longer than a page chains across pages rather than overflowing -- */
		emitSimpleBlock(block, current.length === 0 ? 0 : block.before);
	};

	while (stoppedAfter === 0) {
		const block = source.current();
		if (block === undefined) break;
		if (block === 'pagebreak') {
			if (current.length > 0) newPage();
		} else {
			stepBlock(block, source.next());
		}
		source.advance();
	}

	return { pages, trailing: current, stoppedAfter };
}

export function paginate(script: Screenplay, opts: PaginateOptions = {}): ScriptPage[] {
	const limit = opts.linesPerPage ?? LINES_PER_PAGE;
	assertFiniteInteger(limit, 'linesPerPage', MIN_LINES_PER_PAGE, MAX_LINES_PER_PAGE);
	const fold = runFold(new BlockSource(script, 0), limit, 1, []);
	const pages = fold.pages;
	/* A document's last page closes when it ends; an empty document still has one. */
	if (fold.trailing.length > 0 || pages.length === 0) {
		pages.push({
			number: 1 + pages.length,
			lines: fold.trailing,
			continuedTop: false,
			continuedBottom: false
		});
	}
	markSceneContinues(script, pages);
	return pages;
}

/* ---- incremental pagination ----------------------------------------------

   A keystroke repaginates what changed, not the document. The fold's whole
   memory is the page being built and the lines already on it, so a later
   run may begin at any block boundary whose surroundings are unchanged:
   the diff below finds the first layout-relevant change, the checkpoint
   walks back to its block and carries the open page's prefix, the fold runs
   forward, and the moment a completed page provably matches its cached twin
   — same tail element, same line count — the cached tail is spliced on.

   The contract the tests pin: paginateIncrementally == paginate, always.
   When no checkpoint can be proven (a stale cache, an empty document), the
   answer is the full pass, not a guess. */

export interface PaginationCheckpoint {
	/** 1-based number of the page the fold resumes on. */
	pageNumber: number;
	/** The open page's existing lines, above the resume block. */
	prefix: PageLine[];
	/** First element the fold processes — always a block boundary. */
	elementIndex: number;
}

/** Type, text and dualism are everything the fold reads from an element. */
function layoutEqual(a: Screenplay['elements'][number], b: Screenplay['elements'][number]): boolean {
	return a.type === b.type && a.text === b.text && (a.dual ?? false) === (b.dual ?? false);
}

interface LayoutEdit {
	firstDirty: number;
	tailStartsAt: number;
	tailShift: number;
}

/** The changed region, or null when nothing the fold reads has changed. */
function layoutEditBetween(
	previous: Screenplay['elements'],
	current: Screenplay['elements']
): LayoutEdit | null {
	let first = 0;
	const minLength = Math.min(previous.length, current.length);
	while (first < minLength && layoutEqual(previous[first], current[first])) first++;
	if (first === previous.length && first === current.length) return null;
	let tail = 0;
	while (
		tail < minLength - first &&
		layoutEqual(previous[previous.length - 1 - tail], current[current.length - 1 - tail])
	) tail++;
	return {
		firstDirty: first,
		tailStartsAt: current.length - tail,
		tailShift: current.length - previous.length
	};
}

/** True when the element opens a block in the full block list — the resume
    point must be one, because a flow block is built from its cue forward. */
function opensBlock(elements: Screenplay['elements'], index: number): boolean {
	const el = elements[index];
	if (el.type === 'pagebreak') return true;
	if (!isPrinting(el.type)) return false;
	if (!FLOW_TYPES.has(el.type)) return true;
	if (el.type === 'character') return true;
	for (let i = index - 1; i >= 0; i--) {
		const prev = elements[i];
		if (prev.type === 'pagebreak') return true;
		if (!isPrinting(prev.type)) continue;
		return !FLOW_TYPES.has(prev.type);
	}
	return true;
}

/** Where a resumed fold may pick up, or null for "repaginate from zero".
    The edit's block is walked back on BOTH element lists: a type change can
    make an element open a block in the new document while the old document
    folded it into a flow that began earlier — and that earlier head printed
    on an earlier page. The resume point covers both shapes. */
export function resumeCheckpoint(
	script: Screenplay,
	previous: Screenplay,
	previousPages: ScriptPage[],
	firstDirtyElement: number
): PaginationCheckpoint | null {
	const elements = script.elements;
	if (elements.length === 0 || previousPages.length === 0) return null;
	const clamp = (i: number, list: Screenplay['elements']) => Math.min(Math.max(0, i), list.length - 1);
	let startNew = clamp(firstDirtyElement, elements);
	while (startNew > 0 && !opensBlock(elements, startNew)) startNew--;
	let startOld = clamp(firstDirtyElement, previous.elements);
	while (startOld > 0 && !opensBlock(previous.elements, startOld)) startOld--;
	let start = Math.min(startNew, startOld);
	if (start === 0) return null;
	/* …and then one block further. The only backward-looking rules reach
	   exactly this far: a changed block that now fits may pull itself onto
	   the previous page's tail, and a scene heading keeps with the *next*
	   block — a changed neighbour answers that question differently. */
	let before = start - 1;
	while (before > 0 && !opensBlock(elements, before)) before--;
	if (before > 0) start = before;

	/* The block's first printed line in the cached pages — the elements above
	   it are unchanged, so the old and new indices agree there. */
	for (const page of previousPages) {
		const lines = page.lines;
		for (let j = 0; j < lines.length; j++) {
			if (lines[j].element !== start || lines[j].type === 'blank') continue;
			/* Trailing blanks before the block are its `before` spacing; the
			   resumed fold re-emits them, so the prefix ends before them. */
			let cut = j;
			while (cut > 0 && lines[cut - 1].type === 'blank') cut--;
			return { pageNumber: page.number, prefix: lines.slice(0, cut), elementIndex: start };
		}
	}
	return null;
}

/**
 * Paginate against the previous run: identical pages at identical cost.
 * The full pass runs when there is nothing proven to reuse; the early splice
 * fires only at a page that starts in the unchanged tail with the same shape
 * its cached twin had, where the fold's remaining work is a pure function of
 * unchanged elements.
 */
export function paginateIncrementally(
	current: Screenplay,
	previous: Screenplay,
	previousPages: ScriptPage[],
	opts: PaginateOptions = {}
): ScriptPage[] {
	const limit = opts.linesPerPage ?? LINES_PER_PAGE;
	assertFiniteInteger(limit, 'linesPerPage', MIN_LINES_PER_PAGE, MAX_LINES_PER_PAGE);
	if (previousPages.length === 0) return paginate(current, opts);

	const edit = layoutEditBetween(previous.elements, current.elements);
	if (!edit) return previousPages;
	const checkpoint = resumeCheckpoint(current, previous, previousPages, edit.firstDirty);
	if (!checkpoint) return paginate(current, opts);

	const fold = runFold(
		new BlockSource(current, checkpoint.elementIndex),
		limit,
		checkpoint.pageNumber,
		checkpoint.prefix,
		(completed) => {
		const cached = previousPages[completed.number - 1];
		if (!cached) return false;
		const firstNew = completed.lines.find((l) => l.element >= 0)?.element ?? -1;
		const firstOld = cached.lines.find((l) => l.element >= 0)?.element ?? -1;
		if (firstNew < 0 || firstOld < 0) return false;
		/* A page starting inside the changed region is no twin, whatever its shape. */
		if (firstNew < edit.tailStartsAt) return false;
		const lastElemented = (lines: PageLine[]): number => {
			for (let i = lines.length - 1; i >= 0; i--) {
				if (lines[i].element >= 0) return lines[i].element;
			}
			return -1;
		};
		const lastNew = lastElemented(completed.lines);
		const lastOld = lastElemented(cached.lines);
		return (
			firstNew === firstOld + edit.tailShift &&
			lastNew === lastOld + edit.tailShift &&
			completed.lines.length === cached.lines.length
		);
	});

	const kept = previousPages.slice(0, checkpoint.pageNumber - 1);
	let result: ScriptPage[];
	if (fold.stoppedAfter > 0) {
		/* The page the fold stopped after is in both lists: the fold completed
		   it (that is how the resync saw it) and the cache holds its twin.
		   The cached tail already carries it, so the fold's copy drops out. */
		const tail = previousPages.slice(fold.stoppedAfter - 1);
		if (edit.tailShift !== 0) {
			/* Cached pages speak the old element indices; every line they hold
			   belongs to the unchanged tail, so each shifts by the same delta.
			   Copied line by line — the caller's cache is not ours to mutate. */
			const remapped = tail.map((page) => ({
				...page,
				lines: page.lines.map((line) =>
					line.element >= 0 ? { ...line, element: line.element + edit.tailShift } : { ...line }
				)
			}));
			result = kept.concat(fold.pages.slice(0, -1), remapped);
		} else {
			result = kept.concat(fold.pages.slice(0, -1), tail);
		}
	} else if (fold.trailing.length > 0 || fold.pages.length === 0 && kept.length === 0) {
		result = kept.concat(
			fold.pages,
			fold.trailing.length > 0 || fold.pages.length === 0
				? [{
						number: checkpoint.pageNumber + fold.pages.length,
						lines: fold.trailing,
						continuedTop: false,
						continuedBottom: false
					}]
				: []
		);
	} else {
		result = kept.concat(fold.pages);
	}
	markSceneContinues(current, result);
	return result;
}

/* ---- scene continuations ---------------------------------------------------

   The production convention: when a scene spans a page break, the closing
   page carries (CONTINUED) at the bottom right and the opening page carries
   CONTINUED: at the top left. Departments count on these to know the scene
   was not split editorially. Markers live in the margins — they never
   consume body lines, so adding them cannot shift a page break. */

function markSceneContinues(script: Screenplay, pages: ScriptPage[]): void {
	/* scene index per element: -1 before the first heading */
	const sceneOf: number[] = [];
	let scene = -1;
	script.elements.forEach((el, i) => {
		if (el.type === 'scene') scene++;
		sceneOf[i] = scene;
	});

	const firstElemented = (p: ScriptPage) => p.lines.find((l) => l.element >= 0);
	const lastElemented = (p: ScriptPage) => {
		for (let i = p.lines.length - 1; i >= 0; i--) {
			if (p.lines[i].element >= 0) return p.lines[i];
		}
		return undefined;
	};

	for (let i = 1; i < pages.length; i++) {
		const prev = lastElemented(pages[i - 1]);
		const next = firstElemented(pages[i]);
		if (!prev || !next) continue;
		const sPrev = sceneOf[prev.element];
		const sNext = sceneOf[next.element];
		/* a page boundary is a scene continuation when both sides belong to
		   the same scene and the new page does not open with a fresh heading */
		const spans = sPrev >= 0 && sPrev === sNext && script.elements[next.element].type !== 'scene';
		/* Assignment, not accumulation: the incremental pass splices pages that
		   carry these flags from an older document, so a stale true must be
		   cleared by the same pass that sets the live ones. */
		pages[i - 1].continuedBottom = spans;
		pages[i].continuedTop = spans;
	}
}

/* ---- reporting --------------------------------------------------------- */

/** 1 page ≈ 1 minute — the industry's rule-of-thumb runtime estimate. */
export function estimateRuntime(pages: ScriptPage[]): string {
	const total = pages.length;
	return total === 1 ? '~1 minute' : `~${total} minutes`;
}

/** Count non-blank printed lines — a stable complexity metric for tests/UI. */
export function printedLineCount(pages: ScriptPage[]): number {
	return pages.reduce(
		(sum, p) => sum + p.lines.filter((l) => l.type !== 'blank').length,
		0
	);
}
