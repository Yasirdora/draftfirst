// @ts-nocheck — ported pure core; behavior-preserving extract from writing-desk.html
/**
 * MD-CORE — Markdown → safe HTML.
 *
 * DOM-free, dependency-free, and unit-testable in Node. This is the only path
 * that may produce HTML for the preview or export. User text always goes through
 * escapeHtml; URLs always go through safeUrl. Raw HTML is never passed through.
 *
 * Supported: ATX/setext headings, paragraphs, hard breaks, thematic breaks,
 * blockquotes, fenced/indented code, nested lists (tight/loose), GFM tables,
 * task lists, links (inline/reference/autolink), images, emphasis, strong,
 * inline code, strikethrough, backslash escapes.
 */

/** The only way text ever reaches the output. */
export function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Allow only schemes that cannot execute. Anything else — javascript:,
 * vbscript:, data: text — becomes an inert anchor rather than a trap.
 */
export function safeUrl(url, { allowImageData = false } = {}) {
  const raw = String(url == null ? '' : url).trim().replace(/[\u0000-\u001F\u007F]/g, '');
  if (raw === '') return '';
  if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) {
    if (/^(https?|mailto|tel|ftp):/i.test(raw)) return raw;
    if (allowImageData && /^data:image\/(png|jpe?g|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(raw)) return raw;
    return '';
  }
  return raw; // relative path, #anchor, ./file
}

const ESCAPABLE = '\\\\`*_{}[]()#+-.!>~|"\'';

/* ---- inline ---------------------------------------------------------- */

/**
 * Inline scanner. One pass, left to right, emitting escaped HTML.
 * `refs` holds link reference definitions collected by the block pass.
 */
function renderInline(src, refs) {
  let out = '';
  let plain = '';
  let i = 0;

  const flush = () => { out += escapeHtml(plain); plain = ''; };

  while (i < src.length) {
    const ch = src[i];

    /* backslash escape, and backslash-at-end-of-line as a hard break */
    if (ch === '\\' && i + 1 < src.length) {
      const next = src[i + 1];
      if (next === '\n') { flush(); out += '<br>\n'; i += 2; continue; }
      if (ESCAPABLE.indexOf(next) !== -1) { plain += next; i += 2; continue; }
    }

    /* code span: the longest run of backticks closes it */
    if (ch === '`') {
      let run = 0;
      while (src[i + run] === '`') run++;
      const fence = '`'.repeat(run);
      const end = src.indexOf(fence, i + run);
      if (end !== -1) {
        let code = src.slice(i + run, end);
        if (code.length > 1 && code[0] === ' ' && code[code.length - 1] === ' ' && code.trim() !== '') {
          code = code.slice(1, -1);
        }
        flush();
        out += '<code>' + escapeHtml(code.replace(/\n/g, ' ')) + '</code>';
        i = end + run;
        continue;
      }
    }

    /* autolink */
    if (ch === '<') {
      const close = src.indexOf('>', i);
      if (close !== -1) {
        const body = src.slice(i + 1, close);
        if (/^[a-z][a-z0-9+.-]*:[^\s<>]*$/i.test(body)) {
          const href = safeUrl(body);
          flush();
          out += href ? '<a href="' + escapeHtml(href) + '">' + escapeHtml(body) + '</a>' : escapeHtml('<' + body + '>');
          i = close + 1;
          continue;
        }
        if (/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(body)) {
          flush();
          out += '<a href="mailto:' + escapeHtml(body) + '">' + escapeHtml(body) + '</a>';
          i = close + 1;
          continue;
        }
      }
    }

    /* image */
    if (ch === '!' && src[i + 1] === '[') {
      const parsed = parseLink(src, i + 1, refs, true);
      if (parsed) {
        flush();
        out += parsed.html;
        i = parsed.end;
        continue;
      }
    }

    /* link */
    if (ch === '[') {
      const parsed = parseLink(src, i, refs, false);
      if (parsed) {
        flush();
        out += parsed.html;
        i = parsed.end;
        continue;
      }
    }

    /* strong, emphasis, strikethrough */
    if (ch === '*' || ch === '_' || ch === '~') {
      const emphasis = parseEmphasis(src, i, refs);
      if (emphasis) {
        flush();
        out += emphasis.html;
        i = emphasis.end;
        continue;
      }
    }

    /* hard break: two or more trailing spaces before a newline */
    if (ch === ' ' && /^ {2,}\n/.test(src.slice(i))) {
      const nl = src.indexOf('\n', i);
      flush();
      out += '<br>\n';
      i = nl + 1;
      continue;
    }

    plain += ch;
    i++;
  }

  flush();
  return out;
}

