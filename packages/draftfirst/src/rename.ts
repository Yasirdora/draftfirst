/**
 * Draft First Screenwriting Engine character renaming.
 *
 * A rename is a document-wide refactor: every cue whose base name matches —
 * extensions stripped, case ignored — takes the new name, while extensions
 * ((O.S.), (CONT'D)), the dual-dialogue flag, and every other element stay
 * exactly as they were. Pure: the input is never mutated.
 */

import { CUE_EXTENSION_RE, stripCueExtensions } from './smarttype.js';
import type { Screenplay, ScreenplayElement } from './types.js';

/** Canonical cue-name form: an open paren begins an extension, so the name
   ends before it; whitespace collapses, case canonicalises. "  mara jane " →
   "MARA JANE"; "Mary (O.S.)" → "MARY". Empty result means no name carried. */
export function normalizeCueName(name: string): string {
	return name.replace(/\(.*/, '').replace(/\s+/g, ' ').trim().toUpperCase();
}

export interface RenameResult {
	/** New element stream — untouched elements keep their identity. */
	elements: ScreenplayElement[];
	/** How many cues took the new name. */
	changed: number;
}

/** The cue's extension tail in reading form — " (O.S.) (PRE-LAP)" — or ''. */
function cueExtensions(cue: string): string {
	const matches = cue.match(CUE_EXTENSION_RE);
	if (!matches) return '';
	return matches.map((m) => ` ${m.trim()}`).join('');
}

/** Rename one character across the whole document. Matching is by base name
   only — renameCharacter(script, 'MARA', 'MARY') turns MARA, Mara, and
   MARA (O.S.) into MARY / MARY (O.S.), but never MARIAM, and never the name
   spoken inside dialogue, action, or scene prose. Renaming into an existing
   name IS the merge: the two casts simply become one. */
export function renameCharacter(script: Screenplay, from: string, to: string): RenameResult {
	const target = normalizeCueName(from);
	const next = normalizeCueName(to);
	if (target === '' || next === '' || target === next) {
		return { elements: script.elements, changed: 0 };
	}
	let elements = script.elements;
	let changed = 0;
	for (let i = 0; i < elements.length; i++) {
		const el = elements[i];
		if (el.type !== 'character') continue;
		const base = stripCueExtensions(el.text);
		if (base === '' || base.toUpperCase() !== target) continue;
		if (changed === 0) elements = elements.slice(); /* copy on first write — no match, no new array */
		elements[i] = { ...el, text: next + cueExtensions(el.text) };
		changed += 1;
	}
	return { elements, changed };
}
