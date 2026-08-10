// @ts-nocheck — ported pure core; behavior-preserving extract from writing-desk.html
/**
 * EDIT-CORE — source-text formatting toggles for the Markdown surface.
 *
 * Every function takes (text, start, end) and returns { text, start, end }.
 * Toolbar buttons and keyboard shortcuts share this path so they stay in sync.
 * Pure string transforms — no DOM.
 */

/**
 * Delimiters per mark, preferred first. Markdown gives bold and italic two
 * spellings each, which is not decoration here: inserting `*` next to an
 * existing `*` produces markup that means something else, so the alternate
 * is used whenever the neighbouring character would create that ambiguity.
 */
export const MARKS = {
  bold: ['**', '__'],
  italic: ['*', '_'],
  strike: ['~~'],
  code: ['`']
};

/** Is `md` sitting at this index, and is it that mark rather than a longer one? */
function isMarkAt(text, index, md) {
  if (index < 0 || text.substr(index, md.length) !== md) return false;
  if (md.length === 1 && (md === '*' || md === '_')) {
    return text[index - 1] !== md && text[index + 1] !== md;
  }
  return true;
}

/** The pair of delimiters surrounding the caret, if any, within one paragraph. */
function findEnclosing(text, start, end, md) {
  let left = -1;
  for (let i = start - md.length; i >= 0; i--) {
    if (text[i] === '\n' && text[i - 1] === '\n') break;
    if (isMarkAt(text, i, md)) { left = i; break; }
  }
  if (left === -1) return null;

  let right = -1;
  for (let i = end; i <= text.length - md.length; i++) {
    if (text[i] === '\n' && text[i + 1] === '\n') break;
    if (isMarkAt(text, i, md)) { right = i; break; }
  }
  if (right === -1) return null;

  return { left, right };
}

/*
   Both of these have to ask isMarkAt rather than compare substrings. The
   second asterisk of a `**` pair looks exactly like an italic marker, so a
   selection inside bold text would otherwise report itself as italic too —
   and pressing Italic would strip one asterisk from each side.
*/
const wrappedInside = (text, start, end, md) => {
  const selected = text.slice(start, end);
  return selected.length >= 2 * md.length
    && selected.slice(0, md.length) === md
    && selected.slice(-md.length) === md
    && isMarkAt(text, start, md)
    && isMarkAt(text, end - md.length, md);
};

const wrappedOutside = (text, start, end, md) =>
  start >= md.length
  && text.slice(start - md.length, start) === md
  && text.slice(end, end + md.length) === md
  && isMarkAt(text, start - md.length, md)
  && isMarkAt(text, end, md);

/** Which inline marks apply where the caret is — what the toolbar lights up. */
export function inlineMarks(text, start, end) {
  const active = {};
  for (const kind of Object.keys(MARKS)) {
    active[kind] = MARKS[kind].some((md) =>
      wrappedInside(text, start, end, md)
      || wrappedOutside(text, start, end, md)
      || Boolean(findEnclosing(text, start, end, md)));
  }
  active.link = Boolean(findLink(text, start));
  return active;
}

/** Where the writable text of a line begins, past any block marker. */
export function contentStart(text, position) {
  const from = text.lastIndexOf('\n', position - 1) + 1;
  let to = text.indexOf('\n', from);
  if (to === -1) to = text.length;
  return from + BLOCK_PREFIX.exec(text.slice(from, to))[0].length;
}

/**
 * Pull a selection in off the things emphasis must not swallow: surrounding
 * whitespace, and any block marker at the start of the line.
 *
 * Selecting a whole heading and pressing Bold is the case that matters. The
 * selection carries a trailing newline and the leading `## `, and wrapping
 * that literally gives `**## Title\n**` — a closing marker on the next line
 * and a heading that is no longer a heading.
 */
export function tidySelection(text, start, end) {
  while (start < end && /\s/.test(text[start])) start++;
  while (end > start && /\s/.test(text[end - 1])) end--;

  const content = contentStart(text, start);
  if (start < content) start = Math.min(content, end);

  return { start, end };
}

/** A selection over several lines marks each line, never across the breaks. */
function toggleMarkAcrossLines(text, start, end, kind) {
  const lines = text.slice(start, end).split('\n');

  const marked = lines.map((line) => {
    if (line.trim() === '') return line;
    const tidy = tidySelection(line, 0, line.length);
    if (tidy.start >= tidy.end) return line;
    return toggleMark(line, tidy.start, tidy.end, kind).text;
  }).join('\n');

  return { text: text.slice(0, start) + marked + text.slice(end), start, end: start + marked.length };
}

