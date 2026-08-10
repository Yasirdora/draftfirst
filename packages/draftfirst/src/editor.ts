/** Framework-free editor policy. No DOM, rendering, storage, or Svelte code. */

export type { ChoreoKey } from './choreography.js';
export { nextElement, tabCycle, tabNext, tabSetFor } from './choreography.js';
export {
	looksLikeCue,
	normalizeCue,
	normalizeElementText,
	normalizeParenthetical
} from './normalize.js';
export type { PredictContext, Prediction } from './predict.js';
export { ghostSuffix, ghostTabBehavior, nextWord, predict } from './predict.js';
export type { DetachedDocument, StructuralAnchor } from './structural.js';
export { detachStructural, reattachStructural } from './structural.js';
export type { SummonState } from './summon.js';
export {
	emptyEnterOutcome,
	isSummonNeutralKey,
	newSummonState,
	resetSummon,
	slashSummons
} from './summon.js';
