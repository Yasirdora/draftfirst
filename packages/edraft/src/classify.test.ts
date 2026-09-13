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

	it('recognizes the act cards the corpus carries (RFC-ACT-BREAK §5)', () => {
		const classified = classifyLines([
			{ text: 'TEASER' },
			{ text: 'ACT ONE' },
			{ text: 'ACT 4' },
			{ text: 'COLD OPEN' }
		]);
		expect(classified.map((line) => line.type)).toEqual([
			'actbreak',
			'actbreak',
			'actbreak',
			'actbreak'
		]);
		expect(classified.every((line) => line.confidence === 'high')).toBe(true);
	});

	it('reads an act card as a boundary even inside a speech run', () => {
		/* without the act arm, speech position would type ACT ONE as dialogue
		   and the cue shape would adopt TEASER as a speaker */
		const types = typesOf([
			{ text: 'WALTER' },
			{ text: 'I am the one who knocks.' },
			{ text: 'ACT TWO' },
			{ text: 'EXT. DESERT - DAY' }
		]);
		expect(types).toEqual(['character', 'dialogue', 'actbreak', 'scene']);
	});

	it('refuses the near-misses: a customised card and a lowercase one are not boundaries', () => {
		const types = typesOf([{ text: 'ACT TWO: THE TURN' }, { text: 'Act One' }]);
		expect(types).not.toContain('actbreak');
	});

	it('types a numbered scene heading as a scene and gives the number its home', () => {
		const { script, report } = finalizeImport(
			classifyLines([
				{ text: '2 EXT. NORTH CARTHAGE- MORNING 2' },
				{ text: 'Nick drives.' },
				{ text: '15 INT. HOLE.' },
				{ text: 'Darkness.' }
			]),
			'text',
			[]
		);
		expect(script.elements.map((element) => element.type)).toEqual(['scene', 'action', 'scene', 'action']);
		expect(script.elements[0]).toMatchObject({ text: 'EXT. NORTH CARTHAGE- MORNING', sceneNumber: '2' });
		expect(script.elements[2]).toMatchObject({ text: 'INT. HOLE.', sceneNumber: '15' });
		expect(report.scenes).toBe(2);
		expect(report.characters).toEqual([]);
	});

	it('types the OMITTED card as a scene and keeps no cue of it', () => {
		const { script, report } = finalizeImport(
			classifyLines([{ text: '113 OMITTED.' }, { text: 'OMITTED' }, { text: 'EXT. ROOF - NIGHT' }]),
			'text',
			[]
		);
		expect(script.elements.map((element) => element.type)).toEqual(['scene', 'scene', 'scene']);
		expect(script.elements[0]).toMatchObject({ text: 'OMITTED', sceneNumber: '113' });
		expect(script.elements[1]).toMatchObject({ text: 'OMITTED' });
		expect(report.characters).toEqual([]);
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
		/* "DISSOLVE." carries no shape tell, so only the layout band answers —
		   "THE END" used to stand in here and now means the closing card
		   (RFC-SECONDARY-SLUG §4) */
		const [line] = classifyLines([{ text: 'DISSOLVE.', indentInches: 6.0 }]);
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

	it('recognizes the shot family', () => {
		const types = typesOf([
			{ text: 'CLOSE ON MARA' },
			{ text: 'ANGLE ON THE DOOR' },
			{ text: 'INSERT - THE NOTE' },
			{ text: 'POV MARA - THE HALLWAY' },
			{ text: 'SHOT - CLOSE UP ON KEYBOARD' },
			{ text: 'ESTABLISHING SHOT - MANHATTAN' }
		]);
		expect(types).toEqual(['shot', 'shot', 'shot', 'shot', 'shot', 'shot']);
	});

	it('does not read a mixed-case line opening with a shot word as a shot', () => {
		const [line] = classifyLines([{ text: 'Insert the coin and turn.' }]);
		expect(line?.type).toBe('action');
	});

	it('reads prose directly under a shot as what the camera sees', () => {
		const classified = classifyLines([{ text: 'CLOSE ON MARA' }, { text: 'Her hand trembles.' }]);
		expect(classified.map((line) => line.type)).toEqual(['shot', 'action']);
		expect(classified[1]?.confidence).toBe('high');
	});

	it('lets an uppercase cue interrupt an attached speech — pasted text has no blank lines', () => {
		const types = typesOf([
			{ text: 'MARA' },
			{ text: 'We need to talk.' },
			{ text: 'JONAH', attached: true },
			{ text: 'About what?', attached: true }
		]);
		expect(types).toEqual(['character', 'dialogue', 'character', 'dialogue']);
	});

	it('still reads attached mixed-case prose as continuing speech', () => {
		const types = typesOf([
			{ text: 'MARA' },
			{ text: 'We need to talk' },
			{ text: 'about the rent.', attached: true }
		]);
		expect(types).toEqual(['character', 'dialogue', 'dialogue']);
	});

	it('types the OMIT dash-heading as its retired scene, never as a cue (gone-girl ×27)', () => {
		const { script, report } = finalizeImport(
			classifyLines([{ text: '139 OMIT- INT. DUNNE BEDROOM- NIGHT 139*' }, { text: 'Nick drives.' }]),
			'text',
			[]
		);
		expect(script.elements[0]).toMatchObject({ type: 'scene', text: 'OMITTED', sceneNumber: '139' });
		expect(report.characters).toEqual([]);
	});

	it('ends a speech at the line too wide for its column — action rejoining the left margin (lalaland)', () => {
		/* hard-wrapped sources keep two print columns: dialogue narrow,
		   action wide. The three witnessed boundaries: 19→54, 13→61, 5→55 */
		const boundaries: Array<[string, string]> = [
			['Cappuccino, please.', 'Mia nods. Gets it made. Hands it over to the customer.'],
			['No, I insist.', 'She pays for it anyway. Mia turns back to the counter, deflated.'],
			['Shit.', 'Removing her apron, she hurries out from behind the counter.']
		];
		for (const [speech, action] of boundaries) {
			const types = typesOf([{ text: 'MIA' }, { text: speech }, { text: action, attached: true }]);
			expect(types).toEqual(['character', 'dialogue', 'action']);
		}
	});

	it('keeps the wraps that fit the speech column — the edge tell never fires inside one', () => {
		/* a short-opened speech may continue under the 46 ceiling… */
		const shortOpened = typesOf([
			{ text: 'MIA' },
			{ text: 'Shit.' },
			{ text: 'She did not mean to say that out loud.', attached: true }
		]);
		expect(shortOpened).toEqual(['character', 'dialogue', 'dialogue']);
		/* …and a speech wrapping at its own width keeps all its lines */
		const wrapped = typesOf([
			{ text: 'MIA' },
			{ text: 'I was giving a toast at my friend’s' },
			{ text: 'birthday party and everyone there', attached: true },
			{ text: 'started laughing at me instead.', attached: true }
		]);
		expect(wrapped).toEqual(['character', 'dialogue', 'dialogue', 'dialogue']);
	});

	it('keeps an uppercase cue interrupting the speech even when it outruns the edge', () => {
		/* cue identity beats the width tell — an interrupting speaker is a
		   speaker however short the speech above it was */
		const types = typesOf([
			{ text: 'MIA' },
			{ text: 'No.' },
			{ text: 'SEBASTIAN', attached: true },
			{ text: 'Yes.', attached: true }
		]);
		expect(types).toEqual(['character', 'dialogue', 'character', 'dialogue']);
	});

	it('never splits a speech mid-sentence — the tell needs a sentence boundary', () => {
		/* emilia-perez's pleas run translation-paired lines past the dialogue
		   column; the line above carries no terminal punctuation */
		const types = typesOf([
			{ text: 'RITA' },
			{ text: 'Mr. President, Mr. Judge' },
			{ text: 'Honorable advocates for the family of the deceased,', attached: true }
		]);
		expect(types).toEqual(['character', 'dialogue', 'dialogue']);
	});

	it('keeps a parenthetical-led line inside the speech however wide it runs (emilia-perez ×13)', () => {
		const types = typesOf([
			{ text: 'RITA' },
			{ text: 'favor?' },
			{ text: '(yelling) Hey guys, can you please turn it down!', attached: true }
		]);
		expect(types).toEqual(['character', 'dialogue', 'dialogue']);
	});

	it('keeps a lowercase or inverted-mark opening with the line above it', () => {
		const types = typesOf([
			{ text: 'RITA' },
			{ text: 'Your Honor, I ask for the triumph of Love,' },
			{ text: 'of Innocence, the defeat of Bad Faith, faith, faith,', attached: true }
		]);
		expect(types).toEqual(['character', 'dialogue', 'dialogue']);
	});

	it('keeps shouted dialogue with terminal punctuation inside the speech', () => {
		const types = typesOf([{ text: 'MARA' }, { text: 'GET OUT!', attached: true }]);
		expect(types).toEqual(['character', 'dialogue']);
	});

	it('rescinds a cue whose speech runs prose-wide — a season card, not a speaker (lalaland’s WINTER)', () => {
		/* the card and the two prose lines under it all become action; every
		   word survives, and the false speaker leaves the cast */
		const { script, report } = finalizeImport(
			classifyLines([
				{ text: 'Flash title card:' },
				{ text: 'WINTER', attached: true },
				{ text: 'We settle on a new car. A 1983 Dodge Riviera. In it is', attached: true },
				{ text: 'SEBASTIAN, 32, L.A. native. He’s listening to the radio. He’s', attached: true }
			]),
			'paste',
			[]
		);
		expect(report.characters).toEqual([]);
		expect(script.elements).toHaveLength(1);
		expect(script.elements[0]?.type).toBe('action');
		expect(script.elements[0]?.text).toContain('WINTER');
		expect(script.elements[0]?.text).toContain('We settle on a new car.');
	});

	it('rescinds a cue directly above a structural line — it introduced no speech', () => {
		const followers: Array<{ text: string; align?: 'center' }> = [
			{ text: 'INT. AUDITION ROOMS - DAY' },
			{ text: 'CUT TO:' },
			{ text: 'ONE DAY GONE', align: 'center' },
			{ text: 'CLOSE ON MARA' },
			{ text: 'ACT ONE' }
		];
		for (const follower of followers) {
			const classified = classifyLines([{ text: 'SPRING' }, follower]);
			expect(classified[0]?.type).toBe('action');
			expect(classified[0]?.confidence).toBe('low');
		}
	});

	it('rescinds a cue the document ends under — THE END is a card here', () => {
		const [line] = classifyLines([{ text: 'IRIS FADE OUT.' }, { text: 'THE END', attached: true }]);
		expect(line?.type).toBe('action');
	});

	it('rescinds a cast table’s wide description row but keeps the bare name row above a narrow one (episode-101)', () => {
		/* MAID sits over a wide dotted-leader line cut off by the next cue;
		   TRAVIS MARTINEZ sits over CODY — a second cue-shaped line under a
		   cue classifies as its speech (rule 7 answers to position first),
		   and a narrow one is a real speech's shape */
		const types = typesOf([
			{ text: 'MAID' },
			{ text: 'VAN’S MOM.....................................DEBORAH VANCELETTE', attached: true },
			{ text: 'TRAVIS MARTINEZ', attached: true },
			{ text: 'CODY MARTINEZ', attached: true }
		]);
		expect(types).toEqual(['action', 'action', 'character', 'dialogue']);
	});

	it('rescinds a cue whose wide block a heading cuts off, even when the second wrap runs short (lalaland’s other WINTER)', () => {
		const types = typesOf([
			{ text: 'WINTER' },
			{ text: 'A palm tree, a cloudless sky. We PULL BACK -- to reveal it’s' },
			{ text: 'all painted...', attached: true },
			{ text: 'EXT. STUDIO LOT - DAY' }
		]);
		expect(types).toEqual(['action', 'action', 'action', 'scene']);
	});

	it('keeps a wide line that closes its sentence — a complete utterance, however wide (breaking-bad’s HANK)', () => {
		const types = typesOf([
			{ text: 'HANK' },
			{ text: 'You’re not listening to me, and I am done here.' }
		]);
		expect(types).toEqual(['character', 'dialogue']);
	});

	it('keeps a fused wide line whose second wrap runs short — one long breath, not prose (whiplash)', () => {
		const types = typesOf([
			{ text: 'STUDIO CORE MEMBER #3' },
			{ text: 'I don’t care what you think of me, or how many cheeseburgers' },
			{ text: 'you had for lunch.', attached: true },
			{ text: 'ANDREW', attached: true },
			{ text: 'Yes.', attached: true }
		]);
		expect(types).toEqual(['character', 'dialogue', 'dialogue', 'character', 'dialogue']);
	});

	it('keeps a wide line opening with an ellipsis — it continues a sentence from above (corpus-6’s ELI)', () => {
		const types = typesOf([
			{ text: 'ELI' },
			{ text: '... that’s enough now ... that’s enough ... he mu' },
			{ text: 'take the Holy Spirit in on his own now-.', attached: true },
			{ text: 'INT. CHURCH - DAY' }
		]);
		expect(types).toEqual(['character', 'dialogue', 'dialogue', 'scene']);
	});

	it('never retypes a cue an explicit source style named — the DOCX route keeps its evidence', () => {
		const [line] = classifyLines([
			{ text: 'WINTER', styleName: 'Character' },
			{ text: 'INT. AUDITION ROOMS - DAY' }
		]);
		expect(line?.type).toBe('character');
	});

	it('reads a colon-bearing uppercase line as a label, not a cue', () => {
		const [line] = classifyLines([{ text: 'SECTION HEADING: ACT I - THE CORE ELEMENTS' }]);
		expect(line?.type).toBe('action');
	});

	it('upgrades a transition when a scene follows it', () => {
		const [transition] = classifyLines([
			{ text: 'THE END', indentInches: 6.0 },
			{ text: 'INT. EPILOGUE - DAWN' }
		]);
		expect(transition?.confidence).toBe('high');
	});

	it('types the camera’s own grammar as shots, never speakers — the corpus’s witness list', () => {
		/* godfather-2's VIEW idiom flooded the cast panel (69 of 179 names);
		   heat and corpus-6 carried the ANGLE/POV families. Rule 5 fires
		   before speech position, so these never sit under a cue as speech */
		const witnesses = [
			'VIEW ON HAGEN',
			'VIEW ON THE PAVILION',
			'MOVING VIEW ON THE PRIEST',
			'VIEW ALTERS',
			'THE VIEW BEGINS',
			'VIEW THROUGH THE WINDOW',
			'MED. VIEW',
			'CLOSE VIEW',
			'CLOSE MOVING VIEW',
			'FULL VIEW',
			'HIS VIEW',
			'THEIR VIEW',
			"MICHAEL'S VIEW",
			'LONG SHOT',
			'REAR SHOT - MAN',
			'CLOSE - TWO SHOT',
			'MED. CLOSE',
			'MED. CLOSE ON CLEMENZA',
			'MED. CLOSE - THE PHONE BOOTH',
			'CLOSE ON MICHAEL',
			'WHAT HE SEES',
			'VERY TIGHT ON HANNA IN 3/4 REAR SHOT',
			'ANGLE',
			'ANGLE - WAINGRO',
			'ANGLE, ELI',
			'NEW ANGLE - AN RV',
			'ANOTHER ANGLE',
			'35A ANGLE, MOMENTS LATER. 35A',
			"MOSS'S POV",
			"DANIEL'S POV,",
			"CERRITO'S POV: JAMMING",
			'POINT-OF-VIEW THROUGH WINDSHIELD',
			'TRAVELING POINT OF VIEW',
			/* the labelled frame — heat's colon family, which used to land in
			   somebody's speech or in the cast itself */
			'ECU: CHRIS\' FINGERS',
			'CLOSE: ENVELOPE',
			'CLOSER: HANNA',
			'FRONTAL: GARBAGE TRUCK',
			'TIGHTER: CHRIS',
			'WIDER: NEIL',
			'HIGH + WIDE: HANNA',
			'VIDEO MONITOR: HANNA',
			'REVERSE: BLACK + WHITE',
			'SIDE ANGLE: NEIL',
			"OVER HANNA'S SHOULDER: CERRITO'S",
			/* the dash twin of CLOSE ON, and the verb without the noun */
			'CLOSE - DRILL BIT',
			'CLOSER - NEIL',
			'TRACKING HANNA',
			/* the plural terminal */
			'REAR SHOTS',
			'SHOTS',
			'A SERIES OF SHOTS'
		];
		for (const witness of witnesses) {
			const [line] = classifyLines([{ text: witness }]);
			expect(`${witness} → ${line?.type}`).toBe(`${witness} → shot`);
		}
	});

	it('types a camera line sitting under a cue as the shot it is — and the cue above was no speaker', () => {
		/* the user's Godfather II paste: prose under a VIEW line sat in the
		   speech slot, and the VIEW line sat in the cast */
		const types = typesOf([
			{ text: 'VIEW ON MICHAEL' },
			{ text: 'He had no hint, not in his wildest imagination could he have' },
			{ text: 'guessed that she would do such a thing.', attached: true }
		]);
		expect(types).toEqual(['shot', 'action', 'action']);
	});

	it('leaves a mixed-case VIEW sentence to action — the camera grammar is uppercase-only', () => {
		const types = typesOf([
			{ text: 'VIEW ON MICHAEL, calm, thoughtful.  One can tell that he has' },
			{ text: 'special affection for his niece.', attached: true }
		]);
		expect(types).toEqual(['action', 'action']);
	});

	it('does not read a colon line whose label is no framing word as a shot', () => {
		/* the labelled-frame family names the camera's words only — a label
		   like SYNOPSIS: or CUE MUSIC: is furniture of its own kind */
		const [synopsis] = classifyLines([{ text: 'SYNOPSIS: THE FAMILY' }]);
		expect(synopsis?.type).not.toBe('shot');
		const [cue] = classifyLines([{ text: 'CUE MUSIC -- P.J. HARVEY' }]);
		expect(cue?.type).not.toBe('shot');
	});

	it('keeps a heading that merely contains a camera noun a scene — rule 2 answers first', () => {
		const [line] = classifyLines([{ text: 'EXT. A SICILIAN LANDSCAPE - FULL VIEW - DAY' }]);
		expect(line?.type).toBe('scene');
	});

	it('types a wrapped heading’s time-of-day tail as scene, not as the cue it wears', () => {
		const types = typesOf([
			{ text: "INT. DON CORLEONE'S OLD OFFICE - CLOSE VIEW ON MICHAEL" },
			{ text: 'CORLEONE - DAY', attached: true }
		]);
		expect(types).toEqual(['scene', 'scene']);
	});

	it('types a tail-shaped line under a finished heading as its own slug — and never folds it in', () => {
		/* the fold's tell needs the opening: the heading above already carries
		   its time-of-day, so the card is no continuation. It is a standalone
		   secondary slug (RFC-SECONDARY-SLUG §2) — typed scene, kept its own
		   element */
		const script = toScreenplay(
			classifyLines([
				{ text: 'INT. BOATHOUSE - DAY' },
				{ text: 'CORLEONE - DAY', attached: true }
			])
		);
		expect(script.elements).toEqual([
			{ type: 'scene', text: 'INT. BOATHOUSE - DAY' },
			{ type: 'scene', text: 'CORLEONE - DAY' }
		]);
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

	it('folds a wrapped heading’s time-of-day tail into the heading it completes (godfather-2)', () => {
		const script = toScreenplay(
			classifyLines([
				{ text: "INT. DON CORLEONE'S OLD OFFICE - CLOSE VIEW ON MICHAEL" },
				{ text: 'CORLEONE - DAY', attached: true },
				{ text: 'standing impassively, like a young Prince, recently crowned' }
			])
		);
		expect(script.elements).toEqual([
			{ type: 'scene', text: "INT. DON CORLEONE'S OLD OFFICE - CLOSE VIEW ON MICHAEL CORLEONE - DAY" },
			{ type: 'action', text: 'standing impassively, like a young Prince, recently crowned' }
		]);
	});

	it('never folds a real back-to-back heading into the unfinished one above it', () => {
		const script = toScreenplay(
			classifyLines([{ text: 'INT. BOATHOUSE' }, { text: 'EXT. TAHOE GATE - DAY', attached: true }])
		);
		expect(script.elements.map((element) => element.text)).toEqual(['INT. BOATHOUSE', 'EXT. TAHOE GATE - DAY']);
	});

	it('never folds across a blank line — attachment is the wrap’s evidence', () => {
		const script = toScreenplay(
			classifyLines([
				{ text: 'INT. BOATHOUSE' },
				{ text: 'CORLEONE - DAY' } /* not attached */
			])
		);
		expect(script.elements).toHaveLength(2);
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

describe('classifyLines · secondary slugs, the title-page block, and the closing card (RFC-SECONDARY-SLUG)', () => {
	it('types the corpus’s time-ending secondary slugs as scenes, never speakers', () => {
		/* every line here is a corpus witness: corpus-1, godfather-2, heat,
		   no-country ×5 */
		const types = typesOf([
			{ text: 'INT. SOMEWHERE - DAY' },
			{ text: 'Action under the master heading.' },
			{ text: 'COURTYARD - 1612 HAVENHURST - DAY' },
			{ text: 'THE NEW YORK HARBOR - DAY' },
			{ text: "MARCIAN0'S OFFICE - MARCIANO - DAY" },
			{ text: 'BASIN - DAY' },
			{ text: '2ND HOTEL EAGLE ROOM - NIGHT' },
			{ text: 'OFFICE HALLWAY - DAY' },
			{ text: "SHERIFF BELL'S OFFICE - DAY" },
			{ text: 'COFFEE SHOP - EL PASO - NIGHT' }
		]);
		expect(types).toEqual([
			'scene',
			'action',
			'scene',
			'scene',
			'scene',
			'scene',
			'scene',
			'scene',
			'scene',
			'scene'
		]);
	});

	it('types the quantity-LATER cards as scenes (no-country)', () => {
		const types = typesOf([
			{ text: 'INT. SOMEWHERE - DAY' },
			{ text: 'Action.' },
			{ text: 'MINUTES LATER' },
			{ text: 'More action.' },
			{ text: 'A MINUTE LATER' },
			{ text: 'Still more.' }
		]);
		expect(types).toEqual(['scene', 'action', 'scene', 'action', 'scene', 'action']);
	});

	it('types the ANOTHER PART insert as a scene (godfather-2)', () => {
		const types = typesOf([
			{ text: 'INT. CASINO - NIGHT' },
			{ text: 'Action.' },
			{ text: 'ANOTHER PART OF THE CASINO' },
			{ text: 'More action.' }
		]);
		expect(types).toEqual(['scene', 'action', 'scene', 'action']);
	});

	it('refuses the shapes the grammar names as residue', () => {
		/* X - NAME collides with real speakers (HAGEN'S SON); the tailed LATER
		   card is manchester's "SEVEN YEARS LATER -- THE PRESENT"; "LATER THAT
		   NIGHT" and "SEE YOU LATER" carry no quantity before LATER */
		for (const text of [
			'BEDROOM - JUSTINE',
			"NEIL'S HAND",
			'SEVEN YEARS LATER -- THE PRESENT',
			'LATER THAT NIGHT',
			'SEE YOU LATER',
			'ANOTHER COUNTER'
		]) {
			const types = typesOf([
				{ text: 'INT. SOMEWHERE - DAY' },
				{ text: 'Action.' },
				{ text },
				{ text: 'More action follows here.' }
			]);
			expect(types[2]).not.toBe('scene');
		}
	});

	it('still folds a time-ending card attached under an open heading (rule 2½ answers first)', () => {
		const script = toScreenplay(
			classifyLines([
				{ text: "INT. DON CORLEONE'S OLD OFFICE" },
				{ text: 'CORLEONE - DAY', attached: true }
			])
		);
		expect(script.elements).toEqual([
			{ type: 'scene', text: "INT. DON CORLEONE'S OLD OFFICE CORLEONE - DAY" }
		]);
	});

	it('types the ON-insert as a shot (heat ×5)', () => {
		const types = typesOf([
			{ text: 'INT. SOMEWHERE - DAY' },
			{ text: 'Action.' },
			{ text: 'ON AMBULANCE' },
			{ text: 'It screams through traffic.' },
			{ text: 'ON STATION WAGON' },
			{ text: 'It waits at the light.' }
		]);
		expect(types).toEqual(['scene', 'action', 'shot', 'action', 'shot', 'action']);
	});

	it('types the closing card as centered and keeps it out of the last speech', () => {
		const script = toScreenplay(
			classifyLines([
				{ text: 'EXT. ROOF - NIGHT' },
				{ text: 'MARA' },
				{ text: 'Goodnight.' },
				{ text: 'THE END' }
			])
		);
		expect(script.elements.map((element) => element.type)).toEqual([
			'scene',
			'character',
			'dialogue',
			'centered'
		]);
		expect(script.elements[3]?.text).toBe('THE END');
	});

	it('types THE END. with its period, and never the sentence that ends on the words', () => {
		expect(typesOf([{ text: 'EXT. X - DAY' }, { text: 'Action.' }, { text: 'THE END.' }])[2]).toBe('centered');
		const types = typesOf([
			{ text: 'EXT. X - DAY' },
			{ text: 'Action.' },
			{ text: 'THE END OF A THIRTY FOOT METAL POLE-' },
			{ text: 'More action follows here.' }
		]);
		expect(types[2]).not.toBe('centered');
	});

	it('centers a pasted title page — manchester’s four lines, then the story untouched', () => {
		const script = toScreenplay(
			classifyLines([
				{ text: 'MANCHESTER BY THE SEA' },
				{ text: 'Written & Directed' },
				{ text: 'by' },
				{ text: 'Kenneth Lonergan' },
				{ text: 'EXT. MANCHESTER HARBOR -- SEA. DAY.' },
				{ text: 'A small commercial fishing boat heads out of Manchester.' }
			])
		);
		expect(script.elements.map((element) => element.type)).toEqual([
			'centered',
			'centered',
			'centered',
			'centered',
			'scene',
			'action'
		]);
		/* centered lines never merge — each title line stands on its own */
		expect(script.elements).toHaveLength(6);
	});

	it('centers the block through its dotted-leader cast table (episode-101)', () => {
		const types = typesOf([
			{ text: 'Episode 101' },
			{ text: '"PILOT"' },
			{ text: 'Written by' },
			{ text: 'Vince Gilligan' },
			{ text: 'WALTER WHITE..............Bryan Cranston' },
			{ text: 'JESSE PINKMAN..............Aaron Paul' },
			{ text: 'TEASER' },
			{ text: 'EXT. COW PASTURE - DAY' }
		]);
		expect(types).toEqual([
			'centered',
			'centered',
			'centered',
			'centered',
			'centered',
			'centered',
			'actbreak',
			'scene'
		]);
	});

	it('engages on the credit words, however long the credit line runs (emilia-perez)', () => {
		const types = typesOf([
			{ text: 'EMILIA PÉREZ' },
			{ text: 'A musical written and directed by Jacques Audiard' },
			{ text: 'EXT. MEXICO CITY - NIGHT' },
			{ text: 'Top shot and perpendicular zoom: Mexico City.' }
		]);
		expect(types).toEqual(['centered', 'centered', 'scene', 'action']);
	});

	it('closes the block at an extension cue — gone-girl’s opening speech stays speech', () => {
		const types = typesOf([
			{ text: 'GONE GIRL' },
			{ text: 'GONE GIRL' },
			{ text: 'by Gillian Flynn' },
			{ text: 'NICK (V.0.)' },
			{ text: 'When I think of my wife, I picture cracking her lovely skull.' }
		]);
		expect(types).toEqual(['centered', 'centered', 'centered', 'character', 'dialogue']);
	});

	it('never engages without a credit line — a pasted fragment opening at a cue is untouched', () => {
		const types = typesOf([{ text: 'ELI' }, { text: 'DO YOU ACCEPT JESUS CHRIST AS YOUR SAVIOR?' }]);
		expect(types).toEqual(['character', 'dialogue']);
		const plain = typesOf([{ text: 'JOHN' }, { text: 'Yeah.' }]);
		expect(plain).toEqual(['character', 'dialogue']);
	});

	it('never engages when the opening lines run prose-wide before any credit', () => {
		/* a block that hits its forty-character ceiling before a credit is no
		   title page — the walk stops and the lines classify as they always did */
		const types = typesOf([
			{ text: 'A line of opening prose that runs well past forty characters, the way a story does.' },
			{ text: 'Written by' },
			{ text: 'SOMEBODY' }
		]);
		expect(types[0]).not.toBe('centered');
	});

	it('keeps an explicit source style above the block (the DOCX route)', () => {
		const [line] = classifyLines([
			{ text: 'MANCHESTER BY THE SEA' },
			{ text: 'Written & Directed' },
			{ text: 'by Kenneth Lonergan', styleName: 'Byline' }
		]);
		expect(line?.type).toBe('centered');
		const classified = classifyLines([
			{ text: 'MANCHESTER BY THE SEA' },
			{ text: 'Written & Directed' },
			{ text: 'by Kenneth Lonergan', styleName: 'Character' }
		]);
		expect(classified[2]?.type).toBe('character');
	});
});
