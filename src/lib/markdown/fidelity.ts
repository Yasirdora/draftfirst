/**
 * Fidelity core — pure source comparison for Truth mode.
 *
 * After page (contenteditable) edits, serialise rewrites Markdown.
 * Truth mode compares the baseline source with the serialised result and
 * classifies the change so writers never lose trust silently.
 *
 * No DOM. No network. Safe to unit-test in Node.
 */

export type FidelityStatus =
	/** Byte-identical after light EOL normalisation */
	| 'identical'
	/** Only cosmetic / serialiser style (whitespace, emphasis markers, trailing newline) */
	| 'normalized'
	/** Real content or structure changed (expected after intentional edits) */
	| 'changed'
	/** Content likely lost or structure degraded — soft warn */
	| 'lossy';

export interface DiffHunk {
	/** 0-based line index in the unified view */
	kind: 'equal' | 'remove' | 'add';
	/** Line text without trailing newline */
	text: string;
	/** Line number in before (1-based), if applicable */
	beforeLine?: number;
	/** Line number in after (1-based), if applicable */
	afterLine?: number;
}

export interface FidelityReport {
	status: FidelityStatus;
	before: string;
	after: string;
	hunks: DiffHunk[];
	/** Short human summary for status chrome */
	summary: string;
	/** Show soft warning UI when Truth mode is on */
	warn: boolean;
	/** Counts for badges */
	added: number;
	removed: number;
}

/** Collapse EOL and trim trailing spaces on each line (except hard-break `  `). */
export function normalizeEol(source: string): string {
	return String(source)
		.replace(/\r\n/g, '\n')
		.replace(/\r/g, '\n');
}

/**
 * Cosmetic normalisation: things a honest serialiser may rewrite without
 * changing writer-visible meaning.
 */
export function normalizeCosmetic(source: string): string {
	let text = normalizeEol(source);

	// Trailing newline: serialise always ends with one when non-empty.
	text = text.replace(/\s+$/u, '');
	if (text !== '') text += '\n';

	// Collapse 3+ blank lines (serialise does this).
	text = text.replace(/\n{3,}/g, '\n\n');

	// NBSP → space.
	text = text.replace(/\u00A0/g, ' ');

	// Trailing spaces on lines except hard breaks (exactly two spaces).
	text = text.replace(/[ \t]+$/gm, (match) => (match === '  ' ? '  ' : ''));

	// Emphasis marker style: __ → **, _word_ → *word* for whole-word emphasis only.
	// Keep it conservative — only full-token replacements.
	text = text.replace(/__([^_\n]+?)__/g, '**$1**');
	text = text.replace(/(^|[\s(])_([^_\s][^_\n]*?)_([\s).,;:!?]|$)/g, '$1*$2*$3');

	// Ordered list markers: `1)` → `1.`
	text = text.replace(/^(\s*)(\d+)\)\s+/gm, '$1$2. ');

	// Setext H1/H2 → ATX (serialise only emits ATX).
	text = text.replace(/^(.+)\n=+\s*$/gm, (_, title) => '# ' + String(title).trim());
	text = text.replace(/^(.+)\n-+\s*$/gm, (_, title) => '## ' + String(title).trim());

	// Table divider spacing: |---| → | --- |
	text = text.replace(/\|[ \t]*:?-{3,}:?[ \t]*(?=\|)/g, (cell) => {
		const inner = cell.slice(1).trim();
		return '| ' + inner + ' ';
	});

	return text;
}

