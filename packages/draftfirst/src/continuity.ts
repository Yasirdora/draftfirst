/**
 * Draft First Screenwriting Engine continuity analysis.
 *
 * Reports inconsistent names and locations, unclosed structures, incomplete
 * scene headings, and likely cue errors without modifying the screenplay.
 */

import type { Screenplay } from './types.js';
import { isPrinting } from './types.js';
import { splitSceneHeading, stripCueExtensions } from './smarttype.js';
import { openStructure } from './predict.js';

export interface ContinuityNote {
	/** Stable machine-readable identifier; human copy may evolve independently. */
	code:
		| 'character-spelling-drift'
		| 'location-spelling-drift'
		| 'unclosed-sequence'
		| 'missing-scene-time'
		| 'possible-character-typo'
		| 'orphan-dialogue-flow';
	severity: 'warning' | 'error';
	/** Source element indices containing the evidence, in document order. */
	elementIndices: readonly number[];
	/** Short headline, e.g. "Character cue spelled two ways". */
	kind: string;
	/** The evidence, e.g. "MOLLY (12×)  ·  MOLLY. (1×)". */
	detail: string;
	/** Explanation of the downstream impact. */
	why: string;
}

/* ---- drift detection ------------------------------------------------------- */

/**
 * Normalize case, punctuation, and leading articles for comparison.
 */
export function continuityKey(s: string): string {
	return s
		.toUpperCase()
		.replace(/[''’]/g, '')
		.replace(/[^A-Z0-9 ]/g, ' ')
		.replace(/\b(THE|A|AN)\b/g, ' ')
		.replace(/\s+/g, ' ')
		.trim();
}

/**
 * Group spellings that share a normal form. Each returned group holds two or
 * more surface spellings, most-used first. Deterministic and conservative —
 * genuinely different names ("JOHN" / "JOAN") never group.
 */
export function driftGroups(counts: Map<string, number>): string[][] {
	const byKey = new Map<string, string[]>();
	for (const name of counts.keys()) {
		const key = continuityKey(name);
		if (!key) continue;
		const g = byKey.get(key);
		if (g) g.push(name);
		else byKey.set(key, [name]);
	}
	return [...byKey.values()]
		.filter((g) => g.length > 1)
		.map((g) => g.sort((a, b) => (counts.get(b) ?? 0) - (counts.get(a) ?? 0)));
}

function formatGroup(group: string[], counts: Map<string, number>): string {
	return group.map((n) => `${n} (${counts.get(n) ?? 0}×)`).join('  ·  ');
}

/** Levenshtein distance, early-capped at 3 — we only care about near misses. */
function editDistance(a: string, b: string): number {
	if (Math.abs(a.length - b.length) > 2) return 3;
	let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
	for (let i = 1; i <= a.length; i++) {
		const cur = [i];
		let rowMin = i;
		for (let j = 1; j <= b.length; j++) {
			cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
			rowMin = Math.min(rowMin, cur[j]);
		}
		if (rowMin > 2) return 3;
		prev = cur;
	}
	return prev[b.length];
}

/** Within a keystroke for short names, two for long ones. */
function nearMiss(a: string, b: string): boolean {
	if (a === b) return false;
	const limit = Math.max(a.length, b.length) >= 6 ? 2 : 1;
	return editDistance(a, b) <= limit;
}

/* ---- the pass -------------------------------------------------------------- */

