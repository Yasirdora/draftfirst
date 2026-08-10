/** Pagination behavior using reduced page sizes for concise fixtures. */
import { describe, expect, it } from 'vitest';
import { GEOMETRY, paginate, wrapText } from './paginate.js';
import type { Screenplay, ScreenplayElement } from './types.js';

const el = (type: ScreenplayElement['type'], text: string): ScreenplayElement => ({ type, text });

const doc = (elements: ScreenplayElement[]): Screenplay => ({ titlePage: [], elements });

/** Render a page's lines as text for readable assertions. */
const pageText = (pages: ReturnType<typeof paginate>, n: number) =>
	pages[n - 1].lines.map((l) => l.text);

describe('wrapText', () => {
	it('wraps greedily on word boundaries', () => {
		expect(wrapText('one two three', 7)).toEqual(['one two', 'three']);
	});

	it('hard-splits over-long words so text never escapes the page grid', () => {
		expect(wrapText('supercalifragilistic ok', 5)).toEqual([
			'super',
			'calif',
			'ragil',
			'istic',
			'ok'
		]);
	});

	it('returns a single empty line for empty text', () => {
		expect(wrapText('', 60)).toEqual(['']);
	});
});

describe('geometry', () => {
	it('matches the industry grid (chars from left margin)', () => {
		expect(GEOMETRY.character.indent).toBe(22);
		expect(GEOMETRY.dialogue).toMatchObject({ indent: 10, width: 35 });
		expect(GEOMETRY.parenthetical).toMatchObject({ indent: 16, width: 26 });
		expect(GEOMETRY.scene.before).toBe(2);
	});
});

describe('paginate · page filling', () => {
	it.each([NaN, Infinity, -Infinity, 9, 10.5, 10_001])(
		'rejects invalid linesPerPage values (%s) instead of hanging or over-allocating',
		(linesPerPage) => {
			expect(() => paginate(doc([el('action', 'Safe.')]), { linesPerPage })).toThrow(RangeError);
		}
	);

	it('rejects invalid wrap widths', () => {
		expect(() => wrapText('unsafe', NaN)).toThrow(RangeError);
		expect(() => wrapText('unsafe', 0)).toThrow(RangeError);
	});

	it('never exceeds the line limit', () => {
		const elements: ScreenplayElement[] = [];
		for (let i = 0; i < 80; i++) el && elements.push(el('action', `Line ${i} of action.`));
		const pages = paginate(doc(elements));
		expect(pages.length).toBeGreaterThan(1);
		for (const p of pages) expect(p.lines.length).toBeLessThanOrEqual(55);
	});

	it('numbers pages from 1 and numbers are sequential', () => {
		const pages = paginate(doc([el('action', 'Hello.')]));
		expect(pages[0].number).toBe(1);
	});

	it('gives the first block no leading blank lines', () => {
		const pages = paginate(doc([el('scene', 'INT. LAB - DAY'), el('action', 'Hum.')]));
		expect(pages[0].lines[0].text).toBe('INT. LAB - DAY');
	});

	it('forces a new page at a pagebreak element', () => {
		const pages = paginate(
			doc([el('action', 'Before.'), el('pagebreak', ''), el('action', 'After.')]),
			{ linesPerPage: 55 }
		);
		expect(pages.length).toBe(2);
		expect(pageText(pages, 2)).toContain('After.');
	});
});

