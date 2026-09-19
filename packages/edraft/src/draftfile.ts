/**
 * The .draft 1.0 file (docs/RFC-DRAFT-FORMAT.md §4–§11): a ZIP in the
 * ISO/IEC 21320-1 profile whose parts are JSON, read and written here.
 *
 * A document is its parts. `script` and `notes` are held as ordered JSON
 * trees, not as typed records, so every member this version does not know
 * survives a read and a write in its place (§8.2, must-preserve); the
 * bridges at the end translate to and from the engine's Screenplay for the
 * apps of today. The Swift port (Export/DraftFile.swift) writes the same
 * bytes and reads the same documents; Fixtures/draft.json pins both.
 *
 * Entries are stored, never deflated, until the compression decision
 * (RFC-DRAFT-FORMAT §16 O1) lands. Readers accept both (§4.1).
 */

import { parseFountain } from './parse.js';
import { serialiseFountain } from './serialise.js';
import { decodeUtf8, encodeUtf8 } from './platform.js';
import { sha256Hex } from './sha256.js';
import type { Screenplay, ScreenplayElement, StyleRun, TitlePageLine } from './types.js';
import { readZipEntriesTolerant, ZipFormatError } from './zip.js';
import type { ZipTolerantResult } from './zip.js';
import { writeZipStored } from './zipwrite.js';

/* ------------------------------------------------------------------ */
/* Constants                                                           */
/* ------------------------------------------------------------------ */

export const DRAFT_MEDIA_TYPE = 'application/vnd.edraft.draft+zip';
export const DRAFT_FORMAT_VERSION = '1.0';
const MIN_READER = '1.0';
/** 1980-01-01, the earliest DOS date: no clock in the bytes (§4.4). */
const DOS_DATE_1980 = 0x0021;
const MAX_JSON_DEPTH = 64;
const MAX_ELEMENTS = 100_000;
const MAX_ELEMENT_TEXT = 1_000_000;
const MAX_TITLE_LINES = 100;
const MAX_SECTION_DEPTH = 10;
const MAX_FILE_BYTES = 128 * 1024 * 1024;
/** Whole words within this many UTF-16 units either side of a quote (§6.3). */
const CONTEXT_UNITS = 16;

const ELEMENT_TYPES: ReadonlySet<string> = new Set([
	'scene', 'action', 'character', 'dialogue', 'parenthetical', 'transition', 'shot',
	'general', 'centered', 'lyrics', 'actbreak', 'section', 'synopsis', 'pagebreak'
]);
const STYLE_TOKENS: readonly string[] = ['Bold', 'Italic', 'Underline', 'Strikeout', 'AllCaps', 'HiddenText'];
const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
const VERSION_PATTERN = /^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$/;
const HEX64 = /^[0-9a-f]{64}$/;

/** Member order the canonical form writes, per object kind (§5.1). */
const ORDER = {
	manifest: ['format', 'version', 'minReader', 'writer', 'title', 'parts', 'fingerprints'],
	writer: ['name', 'version'],
	part: ['path', 'sha256', 'size'],
	fingerprints: ['script', 'notes'],
	script: ['titlePage', 'elements', 'nextId'],
	titleLine: ['key', 'text', 'alignment', 'runs'],
	element: ['id', 'type', 'text', 'runs', 'dual', 'sceneNumber', 'depth'],
	run: ['start', 'end', 'styles', 'highlight', 'revisionID', 'tagNumbers'],
	notes: ['threads', 'nextId'],
	thread: ['id', 'anchor', 'messages', 'status'],
	anchor: ['element', 'start', 'end', 'quote', 'prefix', 'suffix'],
	message: ['id', 'by', 'role', 'at', 'text', 'source'],
	status: ['state', 'by', 'at']
} as const;

/* ------------------------------------------------------------------ */
/* Types                                                               */
/* ------------------------------------------------------------------ */

/** A JSON value. Objects are Maps, so member order is exactly as read. */
export type JsonValue = null | boolean | number | string | JsonValue[] | JsonObject;
export type JsonObject = Map<string, JsonValue>;

/** A part carried byte for byte: an origin, an extension, a reserved or
	unknown part, or a damaged one kept rather than lost (§5.6, §7.2, §8.2). */
export interface DraftPart {
	path: string;
	data: Uint8Array;
	/** The part failed a check on read; it is written back unchanged. */
	damaged?: boolean;
}

export interface DraftDocument {
	/** The manifest's title, when the document has one. */
	title?: string;
	/** script.json (§5.3), as read or as the bridges built it. */
	script: JsonObject;
	/** notes.json (§5.4); absent when the document has no notes part. */
	notes?: JsonObject;
	/** Every other part, in no particular order: the writer orders them. */
	parts: DraftPart[];
	/** manifest.json members this version does not know (§8.2). */
	manifestExtra?: JsonObject;
}

export type DraftDiagnosticCode =
	| 'mimetype-missing'
	| 'mimetype-wrong'
	| 'manifest-unreadable'
	| 'read-only-newer-minor'
	| 'directory-damaged'
	| 'invalid-entry-name'
	| 'duplicate-entry'
	| 'part-damaged'
	| 'missing-part'
	| 'unlisted-part'
	| 'outside-edit'
	| 'script-from-rendition'
	| 'anchor-moved'
	| 'anchor-words-changed'
	| 'anchor-detached'
	| 'anchor-degraded';

/** What a reader or a bridge noticed. Every rung below "all valid" says one. */
export interface DraftDiagnostic {
	code: DraftDiagnosticCode;
	/** The part the diagnostic is about. */
	path?: string;
	/** The thread the diagnostic is about. */
	thread?: string;
	detail?: string;
}

export interface DraftReadResult {
	document: DraftDocument;
	diagnostics: DraftDiagnostic[];
	/** The file needs a newer reader to edit it without loss (§8.1). */
	readOnly: boolean;
}

export type DraftFormatErrorCode = 'not-a-draft' | 'over-limits' | 'newer-major' | 'no-script' | 'invalid-document';

/** A file this version refuses, or a document the writer cannot write. */
export class DraftFormatError extends Error {
	readonly code: DraftFormatErrorCode;
	constructor(code: DraftFormatErrorCode, message: string) {
		super(message);
		this.name = 'DraftFormatError';
		this.code = code;
	}
}

export type DraftFormat = 'draft' | 'pdf' | 'fdx' | 'text' | 'unknown';

export interface DraftWriteOptions {
	/** The application writing the file, recorded in the manifest. */
	writer: { name: string; version: string };
}

