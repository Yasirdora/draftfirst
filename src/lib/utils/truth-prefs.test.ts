import { beforeEach, describe, expect, it, vi } from 'vitest';

const store = new Map<string, string>();

vi.stubGlobal('localStorage', {
	getItem: (k: string) => store.get(k) ?? null,
	setItem: (k: string, v: string) => {
		store.set(k, v);
	},
	removeItem: (k: string) => {
		store.delete(k);
	},
	clear: () => store.clear()
});

// Import after stub so the module sees our localStorage.
const {
	getTruthBaseline,
	loadTruthPrefs,
	pruneTruthBaselines,
	removeTruthBaseline,
	setTruthBaselineForDoc,
	setTruthEnabled
} = await import('./truth-prefs');

describe('truth-prefs', () => {
	beforeEach(() => {
		store.clear();
	});

	it('defaults to disabled with empty baselines', () => {
		expect(loadTruthPrefs()).toEqual({ enabled: false, baselines: {} });
	});

	it('persists enabled without wiping baselines', () => {
		setTruthBaselineForDoc('doc-a', '# Hello\n');
		setTruthEnabled(true);
		const prefs = loadTruthPrefs();
		expect(prefs.enabled).toBe(true);
		expect(prefs.baselines['doc-a']).toBe('# Hello\n');
	});

	it('restores per-document baseline across reloads', () => {
		setTruthBaselineForDoc('doc-a', 'trusted source\n');
		expect(getTruthBaseline('doc-a', 'fallback')).toBe('trusted source\n');
		expect(getTruthBaseline('doc-b', 'fallback body')).toBe('fallback body');
	});

	it('removes and prunes baselines', () => {
		setTruthBaselineForDoc('keep', 'a');
		setTruthBaselineForDoc('drop', 'b');
		removeTruthBaseline('drop');
		expect(loadTruthPrefs().baselines).toEqual({ keep: 'a' });
		setTruthBaselineForDoc('gone', 'c');
		pruneTruthBaselines(['keep']);
		expect(loadTruthPrefs().baselines).toEqual({ keep: 'a' });
	});

	it('migrates legacy enabled-only JSON', () => {
		store.set('writing-desk:truth:v1', JSON.stringify({ enabled: true }));
		const prefs = loadTruthPrefs();
		expect(prefs.enabled).toBe(true);
		expect(prefs.baselines).toEqual({});
	});
});