/** Add the mark, or take it away if it is already there. */
export function toggleMark(text, start, end, kind) {
  if (start !== end) {
    const tidy = tidySelection(text, start, end);

    if (tidy.start >= tidy.end) {                 // nothing but whitespace
      return { text, start: tidy.start, end: tidy.start };
    }

    if (text.slice(tidy.start, tidy.end).indexOf('\n') !== -1) {
      return toggleMarkAcrossLines(text, tidy.start, tidy.end, kind);
    }

    start = tidy.start;
    end = tidy.end;
  }

  const options = MARKS[kind];
  const selected = text.slice(start, end);

  for (const md of options) {
    const n = md.length;

    /* the markers are inside the selection */
    if (wrappedInside(text, start, end, md)) {
      const inner = selected.slice(n, -n);
      return { text: text.slice(0, start) + inner + text.slice(end), start, end: start + inner.length };
    }

    /* the markers are just outside it */
    if (wrappedOutside(text, start, end, md)) {
      return {
        text: text.slice(0, start - n) + selected + text.slice(end + n),
        start: start - n,
        end: end - n
      };
    }

    if (start === end) {
      const found = findEnclosing(text, start, end, md);
      if (found) {                                // caret inside: unwrap the run
        const stripped = text.slice(0, found.left) + text.slice(found.left + n, found.right) + text.slice(found.right + n);
        const caret = start - n;
        return { text: stripped, start: caret, end: caret };
      }
    }
  }

  /* Adding. Two collisions call for the alternate spelling: a delimiter
     already pressed against the caret, and italic inside a bold run — where
     a lone `*` would close the `**` rather than open emphasis. Bold inside
     italic is fine, so it keeps the asterisks. */
  let md = options[0];

  if (options[1]) {
    const adjacent = text[start - 1] === options[0][0] || text[end] === options[0][0];
    const insideBold = kind === 'italic' && Boolean(findEnclosing(text, start, end, '**'));
    if (adjacent || insideBold) md = options[1];
  }

  const n = md.length;

  if (start === end) {
    return { text: text.slice(0, start) + md + md + text.slice(start), start: start + n, end: start + n };
  }

  return {
    text: text.slice(0, start) + md + selected + md + text.slice(end),
    start: start + n,
    end: end + n
  };
}

/* ---- blocks ---------------------------------------------------------- */

/** Fence open/close lines (shared concept with MD-CORE). */
const RE_FENCE = /^( {0,3})(`{3,}|~{3,})[ \t]*([^`]*)$/;

const BLOCK_PREFIX = /^([ \t]*)(#{1,6}[ \t]+|>[ \t]?|[-+*][ \t]+\[[ xX]\][ \t]+|[-+*][ \t]+|\d{1,9}[.)][ \t]+)?/;

/** Offsets of the whole lines the selection touches. */
export function lineRange(text, start, end) {
  const from = text.lastIndexOf('\n', start - 1) + 1;
  let to = text.indexOf('\n', end);
  if (to === -1) to = text.length;
  return { from, to };
}

/** paragraph | h1..h6 | quote | ul | ol | task | code */
export function blockKind(text, position) {
  const { from, to } = lineRange(text, position, position);
  const line = text.slice(from, to);

  /* inside a fence? count the fences above. */
  const before = text.slice(0, from).split('\n');
  let fences = 0;
  for (const earlier of before) if (RE_FENCE.test(earlier)) fences++;
  if (fences % 2 === 1) return 'code';

  const heading = /^[ \t]*(#{1,6})[ \t]+/.exec(line);
  if (heading) return 'h' + heading[1].length;
  if (/^[ \t]*>/.test(line)) return 'quote';
  if (/^[ \t]*[-+*][ \t]+\[[ xX]\][ \t]+/.test(line)) return 'task';
  if (/^[ \t]*[-+*][ \t]+/.test(line)) return 'ul';
  if (/^[ \t]*\d{1,9}[.)][ \t]+/.test(line)) return 'ol';
  return 'paragraph';
}

const prefixFor = (kind, index) => {
  if (kind === 'quote') return '> ';
  if (kind === 'ul') return '- ';
  if (kind === 'task') return '- [ ] ';
  if (kind === 'ol') return (index + 1) + '. ';
  if (/^h[1-6]$/.test(kind)) return '#'.repeat(Number(kind.slice(1))) + ' ';
  return '';
};

/**
 * Rewrite the prefix of every line the selection touches. One function for
 * headings, quotes and lists, because to Markdown they are the same move.
 */
export function setBlockKind(text, start, end, kind) {
  const { from, to } = lineRange(text, start, end);
  const lines = text.slice(from, to).split('\n');
  const firstPrefix = BLOCK_PREFIX.exec(lines[0]);

  const rewritten = lines.map((line, index) => {
    const match = BLOCK_PREFIX.exec(line);
    return (match[1] || '') + prefixFor(kind, index) + line.slice(match[0].length);
  }).join('\n');

  const out = text.slice(0, from) + rewritten + text.slice(to);

  /* A caret keeps its place in the words; a selection keeps the lines. */
  if (start === end) {
    const offsetInBody = Math.max(0, start - from - firstPrefix[0].length);
    const newPrefix = (firstPrefix[1] || '').length + prefixFor(kind, 0).length;
    const caret = from + newPrefix + offsetInBody;
    return { text: out, start: caret, end: caret };
  }

  return { text: out, start: from, end: from + rewritten.length };
}

/** Lists and quotes are toggles: applying the kind twice returns to prose. */
export function toggleBlockKind(text, start, end, kind) {
  const { from, to } = lineRange(text, start, end);
  const lines = text.slice(from, to).split('\n');

  const matches = (line) => {
    if (kind === 'quote') return /^[ \t]*>/.test(line);
    if (kind === 'ul') return /^[ \t]*[-+*][ \t]+(?!\[[ xX]\])/.test(line);
    if (kind === 'task') return /^[ \t]*[-+*][ \t]+\[[ xX]\][ \t]+/.test(line);
    if (kind === 'ol') return /^[ \t]*\d{1,9}[.)][ \t]+/.test(line);
    return /^[ \t]*#{1,6}[ \t]+/.test(line);
  };

  const everyLine = lines.every((line) => line.trim() === '' || matches(line));
  return setBlockKind(text, start, end, everyLine ? 'paragraph' : kind);
}

