/**
 * eDraft Screenwriting Engine act derivation (RFC-ACT-BREAK §2, §4).
 *
 * The model stores only the card text. Everything else about an act — its
 * ordinal, its boundaries, its end — is derived from the element list, and
 * this module is the one home of that arithmetic: the FDX boundary's
 * generated End of Act cards, the selector's default card text, and the
 * renumber rule all read it, so they cannot disagree.
 */

import type { ScreenplayElement } from './types.js';

/** The words an act card spells its ordinal with: ONE through TWENTY, then
    digits — some scripts run long (RFC-ACT-BREAK §4). */
export const ACT_ORDINAL_WORDS: readonly string[] = [
	'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', 'NINE', 'TEN',
	'ELEVEN', 'TWELVE', 'THIRTEEN', 'FOURTEEN', 'FIFTEEN', 'SIXTEEN', 'SEVENTEEN',
	'EIGHTEEN', 'NINETEEN', 'TWENTY'
];

/** The ordinal an act card spells, 1-based: a word through twenty, the
    digits beyond. */
export function actOrdinal(n: number): string {
	return ACT_ORDINAL_WORDS[n - 1] ?? String(n);
}

/** The canonical card spelling (RFC-ACT-BREAK §4). A card in this shape
    means only "the act I am" and so follows the renumber rule; anything
    else — TEASER, ACT TWO: THE TURN, a lowercase act one — is the writer's
    text and is never rewritten. */
const CANONICAL_CARD = new RegExp(`^ACT (?:${ACT_ORDINAL_WORDS.join('|')}|[0-9]+)$`);

export function isCanonicalActCard(text: string): boolean {
	return CANONICAL_CARD.test(text);
}

/** The default card a freshly inserted act break carries: the canonical
    spelling of the ordinal it was inserted at. The renumber rule keeps it
    true afterwards, which is the point of starting canonical. */
export function defaultActCard(ordinal: number): string {
	return `ACT ${actOrdinal(ordinal)}`;
}

/** The renumber rule (RFC-ACT-BREAK §4): every card still speaking the
    canonical spelling is renumbered to the ordinal its position now
    carries; a card that doesn't match is the writer's text and is left
    alone. Every act break counts toward the ordinals, custom card or not —
    an act boundary is an act boundary however it is labelled.
 *
 * Idempotent: a second pass changes nothing. That is what lets a surface
 * run it after any edit that touched the act count — insert, delete, undo
 * — without asking which one happened. Unchanged elements keep their
 * identity, so a no-op pass costs a map and nothing else.
 */
export function renumberActs(elements: ScreenplayElement[]): ScreenplayElement[] {
	let ordinal = 0;
	return elements.map((element) => {
		if (element.type !== 'actbreak') return element;
		ordinal++;
		const canonical = defaultActCard(ordinal);
		if (element.text === canonical || !isCanonicalActCard(element.text)) return element;
		return { ...element, text: canonical };
	});
}
