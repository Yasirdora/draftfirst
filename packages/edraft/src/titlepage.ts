/** The title page as lines: migration from the keyed model, and derivation
    back to keyed fields for the surfaces that ask by name (Fountain export,
    DOCX export, the guided sheet). docs/RFC-TITLE-PAGE.md — D1, D3, D8.

    The geometry is the 12pt Courier line grid every screenplay page already
    obeys: textTop 72, lineHeight 12, US Letter height 792. The classic
    keyed renderer anchored the stack at 0.32 × 792 = 253.44pt, which is not
    a grid position; the template below anchors at line 15 (72 + 15 × 12 =
    252pt), so the top stack settles exactly 1.44pt onto the grid — once, at
    migration, pinned by the identity tests. The contact block's classic
    anchor (page height − 72 = 720) IS a grid position (line 54), so contact
    does not move at all. */

import type { TitlePageAlignment, TitlePageLine } from './types.js';

/** Blank lines above the stack's first line: 72 + 15 × 12 = 252pt down. */
export const TITLE_STACK_LEADING_BLANKS = 15;
/** The grid line the contact block's last line sits on: 72 + 54 × 12 = 720. */
export const TITLE_CONTACT_LAST_LINE = 54;

/** The keyed shape documents carried before the line model — migration input. */
export interface LegacyTitlePageEntry {
	key: string;
	values: string[];
}

/** The credit phrases the guided picker offers, mirrored from the Swift
    engine's TitleCredits.StandardCredit. Case-insensitive membership. */
export const STANDARD_CREDIT_PHRASES: readonly string[] = [
	'written by',
	'screenplay by',
	'teleplay by',
	'story by',
	'based on a story by',
	'based on the novel by',
	'adapted from'
];

const blank = (): TitlePageLine => ({ text: '' });
const centre = (text: string, key: string): TitlePageLine => ({ text, key });
const isBlank = (line: TitlePageLine): boolean => line.text.trim() === '';
const nonEmpty = (values: string[]): string[] => values.filter((v) => v.trim() !== '');

/** The classic template, written as lines (D8). Every line the keyed
    renderer would have drawn becomes a line here, at the grid position that
    renderer's arithmetic implies — including the key lines it printed ahead
    of every extra key except Source, and the title in the uppercase the
    renderer forced. Entries with no non-empty values rendered nothing and
    migrate to nothing. */
export function titlePageLinesFromEntries(entries: readonly LegacyTitlePageEntry[]): TitlePageLine[] {
	if (entries.length === 0) return [];
	const find = (key: string): string[] =>
		nonEmpty(
			entries.find((entry) => entry.key.toLowerCase() === key)?.values ?? []
		);
	const lines: TitlePageLine[] = [];
	for (let i = 0; i < TITLE_STACK_LEADING_BLANKS; i++) lines.push(blank());

	for (const value of find('title')) lines.push(centre(value.toUpperCase(), 'Title'));
	lines.push(blank());
	for (const value of find('credit')) lines.push(centre(value, 'Credit'));
	lines.push(blank());
	for (const value of find('author')) lines.push(centre(value, 'Author'));

	for (const entry of entries) {
		const key = entry.key.toLowerCase();
		if (key === 'title' || key === 'credit' || key === 'author' || key === 'contact') continue;
		const values = nonEmpty(entry.values);
		if (values.length === 0) continue;
		lines.push(blank());
		if (key !== 'source') lines.push(centre(entry.key, entry.key));
		for (const value of values) lines.push(centre(value, entry.key));
	}

	const contact = find('contact');
	if (contact.length > 0) {
		const firstLine = TITLE_CONTACT_LAST_LINE - (contact.length - 1);
		while (lines.length < firstLine) lines.push(blank());
		for (const value of contact) {
			lines.push({ text: value, alignment: 'left', key: 'Contact' });
		}
	}

	while (lines.length > 0 && isBlank(lines[lines.length - 1])) lines.pop();
	return lines;
}

/** One keyed field recovered from the lines — Fountain export, DOCX export
    and the guided sheet all ask by name, so derivation answers by name. */
export interface DerivedTitlePageEntry {
	key: string;
	values: string[];
}

/** The inverse of the template, generalised to lines that came from
    anywhere (D3/D7). Annotation-first: a line carrying a key belongs to
    that key. Unannotated lines fall to the heuristics — the opening
    contiguous run is the title, a standard credit phrase opens the credit,
    the run under it is the authors, a trailing left-aligned block is the
    contact. Anything still unclaimed folds into the previous entry as a
    continuation value, because no surface may lose a line silently. */
