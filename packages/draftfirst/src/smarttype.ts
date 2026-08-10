/**
 * Draft First Screenwriting Engine vocabulary extraction.
 *
 * Derives character names, locations, scene times, transitions, and heading
 * prefixes from a screenplay without retaining state.
 */

import type { Screenplay } from './types.js';

/** Canonical scene-time tokens shared by parsing and prediction. */
export const SCENE_TIME_VALUES: readonly string[] = Object.freeze([
	'DAY',
	'NIGHT',
	'MORNING',
	'AFTERNOON',
	'EVENING',
	'DAWN',
	'DUSK',
	'SUNRISE',
	'SUNSET',
	'MAGIC HOUR',
	'MIDNIGHT',
	'LATER',
	'CONTINUOUS',
	'MOMENTS LATER',
	'SAME',
	'SAME TIME',
	'THE NEXT DAY',
	'DAYS LATER',
	'WEEKS LATER',
	'MONTHS LATER',
	'YEARS LATER',
	'FLASHBACK',
	'PRESENT DAY',
	'FUTURE'
]);

const SCENE_TIME_SET = new Set(SCENE_TIME_VALUES);

export interface SmartTypeData {
	/** Character names with extensions stripped — MOLLY, not MOLLY (V.O.). */
	characters: string[];
	/** Location parts of scene headings — POLICE STATION. */
	locations: string[];
	/** Time-of-day parts of scene headings — DAY, NIGHT, LATER. */
	times: string[];
	/** Transitions used — CUT TO:, SMASH CUT TO:. */
	transitions: string[];
	/** Scene heading prefixes seen — INT., EXT., INT./EXT. */
	prefixes: string[];
}

export interface SceneHeadingParts {
	prefix: string;
	location: string;
	time: string;
}

/** Strip cue extensions — (V.O.), (O.S.), (O.C.), (CONT'D), (SUBTITLE)… */
export function stripCueExtensions(cue: string): string {
	return cue
		.replace(/\s*\((?:V\.?O\.?|O\.?S\.?|O\.?C\.?|CONT['’]?D|SUBTITLE|PRE-?LAP|FILTERED|INTO (?:PHONE|RADIO|COMMS?)[^)]*)\)\s*/gi, '')
		.trim();
}

/** Split a scene heading into prefix / location / time parts.
   Parts are canonical UPPERCASE: a heading is a structural token, not
   prose — every consumer (memory, habits, drift checks) compares parts
   case-insensitively, and the model cannot be trusted to carry canonical
   case (blur without commit, paste, and mixed-case imports all leak). */
export function splitSceneHeading(heading: string): SceneHeadingParts {
	const m = /^(INT\.?\/EXT\.?|INT\/EXT|I\/E|INT|EXT|EST)[. ]?\s*/i.exec(heading.trim());
	const rawPrefix = m ? m[1].toUpperCase().replace(/\.$/, '') : '';
	const prefix = rawPrefix === '' ? '' : rawPrefix === 'I/E' ? 'I/E' : `${rawPrefix}.`;
	let rest = m ? heading.trim().slice(m[0].length) : heading.trim();

	let time = '';
	const parts = rest.split(/\s+[-–—]\s+/).map((part) => part.trim());
	if (parts.length > 1) {
		/* A heading may carry a modifier after time (`- DAY - ESTABLISHING`).
		   Select the first recognised time segment; locations may themselves
		   contain spaced dashes (`54TH ST - UPTOWN - DAY`). */
		let timeAt = parts.findIndex((part, index) => index > 0 && SCENE_TIME_SET.has(part.toUpperCase()));
		if (timeAt < 0) timeAt = parts.length - 1; // preserve custom times
		time = parts[timeAt];
		rest = parts.slice(0, timeAt).join(' - ');
	}
	return { prefix, location: rest.toUpperCase(), time: time.toUpperCase() };
}

function pushUnique(list: string[], seen: Set<string>, value: string): void {
	if (value !== '' && !seen.has(value)) {
		seen.add(value);
		list.push(value);
	}
}

/** Derive autocomplete/consistency vocabularies from the document. */
export function collectSmartType(script: Screenplay): SmartTypeData {
	const data: SmartTypeData = {
		characters: [],
		locations: [],
		times: [],
		transitions: [],
		prefixes: []
	};
	const seen = {
		characters: new Set<string>(),
		locations: new Set<string>(),
		times: new Set<string>(),
		transitions: new Set<string>(),
		prefixes: new Set<string>()
	};

	for (const el of script.elements) {
		if (el.type === 'character') {
			/* canonical case at the collection boundary — the engine never
			   trusts the model's casing (blur, paste, import all leak raw) */
			pushUnique(data.characters, seen.characters, stripCueExtensions(el.text).toUpperCase());
		} else if (el.type === 'scene') {
			const { prefix, location, time } = splitSceneHeading(el.text);
			pushUnique(data.prefixes, seen.prefixes, prefix);
			pushUnique(data.locations, seen.locations, location);
			pushUnique(data.times, seen.times, time);
		} else if (el.type === 'transition') {
			pushUnique(data.transitions, seen.transitions, el.text.trim().toUpperCase());
		}
	}
	return data;
}

/** Return location pairs that may differ only by articles or punctuation. */
export function findLocationDrift(script: Screenplay): Array<{ a: string; b: string }> {
	const { locations } = collectSmartType(script);
	const normalise = (s: string) =>
		s.replace(/^(THE|A|AN)\s+/i, '').replace(/['’.,-]/g, '').replace(/\s+/g, ' ').trim().toLowerCase();
	const entries = locations.map((surface, index) => ({ surface, index, key: normalise(surface) }));
	const postings = new Map<string, number[]>();
	for (const entry of entries) {
		for (const token of new Set(entry.key.split(' ').filter(Boolean))) {
			const list = postings.get(token);
			if (list) list.push(entry.index);
			else postings.set(token, [entry.index]);
		}
	}

	const found = new Set<string>();
	for (const entry of entries) {
		if (entry.key === '') continue;
		const tokens = entry.key.split(' ');
		let candidates: readonly number[] = [];
		for (const token of tokens) {
			const list = postings.get(token) ?? [];
			if (candidates.length === 0 || list.length < candidates.length) candidates = list;
		}
		for (const otherIndex of candidates) {
			if (otherIndex === entry.index) continue;
			const a = Math.min(entry.index, otherIndex);
			const b = Math.max(entry.index, otherIndex);
			const pairKey = `${a}:${b}`;
			if (found.has(pairKey)) continue;
			const left = entries[a].key;
			const right = entries[b].key;
			const paddedLeft = ` ${left} `;
			const paddedRight = ` ${right} `;
			if (
				left === right ||
				paddedLeft.includes(paddedRight) ||
				paddedRight.includes(paddedLeft)
			) {
				found.add(pairKey);
			}
		}
	}

	return [...found]
		.map((key) => key.split(':').map(Number) as [number, number])
		.sort(([a1, b1], [a2, b2]) => a1 - a2 || b1 - b2)
		.map(([a, b]) => ({ a: locations[a], b: locations[b] }));
}