/** Find the matching bracket, honouring nesting and escapes. */
function matchBracket(src, start, open, close) {
  let depth = 0;
  for (let i = start; i < src.length; i++) {
    if (src[i] === '\\') { i++; continue; }
    if (src[i] === open) depth++;
    else if (src[i] === close) { depth--; if (depth === 0) return i; }
  }
  return -1;
}

/** `[text](url "title")`, `[text][ref]`, `[ref]` and their image forms. */
function parseLink(src, start, refs, isImage) {
  const labelEnd = matchBracket(src, start, '[', ']');
  if (labelEnd === -1) return null;
  const label = src.slice(start + 1, labelEnd);

  let url = '';
  let title = '';
  let end;

  if (src[labelEnd + 1] === '(') {
    const parenEnd = matchBracket(src, labelEnd + 1, '(', ')');
    if (parenEnd === -1) return null;
    const inside = src.slice(labelEnd + 2, parenEnd).trim();
    const withTitle = /^(<[^>]*>|[^\s]*)(?:\s+["'(](.*)["')])?$/.exec(inside);
    if (!withTitle) return null;
    url = withTitle[1].replace(/^<|>$/g, '');
    title = withTitle[2] || '';
    end = parenEnd + 1;
  } else {
    let key = label;
    if (src[labelEnd + 1] === '[') {
      const refEnd = matchBracket(src, labelEnd + 1, '[', ']');
      if (refEnd === -1) return null;
      const explicit = src.slice(labelEnd + 2, refEnd).trim();
      if (explicit !== '') key = explicit;
      end = refEnd + 1;
    } else {
      end = labelEnd + 1;
    }
    const found = refs[key.toLowerCase()];
    if (!found) return null;
    url = found.url;
    title = found.title || '';
  }

  const href = safeUrl(url, { allowImageData: isImage });
  const titleAttr = title ? ' title="' + escapeHtml(title) + '"' : '';

  if (isImage) {
    if (!href) return { html: escapeHtml('![' + label + ']'), end };
    return {
      html: '<img src="' + escapeHtml(href) + '" alt="' + escapeHtml(label) + '"' + titleAttr + '>',
      end
    };
  }

  const inner = renderInline(label, refs);
  if (!href) return { html: inner, end };
  return { html: '<a href="' + escapeHtml(href) + '"' + titleAttr + '>' + inner + '</a>', end };
}

/**
 * Emphasis for the cases people actually write: **strong**, *em*, __strong__,
 * _em_, ~~struck~~, and those nested inside each other. A delimiter only
 * opens if it is followed by non-space, and only closes if preceded by one.
 */
function parseEmphasis(src, start, refs) {
  const ch = src[start];
  let run = 0;
  while (src[start + run] === ch) run++;

  const tries = ch === '~'
    ? (run >= 2 ? [2] : [])
    : (run >= 2 ? [2, 1] : [1]);

  for (const width of tries) {
    const marker = ch.repeat(width);
    const from = start + width;
    if (from >= src.length || /\s/.test(src[from])) continue;

    let i = from;
    while (i < src.length) {
      if (src[i] === '\\') { i += 2; continue; }
      if (src[i] === '`') {                        // never split a code span
        let r = 0;
        while (src[i + r] === '`') r++;
        const close = src.indexOf('`'.repeat(r), i + r);
        i = close === -1 ? i + r : close + r;
        continue;
      }
      if (src.startsWith(marker, i) && src[i - 1] !== undefined && !/\s/.test(src[i - 1])) {
        if (src[i + width] === ch) { i++; continue; } // longer run: not ours
        const body = src.slice(from, i);
        if (body.trim() === '') break;
        const inner = renderInline(body, refs);
        const tag = ch === '~' ? 'del' : (width === 2 ? 'strong' : 'em');
        return { html: '<' + tag + '>' + inner + '</' + tag + '>', end: i + width };
      }
      i++;
    }
  }

  return null;
}

/* ---- blocks ---------------------------------------------------------- */

const RE_THEMATIC = /^ {0,3}([-*_])[ \t]*(?:\1[ \t]*){2,}$/;
const RE_ATX      = /^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*#*[ \t]*$/;
const RE_FENCE    = /^( {0,3})(`{3,}|~{3,})[ \t]*([^`]*)$/;
const RE_QUOTE    = /^ {0,3}>[ ]?/;
const RE_BULLET   = /^( {0,3})([-+*])([ \t]+|$)/;
const RE_ORDERED  = /^( {0,3})(\d{1,9})([.)])([ \t]+|$)/;
const RE_SETEXT   = /^ {0,3}(=+|-{2,})[ \t]*$/;
const RE_DELIM    = /^ *\|? *:?-{1,}:? *(\| *:?-{1,}:? *)*\|? *$/;
const RE_REFDEF   = /^ {0,3}\[([^\]]+)\]:[ \t]*<?([^\s>]+)>?(?:[ \t]+["'(](.*)["')])?[ \t]*$/;

const isBlank = (line) => /^[ \t]*$/.test(line);

/** A line that would start some other block, so a paragraph must stop. */
function startsBlock(line) {
  return RE_THEMATIC.test(line) || RE_ATX.test(line) || RE_FENCE.test(line)
    || RE_QUOTE.test(line) || RE_BULLET.test(line) || RE_ORDERED.test(line);
}

/** Pull out link reference definitions; they are not content. */
function collectRefs(lines) {
  const refs = Object.create(null);
  const kept = [];
  for (const line of lines) {
    const m = RE_REFDEF.exec(line);
    if (m) {
      refs[m[1].trim().toLowerCase()] = { url: m[2], title: m[3] || '' };
      continue;
    }
    kept.push(line);
  }
  return { refs, lines: kept };
}

/** Split a table row on unescaped pipes, dropping the optional outer ones. */
function tableCells(row) {
  const trimmed = row.trim().replace(/^\|/, '').replace(/\|$/, '');
  const parts = [];
  let cell = '';
  for (let i = 0; i < trimmed.length; i++) {
    if (trimmed[i] === '\\' && trimmed[i + 1] === '|') { cell += '|'; i++; continue; }
    if (trimmed[i] === '|') { parts.push(cell); cell = ''; continue; }
    cell += trimmed[i];
  }
  parts.push(cell);
  return parts.map((c) => c.trim());
}

function renderTable(rows, alignments, refs) {
  const cells = tableCells;

  const style = (index) => {
    const align = alignments[index];
    return align ? ' style="text-align:' + align + '"' : '';
  };

  let html = '<table>\n<thead>\n<tr>';
  cells(rows[0]).forEach((cell, index) => {
    html += '<th' + style(index) + '>' + renderInline(cell, refs) + '</th>';
  });
  html += '</tr>\n</thead>\n';

  if (rows.length > 1) {
    html += '<tbody>\n';
    for (const row of rows.slice(1)) {
      html += '<tr>';
      cells(row).forEach((cell, index) => {
        html += '<td' + style(index) + '>' + renderInline(cell, refs) + '</td>';
      });
      html += '</tr>\n';
    }
    html += '</tbody>\n';
  }

  return html + '</table>\n';
}

/**
 * Blocks, recursively. `lines` has already had reference definitions removed.
 * `tight` is set for the contents of a tight list item, where paragraphs are
 * written without their `<p>` wrapper — the difference between
 * `<li>one</li>` and `<li><p>one</p></li>`.
 */
function renderBlocks(lines, refs, { tight = false } = {}) {
  let html = '';
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    if (isBlank(line)) { i++; continue; }

    /* fenced code */
    const fence = RE_FENCE.exec(line);
    if (fence) {
      const indent = fence[1].length;
      const marker = fence[2][0];
      const width = fence[2].length;
      const info = fence[3].trim().split(/\s+/)[0] || '';
      const body = [];
      i++;
      while (i < lines.length) {
        const closing = new RegExp('^ {0,3}' + (marker === '`' ? '`' : '~') + '{' + width + ',}[ \\t]*$');
        if (closing.test(lines[i])) { i++; break; }
        body.push(lines[i].slice(indent));
        i++;
      }
      const cls = info ? ' class="language-' + escapeHtml(info.replace(/[^\w.+-]/g, '')) + '"' : '';
      html += '<pre><code' + cls + '>' + escapeHtml(body.join('\n')) + (body.length ? '\n' : '') + '</code></pre>\n';
      continue;
    }

    /* thematic break */
    if (RE_THEMATIC.test(line)) { html += '<hr>\n'; i++; continue; }

    /* ATX heading */
    const atx = RE_ATX.exec(line);
    if (atx) {
      const level = atx[1].length;
      html += '<h' + level + '>' + renderInline((atx[2] || '').trim(), refs) + '</h' + level + '>\n';
      i++;
      continue;
    }

    /* blockquote */
    if (RE_QUOTE.test(line)) {
      const body = [];
      while (i < lines.length && (RE_QUOTE.test(lines[i]) || (!isBlank(lines[i]) && body.length && !startsBlock(lines[i])))) {
        body.push(lines[i].replace(RE_QUOTE, ''));
        i++;
      }
      html += '<blockquote>\n' + renderBlocks(body, refs) + '</blockquote>\n';
      continue;
    }

    /* list */
    const bullet = RE_BULLET.exec(line);
    const ordered = RE_ORDERED.exec(line);
    if (bullet || ordered) {
      const result = renderList(lines, i, refs);
      html += result.html;
      i = result.next;
      continue;
    }

    /* indented code */
    if (/^ {4}/.test(line)) {
      const body = [];
      while (i < lines.length && (/^ {4}/.test(lines[i]) || isBlank(lines[i]))) {
        if (isBlank(lines[i]) && !(lines[i + 1] && /^ {4}/.test(lines[i + 1]))) break;
        body.push(lines[i].replace(/^ {4}/, ''));
        i++;
      }
      html += '<pre><code>' + escapeHtml(body.join('\n')) + '\n</code></pre>\n';
      continue;
    }

    /* table — a header row, then a delimiter row with the same cell count */
    if (line.indexOf('|') !== -1 && lines[i + 1] && RE_DELIM.test(lines[i + 1])) {
      const alignments = tableCells(lines[i + 1]).map((cell) => {
        const left = cell.charAt(0) === ':';
        const right = cell.charAt(cell.length - 1) === ':';
        if (left && right) return 'center';
        if (right) return 'right';
        if (left) return 'left';
        return '';
      });

      if (alignments.length === tableCells(line).length) {
        const rows = [line];
        i += 2;
        while (i < lines.length && !isBlank(lines[i]) && lines[i].indexOf('|') !== -1) {
          rows.push(lines[i]);
          i++;
        }
        html += renderTable(rows, alignments, refs);
        continue;
      }
    }

    /* paragraph, or a setext heading if the next line underlines it */
    const paragraph = [line];
    i++;
    while (i < lines.length && !isBlank(lines[i]) && !startsBlock(lines[i])) {
      if (RE_SETEXT.test(lines[i]) && paragraph.length) break;
      if (lines[i].indexOf('|') !== -1 && lines[i + 1] && RE_DELIM.test(lines[i + 1])) break;
      paragraph.push(lines[i]);
      i++;
    }

    if (i < lines.length && RE_SETEXT.test(lines[i])) {
      const level = lines[i].trim()[0] === '=' ? 1 : 2;
      html += '<h' + level + '>' + renderInline(paragraph.join('\n').trim(), refs) + '</h' + level + '>\n';
      i++;
      continue;
    }

    const inline = renderInline(paragraph.join('\n').trim(), refs);
    html += tight ? inline + '\n' : '<p>' + inline + '</p>\n';
  }

  return html;
}

/**
 * A list and everything indented under it. Items are collected by their
 * marker width, then rendered by recursion, so nesting is free.
 */
function renderList(lines, start, refs) {
  const first = RE_BULLET.exec(lines[start]) || RE_ORDERED.exec(lines[start]);
  const isOrdered = !RE_BULLET.exec(lines[start]);
  const startNumber = isOrdered ? parseInt(first[2], 10) : 1;

  /* Two indents decide everything: where this list's markers sit, and where
     its items' content sits. A marker at or before the first is a sibling;
     anything at or past the second belongs inside the item above, which is
     how nesting falls out of recursion. */
  const markerIndent = first[1].length;
  const contentIndent = first[0].length;

  const indentOf = (line) => /^[ \t]*/.exec(line)[0].replace(/\t/g, '    ').length;
  const items = [];
  let loose = false;
  let i = start;
  let pendingBlank = false;

  while (i < lines.length) {
    const line = lines[i];

    if (isBlank(line)) {
      if (i + 1 >= lines.length) { i++; break; }
      pendingBlank = true;
      i++;
      continue;
    }

    const bullet = RE_BULLET.exec(line);
    const ordered = RE_ORDERED.exec(line);
    const marker = bullet || ordered;
    const sameKind = marker && (Boolean(ordered) === isOrdered);
    const indent = indentOf(line);

    if (sameKind && indent <= markerIndent + 1) {
      if (pendingBlank && items.length) loose = true;
      pendingBlank = false;
      items.push([line.slice(marker[0].length)]);
      i++;
      continue;
    }

    /* indented under the item above: keep it, minus one level of indent */
    if (items.length && indent >= contentIndent) {
      if (pendingBlank) { items[items.length - 1].push(''); loose = true; pendingBlank = false; }
      items[items.length - 1].push(line.slice(contentIndent));
      i++;
      continue;
    }

    if (items.length && !pendingBlank && !startsBlock(line)) {
      items[items.length - 1].push(line.trim());   // lazy continuation
      i++;
      continue;
    }

    break;
  }

  const tag = isOrdered ? 'ol' : 'ul';
  const startAttr = isOrdered && startNumber !== 1 ? ' start="' + startNumber + '"' : '';
  let html = '<' + tag + startAttr + '>\n';

  for (const item of items) {
    const task = /^\[([ xX])\][ \t]+/.exec(item[0] || '');
    let cls = '';
    let checkbox = '';

    if (task) {
      item[0] = item[0].slice(task[0].length);
      cls = ' class="task"';
      checkbox = '<input type="checkbox" disabled' + (task[1] === ' ' ? '' : ' checked') + '> ';
    }

    const body = renderBlocks(item, refs, { tight: !loose }).trim();
    html += '<li' + cls + '>' + checkbox + body + '</li>\n';
  }

  return { html: html + '</' + tag + '>\n', next: i };
}

/**
 * Markdown source to an HTML string.
 * Every character of the source ends up either inside a tag this function
 * chose or escaped; nothing from the document is ever emitted as markup.
 */
export function renderMarkdown(source) {
  const text = String(source == null ? '' : source)
    .replace(/\r\n?/g, '\n')
    .replace(/\u0000/g, '\uFFFD');
  const { refs, lines } = collectRefs(text.split('\n'));
  return renderBlocks(lines, refs);
}

/** Headings, for the outline menu. Uses the same regexes as the renderer. */
export function outlineOf(source) {
  const lines = String(source == null ? '' : source).replace(/\r\n?/g, '\n').split('\n');
  const found = [];
  let inFence = false;

  lines.forEach((line, index) => {
    const fence = RE_FENCE.exec(line);
    if (fence) { inFence = !inFence; return; }
    if (inFence) return;
    const atx = RE_ATX.exec(line);
    if (atx) {
      found.push({ level: atx[1].length, text: (atx[2] || '').trim(), line: index });
      return;
    }
    if (RE_SETEXT.test(line) && index > 0 && !isBlank(lines[index - 1]) && !startsBlock(lines[index - 1])) {
      found.push({ level: line.trim()[0] === '=' ? 1 : 2, text: lines[index - 1].trim(), line: index - 1 });
    }
  });

  return found;
}

/** Words the way a writer counts them, not the way split(' ') does. */
export function countWords(source) {
  const text = String(source == null ? '' : source)
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/`[^`]*`/g, ' ')
    .replace(/[#>*_~|=]+/g, ' ');   // not the hyphen: "well-known" is one word
  const matches = text.match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu);
  return matches ? matches.length : 0;
}
