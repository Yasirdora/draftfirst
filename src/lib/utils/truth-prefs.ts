/**
 * Truth mode preference + per-document trusted baselines.
 * Survives reload. Independent of document bodies in the library.
 *
 * `baselines[docId]` is the last Markdown the writer trusted for that note.
 * After page edits, the saved body may diverge; Truth keeps showing that
 * until Accept or an intentional Markdown edit.
 */

const KEY = 'writing-desk:truth:v1';

export interface TruthPrefs {
	/** When true, show fidelity strip after page serialises */
	enabled: boolean;
	/** Trusted source snapshot keyed by library document id */
	baselines: Record<string, string>;
}

function emptyPrefs(): TruthPrefs {
	return { enabled: false, baselines: {} };
}

export function loadTruthPrefs(): TruthPrefs {
	try {
		const raw = localStorage.getItem(KEY);
		if (!raw) return emptyPrefs();
		const data = JSON.parse(raw) as Partial<TruthPrefs> & { enabled?: boolean };
		const baselines =
			data.baselines && typeof data.baselines === 'object' && !Array.isArray(data.baselines)
				? (data.baselines as Record<string, string>)
				: {};
		// Coerce values to strings only
		const clean: Record<string, string> = {};
		for (const [id, body] of Object.entries(baselines)) {
			if (typeof id === 'string' && typeof body === 'string') clean[id] = body;
		}
		return {
			enabled: data.enabled === true,
			baselines: clean
		};
	} catch {
		return emptyPrefs();
	}
}

export function saveTruthPrefs(prefs: TruthPrefs): void {
	try {
		localStorage.setItem(
			KEY,
			JSON.stringify({
				enabled: prefs.enabled === true,
				baselines: prefs.baselines || {}
			})
		);
	} catch {
		/* private mode / quota — non-fatal */
	}
}

/** Toggle Truth mode without wiping per-document baselines. */
export function setTruthEnabled(enabled: boolean): void {
	const prefs = loadTruthPrefs();
	prefs.enabled = enabled === true;
	saveTruthPrefs(prefs);
}

/** Read one baseline without loading the full map twice in hot paths. */
export function getTruthBaseline(docId: string, fallback: string): string {
	const prefs = loadTruthPrefs();
	const stored = prefs.baselines[docId];
	return typeof stored === 'string' ? stored : fallback;
}

export function setTruthBaselineForDoc(docId: string, baseline: string): void {
	const prefs = loadTruthPrefs();
	prefs.baselines[docId] = baseline;
	saveTruthPrefs(prefs);
}

export function removeTruthBaseline(docId: string): void {
	const prefs = loadTruthPrefs();
	if (!(docId in prefs.baselines)) return;
	delete prefs.baselines[docId];
	saveTruthPrefs(prefs);
}

/** Drop baselines for ids that no longer exist (housekeeping). */
export function pruneTruthBaselines(liveIds: Iterable<string>): void {
	const prefs = loadTruthPrefs();
	const live = new Set(liveIds);
	let changed = false;
	for (const id of Object.keys(prefs.baselines)) {
		if (!live.has(id)) {
			delete prefs.baselines[id];
			changed = true;
		}
	}
	if (changed) saveTruthPrefs(prefs);
}
