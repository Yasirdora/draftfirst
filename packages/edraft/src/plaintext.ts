/**
 * Plain-text and paste import. Handles the two shapes plain text arrives in:
 * typewriter layout (whitespace indents, wrapped lines, form feeds) and
 * reflowed prose (no layout at all — the classifier's shape rules carry it).
 *
 * Pagination artifacts of a printed script — page numbers, loose scene
 * numbers, draft stamps, revision marks, (MORE), CONTINUED — are stripped
 * and counted in the report, never silently.
 */

import { classifyLines, finalizeImport } from './classify.js';
import type { ImportResult, RawLine } from './classify.js';
import { isEndActCard } from './acts.js';

export const DEFAULT_MAX_TEXT_SOURCE_CHARACTERS: number = 16 * 1024 * 1024;

/** The source text is beyond what an import may hold. */
export class PlainTextImportError extends RangeError {
	constructor(message: string) {
		super(message);
		this.name = 'PlainTextImportError';
	}
}

export interface PlainTextImportOptions {
	/** Refuse sources longer than this. Default 16 M characters. */
	maxSourceCharacters?: number;
	/** Report label — 'text' for files, 'paste' for the clipboard. */
	format?: string;
}

/* artifacts of a printed page, meaningful only to a reader of paper */
const PAGE_NUMBER = /^\d{1,4}\.?$/;
/* the scene number set loose from its heading: lettered by the production
   ("4A", corpus-6; "57A", episode-101; "A1", lalaland ×42) or printed as the
   twin the page carries twice ("1 1", whiplash ×134; "1A 1A", foryourcon) —
   the pair matches only when both numbers are equal */
