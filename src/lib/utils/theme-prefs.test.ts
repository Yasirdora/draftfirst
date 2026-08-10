/**
 * Theme preference — load/save/resolve/cycle against in-memory storage.
 * Pure logic, DOM-free, runs in Node.
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { loadThemePrefs, nextTheme, resolveDark, saveThemePrefs, type ThemeMode } from './theme-prefs';

function shimLocalStorage() {
	const map = new Map<string, string>();
	const storage = {
		getItem: (key: string) => (map.has(key) ? map.get(key)! : null),
		setItem: (key: string, value: string) => void map.set(key, String(value)),
		removeItem: (key: string) => void map.delete(key),
		clear: () => map.clear(),
		key: (index: number) => [...map.keys()][index] ?? null,
		get length() {
			return map.size;
		}
	};
	vi.stubGlobal('localStorage', storage);
	return map;
}

beforeEach(() => {
	shimLocalStorage();
});

describe('loadThemePrefs', () => {
	it('defaults to system when storage is empty', () => {
		expect(loadThemePrefs()).toBe('system');
	});

	it('defaults to system on corrupt JSON', () => {
		localStorage.setItem('writing-desk:theme:v1', '{not json');
		expect(loadThemePrefs()).toBe('system');
	});

	it('defaults to system on an unknown mode value', () => {
		localStorage.setItem('writing-desk:theme:v1', JSON.stringify({ mode: 'sepia' }));
		expect(loadThemePrefs()).toBe('system');
	});

	it('round-trips every mode through save', () => {
		for (const mode of ['light', 'dark', 'system'] as const) {
			saveThemePrefs(mode);
			expect(loadThemePrefs()).toBe(mode);
		}
	});
});

describe('resolveDark', () => {
	it('maps explicit modes regardless of the OS setting', () => {
		expect(resolveDark('light', true)).toBe(false);
		expect(resolveDark('light', false)).toBe(false);
		expect(resolveDark('dark', true)).toBe(true);
		expect(resolveDark('dark', false)).toBe(true);
	});

	it('follows the OS setting only in system mode', () => {
		expect(resolveDark('system', true)).toBe(true);
		expect(resolveDark('system', false)).toBe(false);
	});
});

describe('nextTheme', () => {
	it('from system always flips visibly — opposite of the OS', () => {
		expect(nextTheme('system', false)).toBe('dark');
		expect(nextTheme('system', true)).toBe('light');
	});

	it('flips between explicit modes when the flip is visible', () => {
		expect(nextTheme('light', true)).toBe('dark'); // dark ≠ light OS → visible
		expect(nextTheme('dark', false)).toBe('light'); // light ≠ dark OS → visible
	});

	it('steps into system when the explicit mode already matches the OS', () => {
		expect(nextTheme('light', false)).toBe('system');
		expect(nextTheme('dark', true)).toBe('system');
	});

	it('reaches every mode in a full cycle on either OS', () => {
		for (const osDark of [false, true]) {
			let mode: ThemeMode = 'system';
			const seen = new Set<ThemeMode>([mode]);
			for (let i = 0; i < 3; i++) {
				mode = nextTheme(mode, osDark);
				seen.add(mode);
			}
			expect(mode).toBe('system'); // cycle closes
			expect(seen).toEqual(new Set<ThemeMode>(['light', 'dark', 'system']));
		}
	});
});
