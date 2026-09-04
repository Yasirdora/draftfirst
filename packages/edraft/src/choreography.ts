/**
 * eDraft Screenwriting Engine keyboard-flow policies.
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
 * Where a line that has nothing on it goes when Return is pressed on it.
 *
 * An empty line is a writer saying they are done with this kind, so Return
 * changes what the line is rather than making another one below it. From
 * anywhere in a speech that means action — the way out of the block. From
 * action it means a character cue, because the thing a writer reaches for
 * after describing something is usually someone speaking, and it makes the
 * blank line a cycle instead of a dead end: press again and it is action
 * once more.
 */
export const EMPTY_LINE_ESCAPE: Readonly<Record<string, AnyElementType>> = {
	action: 'character'
};

/** What an empty line becomes on Return. */
export function emptyLineEscape(current: AnyElementType): AnyElementType {
	return EMPTY_LINE_ESCAPE[current] ?? 'action';
}

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
 *
 * After action the set includes action itself: a cycle that cannot return
 * to what the line was traps the writer — one swipe from action lands on
 * character, and no amount of cycling brings action back. Closing the loop
 * keeps the first stop identical (action still enters at character) while
 * making every gesture reversible.
 */
export const TAB_SET_FRESH: readonly AnyElementType[] = [
	'scene',
	'action',
	'character',
	'transition'
];

/**
 * After a speech the writer is choosing between five real destinations, in
 * the order a script actually goes: keep speaking, cut away, open a new
 * scene, describe, or cue the next voice. Enter lands the new line on a
 * character cue, so one Tab forward from there wraps to dialogue — the
 * speech continues — and one Tab back reaches action. A parenthetical is not
 * in the set: a direction belongs under the cue that introduces the speech
 * (where TAB_SETS.character offers it), not between two lines of one.
 *
 * The fresh set was wrong here for the same reason it was wrong after
 * action, and worse: with dialogue missing from it, no gesture could turn
 * that new line back into the speech the writer meant to continue. The
 * block was a one-way door.
 */
export const TAB_SETS: Readonly<Record<string, readonly AnyElementType[]>> = {
	scene: ['action', 'character', 'transition'],
	action: ['action', 'character', 'transition'],
	character: ['dialogue', 'parenthetical'],
	parenthetical: ['dialogue'],
	dialogue: ['dialogue', 'transition', 'scene', 'action', 'character'],
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
		if (currentText.trim() === '') return emptyLineEscape(current);
		return ENTER_FLOW[current] ?? 'action';
	}
	return tabNext(current);
}