const LETTERED_NUMBER = /^(?:\d{1,4}[A-Z]|[A-Z]\d{1,4})\.?$/;
const PAIRED_NUMBER = /^(\d{1,4}[A-Z]?) +\1\.?$/;
const MORE = /^\(MORE\)$/i;
const CONTD = /^\(CONT['’]?D\)$/i;
const CONTINUED = /^\(?CONTINUED\)?[.:]?$/i;

/* the production's page footer — the draft's colour, date and page:
   "Pink (9/10/2013) 2" (whiplash ×112), "GG- Yellow Revisions 9/27/13 4."
   (gone-girl ×176), "10/29/14 / 2." (foryourcon ×111), "Revision 2."
   (lalaland ×84), "The Irishman D1-5 SZ 9.15.09 2." (pasted-26 ×132),
   "FINAL SHOOTING SCRIPT Pink 7.25.06" (corpus-6 ×23), "GREEN REVISIONS
   12/14/19" (episode-101 ×12) — 650 witnesses, every one a stamp. The
   two-digit year must not eat a following digit, or a bare four-digit-year
   date ("1/5/1999", a title-page line) reads as date-plus-page */
const STAMP_DATE = /\d{1,2}[./]\d{1,2}[./](?:\d{4}|\d{2}(?!\d))/;
const STAMP_MARKER =
	/\b(?:REVISED|REVISIONS?|DRAFT|SCRIPT|SHOOTING|PRODUCTION|FINAL|FULL|PINK|BLUE|WHITE|GREEN|YELLOW|GOLDENROD)\b/i;
const STAMP_CODE = /\b[A-Z]{1,4}-?\d+(?:-\d+)*\b/;
const STAMP_REVISIONS = /^Revisions? \d+\.?$/i;
const STAMP_DATE_PAGE = /^\d{1,2}[./]\d{1,2}[./](?:\d{4}|\d{2}(?!\d))\s*\/?\s*\d{1,4}\.?$/;

/** Whether the line is a production's page footer — draft colour, date, page. */
function isDraftStamp(text: string): boolean {
	if (text.length > 64) return false;
	if (STAMP_REVISIONS.test(text) || STAMP_DATE_PAGE.test(text)) return true;
	if (!STAMP_DATE.test(text)) return false;
	if (!STAMP_MARKER.test(text) && !STAMP_CODE.test(text)) return false;
	/* prose guard: a stamp is furniture tokens and title words only, so no
	   all-lowercase word of four letters lives in one — a sentence carrying
	   a date ("He delivered the FINAL DRAFT on 9/10/2013, late.") is prose,
	   and stays. The guard saves no corpus line; it exists for the next one */
	return !text
		.split(/\s+/)
		.some((token) => /^[a-z]{4,}$/.test(token.replace(/^[^A-Za-z]+|[^A-Za-z]+$/g, '')));
}

/* a revision's asterisk rides the revised line's tail — "AMY wakes, turns,
   gives a look of alarm.*" (gone-girl ×1,426), "TRUMPETER #2 **" (whiplash
   ×21) — or stands alone in the margin on its own line (corpus-6 ×115) */
const REVISION_STAR = /\s?\*{1,2}$/;

/**
 * The line without its trailing revision asterisk, or undefined when the
 * line keeps its ending: a body that still holds a `*` is carrying the
 * emphasis marker's own tail ("**bold**"), which is formatting, never a
 * revision mark.
 */
function stripRevisionStar(text: string): string | undefined {
	const star = REVISION_STAR.exec(text);
	if (star === null) return undefined;
	const body = text.slice(0, star.index).trimEnd();
	if (body.includes('*')) return undefined;
	return body;
}

/** Whether the line is furniture of the printed page — page number, loose
   scene number, draft stamp, (MORE), CONTINUED. */
export function isPaginationArtifact(text: string): boolean {
	return (
		PAGE_NUMBER.test(text) ||
		LETTERED_NUMBER.test(text) ||
		PAIRED_NUMBER.test(text) ||
		MORE.test(text) ||
		CONTD.test(text) ||
		CONTINUED.test(text) ||
		isDraftStamp(text)
	);
}

const TYPEWRITER_TAB_INCHES = 0.8;
const TYPEWRITER_SPACE_INCHES = 0.1;

/* The marked card (corpus: gone-girl ×24, emilia-perez ×4, episode-101 ×2,
   from-the-black ×6): a marker line opens the card, then its content in
   witnessed order — a date line, a time line, and one all-caps line that is
   the card's message and closes it. The first prose line closes the card
   unread. Two shapes carry no message: a marker whose content is prose
   (from-the-black's "Harvard University / Fall 2003", which closes the card
   and types as action — the accepted loss), and the bare time stamp: no
   witnessed card follows a time-only opening with a message, so after a
   time line with no date above it the message slot is shut — the all-caps
   line there is the next cue (from-the-black's "9:48 PM / MARK (V.O.)"),
   never the card's text. A marker carrying its content on the same line
   ("INSERT CHYRON: 1994") is the whole card at once. */
const TITLE_CARD_MARKER = /^(?:TITLE(?:\s+CARD)?|SUPER|INSERT\s+CHYRON)\s*:\s*(.*)$/i;
const CARD_DATE = /^[A-Za-z]+,? \d{1,2}(?:st|nd|rd|th)?,? \d{4}[,.]?$/;
const CARD_TIME = /^\d{1,2}:\d{2}\s*(?:[AP]\.?M\.?)?$/i;

/** An all-caps line, the card's message shape — "ONE DAY GONE". */
function isCardMessage(text: string): boolean {
	return /[A-Z]/.test(text) && text === text.toUpperCase();
}

function leadingIndentInches(text: string): number {
	const lead = /^[\t ]*/.exec(text)?.[0] ?? '';
	let inches = 0;
	for (const char of lead) inches += char === '\t' ? TYPEWRITER_TAB_INCHES : TYPEWRITER_SPACE_INCHES;
	return Math.round(inches * 100) / 100;
}

/**
 * Import plain text (a .txt file, or pasted clipboard content) into a
 * classified screenplay plus its review report.
 */
export function importPlainText(source: string, options: PlainTextImportOptions = {}): ImportResult {
	const max = options.maxSourceCharacters ?? DEFAULT_MAX_TEXT_SOURCE_CHARACTERS;
	if (source.length > max) {
		throw new PlainTextImportError(`source holds ${source.length} characters — over the ${max} limit`);
	}

	const rawLines: RawLine[] = [];
	let stripped = 0;
	let endCards = 0;
	let attached = false;
	let pageBreakPending = false;
	let cardOpen = false;
	let cardHasDate = false;
	let cardSawTime = false;

	/* a stray NUL is a UTF-16 paste leak, never text (pasted-26 ×199) */
	for (const physicalLine of source.replace(/\0/g, '').replace(/\r\n?/g, '\n').split('\n')) {
		/* a form feed is a hard page break; the next content line starts a page */
		const pageSegments = physicalLine.split('\f');
		for (let s = 0; s < pageSegments.length; s++) {
			if (s > 0) {
				pageBreakPending = true;
				attached = false;
			}
			const segment = pageSegments[s];
			if (segment === undefined) continue;
			const trimmed = segment.trim();
			if (trimmed === '') {
				attached = false;
				cardOpen = false;
				continue;
			}
			/* the revision mark is furniture riding on content, not content:
			   it comes off before every other test, and a bare mark drops the
			   way (MORE) does — the thought under way continues across it */
			const text = stripRevisionStar(trimmed) ?? trimmed;
			if (text === '') {
				stripped++;
				continue;
			}
			if (isPaginationArtifact(text)) {
				stripped++;
				continue; /* attachment survives — (MORE) splits a speech, not a thought */
			}
			if (isEndActCard(text)) {
				/* an act ends where the next one begins, so the closing card is
				   furniture (RFC-ACT-BREAK §5) — and a hard boundary: unlike
				   (MORE), no thought continues across it, so attachment dies here */
				endCards++;
				attached = false;
				cardOpen = false;
				continue;
			}
			const cardMarker = TITLE_CARD_MARKER.exec(text);
			if (cardMarker) {
				/* the marker is the card's meaning, not its text — the lines
				   it opens print centered, and nothing continues across it */
				attached = false;
				const inline = (cardMarker[1] ?? '').trim();
				if (inline === '') {
					cardOpen = true;
					cardHasDate = false;
					cardSawTime = false;
				} else {
					rawLines.push({ text: inline, align: 'center' });
				}
				continue;
			}
			if (cardOpen) {
				if (CARD_DATE.test(text)) {
					rawLines.push({ text, align: 'center' });
					cardHasDate = true;
					continue;
				}
				if (CARD_TIME.test(text)) {
					rawLines.push({ text, align: 'center' });
					cardSawTime = true;
					continue;
				}
				/* the message slot: open at the marker and under a date —
				   shut after a bare time stamp, where the caps line is the
				   next speaker, not the card's text */
				if (isCardMessage(text) && (cardHasDate || !cardSawTime)) {
					rawLines.push({ text, align: 'center' });
					cardOpen = false;
					continue;
				}
				cardOpen = false; /* the first prose line closes the card */
			}
			const line: RawLine = { text: text.replace(/\t/g, ' ').replace(/ {2,}/g, ' ') };
			const indent = leadingIndentInches(segment);
			if (indent > 0) line.indentInches = indent;
			if (attached) line.attached = true;
			if (pageBreakPending) {
				line.pageBreak = true;
				pageBreakPending = false;
			}
			rawLines.push(line);
			attached = true;
		}
	}

	const warnings: string[] = [];
	if (stripped > 0) {
		warnings.push(
			`stripped ${stripped} pagination artifact(s) — page numbers, scene-number furniture, draft stamps, revision marks, (MORE), CONTINUED`
		);
	}
	if (endCards > 0) {
		warnings.push(`dropped ${endCards} end-of-act card(s) — an act ends where the next one begins`);
	}
	if (rawLines.length === 0) warnings.push('no text found in the source');

	return finalizeImport(classifyLines(rawLines), options.format ?? 'text', warnings);
}