/* ---- links ----------------------------------------------------------- */

/** The `[text](url)` the caret sits in, if any. */
export function findLink(text, position) {
  const pattern = /\[([^\]]*)\]\(([^)]*)\)/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    if (position >= match.index && position <= match.index + match[0].length) {
      return { from: match.index, to: match.index + match[0].length, label: match[1], url: match[2] };
    }
  }
  return null;
}

/**
 * Insert a link, or remove the one the caret is in. A selection that already
 * looks like a URL becomes the target rather than the label, because that is
 * what someone who just pasted a URL meant.
 */
/** @type {(text: string, start: number, end: number, placeholder?: string) => {text: string, start: number, end: number}} */
export function toggleLink(text, start, end, placeholder = 'https://') {
  const existing = findLink(text, start);
  if (existing && start === end) {
    return {
      text: text.slice(0, existing.from) + existing.label + text.slice(existing.to),
      start: existing.from,
      end: existing.from + existing.label.length
    };
  }

  const selected = text.slice(start, end);
  const url = placeholder || 'https://';

  if (selected && /^[a-z][\w+.-]*:\/\/\S*$|^www\.\S+$|^\S+@\S+\.\S+$/i.test(selected.trim())) {
    const inserted = '[](' + selected.trim() + ')';
    return { text: text.slice(0, start) + inserted + text.slice(end), start: start + 1, end: start + 1 };
  }

  const label = selected || 'link text';
  const inserted = '[' + label + '](' + url + ')';
  const urlStart = start + label.length + 3;
  return {
    text: text.slice(0, start) + inserted + text.slice(end),
    start: selected ? urlStart : start + 1,
    end: selected ? urlStart + url.length : start + 1 + label.length
  };
}

/* ---- odds and ends --------------------------------------------------- */

/** Insert a block of text on its own lines, keeping blank lines around it. */
/** @type {(text: string, start: number, end: number, snippet: string, caretOffset?: number | null) => {text: string, start: number, end: number}} */
export function insertBlock(text, start, end, snippet, caretOffset) {
  const before = text.slice(0, start);
  const after = text.slice(end);
  const lead = before === '' || before.endsWith('\n\n') ? '' : (before.endsWith('\n') ? '\n' : '\n\n');
  const tail = after.startsWith('\n') ? '\n' : '\n\n';
  const inserted = lead + snippet + tail;
  const caret = start + lead.length + (caretOffset == null ? snippet.length : caretOffset);
  return { text: before + inserted + after, start: caret, end: caret };
}

/** Take every inline marker off the selection, leaving the words. */
export function clearFormatting(text, start, end) {
  const selected = text.slice(start, end);
  const cleaned = selected
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/(\*\*|__|~~)(.*?)\1/g, '$2')
    .replace(/(^|[^*_])[*_]([^*_]+)[*_](?![*_])/g, '$1$2')
    .replace(/`([^`]*)`/g, '$1');
  return { text: text.slice(0, start) + cleaned + text.slice(end), start, end: start + cleaned.length };
}
