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

	it('refuses sources over the size limit', () => {
		expect(() => importPlainText('x'.repeat(100), { maxSourceCharacters: 10 })).toThrow(PlainTextImportError);
	});

	it('warns when there is nothing to import', () => {
		const { report } = importPlainText('   \n\n  ');
		expect(report.warnings.join(' ')).toMatch(/no text found/);
	});
});
