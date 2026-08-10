/** The shared import classifier: shapes, layout bands, context repair, reports. */
import { describe, expect, it } from 'vitest';
import { classifyLines, finalizeImport, toScreenplay } from './classify.js';
import type { RawLine } from './classify.js';

function typesOf(lines: RawLine[]): string[] {
	return classifyLines(lines).map((line) => line.type);
}

describe('classifyLines', () => {
	it('trusts an explicit source style above every other signal', () => {
		const [line] = classifyLines([{ text: 'a quiet room, somehow', styleName: 'Scene Heading' }]);
		expect(line?.type).toBe('scene');
		expect(line?.confidence).toBe('high');
	});

	it('recognizes every scene-heading intro', () => {
		const types = typesOf([
			{ text: 'INT. CAFE - DAY' },
			{ text: 'EXT. ROOF - NIGHT' },
			{ text: 'INT./EXT. CAR - MOVING' },
			{ text: 'I/E. STAIRWELL - DUSK' },
			{ text: 'EST. MANHATTAN - DAWN' }
		]);
		expect(types).toEqual(['scene', 'scene', 'scene', 'scene', 'scene']);
	});

	it('recognizes the transition family', () => {
		const types = typesOf([
			{ text: 'CUT TO:' },
			{ text: 'SMASH CUT TO:' },
			{ text: 'MATCH CUT TO:' },
			{ text: 'FADE IN:' },
			{ text: 'FADE OUT.' },
			{ text: 'FADE TO BLACK.' },
			{ text: 'IRIS OUT' }
		]);
		expect(types).toEqual([
			'transition',
			'transition',
			'transition',
			'transition',
			'transition',
			'transition',
			'transition'
		]);
	});

	it('reads a cue at a deep indent with high confidence, without one at medium', () => {
		const [deep, shallow] = classifyLines([
			{ text: 'MARA', indentInches: 2.2 },
			{ text: 'JONAH' }
		]);
		expect(deep?.confidence).toBe('high');
		expect(shallow?.confidence).toBe('medium');
	});

	it('does not mistake uppercase prose with terminal punctuation for a cue', () => {
		const [line] = classifyLines([{ text: 'THE HOUSE STOOD SILENT.' }]);
		expect(line?.type).toBe('action');
	});

	it('reads a bracketed line as a parenthetical inside a speech', () => {
		const classified = classifyLines([{ text: 'MARA' }, { text: '(whispering)' }, { text: 'We are closed.' }]);
		expect(classified.map((line) => line.type)).toEqual(['character', 'parenthetical', 'dialogue']);
		expect(classified.every((line) => line.confidence !== 'low')).toBe(true);
	});

	it('retypes a bracketed line outside any speech as action and flags it low', () => {
		const [line] = classifyLines([{ text: '(beat)' }]);
		expect(line?.type).toBe('action');
		expect(line?.confidence).toBe('low');
		expect(line?.why).toMatch(/brackets outside a speech/);
	});

	it('reads what follows a cue as its dialogue', () => {
		const types = typesOf([{ text: 'MARA' }, { text: 'We need to talk.' }]);
		expect(types).toEqual(['character', 'dialogue']);
	});

	it('reads what follows a parenthetical as dialogue even across a paragraph gap', () => {
		const types = typesOf([{ text: 'MARA' }, { text: '(beat)' }, { text: 'Fine. Tomorrow.' }]);
		expect(types).toEqual(['character', 'parenthetical', 'dialogue']);
	});

	it('flags a cue with no speech beneath it', () => {
		const classified = classifyLines([{ text: 'MARA' }, { text: 'INT. ROOF - NIGHT' }]);
		expect(classified[0]?.confidence).toBe('low');
		expect(classified[0]?.why).toMatch(/no speech beneath/);
	});

	it('uses indent bands only when no stronger signal exists — and flags the guess', () => {
		const [line] = classifyLines([{ text: 'indented prose, no other signal', indentInches: 1.0 }]);
		expect(line?.type).toBe('dialogue');
		expect(line?.confidence).toBe('low');
	});

	it('reads far-right uppercase layout as a transition', () => {
		const [line] = classifyLines([{ text: 'THE END', indentInches: 6.0 }]);
		expect(line?.type).toBe('transition');
		expect(line?.confidence).toBe('medium');
	});

	it('honors explicit alignment', () => {
		const [centered, right] = classifyLines([
			{ text: 'THE END', align: 'center' },
			{ text: 'Cut to:', align: 'right' }
		]);
		expect(centered?.type).toBe('centered');
		expect(right?.type).toBe('transition');
	});

	it('reads prose directly under a heading as that scene’s action', () => {
		const types = typesOf([{ text: 'INT. CAFE - DAY' }, { text: 'Mara stirs her coffee.' }]);
		expect(types).toEqual(['scene', 'action']);
	});

	it('upgrades a transition when a scene follows it', () => {
		const [transition] = classifyLines([
			{ text: 'THE END', indentInches: 6.0 },
			{ text: 'INT. EPILOGUE - DAWN' }
		]);
		expect(transition?.confidence).toBe('high');
	});
});

describe('toScreenplay', () => {
	it('folds attached same-type lines back into one element', () => {
		const script = toScreenplay(
			classifyLines([
				{ text: 'INT. CAFE - DAY' },
				{ text: 'A tiny room. Rain hammers' },
				{ text: 'the window.', attached: true }
			])
		);
		expect(script.elements).toEqual([
			{ type: 'scene', text: 'INT. CAFE - DAY' },
			{ type: 'action', text: 'A tiny room. Rain hammers the window.' }
		]);
	});

	it('turns hard page breaks into structural pagebreak elements', () => {
		const script = toScreenplay(
			classifyLines([{ text: 'INT. A - DAY' }, { text: 'INT. B - NIGHT', pageBreak: true }])
		);
		expect(script.elements.map((element) => element.type)).toEqual(['scene', 'pagebreak', 'scene']);
	});
});

describe('finalizeImport', () => {
	it('counts lines and scenes and collects unique characters', () => {
		const { report } = finalizeImport(
			classifyLines([
				{ text: 'INT. CAFE - DAY' },
				{ text: 'MARA (V.O.)' },
				{ text: 'We need to talk.' },
				{ text: 'MARA' },
				{ text: 'Now.' }
			]),
			'text',
			['one warning']
		);
		expect(report.format).toBe('text');
		expect(report.scenes).toBe(1);
		expect(report.characters).toEqual(['MARA']);
		expect(report.warnings).toEqual(['one warning']);
	});

	it('flags only low-confidence lines, with reasons', () => {
		const { report } = finalizeImport(classifyLines([{ text: '(beat)' }]), 'text', []);
		expect(report.flagged).toHaveLength(1);
		expect(report.flagged[0]?.why).toMatch(/brackets outside a speech/);
	});
});
