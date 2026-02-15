/**
 * Find highlights on the typeset page.
 *
 * Primary path: CSS Custom Highlight API — paints without mutating the DOM,
 * so the page never reflows or “jumps” when matches appear.
 *
 * Fallback: zero-geometry <mark> wrappers (no padding/margin/shadow) only when
 * Highlight API is unavailable.
 */

export const FIND_MARK_CLASS = 'find-mark';
export const FIND_MARK_ACTIVE = 'find-mark--active';

const CSS_HL_ALL = 'wd-find';
const CSS_HL_ACTIVE = 'wd-find-active';

type Hit = { node: Text; start: number; end: number };

function supportsCssHighlight(): boolean {
	return (
		typeof CSS !== 'undefined' &&
		'highlights' in CSS &&
		typeof Highlight !== 'undefined'
	);
}

function collectHits(root: HTMLElement, query: string): Hit[] {
	const q = query.trim();
	if (q.length < 2) return [];

	const lowerQ = q.toLowerCase();
	const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
		acceptNode(node) {
			const value = node.nodeValue;
			if (!value) return NodeFilter.FILTER_REJECT;
			const el = node.parentElement;
			if (!el) return NodeFilter.FILTER_REJECT;
			if (el.closest('mark.find-mark')) return NodeFilter.FILTER_REJECT;
			if (el.closest('script, style')) return NodeFilter.FILTER_REJECT;
			return NodeFilter.FILTER_ACCEPT;
		}
	});

	const hits: Hit[] = [];
	let current: Node | null;
	while ((current = walker.nextNode())) {
		const textNode = current as Text;
		const text = textNode.nodeValue || '';
		const lower = text.toLowerCase();
		let from = 0;
		while (from < lower.length) {
			const at = lower.indexOf(lowerQ, from);
			if (at === -1) break;
			hits.push({ node: textNode, start: at, end: at + q.length });
			from = at + Math.max(1, q.length);
		}
	}
	return hits;
}

function clearLegacyMarks(root: HTMLElement): void {
	const marks = root.querySelectorAll('mark.find-mark');
	for (const mark of marks) {
		const parent = mark.parentNode;
		if (!parent) continue;
		while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
		parent.removeChild(mark);
		parent.normalize();
	}
}

function clearCssHighlights(): void {
	if (!supportsCssHighlight()) return;
	try {
		CSS.highlights.delete(CSS_HL_ALL);
		CSS.highlights.delete(CSS_HL_ACTIVE);
	} catch {
		/* ignore */
	}
}

/** Remove all find highlights (CSS and any legacy marks). */
export function clearFindHighlights(root: HTMLElement | null | undefined): void {
	clearCssHighlights();
	if (root) clearLegacyMarks(root);
}

function scrollParentOf(el: HTMLElement): HTMLElement {
	let p: HTMLElement | null = el.parentElement;
	while (p) {
		const style = getComputedStyle(p);
		const oy = style.overflowY;
		if (
			(oy === 'auto' || oy === 'scroll' || oy === 'overlay') &&
			p.scrollHeight > p.clientHeight + 1
		) {
			return p;
		}
		p = p.parentElement;
	}
	return (document.scrollingElement as HTMLElement) || document.documentElement;
}

/**
 * Nudge the scroll container only if the range is outside the visible area.
 * Never uses scrollIntoView(center/smooth) — that was a major source of “shift”.
 */
function ensureRangeVisible(range: Range, root: HTMLElement): void {
	const scroller = scrollParentOf(root);
	const rr = range.getBoundingClientRect();
	const pr = scroller.getBoundingClientRect();
	const pad = 32;

	if (rr.height === 0 && rr.width === 0) return;

	if (rr.top < pr.top + pad) {
		scroller.scrollTop -= pr.top + pad - rr.top;
	} else if (rr.bottom > pr.bottom - pad) {
		scroller.scrollTop += rr.bottom - (pr.bottom - pad);
	}
}

export interface PaintFindOptions {
	/** Scroll only when the active match is off-screen (default true). */
	scroll?: boolean;
}

/**
 * Highlight every occurrence of query under root.
 * Returns match count. Does not reflow the page when Highlight API is available.
 */
export function paintFindHighlights(
	root: HTMLElement | null | undefined,
	query: string,
	activeIndex: number,
	opts: PaintFindOptions = {}
): number {
	if (!root) return 0;

	const scroll = opts.scroll !== false;
	const q = query.trim();

	// Always clear previous paint first (no leftover geometry).
	clearCssHighlights();
	clearLegacyMarks(root);

	if (q.length < 2) return 0;

	const hits = collectHits(root, q);
	if (hits.length === 0) return 0;

	const active = ((activeIndex % hits.length) + hits.length) % hits.length;

	if (supportsCssHighlight()) {
		const rest: AbstractRange[] = [];
		const focus: AbstractRange[] = [];

		for (let i = 0; i < hits.length; i++) {
			const hit = hits[i];
			const range = document.createRange();
			range.setStart(hit.node, hit.start);
			range.setEnd(hit.node, hit.end);
			if (i === active) focus.push(range);
			else rest.push(range);
		}

		try {
			// Inactive matches
			if (rest.length) CSS.highlights.set(CSS_HL_ALL, new Highlight(...rest));
			// Active match (stronger) — separate registry entry
			if (focus.length) CSS.highlights.set(CSS_HL_ACTIVE, new Highlight(...focus));
		} catch {
			/* fall through to legacy below */
			return paintLegacyMarks(root, hits, active, scroll);
		}

		if (scroll && focus[0] instanceof Range) {
			ensureRangeVisible(focus[0], root);
		}
		return hits.length;
	}

	return paintLegacyMarks(root, hits, active, scroll);
}

/** Last-resort DOM marks with zero box geometry so layout stays put. */
function paintLegacyMarks(
	root: HTMLElement,
	hits: Hit[],
	active: number,
	scroll: boolean
): number {
	const byNode = new Map<Text, Hit[]>();
	for (const hit of hits) {
		const list = byNode.get(hit.node) || [];
		list.push(hit);
		byNode.set(hit.node, list);
	}

	for (const [, nodeHits] of byNode) {
		nodeHits.sort((a, b) => b.start - a.start);
		for (const hit of nodeHits) {
			try {
				const range = document.createRange();
				range.setStart(hit.node, hit.start);
				range.setEnd(hit.node, hit.end);
				const mark = document.createElement('mark');
				mark.className = FIND_MARK_CLASS;
				mark.setAttribute('data-find-mark', '1');
				range.surroundContents(mark);
			} catch {
				/* skip */
			}
		}
	}

	const marks = root.querySelectorAll('mark.find-mark');
	const total = marks.length;
	if (total === 0) return 0;

	const activeIdx = ((active % total) + total) % total;
	marks.forEach((mark, i) => {
		mark.classList.toggle(FIND_MARK_ACTIVE, i === activeIdx);
	});

	if (scroll) {
		const el = marks[activeIdx] as HTMLElement;
		const range = document.createRange();
		range.selectNodeContents(el);
		ensureRangeVisible(range, root);
	}

	return total;
}
