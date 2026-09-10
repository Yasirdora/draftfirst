/**
 * eDraft Screenwriting Engine character renaming.
 *
 * A rename is a document-wide refactor: every cue whose base name matches —
 * extensions stripped, case ignored — takes the new name, while extensions
 * ((O.S.), (CONT'D)), the dual-dialogue flag, and every other element stay
 * exactly as they were. Pure: the input is never mutated.
 */

import type { Screenplay, ScreenplayElement } from './types.js';

/** A cue's trailing parenthetical run — " (O.S.)", " (WHISPERING)",
   " (V.O.) (PRE-LAP)" — is its extension tail, whatever words it carries;
   the name ends before it. ONE rule, shared by matching and by preserving,
   and the same rule the Mac canonicalises with (EditorState's
   canonicalCharacterName): MARA (WHISPERING) is renamable, and the two
   sides can never disagree about who that means. */
const EXTENSION_TAIL_RE = /(?:\s*\([^)]*\))+\s*$/;

/** Canonical cue-name form: the extension tail comes off, whitespace
   collapses, case canonicalises. "  mara jane " → "MARA JANE";
   "Mary (O.S.)" → "MARY". Empty result means no name carried. */
export function normalizeCueName(name: string): string {
	return name.replace(EXTENSION_TAIL_RE, '').replace(/\s+/g, ' ').trim().toUpperCase();
}

export interface RenameResult {
	/** New element stream — untouched elements keep their identity. */
	elements: ScreenplayElement[];
	/** How many cues took the new name. */
	changed: number;
}

/** The cue's extension tail exactly as written — " (O.S.) (PRE-LAP)" — or ''. */
function cueExtensions(cue: string): string {
	const match = EXTENSION_TAIL_RE.exec(cue.trim());
	return match ? match[0] : '';
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
		const base = normalizeCueName(el.text);
		if (base === '' || base !== target) continue;
		if (changed === 0) elements = elements.slice(); /* copy on first write — no match, no new array */
		elements[i] = { ...el, text: next + cueExtensions(el.text) };
		changed += 1;
	}
	return { elements, changed };
}
