/**
 * Source syntax highlighting for the Markdown editor backdrop.
 *
 * The source surface is a plain <textarea> whose text is transparent; this
 * module turns the same Markdown into escaped, span-wrapped HTML for the
 * <pre> that sits behind it. The backdrop is purely cosmetic — the textarea
 * holds the truth — so the tokenizer is deliberately conservative: line-scoped
 * (fences are the only cross-line state), color-only (no metric changes), and
 * every unmatched byte passes through escaped and untouched.
 *
 * Pure and Node-testable — no DOM, no Svelte, no dependencies.
 */

const RE_FENCE = /^\s{0,3}(`{3,}|~{3,})/;
const RE_HEADING = /^(\s{0,3})(#{1,6})(?=\s|$)/;
const RE_SETEXT = /^\s{0,3}=+\s*$/;
const RE_HR = /^\s{0,3}(?:([*\-_])\s*){3,}$/;
const RE_REFDEF = /^(\s{0,3})(\[\^?[^\]\n]+\]:)(\s*)(.*)$/;
const RE_QUOTE = /^(\s{0,3}(?:>[ \t]?)+)(.*)$/;
const RE_LIST = /^(\s{0,3})([-*+]|\d{1,9}[.)])([ \t]+)(.*)$/;
const RE_TASK = /^(\[[ xX]\])([ \t]+)(.*)$/;
const RE_TABLE = /^\s{0,3}\|/;

/** Leftmost match wins: code spans shield their content from further parsing. */
const RE_INLINE =
	/(`+[^`\n]*`+)|(!?\[[^\]\n]*\]\([^)\n]*\))|(\[\^[^\]\n]+\])|(\*\*[^*\n]+\*\*|__[^_\n]+__)|(\*[^*\n]+\*)|(~~[^~\n]+~~)/g;

function esc(text: string): string {
	return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function seg(text: string, cls: string): string {
	return `<span class="${cls}">${esc(text)}</span>`;
}

function token(match: RegExpExecArray): string {
	const [raw, code, link, fn, strong, em, strike] = match;
	if (code) return seg(raw, 'tk-code');
	if (link) {
		const open = raw.startsWith('!') ? '![' : '[';
		const mid = raw.indexOf('](');
		const label = raw.slice(open.length, mid);
		const url = raw.slice(mid + 2, -1);
		return (
			seg(open, 'tk-delim') +
			seg(label, 'tk-link') +
			seg('](', 'tk-delim') +
			seg(url, 'tk-url') +
			seg(')', 'tk-delim')
		);
	}
	if (fn) return seg(raw, 'tk-fn');
	if (strong) {
		const d = raw.startsWith('__') ? '__' : '**';
		return seg(d, 'tk-delim') + esc(raw.slice(2, -2)) + seg(d, 'tk-delim');
	}
	if (em) return seg('*', 'tk-delim') + esc(raw.slice(1, -1)) + seg('*', 'tk-delim');
	if (strike) return seg('~~', 'tk-delim') + esc(raw.slice(2, -2)) + seg('~~', 'tk-delim');
	return esc(raw);
}

function inline(text: string): string {
	let out = '';
	let last = 0;
	RE_INLINE.lastIndex = 0;
	for (let m = RE_INLINE.exec(text); m; m = RE_INLINE.exec(text)) {
		out += esc(text.slice(last, m.index)) + token(m);
		last = m.index + m[0].length;
	}
	return out + esc(text.slice(last));
}

function line(input: string): string {
	let m: RegExpMatchArray | null;
	if ((m = input.match(RE_HEADING))) {
		const [full, indent, hashes] = m;
		return esc(indent) + seg(hashes, 'tk-delim') + seg(input.slice(full.length), 'tk-heading');
	}
	if (RE_SETEXT.test(input) || RE_HR.test(input)) return seg(input, 'tk-delim');
	if ((m = input.match(RE_REFDEF))) {
		const [, indent, label, ws, rest] = m;
		return esc(indent) + seg(label, label.startsWith('[^') ? 'tk-fn' : 'tk-link') + esc(ws) + seg(rest, 'tk-url');
	}
	if ((m = input.match(RE_QUOTE))) {
		const [, markers, rest] = m;
		return seg(markers, 'tk-delim') + inline(rest);
	}
	if ((m = input.match(RE_LIST))) {
		const [, indent, marker, ws, rest] = m;
		const out = esc(indent) + seg(marker, 'tk-delim') + esc(ws);
		const task = rest.match(RE_TASK);
		if (task) return out + seg(task[1], 'tk-delim') + esc(task[2]) + inline(task[3]);
		return out + inline(rest);
	}
	if (RE_TABLE.test(input)) {
		return input
			.split('|')
			.map((cell, i) => (i === 0 ? esc(cell) : seg('|', 'tk-delim') + esc(cell)))
			.join('');
	}
	return inline(input);
}

/**
 * Markdown source → escaped highlight HTML for the backdrop <pre>.
 * A trailing zero-width space keeps the final (visually empty) line's height
 * in sync with the textarea, which always shows a line for a trailing \n.
 */
export function highlightSource(source: string): string {
	let inFence = false;
	let fenceChar = '';
	const out = source.split('\n').map((ln) => {
		const fence = ln.match(RE_FENCE);
		if (fence) {
			const ch = fence[1][0];
			if (!inFence) {
				inFence = true;
				fenceChar = ch;
				return seg(ln, 'tk-fence');
			}
			if (ch === fenceChar) {
				inFence = false;
				return seg(ln, 'tk-fence');
			}
			return seg(ln, 'tk-code-block');
		}
		if (inFence) return seg(ln, 'tk-code-block');
		return line(ln);
	});
	/** Zero-width space, built not pasted — invisible characters don't belong in source. */
	const SENTINEL = String.fromCharCode(0x200b);
	let html = out.join('\n');
	if (source === '' || source.endsWith('\n')) html += SENTINEL;
	return html;
}