/* ------------------------------------------------------------------ */
/* JSON: strict I-JSON in, canonical out (§5.1)                         */
/* ------------------------------------------------------------------ */

class JsonError extends Error {}

/** Parse I-JSON (RFC 7493) strictly: integers only, no duplicate names,
	no lone surrogates, no byte-order mark, at most 64 levels deep. */
export function parseDraftJson(text: string): JsonValue {
	let at = 0;
	const fail = (why: string): never => {
		throw new JsonError(`${why} at ${at}`);
	};
	const space = (): void => {
		while (at < text.length) {
			const c = text.charCodeAt(at);
			if (c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d) at++;
			else break;
		}
	};
	const value = (depth: number): JsonValue => {
		if (depth > MAX_JSON_DEPTH) fail('nested too deep');
		space();
		const c = text[at];
		if (c === '{') return object(depth);
		if (c === '[') return array(depth);
		if (c === '"') return string();
		if (c === '-' || (c !== undefined && c >= '0' && c <= '9')) return number();
		if (text.startsWith('true', at)) return (at += 4), true;
		if (text.startsWith('false', at)) return (at += 5), false;
		if (text.startsWith('null', at)) return (at += 4), null;
		return fail('unexpected character');
	};
	const object = (depth: number): JsonObject => {
		const out: JsonObject = new Map();
		at++;
		space();
		if (text[at] === '}') return at++, out;
		for (;;) {
			space();
			if (text[at] !== '"') fail('expected a member name');
			const name = string();
			if (out.has(name)) fail(`duplicate member "${name}"`);
			space();
			if (text[at] !== ':') fail('expected ":"');
			at++;
			out.set(name, value(depth + 1));
			space();
			if (text[at] === ',') {
				at++;
				continue;
			}
			if (text[at] === '}') return at++, out;
			return fail('expected "," or "}"');
		}
	};
	const array = (depth: number): JsonValue[] => {
		const out: JsonValue[] = [];
		at++;
		space();
		if (text[at] === ']') return at++, out;
		for (;;) {
			out.push(value(depth + 1));
			space();
			if (text[at] === ',') {
				at++;
				continue;
			}
			if (text[at] === ']') return at++, out;
			return fail('expected "," or "]"');
		}
	};
	const string = (): string => {
		at++;
		let out = '';
		for (;;) {
			if (at >= text.length) fail('unterminated string');
			const code = text.charCodeAt(at);
			if (code === 0x22) {
				at++;
				break;
			}
			if (code < 0x20) fail('unescaped control character');
			if (code === 0x5c) {
				const next = text[at + 1];
				at += 2;
				if (next === '"') out += '"';
				else if (next === '\\') out += '\\';
				else if (next === '/') out += '/';
				else if (next === 'b') out += '\b';
				else if (next === 'f') out += '\f';
				else if (next === 'n') out += '\n';
				else if (next === 'r') out += '\r';
				else if (next === 't') out += '\t';
				else if (next === 'u') {
					const hex = text.slice(at, at + 4);
					if (!/^[0-9a-fA-F]{4}$/.test(hex)) fail('bad \\u escape');
					out += String.fromCharCode(parseInt(hex, 16));
					at += 4;
				} else fail('bad escape');
				continue;
			}
			out += text[at];
			at++;
		}
		if (!isWellFormed(out)) fail('lone surrogate');
		return out;
	};
	const number = (): number => {
		const match = /^-?(0|[1-9][0-9]*)/.exec(text.slice(at, at + 32));
		if (!match) return fail('bad number');
		const after = text[at + match[0].length];
		if (after === '.' || after === 'e' || after === 'E') fail('not an integer');
		if (match[0].length > 17) fail('integer out of range');
		const n = Number(match[0]);
		if (!Number.isSafeInteger(n)) fail('integer out of range');
		at += match[0].length;
		return n === 0 ? 0 : n;
	};
	if (text.charCodeAt(0) === 0xfeff) fail('byte-order mark');
	const result = value(1);
	space();
	if (at !== text.length) fail('trailing characters');
	return result;
}

function isWellFormed(text: string): boolean {
	for (let i = 0; i < text.length; i++) {
		const c = text.charCodeAt(i);
		if (c >= 0xd800 && c <= 0xdbff) {
			const d = text.charCodeAt(i + 1);
			if (!(d >= 0xdc00 && d <= 0xdfff)) return false;
			i++;
		} else if (c >= 0xdc00 && c <= 0xdfff) return false;
	}
	return true;
}

/** A string quoted as ECMAScript's JSON.stringify quotes it. */
function quote(text: string): string {
	let out = '"';
	for (let i = 0; i < text.length; i++) {
		const c = text.charCodeAt(i);
		if (c === 0x22) out += '\\"';
		else if (c === 0x5c) out += '\\\\';
		else if (c === 0x08) out += '\\b';
		else if (c === 0x0c) out += '\\f';
		else if (c === 0x0a) out += '\\n';
		else if (c === 0x0d) out += '\\r';
		else if (c === 0x09) out += '\\t';
		else if (c < 0x20) out += '\\u' + c.toString(16).padStart(4, '0');
		else out += text[i];
	}
	return out + '"';
}

/** The canonical form (§5.1): two-space indents, members in their order. */
export function canonicalJson(value: JsonValue): string {
	return pretty(value, '') + '\n';
}

function pretty(value: JsonValue, indent: string): string {
	if (value === null) return 'null';
	if (typeof value === 'boolean' || typeof value === 'number') return String(value);
	if (typeof value === 'string') return quote(value);
	const inner = indent + '  ';
	if (Array.isArray(value)) {
		if (value.length === 0) return '[]';
		return '[\n' + value.map((item) => inner + pretty(item, inner)).join(',\n') + '\n' + indent + ']';
	}
	if (value.size === 0) return '{}';
	const members: string[] = [];
	for (const [name, member] of value) members.push(inner + quote(name) + ': ' + pretty(member, inner));
	return '{\n' + members.join(',\n') + '\n' + indent + '}';
}

