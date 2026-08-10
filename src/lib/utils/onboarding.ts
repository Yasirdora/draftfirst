/**
 * First-run calm: remember whether the writer has dismissed the welcome strip.
 * Separate from document storage so clearing the desk never re-triggers onboarding.
 */

const KEY = 'writing-desk:onboarding:v1';

export interface OnboardingState {
	welcomeDismissed: boolean;
}

export function loadOnboarding(): OnboardingState {
	try {
		const raw = localStorage.getItem(KEY);
		if (!raw) return { welcomeDismissed: false };
		const data = JSON.parse(raw) as Partial<OnboardingState>;
		return { welcomeDismissed: data.welcomeDismissed === true };
	} catch {
		return { welcomeDismissed: false };
	}
}

export function saveOnboarding(state: OnboardingState): void {
	try {
		localStorage.setItem(KEY, JSON.stringify(state));
	} catch {
		/* private mode / quota — welcome may reappear; non-fatal */
	}
}