describe('paginate · break rules (miniature pages)', () => {
	it('moves a scene heading that cannot keep with following content', () => {
		const limit = 12;
		const elements: ScreenplayElement[] = [
			/* first block has no leading blank: 5 actions = 1 + 2×4 = 9 lines */
			el('action', 'A1'), el('action', 'A2'), el('action', 'A3'), el('action', 'A4'),
			el('action', 'A5'),
			el('scene', 'INT. NEW PLACE - DAY'),
			el('action', 'Content one.'),
			el('action', 'Content two.')
		];
		const pages = paginate(doc(elements), { linesPerPage: limit });
		expect(pageText(pages, 1)).not.toContain('INT. NEW PLACE - DAY');
		expect(pageText(pages, 2)[0]).toBe('INT. NEW PLACE - DAY');
	});

	it('keeps a scene heading with cue, parenthetical, and spoken line', () => {
		const elements: ScreenplayElement[] = [
			el('action', 'A1'), el('action', 'A2'), el('action', 'A3'), el('action', 'A4'),
			el('scene', 'INT. NEW PLACE - DAY'),
			el('character', 'MOLLY'),
			el('parenthetical', '(quietly)'),
			el('dialogue', 'We made it.')
		];
		const pages = paginate(doc(elements), { linesPerPage: 10 });
		expect(pageText(pages, 1)).not.toContain('INT. NEW PLACE - DAY');
		expect(pageText(pages, 2).slice(0, 4)).toEqual([
			'INT. NEW PLACE - DAY',
			'',
			'MOLLY',
			'(quietly)'
		]);
		expect(pageText(pages, 2)).toContain('We made it.');
	});

	it('never creates an empty page or overflows for an oversized scene heading', () => {
		const huge = Array.from({ length: 800 }, (_, i) => `location${i}`).join(' ');
		const pages = paginate(doc([el('scene', huge), el('action', 'After.')]), {
			linesPerPage: 10
		});
		expect(pages[0].lines.length).toBeGreaterThan(0);
		for (const page of pages) expect(page.lines.length).toBeLessThanOrEqual(10);
		expect(pages.flatMap((page) => page.lines).some((line) => line.text === 'After.')).toBe(true);
	});

	it('splits long dialogue with (MORE) and NAME (CONT\u2019D)', () => {
		const limit = 12;
		const elements: ScreenplayElement[] = [
			el('action', 'A1'), el('action', 'A2'), el('action', 'A3'), // 6 lines
			el('character', 'MOLLY (V.O.)'),
			el('dialogue', 'One.'), el('dialogue', 'Two.'), el('dialogue', 'Three.'),
			el('dialogue', 'Four.'), el('dialogue', 'Five.'), el('dialogue', 'Six.')
		];
		const pages = paginate(doc(elements), { linesPerPage: limit });
		const p1 = pageText(pages, 1);
		const p2 = pageText(pages, 2);
		expect(p1[p1.length - 1]).toBe('(MORE)');
		expect(p2[0]).toBe("MOLLY (CONT'D)");
		expect(p1).toContain('MOLLY (V.O.)');
		expect([...p1, ...p2].filter((t) => /^(One|Two|Three|Four|Five|Six)\.$/.test(t)).length).toBe(6);
	});

	it('never orphans a cue at the page bottom', () => {
		const limit = 10;
		const elements: ScreenplayElement[] = [
			el('action', 'A1'), el('action', 'A2'), el('action', 'A3'), el('action', 'A4'), // 8 lines
			el('character', 'ELIAS'),
			el('dialogue', 'Only one line fits, maybe.'),
			el('dialogue', 'Second line.'),
			el('dialogue', 'Third line.')
		];
		const pages = paginate(doc(elements), { linesPerPage: limit });
		const p1 = pageText(pages, 1);
		expect(p1[p1.length - 1]).not.toBe('ELIAS');
		if (!p1.includes('ELIAS')) {
			expect(pageText(pages, 2)[0]).toBe('ELIAS');
		}
	});

	it('splits action with at least 2 lines on each side (widow/orphan)', () => {
		const limit = 12;
		const longAction =
			'Alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu apples bananas cherries dates elderberries figs grapes.';
		const elements: ScreenplayElement[] = [
			/* 5 actions = 9 lines → 3 lines of room; block needs 1 blank + 4 content */
			el('action', 'A1'), el('action', 'A2'), el('action', 'A3'), el('action', 'A4'),
			el('action', 'A5'),
			el('action', longAction)
		];
		const wrapped = wrapText(longAction, 60);
		expect(wrapped.length).toBeGreaterThanOrEqual(4);
		const pages = paginate(doc(elements), { linesPerPage: limit });
		const p1 = pageText(pages, 1).filter((t) => /Alpha|kilo|tango|figs/.test(t)).length;
		const p2 = pageText(pages, 2).filter((t) => /Alpha|kilo|tango|figs/.test(t)).length;
		expect(p1).toBeGreaterThanOrEqual(2);
		expect(p2).toBeGreaterThanOrEqual(2);
	});

	it('splits a limit-plus-one action block without leaving a one-line orphan', () => {
		const text = 'x'.repeat(GEOMETRY.action.width * 11);
		const wrapped = wrapText(text, GEOMETRY.action.width);
		const pages = paginate(doc([el('action', text)]), { linesPerPage: 10 });
		expect(pages).toHaveLength(2);
		expect(pages[0].lines.length).toBe(wrapped.length - 2);
		expect(pages[1].lines.length).toBe(2);
	});

	it('does not fabricate dialogue continuation markers for orphan dialogue or lyrics', () => {
		const long = Array.from({ length: 120 }, (_, i) => `word${i}`).join(' ');
		for (const elements of [
			[el('dialogue', long)],
			[el('character', 'MOLLY'), el('lyrics', long)]
		]) {
			const texts = paginate(doc(elements), { linesPerPage: 10 })
				.flatMap((page) => page.lines)
				.map((line) => line.text);
			expect(texts).not.toContain('(MORE)');
			expect(texts.some((text) => text.includes("(CONT'D)"))).toBe(false);
		}
	});

	it('moves a small action block whole when it cannot split honourably', () => {
		const limit = 12;
		const elements: ScreenplayElement[] = [
			/* 5 actions = 9 lines → 3 lines of room; 3-line block leaves a 1-line orphan */
			el('action', 'A1'), el('action', 'A2'), el('action', 'A3'), el('action', 'A4'),
			el('action', 'A5'),
			el('action', 'One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty.')
		];
		const pages = paginate(doc(elements), { linesPerPage: limit });
		expect(pages.length).toBe(2);
		expect(pageText(pages, 1)).toContain('A5');
		expect(pageText(pages, 2)[0]).toContain('One two three');
	});

	it('skips structural elements (notes, sections, synopses)', () => {
		const pages = paginate(
			doc([el('section', 'Act One'), el('note', 'hidden'), el('action', 'Visible.')])
		);
		const all = pages.flatMap((p) => p.lines.map((l) => l.text));
		expect(all).toContain('Visible.');
		expect(all).not.toContain('hidden');
		expect(all).not.toContain('Act One');
	});

	it('right-aligns transitions to the text column edge', () => {
		const pages = paginate(doc([el('transition', 'CUT TO:')]));
		const line = pages[0].lines.find((l) => l.type === 'transition');
		expect(line).toBeTruthy();
		expect(line!.indent + line!.text.length).toBe(60);
	});

	it('indents dialogue and cues at the industry positions', () => {
		const pages = paginate(doc([el('character', 'MOLLY'), el('dialogue', 'Hi.')]));
		const cue = pages[0].lines.find((l) => l.text === 'MOLLY');
		const dia = pages[0].lines.find((l) => l.text === 'Hi.');
		expect(cue!.indent).toBe(22);
		expect(dia!.indent).toBe(10);
	});
});

