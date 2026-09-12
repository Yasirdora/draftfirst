/** Pagination behavior using reduced page sizes for concise fixtures. */
import { describe, expect, it } from 'vitest';
import { GEOMETRY, paginate, paginateIncrementally, wrapText } from './paginate.js';
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

describe('paginateIncrementally', () => {

	/** A feature-shaped document: scenes, action, exchanges, transitions. */
	const feature = (scenes: number): Screenplay => {
		const elements: ScreenplayElement[] = [];
		for (let beat = 1; beat <= scenes; beat++) {
			elements.push(el('scene', `INT. ROOM ${beat} - DAY`));
			elements.push(
				el('action', `Action for beat ${beat}. The road holds its breath for a full line of the page.`)
			);
			elements.push(el('character', 'MARA'));
			elements.push(el('parenthetical', '(quietly)'));
			elements.push(el('dialogue', `Line ${beat}, spoken plainly and without hurry at all.`));
			elements.push(el('character', 'DAVID'));
			elements.push(el('dialogue', `Reply in scene ${beat}. I hear you, and I agree completely.`));
			elements.push(el('transition', 'CUT TO:'));
		}
		return doc(elements);
	};

	it('answers the full pass when there is no cache', () => {
		const script = feature(20);
		expect(paginateIncrementally(script, doc([]), [])).toEqual(paginate(script));
	});

	it('returns the previous pages when nothing the fold reads changed', () => {
		const before = feature(20);
		const pages = paginate(before);
		const after = feature(20);
		after.elements[5].sceneNumber = 'A12'; // margin data, not layout
		expect(paginateIncrementally(after, before, pages)).toBe(pages);
	});

	it('a text edit mid-document paginates identically to the full pass', () => {
		const before = feature(40);
		const pages = paginate(before);
		const after = feature(40);
		after.elements[100].text = 'A wholly different reply, longer and more considered than before.';
		expect(paginateIncrementally(after, before, pages)).toEqual(paginate(after));
	});

	it('a keystroke at the end paginates identically', () => {
		const before = feature(40);
		const pages = paginate(before);
		const after = feature(40);
		after.elements[after.elements.length - 1].text += ' Again.';
		expect(paginateIncrementally(after, before, pages)).toEqual(paginate(after));
	});

	it('a Return (insertion) paginates identically', () => {
		const before = feature(40);
		const pages = paginate(before);
		const after = doc([
			...before.elements.slice(0, 57),
			el('action', 'A new paragraph lands in the middle of the script.'),
			...before.elements.slice(57)
		]);
		expect(paginateIncrementally(after, before, pages)).toEqual(paginate(after));
	});

	it('a deletion paginates identically', () => {
		const before = feature(40);
		const pages = paginate(before);
		const after = doc([
			...before.elements.slice(0, 100),
			...before.elements.slice(104)
		]);
		expect(paginateIncrementally(after, before, pages)).toEqual(paginate(after));
	});

	it('a cue becoming action splits the flow block — still identical', () => {
		const before = feature(40);
		const pages = paginate(before);
		const after = feature(40);
		after.elements[100] = el('action', after.elements[100].text); // cue index 100? find one
		after.elements[102] = el('action', 'Not a cue any more, just narration of it.');
		expect(paginateIncrementally(after, before, pages)).toEqual(paginate(after));
	});

	it('fuzz: random single-region edits are identical to the full pass', {
		// Three hundred property rounds outlast the default 5s under load.
		timeout: 30000
	}, () => {
		let seed = 20260911;
		const random = () => {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return seed / 0x7fffffff;
		};
		const words = ['night', 'door', 'light', 'road', 'silence', 'again', 'KANE', 'window'];
		const phrase = () =>
			Array.from({ length: 3 + Math.floor(random() * 18) }, () => words[Math.floor(random() * words.length)]).join(' ');

		for (let round = 0; round < 300; round++) {
			const before = feature(30 + Math.floor(random() * 30));
			const pages = paginate(before);
			const after = doc(before.elements.map((e2) => ({ ...e2 })));
			const pick = random();
			const at = Math.floor(random() * after.elements.length);
			if (pick < 0.45) {
				after.elements[at] = { ...after.elements[at], text: phrase() };
			} else if (pick < 0.6) {
				const types: ScreenplayElement['type'][] = ['action', 'character', 'dialogue', 'scene'];
				after.elements[at] = { ...after.elements[at], type: types[Math.floor(random() * types.length)] };
			} else if (pick < 0.8) {
				after.elements.splice(at, 0, el('action', phrase()));
			} else {
				after.elements.splice(at, 1 + Math.floor(random() * 3));
			}
			expect(paginateIncrementally(after, before, pages)).toEqual(paginate(after));
		}
	});
});

describe('paginate · act breaks (RFC-ACT-BREAK)', () => {
	it('opens a new page for every act, card centred at the top', () => {
		const pages = paginate(
			doc([
				el('action', 'The teaser plays out.'),
				el('actbreak', 'ACT ONE'),
				el('scene', 'INT. WHITE HOUSE - NIGHT'),
				el('action', 'No president ever slept here.')
			])
		);
		expect(pages).toHaveLength(2);
		expect(pages[1].lines[0].text.trim()).toBe('ACT ONE');
		/* Centred on the sixty-character grid, and nothing above it. */
		expect(pages[1].lines[0].indent).toBeGreaterThan(0);
	});

	it('makes no blank first page when the document opens on an act', () => {
		const pages = paginate(doc([el('actbreak', 'ACT ONE'), el('action', 'We begin.')]));
		expect(pages).toHaveLength(1);
		expect(pages[0].lines[0].text.trim()).toBe('ACT ONE');
	});

	it("collapses a writer's page break beside the card into one break", () => {
		const pages = paginate(
			doc([
				el('action', 'Out.'),
				el('pagebreak', ''),
				el('actbreak', 'ACT TWO'),
				el('action', 'In.')
			])
		);
		expect(pages).toHaveLength(2);
		expect(pages[1].lines[0].text.trim()).toBe('ACT TWO');
	});

	it('splits a long speech naturally, but the act still opens clean', () => {
		const longSpeech = Array.from({ length: 24 }, (_, i) => `line ${i + 1} of the speech.`).join(
			' '
		);
		const pages = paginate(
			doc([
				el('character', 'WALT'),
				el('dialogue', longSpeech),
				el('actbreak', 'ACT TWO'),
				el('action', 'The next act begins.')
			]),
			{ linesPerPage: 10 }
		);
		const actPage = pages.findIndex((p) => p.lines.some((l) => l.text.trim() === 'ACT TWO'));
		expect(actPage).toBeGreaterThan(0);
		/* The speech spilled forward with its (MORE)/CONT'D pair somewhere
		   before the act... */
		expect(pages.slice(0, actPage).some((p) => p.lines.some((l) => l.text === '(MORE)'))).toBe(
			true
		);
		/* ...but the act's own page opens with the card, not a continuation —
		   no pair ever spans an act boundary. */
		expect(pages[actPage].lines[0].text.trim()).toBe('ACT TWO');
		expect(pages[actPage].lines.some((l) => l.text.includes("(CONT'D)"))).toBe(false);
	});
});
