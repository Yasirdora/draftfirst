/**
 * Dialect pack prefs — defaults, corrupt storage, round trip.
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { loadDialectPrefs, saveDialectPrefs, setFootnotesEnabled } from './dialect-prefs';

function shimLocalStorage() {
	const map = new Map<string, string>();
	vi.stubGlobal('localStorage', {
		getItem: (key: string) => (map.has(key) ? map.get(key)! : null),
		setItem: (key: string, value: string) => void map.set(key, String(value)),
		removeItem: (key: string) => void map.delete(key),
		clear: () => map.clear(),
		key: (index: number) => [...map.keys()][index] ?? null,
		get length() {
			return map.size;
		}
	});
	return map;
}

beforeEach(() => {
	shimLocalStorage();
});

describe('loadDialectPrefs', () => {
	it('defaults every pack off when storage is empty', () => {
		expect(loadDialectPrefs()).toEqual({ footnotes: false });
	});

	it('defaults off on corrupt JSON', () => {
		localStorage.setItem('writing-desk:dialects:v1', '{nope');
		expect(loadDialectPrefs()).toEqual({ footnotes: false });
	});

	it('coerces truthy values to strict booleans', () => {
		localStorage.setItem('writing-desk:dialects:v1', JSON.stringify({ footnotes: 1 }));
		expect(loadDialectPrefs()).toEqual({ footnotes: false });
	});
});

describe('saveDialectPrefs / setFootnotesEnabled', () => {
	it('round-trips the enabled state', () => {
		saveDialectPrefs({ footnotes: true });
		expect(loadDialectPrefs().footnotes).toBe(true);
	});

	it('flips one pack without losing the shape', () => {
		setFootnotesEnabled(true);
		expect(loadDialectPrefs()).toEqual({ footnotes: true });
		setFootnotesEnabled(false);
		expect(loadDialectPrefs()).toEqual({ footnotes: false });
	});
});
