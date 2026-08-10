// @ts-nocheck — ported pure core; behavior-preserving extract from writing-desk.html
/**
 * WRITE-CORE — contenteditable page DOM → Markdown.
 *
 * Reads a DOM tree (never writes one). Normalises browser editing quirks
 * (<b> vs <strong>, styled spans, etc.) so the saved source stays clean.
 * Used when the user types on the typeset page.
 */

const BLOCK_TAGS = 'H1 H2 H3 H4 H5 H6 P DIV BLOCKQUOTE UL OL PRE HR TABLE LI'.split(' ');

const isBold = (element) => {
  const weight = element.style && element.style.fontWeight;
  return /^(b|strong)$/i.test(element.tagName) || /^(bold|[6-9]00)$/.test(weight || '');
};

const isItalic = (element) =>
  /^(i|em)$/i.test(element.tagName) || (element.style && element.style.fontStyle === 'italic');

const isStruck = (element) =>
  /^(s|del|strike)$/i.test(element.tagName)
  || (element.style && String(element.style.textDecoration).indexOf('line-through') !== -1);

/** Never emit `****` for an empty run. */
const wrapRun = (md, inner) => inner.trim() === '' ? inner : md + inner + md;

/**
 * Escape the characters that would otherwise be read as markup next time.
 * Underscores are left alone: they do not start emphasis inside a word, and
 * escaping them turns every file_name in a document into file\_name.
 */