/** Strip all Markdown structure to approximate plain text for loss detection. */
export function plainTextSkeleton(source: string): string {
	let text = normalizeEol(source);
	// Fenced code: keep inner text.
	text = text.replace(/```[\w.+-]*\n([\s\S]*?)```/g, '$1');
	// Inline code.
	text = text.replace(/`([^`]+)`/g, '$1');
	// Images → alt.
	text = text.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1');
	// Links → label.
	text = text.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1');
	// Headings / quotes / lists markers.
	text = text.replace(/^#{1,6}\s+/gm, '');
	text = text.replace(/^>\s?/gm, '');
	text = text.replace(/^(\s*)([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?/gm, '$1');
	// Emphasis wrappers.
	text = text.replace(/(\*\*|__|\*|_|~~)(.*?)\1/g, '$2');
	// Table pipes.
	text = text.replace(/\|/g, ' ');
	// Horizontal rules.
	text = text.replace(/^(-{3,}|\*{3,}|_{3,})\s*$/gm, '');
	// Collapse whitespace.
	return text.replace(/\s+/g, ' ').trim().toLowerCase();
}

function splitLines(source: string): string[] {
	const normalized = normalizeEol(source);
	if (normalized === '') return [];
	// Keep trailing empty line representation consistent with split behaviour.
	const endsWithNl = normalized.endsWith('\n');
	const body = endsWithNl ? normalized.slice(0, -1) : normalized;
	return body === '' ? [''] : body.split('\n');
}

/**
 * Myers-inspired O(ND) is overkill for writing docs; use LCS DP for moderate
 * documents and a fast path when identical.
 */
export function diffLines(before: string, after: string): DiffHunk[] {
	const a = splitLines(before);
	const b = splitLines(after);

	if (a.length === 0 && b.length === 0) return [];

	const n = a.length;
	const m = b.length;

	// Cap DP for safety on huge docs — fall back to block replace.
	const MAX = 4000;
	if (n * m > MAX * MAX) {
		const hunks: DiffHunk[] = [];
		for (let i = 0; i < n; i++) hunks.push({ kind: 'remove', text: a[i], beforeLine: i + 1 });
		for (let j = 0; j < m; j++) hunks.push({ kind: 'add', text: b[j], afterLine: j + 1 });
		return hunks;
	}

	const dp: number[][] = Array.from({ length: n + 1 }, () => Array(m + 1).fill(0));
	for (let i = n - 1; i >= 0; i--) {
		for (let j = m - 1; j >= 0; j--) {
			if (a[i] === b[j]) dp[i][j] = dp[i + 1][j + 1] + 1;
			else dp[i][j] = Math.max(dp[i + 1][j], dp[i][j + 1]);
		}
	}

	const hunks: DiffHunk[] = [];
	let i = 0;
	let j = 0;
	while (i < n && j < m) {
		if (a[i] === b[j]) {
			hunks.push({ kind: 'equal', text: a[i], beforeLine: i + 1, afterLine: j + 1 });
			i++;
			j++;
		} else if (dp[i + 1][j] >= dp[i][j + 1]) {
			hunks.push({ kind: 'remove', text: a[i], beforeLine: i + 1 });
			i++;
		} else {
			hunks.push({ kind: 'add', text: b[j], afterLine: j + 1 });
			j++;
		}
	}
	while (i < n) {
		hunks.push({ kind: 'remove', text: a[i], beforeLine: i + 1 });
		i++;
	}
	while (j < m) {
		hunks.push({ kind: 'add', text: b[j], afterLine: j + 1 });
		j++;
	}
	return hunks;
}

function countHunks(hunks: DiffHunk[]): { added: number; removed: number } {
	let added = 0;
	let removed = 0;
	for (const h of hunks) {
		if (h.kind === 'add') added++;
		else if (h.kind === 'remove') removed++;
	}
	return { added, removed };
}

/**
 * Assess fidelity between a baseline source and the current (e.g. serialised) source.
 */
export function assessFidelity(before: string, after: string): FidelityReport {
	const b0 = normalizeEol(before);
	const a0 = normalizeEol(after);

	const hunks = diffLines(b0, a0);
	const { added, removed } = countHunks(hunks);

	// Exact match, or only final trailing newlines differ.
	if (b0 === a0 || b0.replace(/\n+$/, '') === a0.replace(/\n+$/, '')) {
		return {
			status: 'identical',
			before: b0,
			after: a0,
			hunks,
			summary: 'Source matches page',
			warn: false,
			added: 0,
			removed: 0
		};
	}

	if (normalizeCosmetic(b0) === normalizeCosmetic(a0)) {
		return {
			status: 'normalized',
			before: b0,
			after: a0,
			hunks,
			summary: 'Cosmetic rewrite only',
			warn: false,
			added,
			removed
		};
	}

	const plainBefore = plainTextSkeleton(b0);
	const plainAfter = plainTextSkeleton(a0);

	// Lossy: substantial plain-text content disappeared, or many removals with few adds.
	const beforeLen = plainBefore.length;
	const afterLen = plainAfter.length;
	const lostRatio = beforeLen === 0 ? 0 : (beforeLen - afterLen) / beforeLen;
	const contentVanished =
		beforeLen >= 24 && afterLen < beforeLen * 0.55 && removed > added + 1;

	// Link/image targets stripped: labels remain but URLs gone often still keep plain text;
	// detect when many `](` patterns disappear.
	const linksBefore = (b0.match(/\]\(/g) || []).length;
	const linksAfter = (a0.match(/\]\(/g) || []).length;
	const linksLost = linksBefore >= 2 && linksAfter <= linksBefore * 0.4;

	const headingsBefore = (b0.match(/^#{1,6}\s/gm) || []).length;
	const headingsAfter = (a0.match(/^#{1,6}\s/gm) || []).length;
	const headingsLost = headingsBefore >= 2 && headingsAfter === 0;

	if (contentVanished || linksLost || headingsLost || lostRatio > 0.45) {
		return {
			status: 'lossy',
			before: b0,
			after: a0,
			hunks,
			summary: linksLost
				? 'Links may have been simplified'
				: headingsLost
					? 'Headings may have been lost'
					: 'Possible content loss',
			warn: true,
			added,
			removed
		};
	}

	return {
		status: 'changed',
		before: b0,
		after: a0,
		hunks,
		summary:
			added || removed
				? `${removed} removed · ${added} added`
				: 'Source changed',
		warn: false,
		added,
		removed
	};
}

/** Compact hunk list for UI: only changes + limited context. */
export function compactHunks(hunks: DiffHunk[], context = 1, maxChangeLines = 80): DiffHunk[] {
	if (hunks.length === 0) return [];

	const changeIdx: number[] = [];
	for (let i = 0; i < hunks.length; i++) {
		if (hunks[i].kind !== 'equal') changeIdx.push(i);
	}
	if (changeIdx.length === 0) return [];

	const include = new Set<number>();
	for (const idx of changeIdx) {
		for (let k = Math.max(0, idx - context); k <= Math.min(hunks.length - 1, idx + context); k++) {
			include.add(k);
		}
	}

	const out: DiffHunk[] = [];
	let changeLines = 0;
	for (let i = 0; i < hunks.length; i++) {
		if (!include.has(i)) continue;
		if (hunks[i].kind !== 'equal') {
			changeLines++;
			if (changeLines > maxChangeLines) break;
		}
		out.push(hunks[i]);
	}
	return out;
}

/**
 * One independent edit region between trusted baseline and current source —
 * a contiguous run of remove/add lines (no equals in the middle).
 */
export interface TruthChange {
	/** Stable 0-based id within this diff */
	id: number;
	removes: string[];
	adds: string[];
	/** Inclusive start / exclusive end into the full hunks array */
	startHunk: number;
	endHunk: number;
	/** Short human label for the strip */
	summary: string;
}

function clipPreview(text: string, max = 72): string {
	const t = text.replace(/\s+/g, ' ').trim();
	if (t.length <= max) return t || '(empty line)';
	return t.slice(0, max - 1) + '…';
}

/** Human kind label for a change region (calm UI, not git jargon). */
export function changeKindLabel(removes: string[], adds: string[]): string {
	const sample = (removes[0] || adds[0] || '').trim();
	if (/^#{1,6}\s/.test(sample)) return 'Heading';
	if (/^>\s?/.test(sample)) return 'Quote';
	if (/^([-*+]|\d+[.)])\s/.test(sample)) return 'List';
	if (/^\|/.test(sample)) return 'Table';
	if (/^```/.test(sample)) return 'Code';
	if (removes.length && !adds.length) return 'Removed lines';
	if (adds.length && !removes.length) return 'Added lines';
	return 'Text';
}

