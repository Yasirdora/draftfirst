/**
 * Framework-independent state for opening an element-selection menu.
 *
 * Three consecutive Enter presses on empty blocks request the menu. Any other
 * input resets the sequence. A slash requests the menu only on an empty block.
 */

export interface SummonState {
	/** Consecutive Enters pressed on empty lines, unbroken by any other act. */
	run: number;
}

export const newSummonState = (): SummonState => ({ run: 0 });

/** What an Enter press should do, given whether the current line is empty. */
export function emptyEnterOutcome(s: SummonState, blockEmpty: boolean): 'advance' | 'menu' {
	if (!blockEmpty) {
		s.run = 0;
		return 'advance';
	}
	s.run += 1;
	if (s.run >= 3) {
		s.run = 0;
		return 'menu';
	}
	return 'advance';
}

/** Any typing, navigation, or click breaks the run. */
export function resetSummon(s: SummonState): void {
	s.run = 0;
}

/** `/` summons the menu only on an empty line; otherwise it is ordinary text. */
export function slashSummons(blockText: string): boolean {
	return blockText.trim() === '';
}

/** Keys that never break a run on their own (pure modifiers). */
const SUMMON_NEUTRAL_KEYS = new Set([
	'Shift',
	'Control',
	'Alt',
	'Meta',
	'CapsLock'
]);

export function isSummonNeutralKey(key: string): boolean {
	return SUMMON_NEUTRAL_KEYS.has(key);
}
