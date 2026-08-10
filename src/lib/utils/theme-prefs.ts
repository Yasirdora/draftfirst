/**
 * UI theme preference — light, dark, or follow the system.
 * Survives reload. Device-level (like onboarding), independent of the library:
 * the same writer may want dark chrome at night on this machine and light on
 * another, and the library must never carry that choice between machines.
 *
 * Applies to the chrome only. The document sheet stays paper-white either way —
 * see the "Two token scopes" note in app.css.
 */

const KEY = 'writing-desk:theme:v1';

export type ThemeMode = 'light' | 'dark' | 'system';

const MODES: readonly ThemeMode[] = ['light', 'dark', 'system'];

export function loadThemePrefs(): ThemeMode {
	try {
		const raw = localStorage.getItem(KEY);
		if (!raw) return 'system';
		const parsed = JSON.parse(raw) as { mode?: unknown };
		return MODES.includes(parsed.mode as ThemeMode) ? (parsed.mode as ThemeMode) : 'system';
	} catch {
		return 'system';
	}
}

export function saveThemePrefs(mode: ThemeMode): void {
	try {
		localStorage.setItem(KEY, JSON.stringify({ mode }));
	} catch {
		/* private mode / quota — non-fatal */
	}
}

/** Resolve a mode against the OS setting to the concrete theme to paint. */
export function resolveDark(mode: ThemeMode, systemDark: boolean): boolean {
	if (mode === 'system') return systemDark === true;
	return mode === 'dark';
}

/**
 * Next mode for the app-bar toggle, aware of the OS setting.
 * From "system": flip to the explicit opposite of the OS, so the first click
 * always changes what you see. From an explicit mode: flip to the other
 * explicit — unless that already matches the OS, in which case step into
 * "system" (the honest "follow the OS now" step). This keeps every mode
 * reachable on every OS and no click ever lands on an invisible change
 * except the deliberate explicit → system hand-off.
 */
export function nextTheme(mode: ThemeMode, systemDark: boolean): ThemeMode {
	if (mode === 'system') return systemDark ? 'light' : 'dark';
	if (mode === 'light') return systemDark ? 'dark' : 'system';
	return systemDark ? 'system' : 'light';
}