function changeSummary(removes: string[], adds: string[]): string {
	return changeKindLabel(removes, adds);
}

/** Strip Markdown chrome so change copy reads like prose (Apple-style review). */
export function proseFromLines(lines: string[]): string {
	return lines
		.map((l) =>
			l
				.replace(/^#{1,6}\s+/, '')
				.replace(/^>\s?/, '')
				.replace(/^([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?/, '')
				.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
				.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
				.replace(/(\*\*|__|~~|`)/g, '')
				.trim()
		)
		.filter(Boolean)
		.join(' ')
		.replace(/\s+/g, ' ')
		.trim();
}

function quoteClip(text: string, max = 48): string {
	const t = clipPreview(text, max);
	if (t === '(empty line)' || t === '(empty)') return 'empty text';
	return `“${t}”`;
}

/**
 * Visible snippet for UI — prefer prose; fall back to raw Markdown lines so
 * the user always sees something concrete (never a vague category alone).
 */
export function changeVisibleText(lines: string[], max = 56): string {
	const prose = proseFromLines(lines);
	if (prose) return clipPreview(prose, max);
	const raw = lines.join(' ').replace(/\s+/g, ' ').trim();
	if (raw) return clipPreview(raw, max);
	return '(empty)';
}

const isTokenChar = (ch: string | undefined) =>
	Boolean(ch && /[\p{L}\p{N}_']/u.test(ch));

/**
 * Only the part that actually changed — strip shared prefix/suffix.
 * Snaps to word edges so “world” is preferred over “rld”.
 */
export function minimalEditPair(
	before: string,
	after: string,
	maxPart = 48
): { before: string; after: string } {
	const a = before.normalize('NFC');
	const b = after.normalize('NFC');
	if (a === b) return { before: '', after: '' };

	let start = 0;
	const minLen = Math.min(a.length, b.length);
	while (start < minLen && a[start] === b[start]) start++;

	let endA = a.length;
	let endB = b.length;
	while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) {
		endA--;
		endB--;
	}

	// Expand outward to whole words when a cut lands mid-token.
	let s = start;
	while (s > 0 && isTokenChar(a[s - 1]) && isTokenChar(a[s])) s--;
	// Keep both strings aligned: only expand start if `b` has the same characters.
	if (s < start && b.slice(s, start) === a.slice(s, start)) start = s;
	else s = start;

	while (endA < a.length && isTokenChar(a[endA - 1]) && isTokenChar(a[endA])) endA++;
	while (endB < b.length && isTokenChar(b[endB - 1]) && isTokenChar(b[endB])) endB++;

	let rem = a.slice(start, endA);
	let add = b.slice(start, endB);

	// Pure whitespace / punct chips stay visible
	const show = (part: string) => {
		if (part === '') return '';
		const visible = part.replace(/ /g, '·').replace(/\t/g, '⇥').replace(/\n/g, '↵');
		return clipPreview(visible, maxPart);
	};

	rem = show(rem);
	add = show(add);

	// Degenerate: entire strings differ and are huge — clip wholes
	if (!rem && !add) {
		return {
			before: clipPreview(a, maxPart),
			after: clipPreview(b, maxPart)
		};
	}
	return { before: rem, after: add };
}

/**
 * One-line human description — chips of what changed only.
 */
export function humanChangeDescription(change: TruthChange): string {
	const pair = changeVisualPair(change);
	if (pair.before && pair.after) return `“${pair.before}” → “${pair.after}”`;
	if (pair.before) return `Removed “${pair.before}”`;
	if (pair.after) return `Added “${pair.after}”`;
	return 'Changed';
}

/**
 * Visual review pair — only the word(s)/char(s) that differ, not the whole sentence.
 */
export function changeVisualPair(change: TruthChange): { before: string; after: string } {
	const fullBefore = change.removes.length ? changeVisibleText(change.removes, 240) : '';
	const fullAfter = change.adds.length ? changeVisibleText(change.adds, 240) : '';

	if (!fullBefore && !fullAfter) return { before: '', after: '' };
	if (!fullBefore) return { before: '', after: clipPreview(fullAfter, 48) };
	if (!fullAfter) return { before: clipPreview(fullBefore, 48), after: '' };

	return minimalEditPair(fullBefore, fullAfter, 48);
}

/** Short search needle to locate a change on the typeset page. */
export function changeLocateNeedle(change: TruthChange): string {
	const next = proseFromLines(change.adds);
	if (next.length >= 2) return next.slice(0, 80);
	const prev = proseFromLines(change.removes);
	return prev.slice(0, 80);
}

/** Group line hunks into discrete change regions for selective restore. */
export function groupTruthChanges(hunks: DiffHunk[]): TruthChange[] {
	const changes: TruthChange[] = [];
	let i = 0;
	while (i < hunks.length) {
		if (hunks[i].kind === 'equal') {
			i++;
			continue;
		}
		const startHunk = i;
		const removes: string[] = [];
		const adds: string[] = [];
		while (i < hunks.length && hunks[i].kind !== 'equal') {
			if (hunks[i].kind === 'remove') removes.push(hunks[i].text);
			else adds.push(hunks[i].text);
			i++;
		}
		changes.push({
			id: changes.length,
			removes,
			adds,
			startHunk,
			endHunk: i,
			summary: changeSummary(removes, adds)
		});
	}
	return changes;
}

/**
 * Rebuild a document from baseline vs current, restoring selected change regions
 * to the trusted (baseline) side and keeping the rest as current.
 *
 * @param restoreChangeIds — TruthChange.id values to take from baseline
 */
export function applyTruthRestores(
	before: string,
	after: string,
	restoreChangeIds: Iterable<number>
): string {
	const b0 = normalizeEol(before);
	const a0 = normalizeEol(after);
	const hunks = diffLines(b0, a0);
	const changes = groupTruthChanges(hunks);
	const restore = new Set(restoreChangeIds);

	const hunkToChange = new Map<number, number>();
	for (const c of changes) {
		for (let h = c.startHunk; h < c.endHunk; h++) hunkToChange.set(h, c.id);
	}

	const lines: string[] = [];
	for (let i = 0; i < hunks.length; i++) {
		const h = hunks[i];
		if (h.kind === 'equal') {
			lines.push(h.text);
			continue;
		}
		const cid = hunkToChange.get(i);
		const takeBaseline = cid !== undefined && restore.has(cid);
		if (h.kind === 'remove') {
			if (takeBaseline) lines.push(h.text);
		} else if (h.kind === 'add') {
			if (!takeBaseline) lines.push(h.text);
		}
	}

	let text = lines.join('\n');
	// Prefer trailing newline when either side had one (Markdown habit).
	const wantNl = b0.endsWith('\n') || a0.endsWith('\n');
	if (text !== '' && wantNl && !text.endsWith('\n')) text += '\n';
	if (text === '' && wantNl) text = '\n';
	return text;
}

/** Restore a single change region from baseline into current. */
export function restoreTruthChange(before: string, after: string, changeId: number): string {
	return applyTruthRestores(before, after, [changeId]);
}