export function continuityReport(script: Screenplay): ContinuityNote[] {
	const notes: ContinuityNote[] = [];
	const els = script.elements;

	const cueCounts = new Map<string, number>();
	const locCounts = new Map<string, number>();
	const cueIndices = new Map<string, number[]>();
	const locIndices = new Map<string, number[]>();
	const missingTime: Array<{ text: string; index: number }> = [];

	let dialogueFlowOpen = false;
	const orphaned: number[] = [];

	els.forEach((el, i) => {
		if (!isPrinting(el.type)) return;

		if (el.type === 'character') {
			const base = stripCueExtensions(el.text).trim().toUpperCase();
			if (base) {
				cueCounts.set(base, (cueCounts.get(base) ?? 0) + 1);
				const indices = cueIndices.get(base) ?? [];
				indices.push(i);
				cueIndices.set(base, indices);
			}
		}

		if (el.type === 'scene') {
			const { location, time } = splitSceneHeading(el.text);
			if (location) {
				const loc = location.toUpperCase();
				locCounts.set(loc, (locCounts.get(loc) ?? 0) + 1);
				const indices = locIndices.get(loc) ?? [];
				indices.push(i);
				locIndices.set(loc, indices);
				if (!time) missingTime.push({ text: el.text.trim().toUpperCase(), index: i });
			}
		}

		if (el.type === 'character') {
			dialogueFlowOpen = el.text.trim() !== '';
		} else if (el.type === 'dialogue' || el.type === 'parenthetical' || el.type === 'lyrics') {
			if (el.text.trim() !== '' && !dialogueFlowOpen) orphaned.push(i);
		} else if (el.text.trim() !== '') {
			dialogueFlowOpen = false;
		}
	});

	for (const group of driftGroups(cueCounts)) {
		notes.push({
			code: 'character-spelling-drift',
			severity: 'warning',
			elementIndices: group.flatMap((name) => cueIndices.get(name) ?? []).sort((a, b) => a - b),
			kind: 'Character cue spelled two ways',
			detail: formatGroup(group, cueCounts),
			why: 'Cast lists and dialogue counts will split between them.'
		});
	}

	for (const group of driftGroups(locCounts)) {
		notes.push({
			code: 'location-spelling-drift',
			severity: 'warning',
			elementIndices: group.flatMap((name) => locIndices.get(name) ?? []).sort((a, b) => a - b),
			kind: 'Location spelled two ways',
			detail: formatGroup(group, locCounts),
			why: 'Every department downstream treats these as different places.'
		});
	}

	const open = openStructure(els, els.length);
	if (open) {
		notes.push({
			code: 'unclosed-sequence',
			severity: 'error',
			elementIndices: els
				.map((el, index) => ({ el, index }))
				.filter(({ el }) => el.text.trim().toUpperCase().startsWith(open.open))
				.map(({ index }) => index)
				.slice(-1),
			kind: 'Unclosed sequence',
			detail: open.open,
			why: `A reader cannot tell where it ends. Close it with ${open.close}.`
		});
	}

	if (missingTime.length > 0) {
		notes.push({
			code: 'missing-scene-time',
			severity: 'warning',
			elementIndices: missingTime.map(({ index }) => index),
			kind:
				missingTime.length === 1
					? 'A scene heading has no time of day'
					: `${missingTime.length} scene headings have no time of day`,
			detail:
				missingTime.slice(0, 4).map(({ text }) => text).join('  ·  ') +
				(missingTime.length > 4 ? `  ·  and ${missingTime.length - 4} more` : ''),
			why: 'Scheduling splits the shoot by DAY and NIGHT.'
		});
	}

	/**
	 * Report a once-used cue when it is close to an established speaker name.
	 * Short names require edit distance 1; longer names allow distance 2.
	 */
	const established = [...cueCounts.entries()].filter(([, n]) => n >= 3).map(([n]) => n);
	const suspects = [...cueCounts.entries()]
		.filter(([name, n]) => n === 1 && name.length >= 4 && established.some((e) => nearMiss(name, e)))
		.map(([name]) => name);
	if (suspects.length > 0) {
		const nearest = (name: string) =>
			established.find((e) => nearMiss(name, e)) ?? '';
		notes.push({
			code: 'possible-character-typo',
			severity: 'warning',
			elementIndices: suspects.flatMap((name) => cueIndices.get(name) ?? []).sort((a, b) => a - b),
			kind:
				suspects.length === 1
					? 'A character speaks once, under an almost-familiar name'
					: `${suspects.length} characters speak once, under almost-familiar names`,
			detail: suspects
				.slice(0, 6)
				.map((n) => `${n} — did you mean ${nearest(n)}?`)
				.join('  ·  ') + (suspects.length > 6 ? `  ·  and ${suspects.length - 6} more` : ''),
			why: 'Often a typo in a cue. Sometimes exactly what you meant.'
		});
	}

	if (orphaned.length > 0) {
		notes.push({
			code: 'orphan-dialogue-flow',
			severity: 'error',
			elementIndices: orphaned,
			kind:
				orphaned.length === 1
					? 'A line of dialogue has no speaker'
					: `${orphaned.length} lines of dialogue have no speaker`,
			detail: 'Dialogue, lyrics, or direction with no character cue above it.',
			why: 'The page does not say who is speaking.'
		});
	}

	return notes;
}
