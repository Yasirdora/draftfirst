/**
 * Opt-in dialect packs — which extensions beyond CommonMark + GFM are on.
 * Survives reload. Device-level, like theme: a writing choice, not a document.
 *
 * Off means the syntax renders exactly as typed (literal `[^note]` text) —
 * never silently swallowed, never half-parsed.
 */

const KEY = 'writing-desk:dialects:v1';

export interface DialectPrefs {
	footnotes: boolean;
}

const DEFAULTS: DialectPrefs = { footnotes: false };

export function loadDialectPrefs(): DialectPrefs {
	try {
		const raw = localStorage.getItem(KEY);
		if (!raw) return { ...DEFAULTS };
		const data = JSON.parse(raw) as Partial<DialectPrefs>;
		return { footnotes: data.footnotes === true };
	} catch {
		return { ...DEFAULTS };
	}
}

export function saveDialectPrefs(prefs: DialectPrefs): void {
	try {
		localStorage.setItem(KEY, JSON.stringify({ footnotes: prefs.footnotes === true }));
	} catch {
		/* private mode / quota — non-fatal */
	}
}

export function setFootnotesEnabled(enabled: boolean): void {
	const prefs = loadDialectPrefs();
	prefs.footnotes = enabled === true;
	saveDialectPrefs(prefs);
}
