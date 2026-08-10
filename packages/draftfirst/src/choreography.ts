/**
 * Draft First Screenwriting Engine keyboard-flow policies.
 *
 * Enter follows the normal screenplay element sequence. Tab uses a stable
 * fallback ring, while `tabCycle` narrows that ring according to the preceding
 * element so invalid dialogue structures are not offered.
 */

import type { AnyElementType } from './types.js';

export type ChoreoKey = 'enter' | 'tab';

/** Element selected by Enter after a non-empty block. */
export const ENTER_FLOW: Readonly<Record<string, AnyElementType>> = {
	scene: 'action',
	action: 'action',
	character: 'dialogue',
	parenthetical: 'dialogue',
	dialogue: 'character',
	transition: 'scene',
	shot: 'action',
	general: 'action',
	centered: 'action',
	lyrics: 'lyrics'
};

/**
 * Stable fallback order for Tab navigation. Each primary element type appears
 * exactly once, preventing two-state cycles.
 */
export const TAB_RING: readonly AnyElementType[] = [
	'character',
	'dialogue',
	'parenthetical',
	'transition',
	'scene',
	'action'
];

/**
 * The next element on the Tab ring from `current`. `reverse` is ⇧Tab.
 * Types off the ring (shot, general, centered, lyrics) join at action.
 * `tabCycle` narrows this order according to the preceding element.
 */
export function tabNext(current: AnyElementType, reverse = false): AnyElementType {
	let i = TAB_RING.indexOf(current);
	if (i < 0) i = TAB_RING.indexOf('action');
	const step = reverse ? -1 : 1;
	return TAB_RING[(i + step + TAB_RING.length) % TAB_RING.length];
}

/**
 * Allowed Tab targets keyed by the preceding element. The sets preserve cue,
 * parenthetical, and dialogue relationships.
 */
export const TAB_SET_FRESH: readonly AnyElementType[] = [
	'scene',
	'action',
	'character',
	'transition'
];

export const TAB_SETS: Readonly<Record<string, readonly AnyElementType[]>> = {
	scene: ['action', 'character', 'transition'],
	action: ['character', 'transition'],
	character: ['dialogue', 'parenthetical'],
	parenthetical: ['dialogue'],
	dialogue: TAB_SET_FRESH,
	transition: TAB_SET_FRESH
};

/**
 * The set a line may cycle through, given the element directly above it
 * (`null` at document start). Structural elements (shot, general,
 * centered, lyrics, page breaks skipped by the caller) open the fresh set.
 */
export function tabSetFor(prev: AnyElementType | null): readonly AnyElementType[] {
	if (!prev) return TAB_SET_FRESH;
	return TAB_SETS[prev] ?? TAB_SET_FRESH;
}

/**
 * Context-aware Tab: cycle within the set the line above allows.
 * A current type outside its set enters at the head, or the tail in reverse.
 */
export function tabCycle(
	current: AnyElementType,
	prev: AnyElementType | null,
	reverse = false
): AnyElementType {
	const set = tabSetFor(prev);
	const i = set.indexOf(current);
	if (i < 0) return reverse ? set[set.length - 1] : set[0];
	return set[(i + (reverse ? -1 : 1) + set.length) % set.length];
}

/**
 * Resolve the element produced by Enter/Tab in `current`.
 * `currentText` enables the Enter empty-collapse escape hatch.
 */
export function nextElement(
	current: AnyElementType,
	key: ChoreoKey,
	currentText = 'x'
): AnyElementType {
	if (key === 'enter') {
		if (currentText.trim() === '' && current !== 'action') return 'action';
		return ENTER_FLOW[current] ?? 'action';
	}
	return tabNext(current);
}
