/** Structural detach and reattach behavior. */
import { describe, expect, it } from 'vitest';
import { detachStructural, reattachStructural } from './structural.js';
import type { ScreenplayElement } from './types.js';

const el = (type: ScreenplayElement['type'], text: string): ScreenplayElement => ({ type, text });

describe('detachStructural', () => {
	it('separates printing from structural elements', () => {
		const { printable, anchors } = detachStructural([
			el('section', 'Act One'),
			el('scene', 'INT. LAB - DAY'),
			el('action', 'Hum.'),
			el('note', 'rewrite'),
			el('action', 'More.'),
			el('pagebreak', '')
		]);
		expect(printable.map((e) => e.type)).toEqual(['scene', 'action', 'action']);
		expect(anchors.map((a) => a.item.text)).toEqual(['Act One', 'rewrite', '']);
	});

	it('anchors each item to the following printable element', () => {
		const { anchors } = detachStructural([
			el('note', 'fix this'),
			el('scene', 'INT. LAB - DAY'),
			el('action', 'Hum.')
		]);
		expect(anchors[0].anchorType).toBe('scene');
		expect(anchors[0].anchorText).toBe('INT. LAB - DAY');
		expect(anchors[0].anchorOccurrence).toBe(0);
	});

	it('records the exact occurrence when printable elements repeat', () => {
		const { anchors } = detachStructural([
			el('action', 'Same line.'),
			el('note', 'belongs to the second line'),
			el('action', 'Same line.')
		]);
		expect(anchors[0]).toMatchObject({
			anchorType: 'action',
			anchorText: 'Same line.',
			anchorOccurrence: 1
		});
	});

	it('trailing structure has a null anchor', () => {
		const { anchors } = detachStructural([el('action', 'End.'), el('note', 'final note')]);
		expect(anchors[0].anchorType).toBeNull();
	});
});

describe('reattachStructural', () => {
	it('round-trips an unedited document exactly', () => {
		const original = [
			el('section', 'Act One'),
			el('scene', 'INT. LAB - DAY'),
			el('action', 'Hum.'),
			el('note', 'rewrite'),
			el('action', 'More.')
		];
		const { printable, anchors } = detachStructural(original);
		expect(reattachStructural(printable, anchors)).toEqual(original);
	});

	it('preserves the order of adjacent structural elements', () => {
		const original = [
			el('section', 'Act One'),
			el('synopsis', 'The beginning.'),
			el('note', 'Tighten this.'),
			el('scene', 'INT. LAB - DAY')
		];
		const { printable, anchors } = detachStructural(original);
		expect(reattachStructural(printable, anchors)).toEqual(original);
	});

	it('reattaches structure to the correct repeated printable occurrence', () => {
		const original = [
			el('action', 'Same line.'),
			el('note', 'second only'),
			el('action', 'Same line.')
		];
		const { printable, anchors } = detachStructural(original);
		expect(reattachStructural(printable, anchors)).toEqual(original);
	});

	it('keeps compatibility with legacy anchors that have no occurrence', () => {
		const printable = [el('action', 'Same line.'), el('action', 'Same line.')];
		const out = reattachStructural(printable, [
			{
				item: el('note', 'legacy'),
				anchorType: 'action',
				anchorText: 'Same line.'
			}
		]);
		expect(out).toEqual([
			el('note', 'legacy'),
			el('action', 'Same line.'),
			el('action', 'Same line.')
		]);
	});

	it('survives edits to other elements', () => {
		const original = [
			el('note', 'fix the opening'),
			el('scene', 'INT. LAB - DAY'),
			el('action', 'First line.'),
			el('action', 'Second line.')
		];
		const { printable, anchors } = detachStructural(original);
		printable[2] = el('action', 'Second line, rewritten.');
		const out = reattachStructural(printable, anchors);
		expect(out[0]).toEqual(el('note', 'fix the opening'));
		expect(out[1]).toEqual(el('scene', 'INT. LAB - DAY'));
	});

	it('orphaned anchors survive at the end rather than vanishing', () => {
		const original = [el('note', 'important'), el('scene', 'INT. GONE - DAY')];
		const { printable, anchors } = detachStructural(original);
		printable.splice(0, 1);
		const out = reattachStructural(printable, anchors);
		expect(out.some((e) => e.type === 'note' && e.text === 'important')).toBe(true);
	});

	it('empty anchors pass through untouched', () => {
		const printable = [el('action', 'Hello.')];
		expect(reattachStructural(printable, [])).toEqual(printable);
	});
});
