/**
 * Draft First Screenwriting Engine paginator.
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

function buildBlocks(script: Screenplay): Array<Block | 'pagebreak'> {
	const blocks: Array<Block | 'pagebreak'> = [];
	let flow: Block | null = null;

	const flushFlow = () => {
		if (flow) {
			blocks.push(flow);
			flow = null;
		}
	};

	script.elements.forEach((el, idx) => {
		/* Page breaks are non-printing elements that still divide layout blocks. */
		if (el.type === 'pagebreak') {
			flushFlow();
			blocks.push('pagebreak');
			return;
		}
		if (!isPrinting(el.type)) return;

		const geo = GEOMETRY[el.type] ?? GEOMETRY.action;

		if (FLOW_TYPES.has(el.type)) {
			if (el.type === 'character' || !flow) {
				flushFlow();
				flow = {
					kind: 'flow',
					before: GEOMETRY.character.before,
					lines: [],
					cueName: el.type === 'character' ? el.text : undefined,
					continuationEligible: el.type === 'character'
				};
			}
			const activeFlow = flow;
			if (!activeFlow) throw new Error('Dialogue flow could not be initialized.');
			if (el.type === 'lyrics') activeFlow.continuationEligible = false;
			const wrapped =
				el.type === 'character'
					? wrapText(el.text + (el.dual ? ' ^' : ''), GEOMETRY.character.width)
					: wrapText(el.text, geo.width);
			for (const text of wrapped) {
				activeFlow.lines.push({ text, type: el.type, indent: geo.indent, element: idx });
			}
			return;
		}

		flushFlow();

		if (el.type === 'transition' || el.type === 'centered') {
			const align = el.type === 'transition' ? 'right' : 'center';
			blocks.push({
				kind: 'simple',
				before: geo.before,
				lines: wrapText(el.text, PAGE_WIDTH_CHARS).map((text) => {
					const a = alignedLine(text, align);
					return { text: a.text, type: el.type, indent: a.indent, element: idx };
				})
			});
			return;
		}

		const wrapped = wrapText(el.text, geo.width);
		blocks.push({
			kind: el.type === 'scene' ? 'scene' : 'simple',
			before: geo.before,
			lines: wrapped.map((text) => ({ text, type: el.type, indent: geo.indent, element: idx }))
		});
	});

	flushFlow();
	return blocks;
}

/* ---- pagination -------------------------------------------------------- */

const MORE_INDENT = GEOMETRY.dialogue.indent;

export function paginate(script: Screenplay, opts: PaginateOptions = {}): ScriptPage[] {
	const limit = opts.linesPerPage ?? LINES_PER_PAGE;
	assertFiniteInteger(limit, 'linesPerPage', MIN_LINES_PER_PAGE, MAX_LINES_PER_PAGE);
	const blocks = buildBlocks(script);
	const pages: ScriptPage[] = [];
	let current: PageLine[] = [];

	const newPage = (allowEmpty = false) => {
		if (current.length === 0 && !allowEmpty) return;
		pages.push({ number: pages.length + 1, lines: current, continuedTop: false, continuedBottom: false });
		current = [];
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

	for (let b = 0; b < blocks.length; b++) {
		const block = blocks[b];

		if (block === 'pagebreak') {
			if (current.length > 0) newPage();
			continue;
		}

		const before = current.length === 0 ? 0 : block.before;

		/* -- scene heading: keep with at least 2 lines of following content -- */
		if (block.kind === 'scene') {
			const next = blocks[b + 1];
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
			continue;
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
				continue;
			}

			if (!continuationEligible) {
				/* Preserve content and page bounds without inventing a speaker or
				   dialogue continuation for lyrics/cue-less imported material. */
				if (current.length > 0 && spaceLeft() - before < head) newPage();
				emitSimpleBlock(block, current.length === 0 ? 0 : before);
				continue;
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
			continue;
		}

		/* -- simple block: whole, or split with widow/orphan control; a block
		      longer than a page chains across pages rather than overflowing -- */
		emitSimpleBlock(block, current.length === 0 ? 0 : block.before);
	}

	if (current.length > 0 || pages.length === 0) newPage(true);
	markSceneContinues(script, pages);
	return pages;
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
		if (sPrev >= 0 && sPrev === sNext && script.elements[next.element].type !== 'scene') {
			pages[i - 1].continuedBottom = true;
			pages[i].continuedTop = true;
		}
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