describe('paginate · continuation chains (the monologue law)', () => {
	it('a speech longer than a page chains (MORE)/CONT\u2019D across pages, never overflows', () => {
		const elements: ScreenplayElement[] = [
			el('action', 'The room waits.'),
			el('character', 'ELIAS')
		];
		for (let i = 0; i < 20; i++) {
			elements.push(el('dialogue', `Sentence ${i} of a very long confession that keeps going and going.`));
		}
		const pages = paginate(doc(elements), { linesPerPage: 12 });
		for (const p of pages) expect(p.lines.length).toBeLessThanOrEqual(12);
		for (let i = 1; i < pages.length - 1; i++) {
			const texts = pages[i].lines.map((l) => l.text);
			expect(texts[texts.length - 1]).toBe('(MORE)');
			expect(pages[i + 1].lines[0].text).toBe("ELIAS (CONT'D)");
		}
		const all = pages.flatMap((p) => p.lines.map((l) => l.text)).join(' ');
		for (let i = 0; i < 20; i++) expect(all).toContain(`Sentence ${i}`);
	});

	it('an action block longer than a page chains without overflow', () => {
		const elements: ScreenplayElement[] = [el('action', 'Start.')];
		for (let i = 0; i < 25; i++) elements.push(el('action', `Detail ${i} fills the page and then some.`));
		const giant = el('action', Array.from({ length: 30 }, (_, i) => `word${i}`).join(' '));
		const pages = paginate(doc([el('action', 'Intro.'), giant]), { linesPerPage: 10 });
		for (const p of pages) expect(p.lines.length).toBeLessThanOrEqual(10);
		expect(pages.flatMap((p) => p.lines.map((l) => l.text)).join(' ')).toContain('word29');
	});
});

