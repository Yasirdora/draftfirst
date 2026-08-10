/**
 * Smart keys for the Markdown source textarea.
 *
 * Enter continues the structure you are in — lists, tasks, blockquotes —
 * and ends it when the item is empty. Shift+Enter writes a real Markdown
 * hard break (two trailing spaces) so the preview shows the line break.
 * Tab indents; Shift+Tab outdents.
 *
 * Pure and Node-testable: every function takes the textarea value + selection
 * and returns the full replacement text plus the selection to restore.
 * The component owns the DOM; this module owns the decisions.
 */

export interface SourceEdit {
	/** Full replacement text for the textarea. */
	text: string;
	selectionStart: number;
	selectionEnd: number;
}

const LIST_MARKER = /^(\s*)([-+*]|\d{1,9}[.)])(\s+)(\[[ xX]\]\s+)?/;
const QUOTE_PREFIX = /^(\s*(?:>\s*)+)/;

function lineStartOf(value: string, pos: number): number {
	return value.lastIndexOf('\n', pos - 1) + 1;
}

/**
 * Continue a list or blockquote on Enter. Returns null when the caret is not
 * on a continuable line — the caller then lets the default newline happen.
 *
 * Empty item / empty quote line: remove the marker and leave the rest of the
 * line as plain text (the standard "press Enter twice to get out" escape).
 */
export function continueOnEnter(value: string, pos: number): SourceEdit | null {
	const lineStart = lineStartOf(value, pos);
	const before = value.slice(lineStart, pos);

	const list = LIST_MARKER.exec(before);
	if (list) {
		const rest = before.slice(list[0].length);
		if (rest.trim() === '') {
			return {
				text: value.slice(0, lineStart) + value.slice(pos),
				selectionStart: lineStart,
				selectionEnd: lineStart
			};
		}
		let next = list[1] + list[2] + list[3];
		if (/\d/.test(list[2])) {
			const number = parseInt(list[2], 10) + 1;
			next = list[1] + number + list[2].slice(-1) + list[3];
		}
		if (list[4]) next += '[ ] ';
		const insert = '\n' + next;
		return {
			text: value.slice(0, pos) + insert + value.slice(pos),
			selectionStart: pos + insert.length,
			selectionEnd: pos + insert.length
		};
	}

	const quote = QUOTE_PREFIX.exec(before);
	if (quote) {
		const rest = before.slice(quote[1].length);
		if (rest.trim() === '') {
			return {
				text: value.slice(0, lineStart) + value.slice(pos),
				selectionStart: lineStart,
				selectionEnd: lineStart
			};
		}
		const insert = '\n' + quote[1];
		return {
			text: value.slice(0, pos) + insert + value.slice(pos),
			selectionStart: pos + insert.length,
			selectionEnd: pos + insert.length
		};
	}

	return null;
}

/**
 * Shift+Enter — a real hard break: two trailing spaces, newline, then the
 * continuation prefix (the quote markers, or the line's leading indent).
 */
export function hardBreak(value: string, pos: number): SourceEdit {
	const lineStart = lineStartOf(value, pos);
	const before = value.slice(lineStart, pos);
	const quote = QUOTE_PREFIX.exec(before);
	const indent = quote ? quote[1] : (/^\s*/.exec(before)?.[0] ?? '');
	const insert = '  \n' + indent;
	return {
		text: value.slice(0, pos) + insert + value.slice(pos),
		selectionStart: pos + insert.length,
		selectionEnd: pos + insert.length
	};
}

/**
 * Tab / Shift+Tab. Collapsed caret: insert two spaces. Selection: indent or
 * outdent every touched line by two spaces and keep the block selected.
 */
export function indentOnTab(
	value: string,
	start: number,
	end: number,
	shiftKey: boolean
): SourceEdit {
	if (start === end) {
		const text = value.slice(0, start) + '  ' + value.slice(end);
		return { text, selectionStart: start + 2, selectionEnd: start + 2 };
	}
	const lineStart = lineStartOf(value, start);
	const block = value.slice(lineStart, end);
	const shifted = shiftKey ? block.replace(/^ {1,2}/gm, '') : block.replace(/^/gm, '  ');
	return {
		text: value.slice(0, lineStart) + shifted + value.slice(end),
		selectionStart: lineStart,
		selectionEnd: lineStart + shifted.length
	};
}
