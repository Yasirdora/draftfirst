/** The numbered scene heading grammar (routing pack, step 1). */
import { describe, expect, it } from 'vitest';
import { parseNumberedSceneHeading } from './sceneheading.js';

describe('parseNumberedSceneHeading', () => {
	it('reads the leading number a production draft prints (corpus-6)', () => {
		expect(parseNumberedSceneHeading('15 INT. HOLE.')).toEqual({ number: '15', text: 'INT. HOLE.' });
		expect(parseNumberedSceneHeading('23 EXT. SIGNAL HILL - THAT MOMENT.')).toEqual({
			number: '23',
			text: 'EXT. SIGNAL HILL - THAT MOMENT.'
		});
	});

	it('reads the flanked number and drops its revision asterisk (gone-girl)', () => {
		expect(parseNumberedSceneHeading('2 EXT. NORTH CARTHAGE- MORNING 2')).toEqual({
			number: '2',
			text: 'EXT. NORTH CARTHAGE- MORNING'
		});
		expect(parseNumberedSceneHeading('3 EXT. NICK DUNNE’S FRONT YARD- DAWN 3*')).toEqual({
			number: '3',
			text: 'EXT. NICK DUNNE’S FRONT YARD- DAWN'
		});
	});

	it('strips the trailing number only when it repeats the leading one', () => {
		/* "APARTMENT 4" is a place, not a coincidence — but a numbered draft
		   that says 2 … 4 means something else, so the 4 stays put */
		expect(parseNumberedSceneHeading('2 INT. APARTMENT 4')).toEqual({
			number: '2',
			text: 'INT. APARTMENT 4'
		});
	});

	it('reads the OMITTED card, numbered or bare, and normalises its period', () => {
		expect(parseNumberedSceneHeading('113 OMITTED.')).toEqual({ number: '113', text: 'OMITTED' });
		expect(parseNumberedSceneHeading('115 OMITTED')).toEqual({ number: '115', text: 'OMITTED' });
		expect(parseNumberedSceneHeading('OMITTED')).toEqual({ text: 'OMITTED' });
	});

	it('reads La La Land’s short OMIT card as the same card (lalaland ×45)', () => {
		expect(parseNumberedSceneHeading('OMIT')).toEqual({ text: 'OMITTED' });
		expect(parseNumberedSceneHeading('OMIT.')).toEqual({ text: 'OMITTED' });
		expect(parseNumberedSceneHeading('43 OMIT')).toEqual({ number: '43', text: 'OMITTED' });
	});

	it('reads the lettered number a scene added after distribution carries (corpus-6 ×9)', () => {
		expect(parseNumberedSceneHeading('128A EXT./INT. P~~BW MANSION - DUSK. 128A*')).toEqual({
			number: '128A',
			text: 'EXT./INT. P~~BW MANSION - DUSK.'
		});
		expect(parseNumberedSceneHeading('120A INT. SAME. DAWN. 120A')).toEqual({
			number: '120A',
			text: 'INT. SAME. DAWN.'
		});
		expect(parseNumberedSceneHeading('12A INT. APARTMENT - DAY')).toEqual({
			number: '12A',
			text: 'INT. APARTMENT - DAY'
		});
	});

	it('refuses everything that is not a numbered heading', () => {
		expect(parseNumberedSceneHeading('EXT. ROOF - NIGHT')).toBeUndefined();
		expect(parseNumberedSceneHeading('INT. APARTMENT 4')).toBeUndefined();
		expect(parseNumberedSceneHeading('17.')).toBeUndefined();
		expect(parseNumberedSceneHeading('ACT ONE')).toBeUndefined();
		expect(parseNumberedSceneHeading('WALTER')).toBeUndefined();
		expect(parseNumberedSceneHeading('OMITTED FROM THE DRAFT, HE SAID')).toBeUndefined();
		expect(parseNumberedSceneHeading('')).toBeUndefined();
	});
});
