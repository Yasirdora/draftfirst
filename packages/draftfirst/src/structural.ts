/**
 * Draft First Screenwriting Engine structural-element preservation.
 *
 * Editor surfaces may expose only printing elements while the document also
 * contains notes, sections, synopses, and page breaks. These elements must be
 * retained when an editable stream is detached and later reassembled.
 *
 * This module detaches non-printing elements at load time (anchored to the
 * nearest following printable element) and reattaches them at export time.
 * Anchors identify the occurrence of a type+text pair, so repeated lines do
 * not attract structure that originally belonged to a later occurrence.
 * Unmatched leftovers survive at the end of the document rather than
 * vanishing.
 */

import type { AnyElementType, ScreenplayElement } from './types.js';
import { isPrinting } from './types.js';

export interface StructuralAnchor {
	item: ScreenplayElement;
	/** The printable element that followed this item at load time. */
	anchorType: AnyElementType | null;
	anchorText: string | null;
	/**
	 * Zero-based occurrence of the anchor's type+text pair in the original
	 * printable stream. Optional so anchors created by older clients continue
	 * to work; legacy anchors attach to the first matching occurrence.
	 */
	anchorOccurrence?: number | null;
}

export interface DetachedDocument {
	printable: ScreenplayElement[];
	anchors: StructuralAnchor[];
}

/** Split a parsed model into editable (printing) elements and anchored structure. */
export function detachStructural(elements: ScreenplayElement[]): DetachedDocument {
	const printable: ScreenplayElement[] = [];
	const anchors: StructuralAnchor[] = [];
	const pending: StructuralAnchor[] = [];
	const occurrences = new Map<AnyElementType, Map<string, number>>();

	for (const el of elements) {
		if (isPrinting(el.type)) {
			printable.push(el);
			let byText = occurrences.get(el.type);
			if (!byText) {
				byText = new Map();
				occurrences.set(el.type, byText);
			}
			const occurrence = byText.get(el.text) ?? 0;
			byText.set(el.text, occurrence + 1);

			for (const anchor of pending) {
				anchor.anchorType = el.type;
				anchor.anchorText = el.text;
				anchor.anchorOccurrence = occurrence;
			}
			pending.length = 0;
		} else {
			const anchor: StructuralAnchor = {
				item: el,
				anchorType: null,
				anchorText: null,
				anchorOccurrence: null
			};
			anchors.push(anchor);
			pending.push(anchor);
		}
	}
	return { printable, anchors };
}

type AnchorIndex = Map<AnyElementType, Map<string, Map<number, number[]>>>;

function indexAnchor(index: AnchorIndex, anchor: StructuralAnchor, anchorIndex: number): void {
	if (anchor.anchorType === null || anchor.anchorText === null) return;
	const occurrence =
		Number.isSafeInteger(anchor.anchorOccurrence) && (anchor.anchorOccurrence ?? -1) >= 0
			? (anchor.anchorOccurrence as number)
			: 0;

	let byText = index.get(anchor.anchorType);
	if (!byText) {
		byText = new Map();
		index.set(anchor.anchorType, byText);
	}
	let byOccurrence = byText.get(anchor.anchorText);
	if (!byOccurrence) {
		byOccurrence = new Map();
		byText.set(anchor.anchorText, byOccurrence);
	}
	const bucket = byOccurrence.get(occurrence);
	if (bucket) bucket.push(anchorIndex);
	else byOccurrence.set(occurrence, [anchorIndex]);
}

/** Re-insert preserved structure into an edited printable stream. */
export function reattachStructural(
	printable: ScreenplayElement[],
	anchors: StructuralAnchor[]
): ScreenplayElement[] {
	if (anchors.length === 0) return printable;

	const out: ScreenplayElement[] = [];
	const anchorIndex: AnchorIndex = new Map();
	const matched = new Uint8Array(anchors.length);
	const occurrences = new Map<AnyElementType, Map<string, number>>();
	anchors.forEach((anchor, index) => indexAnchor(anchorIndex, anchor, index));

	for (const el of printable) {
		let byText = occurrences.get(el.type);
		if (!byText) {
			byText = new Map();
			occurrences.set(el.type, byText);
		}
		const occurrence = byText.get(el.text) ?? 0;
		byText.set(el.text, occurrence + 1);

		const bucket = anchorIndex.get(el.type)?.get(el.text)?.get(occurrence);
		if (bucket) {
			/* Bucket indices follow the original anchor order. */
			for (const index of bucket) {
				const anchor = anchors[index];
				if (!anchor) continue;
				out.push(anchor.item);
				matched[index] = 1;
			}
		}
		out.push(el);
	}

	/* Append anchors whose original target is no longer present. */
	for (let index = 0; index < anchors.length; index++) {
		const anchor = anchors[index];
		if (matched[index] === 0 && anchor) out.push(anchor.item);
	}
	return out;
}
