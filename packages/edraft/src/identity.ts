import type { Screenplay, ScreenplayElement } from './types.js';
/** A document-local opaque reference. Only the allocator interprets its own counter. */
export type DraftElementID = string & {
	readonly __draftElementID: unique symbol;
};
export function draftElementID(value: string): DraftElementID {
	if (!/^[A-Za-z0-9_-]{1,64}$/.test(value))
		throw new Error('Invalid DraftElementID');
	return value as DraftElementID;
}
const counter = (value: string): boolean => /^[1-9a-z][0-9a-z]{0,63}$/.test(value);
const compare = (a: string, b: string): number => a.length - b.length || (a < b ? -1 : a > b ? 1 : 0);
const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
function successor(value: string): string {
	const out = [...value];
	for (let i = out.length - 1; i >= 0; i--) {
		const n = digits.indexOf(out[i]!);
		if (n < 35) {
			out[i] = digits[n + 1]!;
			return out.join('');
		}
		out[i] = '0';
	}
	if (out.length === 64)
		throw new Error('DraftElementID counter exhausted');
	return '1' + out.join('');
}
/** High-water mark, deliberately outside undo snapshots. Uses string arithmetic
 * so both engines agree beyond JS safe integers. Retired values remain spent. */
export class DraftIDAllocator {
	private next: string;
	get nextId(): string { return this.next; }
	constructor(nextId = '1', reserved: readonly DraftElementID[] = []) {
		if (!counter(nextId))
			throw new Error('Invalid DraftElementID counter');
		this.next = nextId;
		this.retain(nextId, reserved);
	}
	retain(nextId: string, reserved: readonly DraftElementID[] = []): void {
		if (!counter(nextId))
			throw new Error('Invalid DraftElementID counter');
		let next = compare(nextId, this.next) > 0 ? nextId : this.next;
		for (const id of reserved) {
			draftElementID(id);
			// Foreign IDs remain opaque. Reserve any spelling our generator can emit,
			// including after that foreign element is deleted and the file reopened.
			if (counter(id) && compare(id, next) >= 0)
				next = successor(id);
		}
		this.next = next;
	}
	mint(): DraftElementID {
		const value = this.next;
		this.next = successor(value); // Exhaustion fails before consuming a value.
		return draftElementID(value);
	}
}
export type IdentifiedElement = ScreenplayElement & {
	id: DraftElementID;
};
/** Notes are a legacy projection of notes.json, with their own ID namespace. */
export interface IdentifiedScreenplay extends Screenplay {
	nextId: string;
	elements: (IdentifiedElement | (ScreenplayElement & {
		type: 'note';
	}))[];
}
/** Import/paste is adoption: no incoming ID is trusted as destination identity. */
export function identifyScreenplay(source: Screenplay, allocator: DraftIDAllocator = new DraftIDAllocator()): IdentifiedScreenplay {
	const candidate = new DraftIDAllocator(allocator.nextId);
	const elements = source.elements.map(element => {
		const { id: _id, ...copy } = element;
		return element.type === 'note' ? copy as ScreenplayElement & {
			type: 'note';
		} : { ...copy, id: candidate.mint() };
	});
	allocator.retain(candidate.nextId);
	return { ...source, elements, nextId: allocator.nextId };
}
/** Reopen/restore is distinct from import. Reject incomplete or duplicate identity. */
export function restoreIdentifiedScreenplay(source: Screenplay): IdentifiedScreenplay {
	if (source.nextId === undefined)
		throw new Error('Missing DraftElementID counter');
	const seen = new Set<DraftElementID>();
	for (const element of source.elements) {
		if (element.type === 'note')
			continue;
		if (element.id === undefined)
			throw new Error('Missing DraftElementID');
		const id = draftElementID(element.id);
		if (seen.has(id))
			throw new Error('Duplicate DraftElementID');
		seen.add(id);
	}
	const allocator = new DraftIDAllocator(source.nextId, [...seen]);
	return { ...source, elements: source.elements.map(e => ({ ...e })) as IdentifiedScreenplay['elements'], nextId: allocator.nextId };
}