/** RFC 8785 (JCS): no whitespace, members sorted by UTF-16 code units. */
export function jcs(value: JsonValue): string {
	if (value === null) return 'null';
	if (typeof value === 'boolean' || typeof value === 'number') return String(value);
	if (typeof value === 'string') return quote(value);
	if (Array.isArray(value)) return '[' + value.map(jcs).join(',') + ']';
	const names = [...value.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
	return '{' + names.map((name) => quote(name) + ':' + jcs(value.get(name)!)).join(',') + '}';
}

/* ------------------------------------------------------------------ */
/* Small tree helpers                                                  */
/* ------------------------------------------------------------------ */

const isObject = (value: JsonValue | undefined): value is JsonObject => value instanceof Map;
const isInt = (value: JsonValue | undefined): value is number =>
	typeof value === 'number' && Number.isSafeInteger(value);
const isString = (value: JsonValue | undefined): value is string => typeof value === 'string';

function cloneJson(value: JsonValue): JsonValue {
	if (Array.isArray(value)) return value.map(cloneJson);
	if (isObject(value)) return new Map([...value].map(([name, member]) => [name, cloneJson(member)]));
	return value;
}

/** The members of `object` in canonical order: known first, in `order`,
	then the rest as they were (§5.1). */
function ordered(object: JsonObject, order: readonly string[]): JsonObject {
	const out: JsonObject = new Map();
	for (const name of order) if (object.has(name)) out.set(name, object.get(name)!);
	for (const [name, member] of object) if (!out.has(name)) out.set(name, member);
	return out;
}

const mapArray = (value: JsonValue | undefined, fn: (item: JsonObject) => JsonObject): JsonValue | undefined =>
	Array.isArray(value) ? value.map((item) => (isObject(item) ? fn(item) : item)) : value;

function withMember(object: JsonObject, name: string, value: JsonValue | undefined): JsonObject {
	if (value !== undefined) object.set(name, value);
	return object;
}

function canonicalScript(script: JsonObject): JsonObject {
	const out = ordered(script, ORDER.script);
	withMember(out, 'titlePage', mapArray(out.get('titlePage'), (line) =>
		withMember(ordered(line, ORDER.titleLine), 'runs', mapArray(line.get('runs'), (run) => ordered(run, ORDER.run)))));
	withMember(out, 'elements', mapArray(out.get('elements'), (element) =>
		withMember(ordered(element, ORDER.element), 'runs', mapArray(element.get('runs'), (run) => ordered(run, ORDER.run)))));
	return out;
}

function canonicalNotes(notes: JsonObject): JsonObject {
	const out = ordered(notes, ORDER.notes);
	withMember(out, 'threads', mapArray(out.get('threads'), (thread) => {
		const t = ordered(thread, ORDER.thread);
		const anchor = t.get('anchor');
		if (isObject(anchor)) t.set('anchor', ordered(anchor, ORDER.anchor));
		withMember(t, 'messages', mapArray(t.get('messages'), (message) => ordered(message, ORDER.message)));
		withMember(t, 'status', mapArray(t.get('status'), (status) => ordered(status, ORDER.status)));
		return t;
	}));
	return out;
}

/* ------------------------------------------------------------------ */
/* Schema checks (§5.2–§5.4). Each returns the first problem, or null. */
/* ------------------------------------------------------------------ */

function checkRuns(runs: JsonValue | undefined, textLength: number): string | null {
	if (runs === undefined) return null;
	if (!Array.isArray(runs)) return 'runs is not an array';
	let end = 0;
	for (const run of runs) {
		if (!isObject(run)) return 'a run is not an object';
		const start = run.get('start');
		const stop = run.get('end');
		if (!isInt(start) || !isInt(stop) || start < end || stop <= start || stop > textLength) return 'a run is out of place';
		end = stop;
		const styles = run.get('styles');
		if (!Array.isArray(styles) || styles.some((token) => !isString(token) || !STYLE_TOKENS.includes(token))) {
			return 'a run has unknown styles';
		}
		if (new Set(styles).size !== styles.length) return 'a run repeats a style';
		const highlight = run.get('highlight');
		if (highlight !== undefined && highlight !== 'yellow') return 'a run has an unknown highlight';
		const revision = run.get('revisionID');
		if (revision !== undefined && !isInt(revision)) return 'a run has a bad revisionID';
		const tags = run.get('tagNumbers');
		if (tags !== undefined && (!Array.isArray(tags) || !tags.every(isInt))) return 'a run has bad tagNumbers';
	}
	return null;
}

/** Problems with script.json, or null when it is a valid script. */
export function checkDraftScript(script: JsonValue): string | null {
	if (!isObject(script)) return 'script.json is not an object';
	const titlePage = script.get('titlePage');
	if (!Array.isArray(titlePage)) return 'titlePage is not an array';
	if (titlePage.length > MAX_TITLE_LINES) return 'too many title-page lines';
	for (const line of titlePage) {
		if (!isObject(line) || !isString(line.get('text'))) return 'a title-page line has no text';
		const key = line.get('key');
		if (key !== undefined && !isString(key)) return 'a title-page key is not a string';
		const alignment = line.get('alignment');
		if (alignment !== undefined && alignment !== 'left' && alignment !== 'center' && alignment !== 'right') {
			return 'a title-page alignment is unknown';
		}
		const problem = checkRuns(line.get('runs'), (line.get('text') as string).length);
		if (problem) return problem;
	}
	const elements = script.get('elements');
	if (!Array.isArray(elements)) return 'elements is not an array';
	if (elements.length > MAX_ELEMENTS) return 'too many elements';
	const ids = new Set<string>();
	for (const element of elements) {
		if (!isObject(element)) return 'an element is not an object';
		const id = element.get('id');
		if (!isString(id) || !ID_PATTERN.test(id)) return 'an element id is malformed';
		if (ids.has(id)) return `element id ${id} is used twice`;
		ids.add(id);
		const type = element.get('type');
		if (!isString(type) || !ELEMENT_TYPES.has(type)) return `element ${id} has an unknown type`;
		const text = element.get('text');
		if (!isString(text)) return `element ${id} has no text`;
		if (text.length > MAX_ELEMENT_TEXT) return `element ${id} is too long`;
		const problem = checkRuns(element.get('runs'), text.length);
		if (problem) return `element ${id}: ${problem}`;
		const dual = element.get('dual');
		if (dual !== undefined && typeof dual !== 'boolean') return `element ${id} has a bad dual`;
		const sceneNumber = element.get('sceneNumber');
		if (sceneNumber !== undefined && !isString(sceneNumber)) return `element ${id} has a bad sceneNumber`;
		const depth = element.get('depth');
		if (depth !== undefined && (!isInt(depth) || depth < 1 || depth > MAX_SECTION_DEPTH)) {
			return `element ${id} has a bad depth`;
		}
	}
	const nextId = script.get('nextId');
	if (!isString(nextId) || !ID_PATTERN.test(nextId)) return 'nextId is malformed';
	return null;
}

/** Problems with notes.json, or null when it is valid. */
export function checkDraftNotes(notes: JsonValue): string | null {
	if (!isObject(notes)) return 'notes.json is not an object';
	const threads = notes.get('threads');
	if (!Array.isArray(threads)) return 'threads is not an array';
	const ids = new Set<string>();
	const claim = (id: JsonValue | undefined): string | null => {
		if (!isString(id) || !ID_PATTERN.test(id)) return 'a note id is malformed';
		if (ids.has(id)) return `note id ${id} is used twice`;
		ids.add(id);
		return null;
	};
	const optionalStrings = (object: JsonObject, names: readonly string[]): boolean =>
		names.every((name) => object.get(name) === undefined || isString(object.get(name)));
	for (const thread of threads) {
		if (!isObject(thread)) return 'a thread is not an object';
		const problem = claim(thread.get('id'));
		if (problem) return problem;
		const anchor = thread.get('anchor');
		if (anchor !== undefined) {
			if (!isObject(anchor)) return 'an anchor is not an object';
			const element = anchor.get('element');
			if (!isString(element) || !ID_PATTERN.test(element)) return 'an anchor names no element';
			const start = anchor.get('start');
			const end = anchor.get('end');
			if ((start === undefined) !== (end === undefined)) return 'an anchor has only one end';
			if (start !== undefined && (!isInt(start) || !isInt(end) || start < 0 || end < start)) {
				return 'an anchor range is malformed';
			}
			if (!optionalStrings(anchor, ['quote', 'prefix', 'suffix'])) return 'an anchor quote is not a string';
		}
		const messages = thread.get('messages');
		if (!Array.isArray(messages) || messages.length === 0) return 'a thread has no messages';
		for (const message of messages) {
			if (!isObject(message)) return 'a message is not an object';
			const messageProblem = claim(message.get('id'));
			if (messageProblem) return messageProblem;
			if (!isString(message.get('text'))) return 'a message has no text';
			if (!optionalStrings(message, ['by', 'role', 'at'])) return 'a message field is not a string';
			const source = message.get('source');
			if (source !== undefined && (!isObject(source) || ![...source.values()].every(isString))) {
				return 'a message source is malformed';
			}
		}
		const status = thread.get('status');
		if (status !== undefined) {
			if (!Array.isArray(status)) return 'status is not an array';
			for (const entry of status) {
				if (!isObject(entry)) return 'a status entry is not an object';
				if (entry.get('state') !== 'open' && entry.get('state') !== 'resolved') return 'a status state is unknown';
				if (!optionalStrings(entry, ['by', 'at'])) return 'a status field is not a string';
			}
		}
	}
	const nextId = notes.get('nextId');
	if (!isString(nextId) || !ID_PATTERN.test(nextId)) return 'nextId is malformed';
	return null;
}

function checkManifest(manifest: JsonValue): string | null {
	if (!isObject(manifest)) return 'manifest.json is not an object';
	if (manifest.get('format') !== 'draft') return 'format is not "draft"';
	for (const name of ['version', 'minReader']) {
		const version = manifest.get(name);
		if (!isString(version) || !VERSION_PATTERN.test(version)) return `${name} is malformed`;
	}
	const writer = manifest.get('writer');
	if (!isObject(writer) || !isString(writer.get('name')) || !isString(writer.get('version'))) return 'writer is malformed';
	const title = manifest.get('title');
	if (title !== undefined && !isString(title)) return 'title is not a string';
	const parts = manifest.get('parts');
	if (!Array.isArray(parts)) return 'parts is not an array';
	for (const part of parts) {
		if (!isObject(part) || !isString(part.get('path'))) return 'a part has no path';
		const sha = part.get('sha256');
		if (!isString(sha) || !HEX64.test(sha)) return 'a part digest is malformed';
		const size = part.get('size');
		if (!isInt(size) || size < 0) return 'a part size is malformed';
	}
	const fingerprints = manifest.get('fingerprints');
	if (!isObject(fingerprints)) return 'fingerprints is missing';
	const script = fingerprints.get('script');
	if (!isString(script) || !HEX64.test(script)) return 'the script fingerprint is malformed';
	const notes = fingerprints.get('notes');
	if (notes !== undefined && (!isString(notes) || !HEX64.test(notes))) return 'the notes fingerprint is malformed';
	return null;
}

/** §4.2's path rules. */
export function isValidDraftPath(path: string): boolean {
	if (path.length === 0 || path.startsWith('/') || path.endsWith('/') || path.includes('\\')) return false;
	if (/[\x00-\x1f\x7f]/.test(path) || /^[A-Za-z]:/.test(path)) return false;
	return path.split('/').every((segment) => segment.length > 0 && segment !== '.' && segment !== '..');
}

/* ------------------------------------------------------------------ */
/* Anchors (§6.5)                                                      */
/* ------------------------------------------------------------------ */

function occurrences(haystack: string, needle: string): number[] {
	const found: number[] = [];
	if (needle.length === 0) return found;
	for (let at = haystack.indexOf(needle); at >= 0; at = haystack.indexOf(needle, at + 1)) found.push(at);
	return found;
}

/** Re-find every thread's anchor against the script: hold, move within
	its element, move elsewhere with a flag, or detach with a flag. When the
	script was rebuilt from its rendition its ids are new, so no anchor's
	element is trusted: each is found by its words or detached. */
function refindAnchors(script: JsonObject, notes: JsonObject, diagnostics: DraftDiagnostic[], idsTrusted: boolean): void {
	const texts = new Map<string, string>();
	for (const element of script.get('elements') as JsonValue[]) {
		const e = element as JsonObject;
		texts.set(e.get('id') as string, e.get('text') as string);
	}
	for (const item of notes.get('threads') as JsonValue[]) {
		const thread = item as JsonObject;
		const id = thread.get('id') as string;
		const anchor = thread.get('anchor');
		if (!isObject(anchor)) continue;
		const element = anchor.get('element') as string;
		const quote = anchor.get('quote');
		const start = anchor.get('start');
		const end = anchor.get('end');
		const text = idsTrusted ? texts.get(element) : undefined;
		const needle = isString(quote)
			? (isString(anchor.get('prefix')) ? (anchor.get('prefix') as string) : '') +
				quote +
				(isString(anchor.get('suffix')) ? (anchor.get('suffix') as string) : '')
			: undefined;
		const prefixLength = isString(anchor.get('prefix')) ? (anchor.get('prefix') as string).length : 0;
		const place = (at: number): void => {
			anchor.set('start', at + prefixLength);
			anchor.set('end', at + prefixLength + (quote as string).length);
		};
		if (text !== undefined) {
			if (!isString(quote)) continue;
			if (isInt(start) && isInt(end) && text.slice(start, end) === quote) continue;
			const found = occurrences(text, needle!);
			if (found.length === 1) {
				place(found[0]!);
				continue;
			}
			if (isInt(start) && isInt(end)) {
				const s = Math.min(start, text.length);
				anchor.set('start', s);
				anchor.set('end', Math.max(s, Math.min(end, text.length)));
			}
			diagnostics.push({ code: 'anchor-words-changed', thread: id });
			continue;
		}
		if (needle !== undefined) {
			const hits: Array<[string, number]> = [];
			for (const [elementId, elementText] of texts) {
				for (const at of occurrences(elementText, needle)) hits.push([elementId, at]);
			}
			if (hits.length === 1) {
				anchor.set('element', hits[0]![0]);
				place(hits[0]![1]);
				diagnostics.push({ code: 'anchor-moved', thread: id });
				continue;
			}
		}
		thread.delete('anchor');
		diagnostics.push({ code: 'anchor-detached', thread: id });
	}
}

/** JavaScript's \s, one UTF-16 unit at a time — the Swift port matches it. */
function isSpaceUnit(code: number): boolean {
	return (
		(code >= 0x09 && code <= 0x0d) || code === 0x20 || code === 0xa0 || code === 0x1680 ||
		(code >= 0x2000 && code <= 0x200a) || code === 0x2028 || code === 0x2029 || code === 0x202f ||
		code === 0x205f || code === 0x3000 || code === 0xfeff
	);
}

/** The words either side of a quote (§6.3): up to 16 units each side, the
	window's outer edge moved inward so it never cuts a word. */
export function draftAnchorContext(text: string, start: number, end: number): { prefix: string; suffix: string } {
	let from = Math.max(0, start - CONTEXT_UNITS);
	if (from > 0 && !isSpaceUnit(text.charCodeAt(from - 1))) {
		while (from < start && !isSpaceUnit(text.charCodeAt(from))) from++;
		if (from < start) from++;
	}
	let to = Math.min(text.length, end + CONTEXT_UNITS);
	if (to < text.length && !isSpaceUnit(text.charCodeAt(to))) {
		while (to > end && !isSpaceUnit(text.charCodeAt(to - 1))) to--;
		if (to > end) to--;
	}
	return { prefix: text.slice(from, start), suffix: text.slice(end, to) };
}

/* ------------------------------------------------------------------ */
/* Bridges to today's model                                            */
/* ------------------------------------------------------------------ */

function runsToJson(runs: readonly StyleRun[] | undefined): JsonValue | undefined {
	if (runs === undefined) return undefined;
	return runs.map((run) => {
		const out: JsonObject = new Map<string, JsonValue>([
			['start', run.start],
			['end', run.end],
			['styles', [...run.styles]]
		]);
		if (run.highlight !== undefined) out.set('highlight', run.highlight);
		if (run.revisionID !== undefined) out.set('revisionID', run.revisionID);
		if (run.tagNumbers !== undefined) out.set('tagNumbers', [...run.tagNumbers]);
		return out;
	});
}

function runsFromJson(value: JsonValue | undefined): StyleRun[] | undefined {
	if (!Array.isArray(value)) return undefined;
	return value.map((item) => {
		const run = item as JsonObject;
		const out: StyleRun = {
			start: run.get('start') as number,
			end: run.get('end') as number,
			styles: [...(run.get('styles') as string[])] as StyleRun['styles']
		};
		if (run.get('highlight') !== undefined) out.highlight = run.get('highlight') as 'yellow';
		if (run.get('revisionID') !== undefined) out.revisionID = run.get('revisionID') as number;
		if (run.get('tagNumbers') !== undefined) out.tagNumbers = [...(run.get('tagNumbers') as number[])];
		return out;
	});
}

/**
 * A document from today's model (§6.6): every element gets a counter id,
 * and every note element becomes a thread anchored to the whole element
 * after it — the one the parser places it in front of. A note after the
 * last element is about no line, so it is a detached thread, which the
 * bridge back puts at the end where it was. Its text is kept whole; author
 * recognition belongs to the apps.
 */
export function draftFromScreenplay(screenplay: Screenplay, options: { title?: string } = {}): DraftDocument {
	const elements: JsonValue[] = [];
	const pending: string[] = [];
	const threads: JsonValue[] = [];
	let nextNote = 1;
	const anchorPending = (element: string | undefined): void => {
		for (const text of pending.splice(0)) {
			const thread: JsonObject = new Map<string, JsonValue>([['id', (nextNote++).toString(36)]]);
			if (element !== undefined) thread.set('anchor', new Map<string, JsonValue>([['element', element]]));
			thread.set('messages', [new Map<string, JsonValue>([['id', (nextNote++).toString(36)], ['text', text]])]);
			threads.push(thread);
		}
	};
	for (const element of screenplay.elements) {
		if (element.type === 'note') {
			pending.push(element.text);
			continue;
		}
		const id = (elements.length + 1).toString(36);
		const out: JsonObject = new Map<string, JsonValue>([
			['id', id],
			['type', element.type],
			['text', element.text]
		]);
		withMember(out, 'runs', runsToJson(element.runs));
		if (element.dual !== undefined) out.set('dual', element.dual);
		if (element.sceneNumber !== undefined) out.set('sceneNumber', element.sceneNumber);
		if (element.depth !== undefined) out.set('depth', element.depth);
		elements.push(out);
		anchorPending(id);
	}
	anchorPending(undefined);
	const titlePage: JsonValue[] = screenplay.titlePage.map((line) => {
		const out: JsonObject = new Map();
		if (line.key !== undefined) out.set('key', line.key);
		out.set('text', line.text);
		if (line.alignment !== undefined) out.set('alignment', line.alignment);
		withMember(out, 'runs', runsToJson(line.runs));
		return out;
	});
	const document: DraftDocument = {
		script: new Map<string, JsonValue>([
			['titlePage', titlePage],
			['elements', elements],
			['nextId', (elements.length + 1).toString(36)]
		]),
		parts: []
	};
	if (options.title !== undefined) document.title = options.title;
	if (threads.length > 0) {
		document.notes = new Map<string, JsonValue>([
			['threads', threads],
			['nextId', nextNote.toString(36)]
		]);
	}
	return document;
}

/**
 * Today's model from a document: each thread becomes a note element in
 * front of its element, its messages one line each as "Name (Role): text".
 * What today's model cannot hold is said: a word anchor degrades to its
 * line, a detached thread goes to the end.
 */
export function draftToScreenplay(document: DraftDocument): { screenplay: Screenplay; diagnostics: DraftDiagnostic[] } {
	const diagnostics: DraftDiagnostic[] = [];
	const notesFor = new Map<string, string[]>();
	const detached: string[] = [];
	const threads = document.notes?.get('threads');
	for (const item of Array.isArray(threads) ? threads : []) {
		const thread = item as JsonObject;
		const text = (thread.get('messages') as JsonValue[])
			.map((m) => {
				const message = m as JsonObject;
				const by = message.get('by');
				const role = message.get('role');
				const author = isString(by) ? (isString(role) ? `${by} (${role})` : by) : undefined;
				return author !== undefined ? `${author}: ${message.get('text') as string}` : (message.get('text') as string);
			})
			.join('\n');
		const anchor = thread.get('anchor');
		if (!isObject(anchor)) {
			detached.push(text);
			diagnostics.push({ code: 'anchor-detached', thread: thread.get('id') as string });
			continue;
		}
		if (anchor.get('start') !== undefined || anchor.get('quote') !== undefined) {
			diagnostics.push({ code: 'anchor-degraded', thread: thread.get('id') as string });
		}
		const element = anchor.get('element') as string;
		notesFor.set(element, [...(notesFor.get(element) ?? []), text]);
	}
	const elements: ScreenplayElement[] = [];
	for (const item of document.script.get('elements') as JsonValue[]) {
		const e = item as JsonObject;
		for (const text of notesFor.get(e.get('id') as string) ?? []) elements.push({ type: 'note', text });
		const element: ScreenplayElement = { type: e.get('type') as ScreenplayElement['type'], text: e.get('text') as string };
		const runs = runsFromJson(e.get('runs'));
		if (runs !== undefined) element.runs = runs;
		if (e.get('dual') !== undefined) element.dual = e.get('dual') as boolean;
		if (e.get('sceneNumber') !== undefined) element.sceneNumber = e.get('sceneNumber') as string;
		if (e.get('depth') !== undefined) element.depth = e.get('depth') as number;
		elements.push(element);
	}
	for (const text of detached) elements.push({ type: 'note', text });
	const titlePage: TitlePageLine[] = (document.script.get('titlePage') as JsonValue[]).map((item) => {
		const l = item as JsonObject;
		const line: TitlePageLine = { text: l.get('text') as string };
		if (l.get('alignment') !== undefined) line.alignment = l.get('alignment') as TitlePageLine['alignment'] & string;
		const runs = runsFromJson(l.get('runs'));
		if (runs !== undefined) line.runs = runs;
		if (l.get('key') !== undefined) line.key = l.get('key') as string;
		return line;
	});
	return { screenplay: { titlePage, elements }, diagnostics };
}

/* ------------------------------------------------------------------ */
/* Recognising a file by its first bytes (§11.1)                       */
/* ------------------------------------------------------------------ */

function startsWithAscii(bytes: Uint8Array, at: number, text: string): boolean {
	if (at + text.length > bytes.length) return false;
	for (let i = 0; i < text.length; i++) if (bytes[at + i] !== text.charCodeAt(i)) return false;
	return true;
}

function isUtf8(bytes: Uint8Array): boolean {
	let i = 0;
	while (i < bytes.length) {
		const b = bytes[i]!;
		const need = b < 0x80 ? 0 : b >= 0xc2 && b <= 0xdf ? 1 : b >= 0xe0 && b <= 0xef ? 2 : b >= 0xf0 && b <= 0xf4 ? 3 : -1;
		if (need < 0 || i + need >= bytes.length + (need === 0 ? 1 : 0)) return false;
		for (let k = 1; k <= need; k++) if ((bytes[i + k]! & 0xc0) !== 0x80) return false;
		if (need === 2) {
			const code = ((b & 0x0f) << 12) | ((bytes[i + 1]! & 0x3f) << 6) | (bytes[i + 2]! & 0x3f);
			if (code < 0x800 || (code >= 0xd800 && code <= 0xdfff)) return false;
		}
		if (need === 3) {
			const code = ((b & 0x07) << 18) | ((bytes[i + 1]! & 0x3f) << 12) | ((bytes[i + 2]! & 0x3f) << 6) | (bytes[i + 3]! & 0x3f);
			if (code < 0x10000 || code > 0x10ffff) return false;
		}
		i += need + 1;
	}
	return true;
}

/** What a file is, from its bytes — never from its name. */
export function detectDraftFormat(bytes: Uint8Array): DraftFormat {
	if (startsWithAscii(bytes, 0, 'PK')) {
		let at = 0;
		for (let n = 0; n < 512 && at + 30 <= bytes.length && startsWithAscii(bytes, at, 'PK'); n++) {
			const nameLength = bytes[at + 26]! | (bytes[at + 27]! << 8);
			const extraLength = bytes[at + 28]! | (bytes[at + 29]! << 8);
			const packed = (bytes[at + 18]! | (bytes[at + 19]! << 8) | (bytes[at + 20]! << 16) | (bytes[at + 21]! << 24)) >>> 0;
			const name = String.fromCharCode(...bytes.subarray(at + 30, Math.min(bytes.length, at + 30 + nameLength)));
			if (name === 'mimetype' || name === 'manifest.json' || name === 'script.json') return 'draft';
			at += 30 + nameLength + extraLength + packed;
		}
		return 'unknown';
	}
	if (startsWithAscii(bytes, 0, '%PDF-')) return 'pdf';
	let at = startsWithAscii(bytes, 0, 'ï»¿') ? 3 : 0;
	while (at < bytes.length && (bytes[at] === 0x20 || bytes[at] === 0x09 || bytes[at] === 0x0a || bytes[at] === 0x0d)) at++;
	if (startsWithAscii(bytes, at, '<?xml') || startsWithAscii(bytes, at, '<FinalDraft')) return 'fdx';
	return isUtf8(bytes) ? 'text' : 'unknown';
}

/* ------------------------------------------------------------------ */
/* Writing (§4, §5)                                                    */
/* ------------------------------------------------------------------ */

const FIXED_PATHS = ['mimetype', 'manifest.json', 'script.json', 'notes.json', 'script.fountain'];

const byUnits = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);