export const escapeText = (text) => String(text).replace(/([\\`*[\]<>])/g, '\\$1');

/** A paragraph that begins with a block marker needs the first one escaped. */
const escapeLeading = (text) => text.replace(/^(\s*)([#>+-]|\d+[.)])(\s)/, '$1\\$2$3');

const BLOCK_SET = {};
for (const tag of BLOCK_TAGS) BLOCK_SET[tag] = true;

const hasBlockChild = (nodes) => Array.prototype.some.call(nodes,
  (node) => node.nodeType === 1 && BLOCK_SET[node.tagName.toUpperCase()] === true);

export function serialiseInline(node) {
  return serialiseInlineNodes(node.childNodes);
}

function serialiseInlineNodes(nodes) {
  let out = '';

  for (const child of nodes) {
    if (child.nodeType === 3) {
      /* A `<br>` already wrote the line break; the newline the markup is
         indented with must not become a second one. */
      const value = out.slice(-3) === '  \n' ? child.nodeValue.replace(/^\n+/, '') : child.nodeValue;
      out += escapeText(value);
      continue;
    }
    if (child.nodeType !== 1) continue;

    const tag = child.tagName.toUpperCase();

    if (tag === 'BR') { out += '  \n'; continue; }
    if (tag === 'IMG') {
      out += '![' + (child.getAttribute('alt') || '') + '](' + (child.getAttribute('src') || '') + ')';
      continue;
    }
    if (tag === 'INPUT') continue;                 // the task box, handled by its item
    if (tag === 'CODE') { out += '`' + child.textContent + '`'; continue; }
    if (tag === 'A') {
      const href = child.getAttribute('href') || '';
      const label = serialiseInline(child);
      out += href ? '[' + label + '](' + href + ')' : label;
      continue;
    }

    const inner = serialiseInline(child);
    if (isBold(child)) out += wrapRun('**', inner);
    else if (isItalic(child)) out += wrapRun('*', inner);
    else if (isStruck(child)) out += wrapRun('~~', inner);
    else out += inner;
  }

  return out;
}

const indentLines = (text, prefix, firstPrefix) =>
  text.split('\n').map((line, index) => (index === 0 ? (firstPrefix == null ? prefix : firstPrefix) : prefix) + line).join('\n');

function serialiseList(list, ordered) {
  const items = [];
  let number = Number(list.getAttribute('start') || 1);

  for (const item of list.children) {
    if (item.tagName !== 'LI') continue;

    const nested = [];
    const own = [];
    let box = null;

    for (const child of item.childNodes) {
      if (child.nodeType === 1 && (child.tagName === 'UL' || child.tagName === 'OL')) nested.push(child);
      else if (child.nodeType === 1 && child.tagName === 'INPUT' && child.type === 'checkbox' && !box) box = child;
      else own.push(child);
    }

    const body = (hasBlockChild(own) ? serialiseBlocks(own) : serialiseInlineNodes(own)).trim();

    let marker = ordered ? number + '. ' : '- ';
    if (box) marker += box.checked ? '[x] ' : '[ ] ';
    number++;

    let text = indentLines(body, ' '.repeat(marker.length), marker);

    for (const child of nested) {
      const sub = serialiseList(child, child.tagName === 'OL');
      text += '\n' + indentLines(sub, '  ');
    }

    items.push(text);
  }

  return items.join('\n');
}

function serialiseTable(table) {
  const rows = [];
  let alignments = [];

  for (const row of table.querySelectorAll('tr')) {
    const cells = [];
    for (const cell of row.cells) {
      cells.push(serialiseInline(cell).replace(/\|/g, '\\|').trim());
      if (rows.length === 0) alignments.push((cell.style && cell.style.textAlign) || '');
    }
    rows.push('| ' + cells.join(' | ') + ' |');
  }

  if (rows.length === 0) return '';

  const divider = '| ' + alignments.map((align) => {
    if (align === 'center') return ':---:';
    if (align === 'right') return '---:';
    if (align === 'left') return ':---';
    return '---';
  }).join(' | ') + ' |';

  return [rows[0], divider].concat(rows.slice(1)).join('\n');
}

/** One block element to one chunk of Markdown, or '' if there is nothing in it. */
function serialiseBlock(node) {
  if (node.nodeType === 3) {
    const text = escapeText(node.nodeValue).trim();
    return text;
  }

  if (node.nodeType !== 1) return '';

  const tag = node.tagName.toUpperCase();

  if (/^H[1-6]$/.test(tag)) {
    const inner = serialiseInline(node).trim();
    return inner === '' ? '' : '#'.repeat(Number(tag[1])) + ' ' + inner;
  }

  if (tag === 'HR') return '---';

  if (tag === 'PRE') {
    const code = node.querySelector('code') || node;
    const language = /language-([\w.+-]+)/.exec(code.className || '');
    return '```' + (language ? language[1] : '') + '\n' + code.textContent.replace(/\n$/, '') + '\n```';
  }

  if (tag === 'BLOCKQUOTE') {
    const inner = serialiseChildren(node).trim();
    return inner.split('\n').map((line) => (line === '' ? '>' : '> ' + line)).join('\n');
  }

  if (tag === 'UL' || tag === 'OL') return serialiseList(node, tag === 'OL');

  if (tag === 'TABLE') return serialiseTable(node);

  if (tag === 'DIV' && hasBlockChild(node.childNodes)) return serialiseBlocks(node.childNodes).trim();

  const inline = serialiseInline(node).trim();
  return inline === '' ? '' : escapeLeading(inline);
}

/** A list of sibling blocks, separated by blank lines. */
function serialiseBlocks(nodes) {
  const parts = [];

  for (const child of nodes) {
    const text = serialiseBlock(child);
    if (text !== '') parts.push(text);
  }

  return parts.join('\n\n');
}

/**
 * The contents of a container — as blocks if it holds any, otherwise as one
 * run of inline text. Editing surfaces produce both shapes, sometimes in the
 * same document.
 */
function serialiseChildren(node) {
  return hasBlockChild(node.childNodes)
    ? serialiseBlocks(node.childNodes)
    : escapeLeading(serialiseInlineNodes(node.childNodes).trim());
}

/** The whole page, as Markdown. */
export function serialiseMarkdown(root) {
  const text = serialiseChildren(root)
    .replace(/\u00A0/g, ' ')                                        // the spaces contenteditable inserts
    .replace(/[ \t]+$/gm, (match) => (match === '  ' ? '  ' : ''))   // keep hard breaks, drop stray spaces
    .replace(/\n{3,}/g, '\n\n')
    .trim();

  return text === '' ? '' : text + '\n';
}
