/** Plain-text and paste import: typewriter layout, reflowed prose, artifacts. */
import { describe, expect, it } from 'vitest';
import { importPlainText, PlainTextImportError } from './plaintext.js';

describe('importPlainText', () => {
	it('reads a typewriter-layout script exactly', () => {
		const source = [
			'INT. FISH & CHIP SHOP - DAY',
			'',
			'A tiny, quiet room. Rain hammers',
			'the window.',
			'',
			'                      MARA',
			'                (whispering)',
			"          We're closed.",
			'',
			'                                             CUT TO:',
			'',
			'EXT. STREET - NIGHT'
		].join('\n');
		const { script, report } = importPlainText(source);
		expect(script.elements.map((element) => element.type)).toEqual([
			'scene',
			'action',
			'character',
			'parenthetical',
			'dialogue',
			'transition',
			'scene'
		]);
		expect(script.elements[1]?.text).toBe('A tiny, quiet room. Rain hammers the window.');
		expect(report.scenes).toBe(2);
		expect(report.characters).toEqual(['MARA']);
		expect(report.flagged).toEqual([]);
	});

	it('reads reflowed prose with no layout at all', () => {
		const source = [
			'INT. CAFE - DAY',
			'',
			'Mara stirs her coffee.',
			'',
			'MARA',
			'',
			'We need to talk.',
			'',
			'CUT TO:',
			'',
			'EXT. ROOF - NIGHT'
		].join('\n');
		const { script, report } = importPlainText(source);
		expect(script.elements.map((element) => element.type)).toEqual([
			'scene',
			'action',
			'character',
			'dialogue',
			'transition',
			'scene'
		]);
		expect(report.flagged).toEqual([]);
	});

	it('strips pagination artifacts and counts them in the report', () => {
		const source = ['1.', 'INT. CAFE - DAY', '(MORE)', 'CONTINUED:', '2', 'MARA', 'Hi.', "(CONT'D)"].join('\n');
		const { script, report } = importPlainText(source);
		expect(script.elements.map((element) => element.type)).toEqual(['scene', 'character', 'dialogue']);
		expect(report.warnings.join(' ')).toMatch(/stripped 5 pagination artifact/);
	});

	it('strips the scene number set loose from its heading', () => {
		/* corpus-witnessed: "4A" (corpus-6), "A1" (lalaland ×42), the page's
		   twin numbers "1 1" (whiplash ×134) and "1A 1A" (foryourcon) — a
		   pair counts only when both numbers are equal */
		const source = ['4A', 'A1', '1 1', '1A 1A', '23A.', 'INT. CAFE - DAY', 'APARTMENT 4A', '1 2'].join('\n');
		const { script, report } = importPlainText(source);
		/* "APARTMENT 4A" is a place, not furniture; "1 2" is not a twin */
		expect(script.elements.map((element) => element.text)).toEqual([
			'INT. CAFE - DAY',
			'APARTMENT 4A',
			'1 2'
		]);
		expect(report.warnings.join(' ')).toMatch(/stripped 5 pagination artifact/);
	});

	it('strips the production’s page footer — draft colour, date and page', () => {
		/* 650 witnesses across seven corpus files */
		const source = [
			'Pink (9/10/2013) 2',
			'10/29/14 / 2.',
			'Revision 2.',
			'GG- Yellow Revisions 9/27/13 4.',
			'The Irishman D1-5 SZ 9.15.09 2.',
			'FINAL SHOOTING SCRIPT Pink 7.25.06',
			'GREEN REVISIONS 12/14/19',
			'INT. CAFE - DAY'
		].join('\n');
		const { script, report } = importPlainText(source);
		expect(script.elements.map((element) => element.text)).toEqual(['INT. CAFE - DAY']);
		expect(report.warnings.join(' ')).toMatch(/stripped 7 pagination artifact/);
	});

	it('keeps the date lines that are not stamps, and the prose that carries one', () => {
		/* the bare date belongs to the title page the import does not model
		   yet; the sentence is prose whatever it mentions */
		const source = [
			'1/5/1999',
			'',
			'5/27/05',
			'',
			'28/29/30 OUT',
			'',
			'He delivered the FINAL DRAFT on 9/10/2013, late.',
			'',
			'INT. CAFE - DAY'
		].join('\n');
		const { script, report } = importPlainText(source);
		expect(script.elements.map((element) => element.text)).toEqual([
			'1/5/1999',
			'5/27/05',
			'28/29/30 OUT',
			'He delivered the FINAL DRAFT on 9/10/2013, late.',
			'INT. CAFE - DAY'
		]);
		expect(report.warnings.join(' ')).not.toMatch(/stripped/);
	});

	it('strips the revision asterisk riding a line’s tail', () => {
		/* gone-girl ×1,426, whiplash ×21 ("TRUMPETER #2 **"), corpus-6 ×189 */
		const { script } = importPlainText(
			['INT. CAFE - DAY', 'AMY wakes, turns, gives a look of alarm.*', 'TRUMPETER #2 **'].join('\n')
		);
		expect(script.elements.map((element) => element.text)).toEqual([
			'INT. CAFE - DAY',
			'AMY wakes, turns, gives a look of alarm.',
			'TRUMPETER #2'
		]);
	});

	it('drops the bare margin mark and lets the thought under way continue across it', () => {
		/* corpus-6 ×115: the mark sits alone on its line inside a wrapped
		   paragraph — it splits a speech the way (MORE) does: not at all */
		const source = ['MARA', 'The first part of the speech', '*', 'and the rest of it.'].join('\n');
		const { script } = importPlainText(source);
		expect(script.elements.map((element) => element.type)).toEqual(['character', 'dialogue']);
		expect(script.elements[1]?.text).toBe('The first part of the speech and the rest of it.');
	});

	it('never eats the emphasis marker’s tail — a body holding a star keeps its ending', () => {
		const { script } = importPlainText(['**MARK**', 'He said **exactly** that.*'].join('\n'));
		expect(script.elements.map((element) => element.text)).toEqual(['**MARK**', 'He said **exactly** that.*']);
	});

	it('strips the NUL bytes a UTF-16 paste leaks (pasted-26 ×199)', () => {
		const { script } = importPlainText('\0\0INT. CAFE - DAY\0');
		expect(script.elements.map((element) => element.text)).toEqual(['INT. CAFE - DAY']);
	});

	it('drops end-of-act cards, counts them, and ends the speech they closed (RFC-ACT-BREAK §5)', () => {
		/* the Breaking Bad shape, witnessed in the corpus: the teaser's own
		   END TEASER, then ACT ONE through ACT FOUR with END ACT <n> */
		const source = [
			'EXT. COW PASTURE - DAY',
			'',
			'A cow stands around.',
			'',
			'END TEASER',
			'',
			'ACT ONE',
			'',
			'EXT. WHITE RESIDENCE - NIGHT',
			'',
			'WALTER',
			'I am the one who knocks.',
			'END ACT ONE',
			'ACT TWO',
			'',
			'INT. LAB - DAY'
		].join('\n');
		const { script, report } = importPlainText(source);
		expect(script.elements.map((element) => element.type)).toEqual([
			'scene',
			'action',
			'actbreak',
			'scene',
			'character',
			'dialogue',
			'actbreak',
			'scene'
		]);
		expect(report.warnings.join(' ')).toMatch(/dropped 2 end-of-act card/);
	});

	it('lets no thought continue across a dropped end-of-act card', () => {
		/* attachment dies at the boundary: without the reset, ACT TWO would
		   sit "attached" to the speech above it */
		const source = ['WALTER', 'I am the one who knocks.', 'END OF ACT ONE', 'ACT TWO'].join('\n');
		const { script } = importPlainText(source);
		expect(script.elements.map((element) => element.type)).toEqual(['character', 'dialogue', 'actbreak']);
	});

	it('turns form feeds into pagebreak elements', () => {
		const { script } = importPlainText('INT. A - DAY\f\n\nINT. B - NIGHT');
		expect(script.elements.map((element) => element.type)).toEqual(['scene', 'pagebreak', 'scene']);
	});

	it('normalizes a mid-line tab to a space', () => {
		const { script } = importPlainText('INT.\tKITCHEN - DAY\n\nMARA\t(CONT’D)\nHi.');
		expect(script.elements.map((element) => element.text)).toEqual([
			'INT. KITCHEN - DAY',
			'MARA (CONT’D)',
			'Hi.'
		]);
	});

	it('normalizes Windows line endings', () => {
		const { script } = importPlainText('INT. CAFE - DAY\r\n\r\nMARA\r\nHi.');
		expect(script.elements.map((element) => element.type)).toEqual(['scene', 'character', 'dialogue']);
	});

	it('labels the format for the review sheet', () => {
		const { report } = importPlainText('INT. CAFE - DAY', { format: 'paste' });
		expect(report.format).toBe('paste');
	});

	it('classifies a pasted stream with no blank lines line by line', () => {
		/* clipboard text from chat apps arrives fully attached — every line borders
		   the next, so cues and camera framing must break the speech run */
		const source = [
			'INT. WRITERDUET DASHBOARD - DAY',
			'A glowing canvas floats in the void.',
			'SECTION HEADING: ACT I - THE CORE ELEMENTS',
			'MARCUS',
			"We're starting with a Scene Heading — also called a slugline.",
			'AVA',
			'(wryly)',
			'Right below it comes Action text.',
			'SHOT - CLOSE UP ON KEYBOARD',
			'The mechanical keys clack sharply.',
			'MARCUS (O.S.)',
			'That was a Shot element.',
			'CUT TO:',
			'EXT. EXPORT SUITE - NIGHT',
			'FADE OUT.'
		].join('\n');
		const { classified } = importPlainText(source, { format: 'paste' });
		expect(classified.map((line) => line.type)).toEqual([
			'scene',
			'action',
			'action',
			'character',
			'dialogue',
			'character',
			'parenthetical',
			'dialogue',
			'shot',
			'action',
			'character',
			'dialogue',
			'transition',
			'scene',
			'transition'
		]);
	});

	it('refuses sources over the size limit', () => {
		expect(() => importPlainText('x'.repeat(100), { maxSourceCharacters: 10 })).toThrow(PlainTextImportError);
	});

	it('warns when there is nothing to import', () => {
		const { report } = importPlainText('   \n\n  ');
		expect(report.warnings.join(' ')).toMatch(/no text found/);
	});
});