export function deriveTitlePage(lines: readonly TitlePageLine[]): DerivedTitlePageEntry[] {
	const entries: DerivedTitlePageEntry[] = [];
	const byKey = new Map<string, DerivedTitlePageEntry>();
	/** Which entry owns each line — pass 3's fold walks by ownership. */
	const owners = new Map<number, DerivedTitlePageEntry>();
	const claimAt = (index: number, key: string): void => {
		const line = lines[index];
		if (line === undefined) return;
		const needle = key.toLowerCase();
		let entry = byKey.get(needle);
		if (!entry) {
			entry = { key, values: [] };
			byKey.set(needle, entry);
			entries.push(entry);
		}
		entry.values.push(text(line));
		owners.set(index, entry);
	};

	const text = (line: TitlePageLine): string => line.text.trim();
	const alignmentOf = (line: TitlePageLine): TitlePageAlignment => line.alignment ?? 'center';

	/* Pass 1 — annotated lines group under their keys. A line whose text is
	   its own key, standing first in a non-Source group, is the label the
	   template prints above the values, not a value itself — without this
	   the serialise → parse cycle would grow a copy of the key on every
	   round trip. */
	const groups = new Map<string, number[]>();
	const keyNames = new Map<string, string>();
	/** Label lines — accounted for, carrying no value, exempt from the fold. */
	const labelLines = new Set<number>();
	for (const [index, line] of lines.entries()) {
		if (isBlank(line) || line.key === undefined || line.key.trim() === '') continue;
		const key = line.key.trim();
		const needle = key.toLowerCase();
		if (!groups.has(needle)) {
			groups.set(needle, []);
			keyNames.set(needle, key);
		}
		groups.get(needle)?.push(index);
	}
	for (const [needle, indexes] of groups) {
		const key = keyNames.get(needle);
		if (key === undefined) continue;
		const firstIndex = indexes[0];
		const first = firstIndex === undefined ? undefined : lines[firstIndex];
		const labelled =
			firstIndex !== undefined &&
			needle !== 'source' &&
			indexes.length > 1 &&
			first !== undefined &&
			text(first).toLowerCase() === needle;
		if (labelled) labelLines.add(firstIndex);
		for (const index of indexes.slice(labelled ? 1 : 0)) claimAt(index, key);
	}

	/* Pass 2 — heuristics claim the lines no annotation did, only for keys
	   the annotations did not already provide. */
	const free = (index: number): boolean => {
		const line = lines[index];
		return line !== undefined && !isBlank(line) && !owners.has(index);
	};
	const has = (key: string): boolean => byKey.has(key);
	const isCreditPhrase = (line: TitlePageLine): boolean =>
		STANDARD_CREDIT_PHRASES.includes(text(line).toLowerCase());
	const contiguousFrom = (start: number): number[] => {
		const claimed: number[] = [];
		for (let i = start; i < lines.length && free(i); i++) claimed.push(i);
		return claimed;
	};

	if (!has('title')) {
		const start = lines.findIndex((_, index) => free(index));
		if (start >= 0) for (const index of contiguousFrom(start)) claimAt(index, 'Title');
	}
	if (!has('credit')) {
		const at = lines.findIndex((line, index) => free(index) && isCreditPhrase(line));
		if (at >= 0) claimAt(at, 'Credit');
	}
	if (!has('author') && has('credit')) {
		const creditAt = lines.findIndex(
			(line, index) => owners.get(index) === byKey.get('credit') && isCreditPhrase(line)
		);
		if (creditAt >= 0) for (const index of contiguousFrom(creditAt + 1)) claimAt(index, 'Author');
	}
	if (!has('contact')) {
		const trailing: number[] = [];
		for (let i = lines.length - 1; i >= 0; i--) {
			const line = lines[i];
			if (line === undefined) continue;
			if (isBlank(line)) {
				if (trailing.length > 0) break;
				continue;
			}
			/* The block must reach the page's end: a left line with non-left
			   content below it is not a contact block. */
			if (free(i) && alignmentOf(line) === 'left') trailing.unshift(i);
			else break;
		}
		for (const index of trailing) claimAt(index, 'Contact');
	}

	/* Pass 3 — nothing is lost: an unclaimed line continues the nearest
	   entry above it. */
	let last: DerivedTitlePageEntry | undefined;
	for (const [index, line] of lines.entries()) {
		if (isBlank(line) || labelLines.has(index)) continue;
		const owner = owners.get(index);
		if (owner) {
			last = owner;
			continue;
		}
		if (last) {
			last.values.push(text(line));
			owners.set(index, last);
		} else {
			claimAt(index, 'Title');
			last = byKey.get('title');
		}
	}

	return entries;
}

/** What the guided surfaces ask most: the values under one key, derived. */
export function titlePageValues(lines: readonly TitlePageLine[], key: string): string[] {
	const needle = key.toLowerCase();
	return (
		deriveTitlePage(lines).find((entry) => entry.key.toLowerCase() === needle)?.values ?? []
	);
}