/** Write a document as a .draft file — the same bytes on every platform. */
export function writeDraft(document: DraftDocument, options: DraftWriteOptions): Uint8Array {
	const scriptProblem = checkDraftScript(document.script);
	if (scriptProblem) throw new DraftFormatError('invalid-document', `the script is invalid: ${scriptProblem}`);
	if (document.notes !== undefined) {
		const notesProblem = checkDraftNotes(document.notes);
		if (notesProblem) throw new DraftFormatError('invalid-document', `the notes are invalid: ${notesProblem}`);
	}
	const script = canonicalScript(document.script);
	const notes = document.notes === undefined ? undefined : canonicalNotes(document.notes);

	/* Fresh parts, then what is carried. A damaged part keeps its path unless
       a fresh part takes it; then it moves to damaged/, never away (§7.2). */
	const fresh = new Map<string, Uint8Array>();
	fresh.set('script.json', encodeUtf8(canonicalJson(script)));
	if (notes !== undefined) fresh.set('notes.json', encodeUtf8(canonicalJson(notes)));
	fresh.set('script.fountain', encodeUtf8(serialiseFountain(draftToScreenplay({ ...document, script }).screenplay)));
	const carried = new Map<string, Uint8Array>();
	for (const part of document.parts) {
		let path = part.path;
		if (!isValidDraftPath(path)) throw new DraftFormatError('invalid-document', `part path "${path}" is not allowed`);
		const taken = fresh.has(path) || path === 'mimetype' || path === 'manifest.json';
		if (taken) {
			if (part.damaged !== true) throw new DraftFormatError('invalid-document', `part "${path}" is written by the writer`);
			path = `damaged/${path}`;
		}
		while (carried.has(path)) path = `damaged/${path}`;
		carried.set(path, part.data);
	}
	const origin = [...carried.keys()].filter((path) => path.startsWith('origin/')).sort(byUnits);
	const extensions = [...carried.keys()].filter((path) => path.startsWith('ext/')).sort(byUnits);
	const others = [...carried.keys()]
		.filter((path) => !path.startsWith('origin/') && !path.startsWith('ext/'))
		.sort(byUnits);
	const body: Array<[string, Uint8Array]> = [];
	for (const path of ['script.json', 'notes.json', 'script.fountain']) {
		if (fresh.has(path)) body.push([path, fresh.get(path)!]);
		else if (carried.has(path)) {
			body.push([path, carried.get(path)!]);
			carried.delete(path);
		}
	}
	for (const path of [...origin, ...others, ...extensions]) {
		if (carried.has(path)) body.push([path, carried.get(path)!]);
	}

	const manifest: JsonObject = new Map<string, JsonValue>([
		['format', 'draft'],
		['version', DRAFT_FORMAT_VERSION],
		['minReader', MIN_READER],
		['writer', new Map<string, JsonValue>([['name', options.writer.name], ['version', options.writer.version]])]
	]);
	if (document.title !== undefined) manifest.set('title', document.title);
	manifest.set(
		'parts',
		body.map(([path, data]) => new Map<string, JsonValue>([['path', path], ['sha256', sha256Hex(data)], ['size', data.length]]))
	);
	const fingerprints: JsonObject = new Map<string, JsonValue>([['script', sha256Hex(encodeUtf8(jcs(script)))]]);
	if (notes !== undefined) fingerprints.set('notes', sha256Hex(encodeUtf8(jcs(notes))));
	manifest.set('fingerprints', fingerprints);
	for (const [name, value] of document.manifestExtra ?? []) {
		if (!ORDER.manifest.includes(name as (typeof ORDER.manifest)[number])) manifest.set(name, cloneJson(value));
	}

	return writeZipStored(
		[
			{ name: 'mimetype', data: encodeUtf8(DRAFT_MEDIA_TYPE) },
			{ name: 'manifest.json', data: encodeUtf8(canonicalJson(manifest)) },
			...body.map(([name, data]) => ({ name, data }))
		],
		{ dosDate: DOS_DATE_1980, dosTime: 0, utf8Names: true }
	);
}