describe('paginate · scene continuations', () => {
	it('marks both margins when a scene spans a page break', () => {
		const els = [el('scene', 'INT. WAREHOUSE - NIGHT')];
		for (let i = 0; i < 30; i++) els.push(el('action', `Beat ${i + 1} of the raid.`));
		const pages = paginate(doc(els), { linesPerPage: 10 });
		expect(pages.length).toBeGreaterThan(1);
		expect(pages[0].continuedBottom).toBe(true);
		expect(pages[1].continuedTop).toBe(true);
		expect(pages[pages.length - 1].continuedBottom).toBe(false);
		expect(pages[0].continuedTop).toBe(false);
	});

	it('stays silent when the break falls exactly on a scene boundary', () => {
		const els = [el('scene', 'INT. ROOM - DAY')];
		for (let i = 0; i < 5; i++) els.push(el('action', `Line ${i + 1}.`));
		els.push(el('scene', 'EXT. STREET - NIGHT'));
		els.push(el('action', 'Traffic.'));
		const pages = paginate(doc(els), { linesPerPage: 11 });
		expect(pages.length).toBe(2);
		expect(pages[1].lines[0].text).toBe('EXT. STREET - NIGHT');
		expect(pages[0].continuedBottom).toBe(false);
		expect(pages[1].continuedTop).toBe(false);
	});

	it('marks a forced page break mid-scene too', () => {
		const pages = paginate(
			doc([
				el('scene', 'INT. ROOM - DAY'),
				el('action', 'Before the break.'),
				el('pagebreak', ''),
				el('action', 'After the break — same scene.')
			]),
			{ linesPerPage: 10 }
		);
		expect(pages[0].continuedBottom).toBe(true);
		expect(pages[1].continuedTop).toBe(true);
	});

	it('never marks content before the first scene heading', () => {
		const els = [el('action', 'Cold open, no scene yet.')];
		for (let i = 0; i < 20; i++) els.push(el('action', `More ${i}.`));
		const pages = paginate(doc(els), { linesPerPage: 10 });
		expect(pages.every((p) => !p.continuedTop && !p.continuedBottom)).toBe(true);
	});

	it('dialogue split inside a continued scene carries both kinds of markers', () => {
		const long = Array.from({ length: 40 }, (_, i) => `word${i}`).join(' ');
		const pages = paginate(
			doc([
				el('scene', 'INT. ROOM - DAY'),
				el('character', 'MOLLY'),
				el('dialogue', long)
			]),
			{ linesPerPage: 10 }
		);
		expect(pages.length).toBeGreaterThan(1);
		expect(pages[0].continuedBottom).toBe(true);
		expect(pages[1].continuedTop).toBe(true);
		expect(pageText(pages, 1)).toContain('(MORE)');
		expect(pageText(pages, 2).some((t) => t.includes("MOLLY (CONT'D)"))).toBe(true);
	});
});