/* ------------------------------------------------------------------ */
/* Reading (§7, §8, §11)                                               */
/* ------------------------------------------------------------------ */

function readJson(data: Uint8Array): JsonValue | undefined {
	if (!isUtf8(data)) return undefined;
	try {
		return parseDraftJson(decodeUtf8(data));
	} catch (error) {
		if (error instanceof JsonError) return undefined;
		throw error;
	}
}

function parseVersion(version: string): [number, number] {
	const [major, minor] = version.split('.');
	return [Number(major), Number(minor)];
}

/**
 * Read a .draft file. Every rung of the recovery ladder (§7.2) is here: an
 * outside edit is used and said; a damaged part is kept byte for byte and
 * said; a damaged script opens from its Fountain rendition, and says so; a
 * truncated file is read from its local headers. A file with no script in
 * any readable form is refused — never opened empty.
 */
export async function readDraft(bytes: Uint8Array): Promise<DraftReadResult> {
	if (bytes.length > MAX_FILE_BYTES) {
		throw new DraftFormatError('over-limits', `the file is over the ${MAX_FILE_BYTES}-byte limit`);
	}
	let zip: ZipTolerantResult;
	try {
		zip = await readZipEntriesTolerant(bytes);
	} catch (error) {
		if (!(error instanceof ZipFormatError)) throw error;
		const limits = /limit/.test(error.message);
		throw new DraftFormatError(limits ? 'over-limits' : 'not-a-draft', `not a readable .draft: ${error.message}`);
	}
	const diagnostics: DraftDiagnostic[] = [];
	if (zip.directory === 'local') diagnostics.push({ code: 'directory-damaged', detail: 'read from the local headers' });

	/* Entries by path, first of a name wins; the rest are kept, not lost. */
	const entries = new Map<string, { data: Uint8Array; error?: string }>();
	const seen = new Set<string>();
	const parts: DraftPart[] = [];
	zip.entries.forEach((entry, index) => {
		const validName = isUtf8(entry.nameBytes) && isValidDraftPath(entry.name);
		const key = entry.name.normalize('NFC').toLowerCase();
		if (!validName || seen.has(key)) {
			diagnostics.push({
				code: validName ? 'duplicate-entry' : 'invalid-entry-name',
				path: `damaged/entry-${index}`,
				detail: validName ? entry.name : 'the name is not an allowed path'
			});
			parts.push({ path: `damaged/entry-${index}`, data: entry.data, damaged: true });
			return;
		}
		seen.add(key);
		entries.set(entry.name, entry.error === undefined ? { data: entry.data } : { data: entry.data, error: entry.error });
	});
	const isDraft = ['mimetype', 'manifest.json', 'script.json', 'script.fountain'].some((path) => entries.has(path));
	if (!isDraft) throw new DraftFormatError('not-a-draft', 'the archive is not a .draft (no mimetype, manifest or script)');

	const damaged = (path: string, detail: string): void => {
		diagnostics.push({ code: 'part-damaged', path, detail });
		parts.push({ path, data: entries.get(path)!.data, damaged: true });
	};

	/* mimetype (§4.2) */
	const mimetype = entries.get('mimetype');
	if (mimetype === undefined) diagnostics.push({ code: 'mimetype-missing' });
	else if (
		mimetype.error !== undefined ||
		zip.entries[0]?.name !== 'mimetype' ||
		!isUtf8(mimetype.data) ||
		decodeUtf8(mimetype.data) !== DRAFT_MEDIA_TYPE
	) {
		diagnostics.push({ code: 'mimetype-wrong' });
		parts.push({ path: 'mimetype', data: mimetype.data, damaged: true });
	}

	/* manifest.json (§5.2, §8.1) */
	let readOnly = false;
	let listed: Map<string, string> | undefined;
	let title: string | undefined;
	let manifestExtra: JsonObject | undefined;
	const manifestEntry = entries.get('manifest.json');
	const manifest = manifestEntry?.error === undefined && manifestEntry ? readJson(manifestEntry.data) : undefined;
	const manifestProblem = manifest === undefined ? 'it is not valid I-JSON' : checkManifest(manifest);
	if (manifestEntry === undefined || manifestProblem !== null) {
		diagnostics.push({ code: 'manifest-unreadable', detail: manifestEntry === undefined ? 'it is missing' : manifestEntry.error ?? manifestProblem! });
		if (manifestEntry !== undefined) parts.push({ path: 'manifest.json', data: manifestEntry.data, damaged: true });
	} else {
		const m = manifest as JsonObject;
		const [major] = parseVersion(m.get('version') as string);
		const [readerMajor, readerMinor] = parseVersion(m.get('minReader') as string);
		const [ourMajor, ourMinor] = parseVersion(DRAFT_FORMAT_VERSION);
		if (major > ourMajor || readerMajor > ourMajor) {
			throw new DraftFormatError('newer-major', `the file needs a reader of version ${m.get('minReader') as string} or later`);
		}
		if (readerMajor === ourMajor && readerMinor > ourMinor) {
			readOnly = true;
			diagnostics.push({ code: 'read-only-newer-minor', detail: m.get('minReader') as string });
		}
		listed = new Map();
		for (const part of m.get('parts') as JsonValue[]) {
			const p = part as JsonObject;
			listed.set(p.get('path') as string, p.get('sha256') as string);
		}
		if (isString(m.get('title'))) title = m.get('title') as string;
		for (const [name, value] of m) {
			if (!ORDER.manifest.includes(name as (typeof ORDER.manifest)[number])) {
				manifestExtra ??= new Map();
				manifestExtra.set(name, value);
			}
		}
	}
	if (listed !== undefined) {
		for (const path of listed.keys()) if (!entries.has(path)) diagnostics.push({ code: 'missing-part', path });
		for (const path of entries.keys()) {
			if (path !== 'mimetype' && path !== 'manifest.json' && !listed.has(path)) diagnostics.push({ code: 'unlisted-part', path });
		}
	}
	/** A part's JSON if it is whole and valid; an outside edit is said. */
	const jsonPart = (path: string, check: (value: JsonValue) => string | null): JsonObject | undefined => {
		const entry = entries.get(path);
		if (entry === undefined) return undefined;
		if (entry.error !== undefined) {
			damaged(path, entry.error);
			return undefined;
		}
		const value = readJson(entry.data);
		const problem = value === undefined ? 'it is not valid I-JSON' : check(value);
		if (problem !== null) {
			damaged(path, problem);
			return undefined;
		}
		const digest = listed?.get(path);
		if (digest !== undefined && digest !== sha256Hex(entry.data)) diagnostics.push({ code: 'outside-edit', path });
		return value as JsonObject;
	};

	/* script.json, or the rendition (§5.5, §7.2) */
	let script = jsonPart('script.json', checkDraftScript);
	let notes = jsonPart('notes.json', checkDraftNotes);
	let fromRenditionIds = false;
	const rendition = entries.get('script.fountain');
	if (rendition !== undefined && rendition.error !== undefined) damaged('script.fountain', rendition.error);
	if (script === undefined) {
		if (rendition === undefined || rendition.error !== undefined || !isUtf8(rendition.data)) {
			throw new DraftFormatError('no-script', 'neither script.json nor its Fountain rendition can be read');
		}
		let fromRendition: DraftDocument;
		try {
			fromRendition = draftFromScreenplay(parseFountain(decodeUtf8(rendition.data), { emphasis: 'runs' }));
		} catch {
			throw new DraftFormatError('no-script', 'neither script.json nor its Fountain rendition can be read');
		}
		diagnostics.push({ code: 'script-from-rendition', detail: 'element ids and word anchors are lost' });
		script = fromRendition.script;
		if (notes === undefined && fromRendition.notes !== undefined) notes = fromRendition.notes;
		else fromRenditionIds = true;
	} else if (rendition !== undefined && rendition.error === undefined && listed?.has('script.fountain')) {
		const digest = listed.get('script.fountain');
		if (digest !== sha256Hex(rendition.data)) diagnostics.push({ code: 'outside-edit', path: 'script.fountain' });
	}

	/* Everything else is carried as it came (§5.6, §8.2). */
	for (const [path, entry] of entries) {
		if (FIXED_PATHS.includes(path)) continue;
		if (entry.error !== undefined) {
			damaged(path, entry.error);
			continue;
		}
		const digest = listed?.get(path);
		if (digest !== undefined && digest !== sha256Hex(entry.data)) diagnostics.push({ code: 'outside-edit', path });
		parts.push({ path, data: entry.data });
	}

	if (notes !== undefined) refindAnchors(script, notes, diagnostics, !fromRenditionIds);
	const document: DraftDocument = { script, parts };
	if (notes !== undefined) document.notes = notes;
	if (title !== undefined) document.title = title;
	if (manifestExtra !== undefined) document.manifestExtra = manifestExtra;
	return { document, diagnostics, readOnly };
}
