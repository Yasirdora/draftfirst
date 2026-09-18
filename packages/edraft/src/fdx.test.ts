/** FDX import, export, diagnostics, limits, and round-trip behavior. */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
	decodeXmlEntities,
	encodeXmlEntities,
	type FdxScriptNote,
	openFdx,
	parseFdx,
	writeFdx,
	writeFdxWithDiagnostics
} from './fdx.js';
import { canonicalCasing } from './normalize.js';
import { parseFountain } from './parse.js';
import { serialiseFountain } from './serialise.js';
import { SAMPLE_FOUNTAIN } from '../test/fixtures/sample.js';
import type { ElementType, Screenplay } from './types.js';

/** A file with every ScriptNote Range value emptied. A save rewrites the Range
    of each note whose words moved (IL-0033); a comparison of the script sets
    those values aside, and the notes' words are proven on their own. */
const withoutNoteRanges = (xml: string) => xml.replace(/(<ScriptNote\b[^>]*?\sRange=")[^"]*(")/g, '$1$2');

const FOREIGN_FDX = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft DocumentType="Script" Version="3">
  <Content>
    <Paragraph Type="Scene Heading" Number="1">
      <SceneProperties Length="2/8" Page="1"/>
      <Text>INT. FISH &amp; CHIP SHOP - DAY</Text>
    </Paragraph>
    <Paragraph Type="Action"><Text>A &quot;quiet&quot; room &lt;somehow&gt;.</Text></Paragraph>
    <Paragraph Type="Character"><Text>MOLLY (V.O.)</Text></Paragraph>
    <Paragraph Type="Parenthetical"><Text>(beat)</Text></Paragraph>
    <Paragraph Type="Dialogue"><Text>We&apos;re closed.</Text></Paragraph>
    <Paragraph Type="Dialogue"><Text>Come back tomorrow.</Text></Paragraph>
    <Paragraph Type="Transition"><Text>CUT TO:</Text></Paragraph>
    <Paragraph Alignment="Center" Type="General"><Text>THE END</Text></Paragraph>
  </Content>
  <TitlePage>
    <Content>
      <Paragraph Alignment="Center" Type="General"><Text>Chips</Text></Paragraph>
      <Paragraph Alignment="Center" Type="General"><Text>written by</Text></Paragraph>
      <Paragraph Alignment="Center" Type="General"><Text>A. Writer</Text></Paragraph>
    </Content>
  </TitlePage>
</FinalDraft>`;

describe('entities', () => {
	it('decode/encode round-trips', () => {
		const raw = `A & "B" <C> 'D'`;
		expect(decodeXmlEntities(encodeXmlEntities(raw))).toBe(raw);
	});

	it('decodes numeric entities', () => {
		expect(decodeXmlEntities('&#65;&#x42;')).toBe('AB');
	});

	it('preserves invalid numeric entities without throwing', () => {
		expect(() => decodeXmlEntities('&#x110000;&#55296;&#999999999999999999999;')).not.toThrow();
		expect(decodeXmlEntities('&#x110000;&#55296;')).toBe('&#x110000;&#55296;');
	});

	it('decodes entities only once', () => {
		expect(decodeXmlEntities('&amp;lt;')).toBe('&lt;');
	});
});


/**
 * A production draft in miniature: the constructs a real Final Draft file
 * carries that a screenplay model cannot hold — revisions, locked pages,
 * tags, emphasis runs, and a scene heading with its arc beats nested inside.
 */
const PRODUCTION_FDX = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft DocumentType="Script" Template="No" Version="6">
  <Content>
    <Paragraph Type="Scene Heading" Number="1" id="a1">
      <SceneProperties Length="4/8" Page="1" Title="Set up Gold Key">
        <SceneArcBeats>
          <CharacterArcBeat Name="TANGLE">
            <Paragraph><Text>Tangle is obsessed with the treasure.</Text></Paragraph>
          </CharacterArcBeat>
        </SceneArcBeats>
      </SceneProperties>
      <Text>INT. HOME LIBRARY - DAY</Text>
    </Paragraph>
    <Paragraph Type="Action" id="a2"><Text>Majestic.</Text></Paragraph>
    <Paragraph Type="Action" id="a3"><Text RevisionID="2">Light </Text><Text Style="Italic">glinting</Text><Text> off it.</Text></Paragraph>
    <Paragraph Alignment="Center" Type="General"><Text>The end</Text></Paragraph>
  </Content>
  <LockedPages><LockedPage Number="1"/></LockedPages>
  <Revisions><Revision Color="Blue" Mark="*" Name="First Revision" Number="1"/></Revisions>
  <TagData><TagDefinition Id="t1" Label="Spanish moss"/></TagData>
</FinalDraft>`;

describe('openFdx · preserving round trip', () => {
	/**
	 * The invariant the whole thing rests on: opening a file and saving it
	 * without editing gives back the same file, to the byte.
	 *
	 * Rebuilding from the screenplay instead loses everything the screenplay
	 * cannot hold. Measured on a real production draft: 19 revisions, 171
	 * revised runs, 25 locked pages, 73 deleted-text marks, 248 production
	 * tags, 6 dual-dialogue blocks, 136 emphasis runs and 3 script notes — all
	 * gone from opening the file, changing one word and saving.
	 */
	it('a save with no edit returns the identical file', () => {
		const doc = openFdx(PRODUCTION_FDX);
		expect(doc.rewrite(doc.script).xml).toBe(PRODUCTION_FDX);
	});

	it('an edit rewrites that paragraph and touches nothing else', () => {
		const doc = openFdx(PRODUCTION_FDX);
		const edited = {
			...doc.script,
			elements: doc.script.elements.map((e) =>
				e.text === 'Majestic.' ? { ...e, text: 'Majestic, and lit.' } : e
			)
		};
		const xml = doc.rewrite(edited).xml;

		expect(xml).toContain('Majestic, and lit.');
		expect(xml).not.toContain('>Majestic.<');
		// Everything the screenplay cannot hold survived the edit.
		expect(xml).toContain('<Revision');
		expect(xml).toContain('<LockedPage');
		expect(xml).toContain('<TagDefinition');
		expect(xml).toContain('Style="Italic"');
		// Including on the edited paragraph's own neighbours.
		expect(xml).toContain('<SceneProperties');
	});

	/**
	 * A scene heading carries <SceneProperties> and, with the Beat Board, an
	 * arc beat per character. Editing the heading's words must not cost the
	 * writer their beats.
	 */
	it('keeps a scene heading nested blocks when its text changes', () => {
		const doc = openFdx(PRODUCTION_FDX);
		const edited = {
			...doc.script,
			elements: doc.script.elements.map((e) =>
				e.type === 'scene' ? { ...e, text: 'INT. SOMEWHERE ELSE - NIGHT' } : e
			)
		};
		const xml = doc.rewrite(edited).xml;
		expect(xml).toContain('INT. SOMEWHERE ELSE - NIGHT');
		expect(xml).toContain('<CharacterArcBeat Name="TANGLE">');
		expect(xml).toContain('Tangle is obsessed');
		expect(xml).toContain('Number="1"');
	});

	/**
	 * Fountain has no `Shot` and no `General`, so both come back as action.
	 * Rewriting them as Action would be a loss the writer never asked for —
	 * and it is what dropped all twelve `<DualDialogue>` wrappers on a real
	 * production draft, since those live in the whitespace between the
	 * paragraphs being replaced.
	 */
	it('keeps a kind Fountain cannot carry, even when the words change', () => {
		const xml = `<FinalDraft><Content>
<Paragraph Type="Shot"><Text>CLOSE ON: A GOLD KEY</Text></Paragraph>
</Content></FinalDraft>`;
		const doc = openFdx(xml);
		expect(doc.script.elements[0].type).toBe('shot');

		// What the editor gives back after a Fountain round trip: action.
		const out = doc.rewrite({
			titlePage: [],
			elements: [{ type: 'action', text: 'CLOSE ON: A SILVER KEY' }]
		}).xml;
		expect(out).toContain('Type="Shot"');
		expect(out).toContain('CLOSE ON: A SILVER KEY');
	});

	/** A kind Fountain *can* carry is the writer's to change. */
	it('writes a kind the writer really did change', () => {
		const xml = `<FinalDraft><Content>
<Paragraph Type="Action" id="k1"><Text>MARA</Text></Paragraph>
</Content></FinalDraft>`;
		const doc = openFdx(xml);
		const out = doc.rewrite({
			titlePage: [],
			elements: [{ type: 'character', text: 'MARA' }]
		}).xml;
		expect(out).toContain('Type="Character"');
		expect(out).toContain('id="k1"');
	});

	it('writes a whole file when there is nothing to preserve', () => {
		const doc = openFdx('not xml at all');
		const xml = doc.rewrite({
			titlePage: [],
			elements: [{ type: 'action', text: 'A fresh start.' }]
		}).xml;
		expect(xml).toContain('<FinalDraft');
		expect(xml).toContain('A fresh start.');
	});
});

describe('parseFdx · import', () => {
	/**
	 * A scene heading in a real Final Draft file is not a leaf.
	 *
	 * It carries <SceneProperties>, and if the writer uses the Beat Board that
	 * holds a <CharacterArcBeat> per character in the scene, each with its own
	 * <Paragraph><Text>. The heading's own text comes *after* all of it.
	 *
	 * Read naively, the nested paragraph closes the heading before its text is
	 * reached: measured on two real features, every one of 37 and 34 headings
	 * imported empty, the Navigator showed "No Scenes Yet", and the arc beats
	 * appeared in the script as body copy.
	 */
	it('takes a scene heading own text, not its arc beats', () => {
		const xml = `<FinalDraft><Content>
<Paragraph Type="Scene Heading" Number="1">
  <SceneProperties Length="4/8" Page="1" Title="Set up Gold Key">
    <SceneArcBeats>
      <CharacterArcBeat Name="TANGLE">
        <Paragraph><Text>Tangle is obsessed with the treasure.</Text></Paragraph>
      </CharacterArcBeat>
      <CharacterArcBeat Name="UNCLE">
        <Paragraph><Text>Uncle keeps the secret.</Text></Paragraph>
      </CharacterArcBeat>
    </SceneArcBeats>
  </SceneProperties>
  <Text>INT. HOME LIBRARY - DAY</Text>
</Paragraph>
<Paragraph Type="Action"><Text>Majestic.</Text></Paragraph>
</Content></FinalDraft>`;
		const { script, diagnostics } = parseFdx(xml);
		expect(script.elements).toEqual([
			{ type: 'scene', text: 'INT. HOME LIBRARY - DAY', sceneNumber: '1' },
			{ type: 'action', text: 'Majestic.' }
		]);
		expect(diagnostics.filter((d) => d.code === 'FDX_NESTED_PARAGRAPH')).toHaveLength(0);
	});

	/**
	 * The screenplay is the <Content> under <FinalDraft>. A feature written
	 * with the Beat Board carries one per <Outline> section — fifty-three of
	 * them in the files this was measured against — and taking paragraphs from
	 * all of them puts the writer's beats, page goals and cast list into the
	 * script.
	 */
	it('reads the screenplay Content and not the outline sections', () => {
		const xml = `<FinalDraft>
<Content><Paragraph Type="Action"><Text>On the page.</Text></Paragraph></Content>
<Outline><Content>
  <Paragraph Type="Beat"><Text>Not on the page.</Text></Paragraph>
  <Paragraph Type="PageGoal"><Text>Nor this.</Text></Paragraph>
</Content></Outline>
</FinalDraft>`;
		expect(parseFdx(xml).script.elements).toEqual([{ type: 'action', text: 'On the page.' }]);
	});

	/** A paragraph that genuinely never closes is still recovered, and still says so. */
	it('still warns when a paragraph is left unclosed', () => {
		const xml = `<FinalDraft><Content>` +
			`<Paragraph Type="Action"><Text>First.</Text>` +
			`<Paragraph Type="Action"><Text>Second.</Text></Paragraph>` +
			`</Content></FinalDraft>`;
		const { script } = parseFdx(xml);
		expect(script.elements.map((e) => e.text)).toContain('First.');
	});

	it('maps FDX paragraph types to the model', () => {
		const { script } = parseFdx(FOREIGN_FDX);
		expect(script.elements.map((e) => e.type)).toEqual([
			'scene',
			'action',
			'character',
			'parenthetical',
			'dialogue',
			'dialogue',
			'transition',
			'centered'
		]);
	});

	it('decodes entities in text', () => {
		const { script } = parseFdx(FOREIGN_FDX);
		expect(script.elements[0].text).toBe('INT. FISH & CHIP SHOP - DAY');
		expect(script.elements[1].text).toBe('A "quiet" room <somehow>.');
		expect(script.elements[4].text).toBe("We're closed.");
	});

	it('captures scene numbers from the Number attribute', () => {
		const { script } = parseFdx(FOREIGN_FDX);
		expect(script.elements[0].sceneNumber).toBe('1');
	});

	it('imports the title page verbatim — text, alignment, no invented keys', () => {
		const { script } = parseFdx(FOREIGN_FDX);
		/* What the file says is what the model holds (RFC-TITLE-PAGE D5);
		   the positional key guess is gone. */
		expect(script.titlePage).toEqual([
			{ text: 'Chips', alignment: 'center' },
			{ text: 'written by', alignment: 'center' },
			{ text: 'A. Writer', alignment: 'center' }
		]);
	});

	it('warns on unknown paragraph types but keeps going', () => {
		const xml = `<?xml version="1.0"?><FinalDraft DocumentType="Script" Version="3"><Content><Paragraph Type="Cast List"><Text>MOLLY</Text></Paragraph></Content></FinalDraft>`;
		const { script, warnings } = parseFdx(xml);
		expect(script.elements[0].type).toBe('general');
		expect(warnings.length).toBeGreaterThan(0);
	});

	it('never throws on malformed input', () => {
		expect(() => parseFdx('not xml at all')).not.toThrow();
		expect(() => parseFdx('')).not.toThrow();
	});

	it('reads the script body even when TitlePage comes first (variant files)', () => {
		const xml = `<?xml version="1.0"?><FinalDraft DocumentType="Script" Version="3"><TitlePage><Content><Paragraph Type="General"><Text>A TITLE</Text></Paragraph></Content></TitlePage><Content><Paragraph Type="Scene Heading"><Text>INT. LAB - DAY</Text></Paragraph><Paragraph Type="Action"><Text>Hum.</Text></Paragraph></Content></FinalDraft>`;
		const { script } = parseFdx(xml);
		expect(script.elements[0]).toMatchObject({ type: 'scene', text: 'INT. LAB - DAY' });
		expect(script.elements[1]).toMatchObject({ type: 'action', text: 'Hum.' });
		expect(script.titlePage[0]).toEqual({ text: 'A TITLE' });
	});

	it('accepts exact single-quoted attributes and greater-than signs inside values', () => {
		const xml = `<FinalDraft><Content><Paragraph DataType="Action" Type = 'Scene Heading' Number = 'A>7'><Text>INT. LAB - DAY</Text></Paragraph></Content></FinalDraft>`;
		const { script } = parseFdx(xml);
		expect(script.elements[0]).toEqual({
			type: 'scene',
			text: 'INT. LAB - DAY',
			sceneNumber: 'A>7'
		});
	});

	it('ignores comments and preserves CDATA text literally', () => {
		const xml = `<FinalDraft><Content><!-- <Paragraph Type="Action">bad</Paragraph> --><Paragraph Type="Action"><Text><![CDATA[A < B & C]]></Text></Paragraph></Content></FinalDraft>`;
		expect(parseFdx(xml).script.elements).toEqual([{ type: 'action', text: 'A < B & C' }]);
	});

	it('rejects oversized input without parsing a partial screenplay', () => {
		const result = parseFdx('<FinalDraft><Content/></FinalDraft>', { maxSourceCharacters: 10 });
		expect(result.script.elements).toEqual([]);
		expect(result.diagnostics[0].code).toBe('FDX_INPUT_TOO_LARGE');
	});

	it('bounds repeated warnings', () => {
		const paragraphs = Array.from(
			{ length: 8 },
			(_, index) => `<Paragraph Type="Unknown ${index}"><Text>x</Text></Paragraph>`
		).join('');
		const result = parseFdx(`<FinalDraft><Content>${paragraphs}</Content></FinalDraft>`, {
			maxWarnings: 2
		});
		expect(result.diagnostics).toHaveLength(2);
		expect(result.diagnostics[1].code).toBe('FDX_DIAGNOSTICS_TRUNCATED');
	});
});

describe('writeFdx · export', () => {
	it('emits a valid FinalDraft envelope', () => {
		const fdx = writeFdx(parseFountain(SAMPLE_FOUNTAIN));
		expect(fdx).toContain('<FinalDraft xmlns:EDraft="https://edraft.xyz/ns/fdx/1"');
		expect(fdx).toContain('DocumentType="Script" Version="3">');
		expect(fdx).toContain('</FinalDraft>');
		expect(fdx).toContain('<TitlePage>');
	});

	it('escapes text and preserves scene numbers', () => {
		const script: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'scene', text: 'INT. A & B - DAY', sceneNumber: 'A7' },
				{ type: 'dialogue', text: `It's <fine> "really".` }
			]
		};
		const fdx = writeFdx(script);
		expect(fdx).toContain('INT. A &amp; B - DAY');
		expect(fdx).toContain('Number="A7"');
		expect(fdx).toContain('It&apos;s &lt;fine&gt; &quot;really&quot;.');
	});

	it('marks centered paragraphs with Alignment="Center"', () => {
		const fdx = writeFdx({ titlePage: [], elements: [{ type: 'centered', text: 'THE END' }] });
		expect(fdx).toContain('Alignment="Center"');
	});

	it('reports structural elements that the supported FDX subset omits', () => {
		const result = writeFdxWithDiagnostics({
			titlePage: [],
			elements: [
				{ type: 'pagebreak', text: '' },
				{ type: 'action', text: 'Visible.' }
			]
		});
		expect(result.xml).toContain('Visible.');
		expect(result.xml).toContain('eDraft warning: 1 unsupported element(s) omitted');
		expect(result.diagnostics).toContainEqual(
			expect.objectContaining({ code: 'FDX_STRUCTURAL_ELEMENTS_OMITTED', count: 1 })
		);
	});

	/**
	 * The outline is not decoration. Final Draft's Outline levels and its
	 * Summary are a writer's act and sequence structure, and reading them as
	 * General put 82 of them on the page as stage directions across the two
	 * production drafts this was measured on.
	 */
	it('writes the outline back as the levels Final Draft reads', () => {
		const result = writeFdxWithDiagnostics({
			titlePage: [],
			elements: [
				{ type: 'section', text: 'Act One', depth: 1 },
				{ type: 'section', text: 'Meet Tangle', depth: 2 },
				{ type: 'synopsis', text: 'They meet.' },
				{ type: 'action', text: 'Visible.' }
			]
		});
		expect(result.xml).toContain('<Paragraph Type="Outline 1"><Text>Act One</Text></Paragraph>');
		expect(result.xml).toContain('<Paragraph Type="Outline 2"><Text>Meet Tangle</Text></Paragraph>');
		expect(result.xml).toContain('<Paragraph Type="Summary"><Text>They meet.</Text></Paragraph>');
		expect(result.diagnostics).toEqual([]);
	});

	it('reads the outline back at the level it was written', () => {
		const original: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'section', text: 'Act One', depth: 1 },
				{ type: 'section', text: 'Set up Gold Key', depth: 3 },
				{ type: 'synopsis', text: 'Tangle questions Uncle.' },
				{ type: 'scene', text: 'INT. LIBRARY - DAY' }
			]
		};
		expect(parseFdx(writeFdx(original)).script).toEqual(original);
	});

	/** Final Draft lets a writer rename the levels; the number still rules. */
	it('reads a renamed outline level', () => {
		const xml = `<FinalDraft><Content>
<Paragraph Type="Outline 1 (Acts)"><Text>Act One</Text></Paragraph>
<Paragraph Type="Outline 3 (Scenes)"><Text>Set up Gold Key</Text></Paragraph>
</Content></FinalDraft>`;
		const result = parseFdx(xml);
		expect(result.script.elements).toEqual([
			{ type: 'section', text: 'Act One', depth: 1 },
			{ type: 'section', text: 'Set up Gold Key', depth: 3 }
		]);
		expect(result.diagnostics).toEqual([]);
	});

	it('writes a note as the Note paragraph Final Draft reads', () => {
		const result = writeFdxWithDiagnostics({
			titlePage: [],
			elements: [
				{ type: 'action', text: 'Visible.' },
				{ type: 'note', text: 'Check this against the schedule.' }
			]
		});
		expect(result.xml).toContain(
			'<Paragraph Type="Note"><Text>Check this against the schedule.</Text></Paragraph>'
		);
		expect(result.diagnostics).toEqual([]);
	});

	it('round-trips a note through Final Draft and back', () => {
		const original: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'scene', text: 'INT. ROOM - DAY' },
				{ type: 'note', text: 'Is this the same room as scene 4?' },
				{ type: 'action', text: 'She waits.' }
			]
		};
		expect(parseFdx(writeFdx(original)).script).toEqual(original);
	});

	it('replaces illegal XML characters and reports the repair', () => {
		const result = writeFdxWithDiagnostics({
			titlePage: [],
			elements: [{ type: 'action', text: 'A\u0000B' }]
		});
		expect(result.xml).toContain('A�B');
		expect(result.xml).not.toContain('\u0000');
		expect(result.diagnostics[0].code).toBe('FDX_INVALID_XML_CHARACTER_REPLACED');
	});

	it('preserves arbitrary and duplicate title keys, blank lines, and lyrics', () => {
		const original: Screenplay = {
			titlePage: [
				{ text: 'One', key: 'Custom' },
				{ text: 'Two', key: 'Custom' },
				{ text: '' },
				{ text: 'Again', key: 'Custom' }
			],
			elements: [{ type: 'lyrics', text: 'La la' }]
		};
		const roundTrip = parseFdx(writeFdx(original)).script;
		expect(roundTrip).toEqual({
			titlePage: [
				{ text: 'One', alignment: 'center', key: 'Custom' },
				{ text: 'Two', alignment: 'center', key: 'Custom' },
				{ text: '', alignment: 'center' },
				{ text: 'Again', alignment: 'center', key: 'Custom' }
			],
			elements: [{ type: 'lyrics', text: 'La la' }]
		});
	});
});

describe('FDX round-trips (hard invariants)', () => {
	it('model → fdx → model is an identity for the sample script', () => {
		const model = parseFountain(SAMPLE_FOUNTAIN);
		const back = parseFdx(writeFdx(model)).script;
		/* Everything FDX has a paragraph for survives exactly. Only a page
		   break has none — see `fdxTypeOf`. */
		const representable = model.elements.filter((e) => e.type !== 'pagebreak');
		expect(back.elements).toEqual(representable);
	});

	it('fdx → model → fdx → model is an identity for foreign files', () => {
		const once = parseFdx(FOREIGN_FDX).script;
		const twice = parseFdx(writeFdx(once)).script;
		expect(twice.elements).toEqual(once.elements);
	});

	it('fountain → model → fdx → model preserves type+text of every element', () => {
		const model = parseFountain(SAMPLE_FOUNTAIN);
		const viaFdx = parseFdx(writeFdx(model)).script;
		const representable = model.elements.filter((e) => e.type !== 'pagebreak');
		expect(viaFdx.elements.map((e) => [e.type, e.text])).toEqual(
			representable.map((e) => [e.type, e.text])
		);
	});
});

/**
 * The rename compatibility contract. An .fdx exported under the old name
 * carries `draftfirst:` extension attributes; it must keep importing with
 * full fidelity. We read the old prefix and never write it again.
 */
describe('pre-rename FDX files', () => {
	const legacyFdx = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft xmlns:DraftFirst="https://draftfirst.xyz/ns/fdx/1" DocumentType="Script" Version="3">
<Content>
<Paragraph Type="General" DraftFirst:ElementType="lyrics"><Text>Sing me home</Text></Paragraph>
</Content>
<TitlePage>
<Content>
<Paragraph Alignment="Center" Type="General" DraftFirst:TitleKey="Title" DraftFirst:TitleEntry="0"><Text>Old Name</Text></Paragraph>
<Paragraph Alignment="Center" Type="General" DraftFirst:TitleKey="Author" DraftFirst:TitleEntry="1"><Text>A. Writer</Text></Paragraph>
</Content>
</TitlePage>
</FinalDraft>
`;

	it('restores lyrics from the legacy element-type attribute', () => {
		const { script } = parseFdx(legacyFdx);
		expect(script.elements[0]).toMatchObject({ type: 'lyrics', text: 'Sing me home' });
	});

	it('restores title keys from legacy attributes as line annotations', () => {
		const { script } = parseFdx(legacyFdx);
		expect(script.titlePage).toEqual([
			{ text: 'Old Name', alignment: 'center', key: 'Title' },
			{ text: 'A. Writer', alignment: 'center', key: 'Author' }
		]);
	});

	it('re-exports the same document under the current namespace only', () => {
		const xml = writeFdx(parseFdx(legacyFdx).script);
		expect(xml).toContain('xmlns:EDraft="https://edraft.xyz/ns/fdx/1"');
		expect(xml).toContain('EDraft:ElementType="lyrics"');
		expect(xml).not.toContain('draftfirst.xyz');
		expect(xml).not.toContain('DraftFirst:');
	});
});

/**
 * How Final Draft shouts.
 *
 * It stores what the writer typed and marks the run `Style="AllCaps"`, so a
 * file can hold `cHroNo-aGEnT vAL` and have displayed CHRONO-AGENT VAL for the
 * life of the document. Every string here is lifted verbatim from a writer's
 * own .fdx.
 */
describe('FDX AllCaps runs', () => {
	const fdx = `<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<FinalDraft DocumentType="Script" Template="No" Version="6">
  <Content>
    <Paragraph Type="Scene Heading"><Text Style="AllCaps">iNt. eARThLInG cAFe - MoRNiNg</Text></Paragraph>
    <Paragraph Type="Action"><Text>The espresso machine hisses violently.</Text></Paragraph>
    <Paragraph Type="Character"><Text Style="AllCaps">cHroNo-aGEnT vAL</Text></Paragraph>
    <Paragraph Type="Dialogue"><Text>Greetings, carbon-based ancestors!</Text></Paragraph>
    <Paragraph Type="Transition"><Text Style="AllCaps">mATcH cUt tO:</Text></Paragraph>
    <Paragraph Type="Action"><Text Style="Bold+Underline+AllCaps">a shouted stage direction</Text></Paragraph>
  </Content>
</FinalDraft>`;

	it('shouts every run the file marks AllCaps', () => {
		const { script } = parseFdx(fdx);
		expect(script.elements.map((e) => e.text)).toEqual([
			'INT. EARTHLING CAFE - MORNING',
			'The espresso machine hisses violently.',
			'CHRONO-AGENT VAL',
			'Greetings, carbon-based ancestors!',
			'MATCH CUT TO:',
			'A SHOUTED STAGE DIRECTION'
		]);
	});

	it('leaves unmarked runs exactly as the writer typed them', () => {
		const { script } = parseFdx(fdx);
		expect(script.elements[1].text).toBe('The espresso machine hisses violently.');
		expect(script.elements[3].text).toBe('Greetings, carbon-based ancestors!');
	});

	it('reads AllCaps as one entry in the style list, never as a substring', () => {
		const notCaps = `<?xml version="1.0"?><FinalDraft DocumentType="Script"><Content>
<Paragraph Type="Action"><Text Style="AllCapsish">left alone</Text></Paragraph>
</Content></FinalDraft>`;
		expect(parseFdx(notCaps).script.elements[0].text).toBe('left alone');
	});
});

describe('runs in FDX — emphasis, revision, tags and the highlight', () => {
	it('reads a run’s attributes into the model', () => {
		const xml = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft xmlns:EDraft="https://edraft.xyz/ns/fdx/1" DocumentType="Script" Version="3"><Content>
<Paragraph Type="Action"><Text>plain </Text><Text Style="Bold+Italic">strong</Text><Text RevisionID="2"> revised</Text><Text EDraft:Highlight="Yellow"> marked</Text></Paragraph>
</Content></FinalDraft>`;

		const element = parseFdx(xml).script.elements[0];
		expect(element.text).toBe('plain strong revised marked');
		expect(element.runs).toEqual([
			{ start: 6, end: 12, styles: ['Bold', 'Italic'] },
			{ start: 12, end: 20, styles: [], revisionID: 2 },
			{ start: 20, end: 27, styles: [], highlight: 'yellow' }
		]);
	});

	it('writes runs back out, in canonical style order', () => {
		const script: Screenplay = {
			titlePage: [],
			elements: [
				{
					type: 'action',
					text: 'The strong marked words.',
					runs: [
						{ start: 4, end: 10, styles: ['Italic', 'Bold'] },
						{ start: 11, end: 17, styles: [], highlight: 'yellow' }
					]
				}
			]
		};
		const xml = writeFdx(script);
		expect(xml).toContain('<Text>The </Text>');
		expect(xml).toContain('<Text Style="Bold+Italic">strong</Text>');
		expect(xml).toContain('<Text EDraft:Highlight="Yellow">marked</Text>');
		expect(xml).toContain('<Text> words.</Text>');
	});

	it('round-trips runs losslessly through our own write and read', () => {
		const script: Screenplay = {
			titlePage: [],
			elements: [
				{
					type: 'dialogue',
					text: 'A bold thing, a marked thing.',
					runs: [
						{ start: 2, end: 6, styles: ['Bold'] },
						{ start: 16, end: 22, styles: [], highlight: 'yellow' }
					]
				}
			]
		};
		const back = parseFdx(writeFdx(script)).script.elements[0];
		expect(back.text).toBe('A bold thing, a marked thing.');
		expect(back.runs).toEqual([
			{ start: 2, end: 6, styles: ['Bold'] },
			{ start: 16, end: 22, styles: [], highlight: 'yellow' }
		]);
	});

	it('a runless document writes the same plain text it always did', () => {
		const script: Screenplay = {
			titlePage: [],
			elements: [{ type: 'action', text: 'No runs here.' }]
		};
		const xml = writeFdx(script);
		expect(xml).toContain('<Paragraph Type="Action"><Text>No runs here.</Text></Paragraph>');
		expect(xml).not.toContain('Style=');
		expect(xml).not.toContain('Highlight');
	});

	it('the preserving rewrite declares the namespace when it first needs it', () => {
		const xml = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft DocumentType="Script" Template="No" Version="6">
  <Content>
    <Paragraph Type="Action"><Text>Mark me.</Text></Paragraph>
  </Content>
</FinalDraft>`;
		const doc = openFdx(xml);
		const edited: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'action', text: 'Mark me.', runs: [{ start: 0, end: 4, styles: [], highlight: 'yellow' }] }
			]
		};
		const out = doc.rewrite(edited).xml;
		expect(out).toContain('xmlns:EDraft="https://edraft.xyz/ns/fdx/1"');
		expect(out).toContain('<Text EDraft:Highlight="Yellow">Mark</Text>');
	});
});

describe('FDX · act breaks (RFC-ACT-BREAK §3)', () => {
	it('reads New Act as an actbreak and absorbs End of Act', () => {
		const xml = `<FinalDraft><Content>
<Paragraph Type="Action"><Text>The teaser plays out.</Text></Paragraph>
<Paragraph Type="End of Act" Alignment="Center"><Text>END OF TEASER</Text></Paragraph>
<Paragraph Type="New Act" Alignment="Center"><Text>ACT ONE</Text></Paragraph>
<Paragraph Type="Action"><Text>No president ever slept here.</Text></Paragraph>
</Content></FinalDraft>`;
		const { script } = parseFdx(xml);
		expect(script.elements).toEqual([
			{ type: 'action', text: 'The teaser plays out.' },
			{ type: 'actbreak', text: 'ACT ONE' },
			{ type: 'action', text: 'No president ever slept here.' }
		]);
	});

	it('writes New Act centred and generates the End of Act the act ends', () => {
		const fdx = writeFdx({
			titlePage: [],
			elements: [
				{ type: 'action', text: 'Teaser.' },
				{ type: 'actbreak', text: 'ACT ONE' },
				{ type: 'action', text: 'Middle.' },
				{ type: 'actbreak', text: 'ACT TWO' },
				{ type: 'action', text: 'End.' }
			]
		});
		expect(fdx).toContain(
			'<Paragraph Type="New Act" Alignment="Center"><Text>ACT ONE</Text></Paragraph>'
		);
		expect(fdx).toContain(
			'<Paragraph Type="End of Act" Alignment="Center"><Text>END OF ACT ONE</Text></Paragraph>'
		);
		expect(fdx.indexOf('END OF ACT ONE')).toBeLessThan(fdx.indexOf('ACT TWO'));
		/* The document's own end ends the last act — nothing is generated there. */
		expect(fdx).not.toContain('END OF ACT TWO');
	});

	it('round-trips acts: export → import lands the model back exactly', () => {
		const script: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'action', text: 'Teaser.' },
				{ type: 'actbreak', text: 'ACT ONE' },
				{ type: 'action', text: 'Middle.' },
				{ type: 'actbreak', text: 'TEASER, BUT EVIL' },
				{ type: 'action', text: 'End.' }
			]
		};
		const { script: back } = parseFdx(writeFdx(script));
		expect(back.elements).toEqual(script.elements);
	});

	it('names the generated End of Act the way the act names itself', () => {
		/* Breaking Bad's own spelling: the teaser closes as END TEASER, the
		   canonical acts as END OF ACT <their ordinal> — a writer's card is
		   mirrored, never renamed (RFC-ACT-BREAK §3, refined in phase 3).
		   The fixture is renumber-stable: TEASER is custom and keeps its
		   name, so ACT TWO is the second act's canonical card. */
		const fdx = writeFdx({
			titlePage: [],
			elements: [
				{ type: 'action', text: 'Cold pasture.' },
				{ type: 'actbreak', text: 'TEASER' },
				{ type: 'action', text: 'Middle.' },
				{ type: 'actbreak', text: 'ACT TWO' },
				{ type: 'action', text: 'Later.' },
				{ type: 'actbreak', text: 'ACT TWO: THE TURN' },
				{ type: 'action', text: 'Nearly.' },
				{ type: 'actbreak', text: 'ACT THREE' },
				{ type: 'action', text: 'End.' }
			]
		});
		expect(fdx).toContain(
			'<Paragraph Type="End of Act" Alignment="Center"><Text>END TEASER</Text></Paragraph>'
		);
		expect(fdx).toContain(
			'<Paragraph Type="End of Act" Alignment="Center"><Text>END OF ACT TWO</Text></Paragraph>'
		);
		expect(fdx).toContain(
			'<Paragraph Type="End of Act" Alignment="Center"><Text>END ACT TWO: THE TURN</Text></Paragraph>'
		);
		/* the document's own end ends the last act — nothing is generated there */
		expect(fdx).not.toContain('END OF ACT THREE');
	});

	it('escapes a writer’s own card when it is mirrored into the End of Act', () => {
		const fdx = writeFdx({
			titlePage: [],
			elements: [
				{ type: 'actbreak', text: 'ACT ONE' },
				{ type: 'action', text: 'Middle.' },
				{ type: 'actbreak', text: 'FISH & CHIP SHOP' },
				{ type: 'action', text: 'Nearly.' },
				{ type: 'actbreak', text: 'ACT THREE' }
			]
		});
		expect(fdx).toContain('<Text>END FISH &amp; CHIP SHOP</Text>');
	});
});

describe('FDX · ScriptNotes', () => {
	/* A real feature's eleven notes, anonymised: every letter is x or X, so
	   each paragraph keeps its length and every Range lands where it did. */
	const SAMPLE = readFileSync(
		new URL('../../../apple/eDraftEngine/Fixtures/sample0-2.fdx', import.meta.url),
		'utf8'
	);
	const sample = parseFdx(SAMPLE);
	const note = (id: string) => sample.scriptNotes.find((candidate) => candidate.id === id);
	const block = (xml: string) =>
		xml.slice(xml.indexOf('<ScriptNotes>'), xml.indexOf('</ScriptNotes>') + '</ScriptNotes>'.length);

	it('reads eleven notes in file order, each by the writer the file names', () => {
		expect(sample.scriptNotes.map((n) => n.id)).toEqual([
			'107', '113', '143', '119', '152', '137', '108', '109', '110', '111', '112'
		]);
		expect(sample.scriptNotes.filter((n) => n.author === 'Writer A').map((n) => n.id)).toEqual([
			'107', '143', '152', '108', '109', '110', '111', '112'
		]);
		expect(sample.scriptNotes.filter((n) => n.author === 'Writer B').map((n) => n.id)).toEqual([
			'113', '119', '137'
		]);
		expect(sample.diagnostics).toEqual([]);
	});

	/* The Ranges in sample0-2.fdx were measured before an eDraft save moved
	   its text; the files Final Draft wrote are where a Range can be held to
	   the words it was written on. */
	const finalDraftWritten = (name: string) =>
		parseFdx(readFileSync(new URL(`../../../apple/eDraftEngine/Fixtures/${name}`, import.meta.url), 'utf8'));

	it.each([
		['finaldraft-sample02.fdx', 11, 10],
		['finaldraft-sample01.fdx', 12, 11]
	] as const)('every note in %s lands on whole words, or is empty', (name, notes, onWords) => {
		const { script, scriptNotes } = finalDraftWritten(name);
		const letter = (character: string | undefined) => character !== undefined && /[\p{L}\p{N}]/u.test(character);
		const midWord = (at: { element: number; offset: number }) => {
			const text = script.elements[at.element].text;
			return letter(text[at.offset - 1]) && letter(text[at.offset]);
		};
		expect(scriptNotes).toHaveLength(notes);
		const anchors = scriptNotes.map((scriptNote) => scriptNote.anchor);
		expect(anchors.filter((anchor) => anchor === undefined)).toEqual([]);
		expect(scriptNotes.filter(({ anchor }) => anchor && (midWord(anchor.start) || midWord(anchor.end))).map((n) => n.id)).toEqual([]);
		const empty = anchors.filter((anchor) => anchor && anchor.start.element === anchor.end.element && anchor.start.offset === anchor.end.offset);
		expect(empty).toHaveLength(notes - onWords);
	});

	it('anchors each Range on the words Final Draft measured it on, two units for each embedded block before it', () => {
		const { script, scriptNotes } = finalDraftWritten('finaldraft-sample02.fdx');
		const elements = script.elements;
		const at = (id: string) => scriptNotes.find((candidate) => candidate.id === id)?.anchor;
		/* before any block: the shot it is about, whole */
		expect(at('107')).toEqual({ start: { element: 6, offset: 0 }, end: { element: 6, offset: 20 } });
		expect([elements[6].type, elements[6].text.length]).toEqual(['shot', 20]);
		/* after five dual dialogues: exactly one action line */
		expect(at('109')).toEqual({ start: { element: 310, offset: 0 }, end: { element: 310, offset: 41 } });
		expect([elements[310].type, elements[310].text.length]).toEqual(['action', 41]);
		/* exactly one line of dialogue */
		expect(at('110')).toEqual({ start: { element: 548, offset: 0 }, end: { element: 548, offset: 6 } });
		expect([elements[548].type, elements[548].text.length]).toEqual(['dialogue', 6]);
		/* after the omitted scene too: from a cue to the start of the next line */
		expect(at('111')).toEqual({ start: { element: 593, offset: 0 }, end: { element: 595, offset: 0 } });
		/* zero-length, at the end of the script's last line */
		expect(at('112')).toEqual({ start: { element: 779, offset: 13 }, end: { element: 779, offset: 13 } });
		expect(elements).toHaveLength(780);
	});

	it('counts a block embedded in a paragraph as two units where it sits, its own text nothing', () => {
		const ranges = ['0,4', '5,7', '8,15', '15,16', '17,18', '18,21'];
		const xml = `<FinalDraft><Content><Paragraph Type="Action"><Text>Hum.</Text></Paragraph><Paragraph Type="General"><DualDialogue><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Yes.</Text></Paragraph><Paragraph Type="Character"><Text>JON</Text></Paragraph><Paragraph Type="Dialogue"><Text>No.</Text></Paragraph></DualDialogue></Paragraph><Paragraph Type="Scene Heading"><Text>Omitted</Text><OmittedScene><Paragraph Type="Scene Heading"><Text>EXT. YARD - DAY</Text></Paragraph></OmittedScene></Paragraph><Paragraph Type="Action"><Text>Go.</Text></Paragraph></Content><ScriptNotes>${ranges
			.map((range) => `<ScriptNote Range="${range}"><Paragraph><Text>n</Text></Paragraph></ScriptNote>`)
			.join('')}</ScriptNotes></FinalDraft>`;
		const { script, scriptNotes } = parseFdx(xml);
		expect(script.elements.map((element) => [element.type, element.text])).toEqual([
			['action', 'Hum.'],
			['character', 'MARA'],
			['dialogue', 'Yes.'],
			['character', 'JON'],
			['dialogue', 'No.'],
			['scene', 'Omitted'],
			['action', 'Go.']
		]);
		const span = (element: number, start: number, endElement: number, end: number) => ({
			start: { element, offset: start },
			end: { element: endElement, offset: end }
		});
		expect(scriptNotes.map((scriptNote) => scriptNote.anchor)).toEqual([
			span(0, 0, 0, 4), // the line before
			span(1, 0, 1, 0), // the dual dialogue's two units and its break: its first line
			span(5, 0, 5, 7), // "Omitted"
			span(5, 7, 5, 7), // the omitted scene's two units: its place, after the text
			span(5, 7, 6, 0), // the break after it, to the next line
			span(6, 0, 6, 3) // the line after both — past the script's end, counted as zero
		]);
	});

	it('keeps a body’s paragraphs, blank ones included', () => {
		const long = note('112')?.text.split('\n') ?? [];
		expect(long).toHaveLength(9);
		expect(long.filter((line) => line === '')).toHaveLength(4);
		expect(note('137')?.text.split('\n')).toHaveLength(8);
	});

	it('leaves out what the file leaves empty, and never reads WriterID', () => {
		expect(note('143')?.color).toBeUndefined(); // #000000000000
		expect(note('107')?.color).toBe('#6363A7A7EFEF');
		expect(note('152')?.title).toBeUndefined(); // Name=""
		expect(note('143')?.title).toBe('Re: Re: Xxxx Xxx');
		expect(note('137')?.category).toBe('Alt Scenes');
		expect(JSON.stringify(sample.scriptNotes)).not.toContain('b63f73e5');
	});

	it('is the same reading through openFdx', () => {
		expect(openFdx(SAMPLE).scriptNotes).toEqual(sample.scriptNotes);
		expect(parseFdx(FOREIGN_FDX).scriptNotes).toEqual([]);
	});

	it('a save with no edit keeps the ScriptNotes block byte for byte', () => {
		const document = openFdx(SAMPLE);
		const saved = document.rewrite(document.script).xml;
		expect(saved).toContain('<ScriptNotes>');
		expect(block(saved)).toBe(block(SAMPLE));
	});

	it('editing an annotated line keeps every byte of the ScriptNotes block but the Ranges that follow their words', () => {
		const document = openFdx(SAMPLE);
		const script: Screenplay = {
			...document.script,
			elements: document.script.elements.map((element, index) =>
				index === 536 ? { ...element, text: 'XXXXXX (V.O.)' } : element
			)
		};
		const saved = document.rewrite(script).xml;
		expect(saved).toContain('XXXXXX (V.O.)');
		expect(withoutNoteRanges(block(saved))).toBe(withoutNoteRanges(block(SAMPLE)));
	});

	it('counts every paragraph break, the absorbed End of Act included', () => {
		/* paragraphs start at 0, 15, 20 and 35; the script ends at 38 */
		const xml = `<FinalDraft><Content><Paragraph Type="Scene Heading"><Text>INT. LAB - DAY</Text></Paragraph><Paragraph Type="Action"><Text>Hum.</Text></Paragraph><Paragraph Type="End of Act"><Text>END OF ACT ONE</Text></Paragraph><Paragraph Type="Action"><Text>Go.</Text></Paragraph></Content><ScriptNotes>${[
			'15,19', '14,14', '22,22', '35,99', '60,70', '19,15', 'abc'
		]
			.map((range) => `<ScriptNote Range="${range}"><Paragraph><Text>n</Text></Paragraph></ScriptNote>`)
			.join('')}</ScriptNotes></FinalDraft>`;
		const [exact, onBreak, inAbsorbed, pastEnd, stale, reversed, unreadable] = parseFdx(xml).scriptNotes;
		expect(exact.anchor).toEqual({ start: { element: 1, offset: 0 }, end: { element: 1, offset: 4 } });
		expect(onBreak.anchor?.start).toEqual({ element: 0, offset: 14 });
		expect(inAbsorbed.anchor?.start).toEqual({ element: 2, offset: 0 });
		expect(pastEnd.anchor?.end).toEqual({ element: 2, offset: 3 });
		expect(stale.range).toEqual({ start: 60, end: 70 });
		expect(stale.anchor).toBeUndefined();
		expect(reversed.range).toEqual({ start: 15, end: 19 });
		expect(unreadable.range).toBeUndefined();
	});

	it('reads only direct children, decodes the author, and stops at the limit', () => {
		const xml = `<FinalDraft><Content><Paragraph Type="Action"><ScriptNote WriterName="Nobody"/><Text>Hum.</Text></Paragraph></Content><ScriptNotes><ScriptNote WriterName="  Ren&#233;e &amp; Co  "><Paragraph><Text Style="AllCaps">cut to:</Text></Paragraph><Paragraph/><Paragraph><SceneProperties><Paragraph><Text>hidden</Text></Paragraph></SceneProperties><Text>seen</Text></Paragraph></ScriptNote></ScriptNotes></FinalDraft>`;
		const [only, ...rest] = parseFdx(xml).scriptNotes;
		expect(rest).toEqual([]);
		expect(only.author).toBe('Renée & Co');
		expect(only.text).toBe('CUT TO:\n\nseen');

		const limited = parseFdx(xml.replace('</ScriptNotes>', '<ScriptNote/></ScriptNotes>'), {
			maxParagraphs: 4
		});
		expect(limited.scriptNotes).toHaveLength(1);
		expect(limited.diagnostics.map((d) => d.code)).toEqual(['FDX_SCRIPT_NOTES_LIMIT_REACHED']);
	});
});

/**
 * End of Act through a save.
 *
 * The import absorbs End of Act (RFC-ACT-BREAK D3), so no element stands for
 * it. Left to the alignment, every save deleted the card — and a card with no
 * Alignment, typed General, was paired with the writer's next edit and given
 * their text. The save now keeps each card verbatim in front of the next
 * paragraph it keeps, or after the last element when none is left.
 */
describe('openFdx · End of Act', () => {
	/* A real feature, anonymised, with one End of Act card near its end. */
	const SAMPLE = readFileSync(
		new URL('../../../apple/eDraftEngine/Fixtures/sample0-2.fdx', import.meta.url),
		'utf8'
	);
	const twoActs = (card: string) => `<FinalDraft><Content>
<Paragraph Type="New Act"><Text>ACT ONE</Text></Paragraph>
<Paragraph Type="Action" id="a1"><Text>Hum.</Text></Paragraph>
${card}
<Paragraph Type="New Act"><Text>ACT TWO</Text></Paragraph>
<Paragraph Type="Action" id="a2"><Text>Buzz.</Text></Paragraph>
</Content></FinalDraft>`;
	const CARD = '<Paragraph Alignment="Center" Type="End of Act"><Text>END OF ACT ONE</Text></Paragraph>';
	const BARE = '<Paragraph Type="End of Act"><Text>END OF ACT ONE</Text></Paragraph>';

	it('a save with no edit returns the feature byte for byte, its End of Act included', () => {
		expect(SAMPLE).toContain('Type="End of Act" id=');
		const document = openFdx(SAMPLE);
		expect(document.rewrite(document.script).xml).toBe(SAMPLE);
	});

	it('so does the app’s own path: into Fountain and back, with no edit', () => {
		/* ScreenplayFile.open shouts the kinds a screenplay shouts and hands the
		   editor Fountain; ScreenplayFile.encode parses it with runs and saves. */
		const imported = parseFdx(SAMPLE).script;
		const source = serialiseFountain({
			...imported,
			elements: imported.elements.map((element) => ({
				...element,
				text: canonicalCasing(element.type as ElementType, element.text)
			}))
		});
		// With the reading the app passes since IL-0027: without it, every
		// paragraph Fountain cannot carry — the dual dialogue cues' tags among
		// them — is judged edited.
		const reading = parseFountain(source, { emphasis: 'runs' });
		expect(openFdx(SAMPLE).rewrite(reading, { unedited: reading }).xml).toBe(SAMPLE);
	});

	it('a card with no Alignment never takes the writer’s edit', () => {
		const document = openFdx(twoActs(BARE));
		const saved = document.rewrite({
			...document.script,
			elements: document.script.elements.map((element) =>
				element.text === 'Buzz.' ? { ...element, text: 'Buzz, buzz.' } : element
			)
		}).xml;
		expect(saved).toContain(BARE);
		expect(saved).toContain('<Paragraph Type="Action" id="a2"><Text>Buzz, buzz.</Text></Paragraph>');
		expect(saved).not.toContain('Type="End of Act"><Text>Buzz');
	});

	it('lines added at the end of an act land before its card', () => {
		const document = openFdx(twoActs(CARD));
		const elements = document.script.elements;
		const saved = document.rewrite({
			...document.script,
			elements: [...elements.slice(0, 2), { type: 'action', text: 'A new last line.' }, ...elements.slice(2)]
		}).xml;
		expect(saved.indexOf('A new last line.')).toBeLessThan(saved.indexOf(CARD));
		expect(saved.indexOf(CARD)).toBeLessThan(saved.indexOf('ACT TWO'));
	});

	it('keeps the card when the act break it closes is deleted', () => {
		const document = openFdx(twoActs(CARD));
		const withoutActTwo = {
			...document.script,
			elements: document.script.elements.filter((element) => element.text !== 'ACT TWO')
		};
		const saved = document.rewrite(withoutActTwo).xml;
		expect(saved).toContain(CARD);
		expect(saved.indexOf(CARD)).toBeLessThan(saved.indexOf('Buzz.'));

		const nothingAfter = document.rewrite({ ...document.script, elements: document.script.elements.slice(0, 2) }).xml;
		expect(nothingAfter.indexOf('Hum.')).toBeLessThan(nothingAfter.indexOf(CARD));
	});

	/* Every byte outside the edited paragraph matches the original — for lines
	   across the feature, and for both paragraphs beside its card. */
	it.each([0, 6, 9, 17, 298, 536, 764, 765, 766, 767])(
		'an edit to element %i changes bytes only inside that paragraph',
		(index) => {
			const document = openFdx(SAMPLE);
			const marker = `EDITED ${index}`;
			const original = withoutNoteRanges(SAMPLE);
			const saved = withoutNoteRanges(document.rewrite({
				...document.script,
				elements: document.script.elements.map((element, at) =>
					at === index ? { ...element, text: marker } : element
				)
			}).xml);
			const shorter = Math.min(original.length, saved.length);
			let prefix = 0;
			while (prefix < shorter && original[prefix] === saved[prefix]) prefix++;
			let suffix = 0;
			while (
				suffix < shorter - prefix &&
				original[original.length - 1 - suffix] === saved[saved.length - 1 - suffix]
			) {
				suffix++;
			}
			expect(original.slice(prefix, original.length - suffix)).not.toContain('Paragraph');
			expect(saved.slice(prefix, saved.length - suffix)).not.toContain('Paragraph');
			expect(
				saved.slice(Math.max(0, prefix - marker.length), saved.length - suffix + marker.length)
			).toContain(marker);
		}
	);
});

/**
 * Files Final Draft itself wrote.
 *
 * The no-edit proof above ran on a file an old eDraft save had already
 * stripped of its production tags, so it could not fail — and a save that
 * lost 400 of 407 tags passed it. These fixtures are anonymised copies of
 * files Final Draft wrote, still carrying everything a careless save loses,
 * and the guard below refuses any fixture that does not.
 */
describe('openFdx · files Final Draft wrote', () => {
	const fixture = (name: string) =>
		readFileSync(new URL(`../../../apple/eDraftEngine/Fixtures/${name}`, import.meta.url), 'utf8');
	const FILES = ['finaldraft-sample02.fdx', 'finaldraft-sample01.fdx'] as const;

	/** What a no-edit proof on a file depends on, counted. */
	const hazards = (xml: string) => {
		const elements = parseFdx(xml).script.elements;
		const runs = elements.flatMap((element) => element.runs ?? []);
		const count = (pattern: RegExp) => (xml.match(pattern) ?? []).length;
		const styled = (type: string, styles: string[]) =>
			elements.filter(
				(element) =>
					element.type === type &&
					(element.runs ?? []).some((run) => run.styles.some((style) => styles.includes(style)))
			).length;
		return {
			eDraftNamespace: xml.includes('xmlns:EDraft'),
			bareParagraphLines: count(/^\s*<Paragraph Type="[^"]+"><Text>/gm),
			taggedRuns: runs.filter((run) => (run.tagNumbers ?? []).length > 0).length,
			revisionRuns: runs.filter((run) => run.revisionID !== undefined).length,
			adornmentSplits: count(/<Text [^>]*AdornmentStyle="-1"/g),
			dualDialogue: count(/<DualDialogue>/g),
			omittedScenes: count(/<OmittedScene>/g),
			endOfAct: count(/<Paragraph [^>]*Type="End of Act"/g),
			emphasisedHeadings: styled('scene', ['Bold', 'Italic']),
			italicParentheticals: styled('parenthetical', ['Italic']),
			multiLineParagraphs: elements.filter((element) => element.text.includes('\n')).length,
			trailingSpaces: elements.filter((element) => element.text.endsWith(' ')).length,
			astral: elements.filter((element) => /[\uD800-\uDBFF]/.test(element.text)).length
		};
	};
	const REQUIRED: Record<(typeof FILES)[number], ReturnType<typeof hazards>> = {
		'finaldraft-sample02.fdx': {
			eDraftNamespace: false, bareParagraphLines: 0, taggedRuns: 394, revisionRuns: 98,
			adornmentSplits: 10, dualDialogue: 6, omittedScenes: 1, endOfAct: 1, emphasisedHeadings: 1,
			italicParentheticals: 2, multiLineParagraphs: 0, trailingSpaces: 9, astral: 0
		},
		'finaldraft-sample01.fdx': {
			eDraftNamespace: false, bareParagraphLines: 0, taggedRuns: 0, revisionRuns: 2,
			adornmentSplits: 3, dualDialogue: 6, omittedScenes: 0, endOfAct: 1, emphasisedHeadings: 1,
			italicParentheticals: 2, multiLineParagraphs: 1, trailingSpaces: 3, astral: 4
		}
	};
	/** Why a file cannot stand as a fidelity fixture — nothing, when it can. */
	const provenanceProblems = (xml: string, required: ReturnType<typeof hazards>): string[] => {
		const found = hazards(xml);
		const problems: string[] = [];
		if (found.eDraftNamespace || found.bareParagraphLines > 0) problems.push('carries eDraft save marks');
		for (const key of Object.keys(required) as (keyof typeof required)[]) {
			if (found[key] !== required[key]) problems.push(`${key}: ${found[key]}, needs ${required[key]}`);
		}
		return problems;
	};

	/** The file as the app's editor first holds it: its Fountain source… */
	const fountainSource = (xml: string): string => {
		const imported = parseFdx(xml).script;
		return serialiseFountain({
			...imported,
			elements: imported.elements.map((element) => ({
				...element,
				text: canonicalCasing(element.type as ElementType, element.text)
			}))
		});
	};
	/** …and that source read back. */
	const fountainReading = (xml: string): Screenplay => parseFountain(fountainSource(xml), { emphasis: 'runs' });
	const tags = (xml: string) => (xml.match(/TagNumber="/g) ?? []).length;
	/**
	 * Every byte outside one paragraph matches: the changed stretch holds no
	 * boundary between two of the script's paragraphs. Final Draft indents
	 * those four spaces; the paragraphs nested inside a scene heading's
	 * SceneProperties sit deeper, and are part of the paragraph they are in.
	 * (Retyping the whole numbered heading Fountain re-reads as Action retypes
	 * Fountain's `#2#` too — an edit that cannot be placed — so that paragraph
	 * is still rewritten whole, scene data and all.)
	 */
	const confinedToOneParagraph = (file: string, saved: string, marker: string) => {
		const before = withoutNoteRanges(file);
		const after = withoutNoteRanges(saved);
		const shorter = Math.min(before.length, after.length);
		let prefix = 0;
		while (prefix < shorter && before[prefix] === after[prefix]) prefix++;
		let suffix = 0;
		while (suffix < shorter - prefix && before[before.length - 1 - suffix] === after[after.length - 1 - suffix]) suffix++;
		const boundary = /<\/Paragraph>\s*\n {4}<Paragraph[ >]|\n {4}<Paragraph[ >][\s\S]*\n {4}<Paragraph[ >]/;
		expect(before.slice(prefix, before.length - suffix)).not.toMatch(boundary);
		expect(after.slice(prefix, after.length - suffix)).not.toMatch(boundary);
		expect(after.slice(Math.max(0, prefix - marker.length), after.length - suffix + marker.length)).toContain(marker);
	};

	it.each(FILES)('%s is a file Final Draft wrote, with everything the proofs depend on', (name) => {
		expect(provenanceProblems(fixture(name), REQUIRED[name])).toEqual([]);
	});

	it('the guard turns away a file eDraft has saved', () => {
		const problems = provenanceProblems(fixture('sample0-2.fdx'), REQUIRED['finaldraft-sample02.fdx']);
		expect(problems).toContain('carries eDraft save marks');
		expect(problems.some((problem) => problem.startsWith('taggedRuns'))).toBe(true);
	});

	it.each(FILES)('a save with no edit returns %s byte for byte', (name) => {
		const xml = fixture(name);
		const document = openFdx(xml);
		expect(document.rewrite(document.script).xml).toBe(xml);
	});

	it.each(FILES)('so does a save through Fountain with no edit, given the unedited reading (%s)', (name) => {
		const xml = fixture(name);
		const reading = fountainReading(xml);
		const saved = openFdx(xml).rewrite(reading, { unedited: reading });
		expect(saved.diagnostics).toEqual([]);
		expect(saved.xml).toBe(xml);
	});

	it('without the unedited reading, that same save loses the tags — the leak this closes', () => {
		const xml = fixture('finaldraft-sample02.fdx');
		const saved = openFdx(xml).rewrite(fountainReading(xml)).xml;
		expect(tags(saved)).toBeLessThan(tags(xml) / 2);
	});

	/* An edit through Fountain changes bytes only inside the edited paragraph —
	   across the script, and beside the omitted scene, the dual dialogue and
	   the End of Act. */
	it.each([0, 6, 19, 42, 150, 336, 520, 700, 760, 761])(
		'an edit through Fountain to element %i of sample02 changes bytes only inside that paragraph',
		(index) => {
			const xml = fixture('finaldraft-sample02.fdx');
			const reading = fountainReading(xml);
			const marker = `EDITED ${index}`;
			const edited = {
				...reading,
				elements: reading.elements.map((element, at) => (at === index ? { ...element, text: marker } : element))
			};
			confinedToOneParagraph(xml, openFdx(xml).rewrite(edited, { unedited: reading }).xml, marker);
		}
	);

	it.each([0, 21, 300, 823])('an edit through the engine to element %i of sample01 changes bytes only inside that paragraph', (index) => {
		const xml = fixture('finaldraft-sample01.fdx');
		const document = openFdx(xml);
		const marker = `EDITED ${index}`;
		const edited = {
			...document.script,
			elements: document.script.elements.map((element, at) => (at === index ? { ...element, text: marker } : element))
		};
		confinedToOneParagraph(xml, document.rewrite(edited).xml, marker);
	});

	it('a tagged paragraph beside an edited one keeps every tag', () => {
		const xml = fixture('finaldraft-sample02.fdx');
		const reading = fountainReading(xml);
		const imported = parseFdx(xml).script.elements;
		const taggedAt = imported.findIndex((element, at) => at > 0 && (element.runs ?? []).some((run) => run.tagNumbers?.length) && imported[at + 1]?.type === 'action');
		const edited = {
			...reading,
			elements: reading.elements.map((element, at) => (at === taggedAt + 1 ? { ...element, text: 'A new line.' } : element))
		};
		const saved = openFdx(xml).rewrite(edited, { unedited: reading }).xml;
		const lost = tags(xml) - tags(saved);
		const inEdited = ((imported[taggedAt + 1].runs ?? []).filter((run) => run.tagNumbers?.length)).length;
		expect(lost).toBeLessThanOrEqual(inEdited);
		expect(taggedAt).toBeGreaterThan(0);
	});

	it('reports the paragraphs an unedited reading cannot be paired with, and judges them as before', () => {
		const xml = fixture('finaldraft-sample01.fdx');
		const stranger = parseFountain('EXT. SOMEWHERE ELSE - NIGHT\n\nNothing like the file.\n', { emphasis: 'runs' });
		const saved = openFdx(xml).rewrite(stranger, { unedited: stranger });
		expect(saved.diagnostics.map((diagnostic) => diagnostic.code)).toContain('FDX_REWRITE_UNEDITED_UNALIGNED');
	});

	/* IL-0028: an edited paragraph is merged, not rewritten. Each edit is made
	   the way the app makes it — to the Fountain source, read back with its
	   emphasis — and each expected file is the original with only the writer's
	   characters changed. */
	/* IL-0033: a save keeps every ScriptNote on its words. Final Draft counts a
	   Range over the script as it stands; copied unchanged, one word typed near
	   the start moved ten of the eleven notes in sample02 off their words. */
	describe('ScriptNote Ranges through a save', () => {
		/** The words a note covers, as the import reads them. */
		const covered = (script: Screenplay, anchor: FdxScriptNote['anchor']) => {
			if (!anchor) return null;
			const { start, end } = anchor;
			const texts = script.elements.slice(start.element, end.element + 1).map((element) => element.text);
			if (texts.length === 1) return texts[0].slice(start.offset, end.offset);
			texts[0] = texts[0].slice(start.offset);
			texts[texts.length - 1] = texts[texts.length - 1].slice(0, end.offset);
			return texts.join('\n');
		};
		const notesBlock = (xml: string) => xml.slice(xml.indexOf('<ScriptNotes>'), xml.indexOf('</ScriptNotes>'));
		const typed = (at: number) => (elements: Screenplay['elements']) =>
			elements.map((element, index) => (index === at ? { ...element, text: element.text.replace(' ', ' QZQZ ') } : element));

		it.each(FILES)('after any edit to %s, every note the edit did not touch covers the same words', (name) => {
			const xml = fixture(name);
			const before = parseFdx(xml);
			const reading = fountainReading(xml);
			const noted = new Set(
				before.scriptNotes.flatMap(({ anchor }) =>
					anchor ? Array.from({ length: anchor.end.element - anchor.start.element + 1 }, (_, k) => anchor.start.element + k) : []
				)
			);
			// Lines the reading holds at the import's own index, with no note on them.
			const free = reading.elements.flatMap((element, index) =>
				element.text === before.script.elements[index]?.text && element.text.includes(' ') && !noted.has(index) && element.type === 'action' ? [index] : []
			);
			const spread = Array.from({ length: 6 }, (_, k) => free[Math.floor(((k + 1) * free.length) / 8)]);
			const dual = reading.elements.findIndex((element) => element.dual);
			const edits: [string, (elements: Screenplay['elements']) => Screenplay['elements']][] = [
				...spread.map((at): [string, (elements: Screenplay['elements']) => Screenplay['elements']] => [`a word typed in line ${at}`, typed(at)]),
				...spread.slice(0, 3).map((at): [string, (elements: Screenplay['elements']) => Screenplay['elements']] => [
					`a word deleted in line ${at}`,
					(elements) => elements.map((element, index) => (index === at ? { ...element, text: element.text.replace(/ \S+/, '') } : element))
				]),
				['a line added', (elements) => [...elements.slice(0, free[1]), { type: 'action', text: 'A new line.' }, ...elements.slice(free[1])]],
				['a line deleted', (elements) => [...elements.slice(0, free[1]), ...elements.slice(free[1] + 1)]],
				['a dual dialogue line edited', (elements) => elements.map((element, index) => (index === dual + 1 ? { ...element, text: `Q${element.text}` } : element))],
				['a dual dialogue dissolved', (elements) => elements.map((element, index) => (index === dual ? { type: element.type, text: element.text } : element))]
			];
			expect(edits.length).toBeGreaterThanOrEqual(12);
			for (const [label, change] of edits) {
				const saved = openFdx(xml).rewrite({ ...reading, elements: change(reading.elements) }, { unedited: reading });
				const after = parseFdx(saved.xml);
				const off = before.scriptNotes.filter((note, index) => covered(before.script, note.anchor) !== covered(after.script, after.scriptNotes[index].anchor));
				expect(off.map((note) => note.id), label).toEqual([]);
				expect(withoutNoteRanges(notesBlock(saved.xml)), label).toBe(withoutNoteRanges(notesBlock(xml)));
				expect(
					saved.diagnostics.filter((diagnostic) => !['FDX_REWRITE_SCRIPT_NOTE_RANGES_MOVED', 'FDX_REWRITE_DUAL_DIALOGUE_DISSOLVED'].includes(diagnostic.code)),
					label
				).toEqual([]);
			}
		});

		it('an edit inside a note’s words stays inside the note', () => {
			const xml = fixture('finaldraft-sample02.fdx');
			const reading = fountainReading(xml);
			const saved = openFdx(xml).rewrite(
				{ ...reading, elements: reading.elements.map((element, index) => (index === 310 ? { ...element, text: element.text.replace(' ', ' INSIDE ') } : element)) },
				{ unedited: reading }
			);
			const after = parseFdx(saved.xml);
			const note = after.scriptNotes.find((candidate) => candidate.id === '109');
			expect(covered(after.script, note?.anchor)).toBe(after.script.elements[310].text);
			expect(after.script.elements[310].text).toContain('INSIDE');
		});

		it('a note whose words are all deleted closes to zero length where they stood, and says so', () => {
			const xml = fixture('finaldraft-sample02.fdx');
			const reading = fountainReading(xml);
			// Note 108 covers the line of dialogue at 53; its cue is 52.
			expect(covered(parseFdx(xml).script, parseFdx(xml).scriptNotes.find((note) => note.id === '108')?.anchor)).toBe(reading.elements[53].text);
			const saved = openFdx(xml).rewrite({ ...reading, elements: [...reading.elements.slice(0, 52), ...reading.elements.slice(54)] }, { unedited: reading });
			const note = parseFdx(saved.xml).scriptNotes.find((candidate) => candidate.id === '108');
			expect(note?.range).toEqual({ start: 2177, end: 2177 });
			expect(note?.anchor).toEqual({ start: { element: 52, offset: 0 }, end: { element: 52, offset: 0 } });
			expect(saved.diagnostics.map((diagnostic) => diagnostic.code)).toContain('FDX_REWRITE_SCRIPT_NOTE_WORDS_DELETED');
			expect(saved.warnings.some((warning) => warning.includes('lost all their words'))).toBe(true);
			expect(saved.warnings.some((warning) => warning.includes('were moved'))).toBe(false);
		});

		it('keeps a note’s edges: typed at an edge stays out, typed inside joins, written end first stays so, stale stays stale', () => {
			const lab = (lines: string[], ranges: string[]) =>
				`<FinalDraft><Content>\n${lines.map((line) => `<Paragraph Type="Action"><Text>${line}</Text></Paragraph>`).join('\n')}\n</Content><ScriptNotes>${ranges
					.map((range, index) => `<ScriptNote Id="${index + 1}" Range="${range}"><Paragraph><Text>n</Text></Paragraph></ScriptNote>`)
					.join('')}</ScriptNotes></FinalDraft>`;
			// Paragraphs start at 0, 9 and 21; the script ends at 30.
			const xml = lab(['One two.', 'Three four.', 'Five six.'], ['0,3', '9,14', '19,15', '30,30', '99,120']);
			const document = openFdx(xml);
			const edited = (texts: string[]) => ({ ...document.script, elements: texts.map((text) => ({ type: 'action' as const, text })) });
			expect(document.rewrite(edited(['One and two.', 'Thrxee four.', 'Five six.'])).xml).toBe(
				lab(['One and two.', 'Thrxee four.', 'Five six.'], ['0,3', '13,19', '24,20', '35,35', '99,120'])
			);
			const gone = document.rewrite(edited(['One two.', 'Five six.']));
			expect(gone.xml).toBe(lab(['One two.', 'Five six.'], ['0,3', '9,9', '9,9', '18,18', '99,120']));
			expect(gone.diagnostics.find((diagnostic) => diagnostic.code === 'FDX_REWRITE_SCRIPT_NOTE_WORDS_DELETED')?.count).toBe(2);
		});
	});

	/* IL-0032: Final Draft keeps dual dialogue as a paragraph with no text of
	   its own holding a <DualDialogue>, its paragraphs the two speeches. Read
	   as metadata, all 48 lines in these two files were invisible. */
	describe('dual dialogue', () => {
		/** Each dual dialogue in the file: where its paragraph sits (from the
		    line break before it), and its lines' paragraphs. */
		const blocksOf = (xml: string) =>
			[...xml.matchAll(/\n {4}<Paragraph [^>]*>\n {6}<DualDialogue>[\s\S]*?<\/DualDialogue>\n {4}<\/Paragraph>/g)].map((match) => ({
				start: match.index,
				end: match.index + match[0].length,
				lines: [...match[0].matchAll(/\n {8}(<Paragraph Type="([^"]+)"[^>]*>[\s\S]*?\n {8}<\/Paragraph>)/g)].map((line) => ({
					bytes: line[1],
					type: line[2].toLowerCase(),
					text: [...line[1].matchAll(/<Text[^>]*>([^<]*)<\/Text>/g)].map((run) => decodeXmlEntities(run[1])).join('')
				}))
			}));

		it.each(FILES)('every line of every dual dialogue in %s is in the script, the second cue dual', (name) => {
			const xml = fixture(name);
			const { script, diagnostics } = parseFdx(xml);
			const blocks = blocksOf(xml);
			expect(blocks).toHaveLength(6);
			expect(diagnostics).toEqual([]);
			expect(script.elements.filter((element) => element.type === 'general' && element.text === '')).toEqual([]);
			const dualCues = script.elements.flatMap((element, index) => (element.dual ? [index] : []));
			expect(dualCues).toHaveLength(6);
			blocks.forEach((block, at) => {
				const first = dualCues[at] - 2;
				const lines = script.elements.slice(first, first + block.lines.length);
				expect(lines.map((line) => [line.type, line.text])).toEqual(block.lines.map((line) => [line.type, line.text]));
				expect(lines.map((line) => line.dual ?? false)).toEqual([false, false, true, false]);
			});
		});

		it.each(FILES)('a typo in any dual dialogue line of %s changes that one character, inside its block', (name) => {
			const xml = fixture(name);
			const reading = fountainReading(xml);
			const dualCues = reading.elements.flatMap((element, index) => (element.dual ? [index] : []));
			expect(dualCues).toHaveLength(6);
			for (const cue of dualCues) {
				for (const line of [cue - 2, cue - 1, cue, cue + 1]) {
					const edited = {
						...reading,
						elements: reading.elements.map((element, index) =>
							index === line ? { ...element, text: `Q${element.text.slice(1)}` } : element
						)
					};
					const saved = openFdx(xml).rewrite(edited, { unedited: reading });
					let at = 0;
					while (xml[at] === saved.xml[at]) at++;
					expect(saved.diagnostics).toEqual([]);
					expect(saved.xml).toBe(`${xml.slice(0, at)}Q${xml.slice(at + 1)}`);
					expect(blocksOf(xml).some((block) => block.start < at && at < block.end)).toBe(true);
				}
			}
		});

		const firstBlockSaved = (find: string, replace: string) => {
			const xml = fixture('finaldraft-sample02.fdx');
			const source = fountainSource(xml);
			expect(source.split(find)).toHaveLength(2);
			const saved = openFdx(xml).rewrite(parseFountain(source.replace(find, () => replace), { emphasis: 'runs' }), {
				unedited: parseFountain(source, { emphasis: 'runs' })
			});
			return { xml, saved, block: blocksOf(xml)[0] };
		};
		const PAIR = '\nXXXXX\nXxx?\n\nXXXXXX ^\nXxx.\n';

		it('lines added to the second speaker are written inside the block', () => {
			const { xml, saved, block } = firstBlockSaved(PAIR, `${PAIR}(xxxxx)\nXxx xxx.\n`);
			const closing = block.end - '\n      </DualDialogue>\n    </Paragraph>'.length;
			expect(saved.diagnostics).toEqual([]);
			expect(saved.xml).toBe(
				`${xml.slice(0, closing)}\n        <Paragraph Type="Parenthetical"><Text>(xxxxx)</Text></Paragraph>\n        <Paragraph Type="Dialogue"><Text>Xxx xxx.</Text></Paragraph>${xml.slice(closing)}`
			);
		});

		it('deleting the whole pair removes its paragraph and nothing else', () => {
			const { xml, saved, block } = firstBlockSaved(PAIR, '\n');
			expect(saved.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['FDX_REWRITE_SCRIPT_NOTE_RANGES_MOVED']);
			expect(withoutNoteRanges(saved.xml)).toBe(withoutNoteRanges(xml.slice(0, block.start) + xml.slice(block.end)));
		});

		it('a pair the writer un-duals is dissolved in place — each line keeping its own bytes — and reported', () => {
			const { xml, saved, block } = firstBlockSaved(PAIR, PAIR.replace(' ^', ''));
			expect(saved.diagnostics.map((diagnostic) => diagnostic.code)).toEqual([
				'FDX_REWRITE_DUAL_DIALOGUE_DISSOLVED',
				'FDX_REWRITE_SCRIPT_NOTE_RANGES_MOVED'
			]);
			expect(withoutNoteRanges(saved.xml)).toBe(
				withoutNoteRanges(xml.slice(0, block.start) + block.lines.map((line) => `\n    ${line.bytes}`).join('') + xml.slice(block.end))
			);
		});

		it('an edit through the engine alone lands inside the block too', () => {
			const xml = fixture('finaldraft-sample01.fdx');
			const document = openFdx(xml);
			const cue = document.script.elements.findIndex((element) => element.dual);
			const saved = document.rewrite({
				...document.script,
				elements: document.script.elements.map((element, index) => (index === cue + 1 ? { ...element, text: `Q${element.text.slice(1)}` } : element))
			});
			let at = 0;
			while (xml[at] === saved.xml[at]) at++;
			expect(saved.xml).toBe(`${xml.slice(0, at)}Q${xml.slice(at + 1)}`);
			expect(blocksOf(xml)[0].start).toBeLessThan(at);
			expect(at).toBeLessThan(blocksOf(xml)[0].end);
		});

		it('reads each line of a dual dialogue exactly as a body paragraph — a parenthetical, a tag — the second cue dual', () => {
			const { script, diagnostics } = parseFdx(
				'<FinalDraft><Content><Paragraph Type="Action"><Text>Hum.</Text></Paragraph><Paragraph Type="General"><DualDialogue><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Yes.</Text></Paragraph><Paragraph Type="Character"><Text TagNumber="4">JON</Text></Paragraph><Paragraph Type="Parenthetical"><Text>(beat)</Text></Paragraph><Paragraph Type="Dialogue"><Text>No.</Text></Paragraph></DualDialogue></Paragraph><Paragraph Type="Action"><Text>Go.</Text></Paragraph></Content></FinalDraft>'
			);
			expect(diagnostics).toEqual([]);
			expect(script.elements).toEqual([
				{ type: 'action', text: 'Hum.' },
				{ type: 'character', text: 'MARA' },
				{ type: 'dialogue', text: 'Yes.' },
				{ type: 'character', text: 'JON', runs: [{ start: 0, end: 3, styles: [], tagNumbers: [4] }], dual: true },
				{ type: 'parenthetical', text: '(beat)' },
				{ type: 'dialogue', text: 'No.' },
				{ type: 'action', text: 'Go.' }
			]);
		});

		it('dual dialogue in any other form is read as before, and reported', () => {
			const block = '<DualDialogue><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Yes.</Text></Paragraph><Paragraph Type="Character"><Text>JON</Text></Paragraph><Paragraph Type="Dialogue"><Text>No.</Text></Paragraph></DualDialogue>';
			const { script, diagnostics } = parseFdx(
				`<FinalDraft><Content><Paragraph Type="General"><Text>Look:</Text>${block}</Paragraph><Paragraph Type="General">${block}${block}</Paragraph></Content></FinalDraft>`
			);
			expect(script.elements).toEqual([
				{ type: 'general', text: 'Look:' },
				{ type: 'general', text: '' }
			]);
			expect(diagnostics.map((diagnostic) => [diagnostic.code, diagnostic.paragraphIndex])).toEqual([
				['FDX_DUAL_DIALOGUE_NOT_READ', 0],
				['FDX_DUAL_DIALOGUE_NOT_READ', 1]
			]);
		});
	});

	describe('an edited paragraph keeps everything the writer did not touch', () => {
		/** The save of `xml` after the app's source had `find` (once) replaced. */
		const savedAfter = (xml: string, find: string, replace: string) => {
			const source = fountainSource(xml);
			expect(source.split(find)).toHaveLength(2);
			const edited = parseFountain(source.replace(find, () => replace), { emphasis: 'runs' });
			return openFdx(xml).rewrite(edited, { unedited: parseFountain(source, { emphasis: 'runs' }) });
		};
		/** The file with its one `before` replaced. */
		const fileWith = (xml: string, before: string, after: string) => {
			expect(xml.split(before)).toHaveLength(2);
			return xml.replace(before, () => after);
		};

		it.each([
			[
				'E1 a typo in a tagged action line: one run changes; its 10 neighbours, 5 tags and revision mark stand',
				'finaldraft-sample02.fdx',
				['Xxxx XXXXXX, 12,', 'Xyxx XXXXXX, 12,'],
				['31a77a253272">\n      <Text>Xxxx </Text>', '31a77a253272">\n      <Text>Xyxx </Text>']
			],
			[
				'E2 the emphasised numbered heading Fountain reads as Action: a Scene Heading still, scene data and 7 tags kept, no #2# written',
				'finaldraft-sample02.fdx',
				['***(X1)*** #2#', '***(X2)*** #2#'],
				['TagNumber="603">(X1)</Text>', 'TagNumber="603">(X2)</Text>']
			],
			[
				'E3 an italic parenthetical: the italic run grows, the plain brackets stand',
				'finaldraft-sample02.fdx',
				['(*xx. xxxxx, xxx*)', '(*xx. xxxxx, xxx, xxxxx*)'],
				['<Text Style="Italic">xx. xxxxx, xxx</Text>', '<Text Style="Italic">xx. xxxxx, xxx, xxxxx</Text>']
			],
			[
				'E3b the italic (beat) Fountain reads as Dialogue: still a Parenthetical',
				'finaldraft-sample02.fdx',
				['*...Xxx xxxxxxxx.*\n*(beat)*', '*...Xxx xxxxxxxx.*\n*(beat, xxxxx)*'],
				['<Text Style="Italic">(beat)</Text>', '<Text Style="Italic">(beat, xxxxx)</Text>']
			],
			[
				'E4 the second line of a two-line Summary: one Summary still, its line break kept',
				'finaldraft-sample01.fdx',
				['\nX & X xxxx xxxx xxxxxxxx.\n', '\nX & X yxxx xxxx xxxxxxxx.\n'],
				['xxxxx:\nX &amp; X xxxx xxxx xxxxxxxx.</Text>', 'xxxxx:\nX &amp; X yxxx xxxx xxxxxxxx.</Text>']
			],
			[
				'E5 early in a line that ends in a space: the space is kept',
				'finaldraft-sample01.fdx',
				['Xx xxx. Xxx... ', 'Yx xxx. Xxx... '],
				['<Text>Xx xxx. Xxx... </Text>', '<Text>Yx xxx. Xxx... </Text>']
			],
			[
				'E6 beside an AllCaps word: its stored letters, style and tag stand',
				'finaldraft-sample02.fdx',
				['XXXXXX xxxxx xxx xxxxx xxx xxxxxxx xxxxxx.', 'XXXXXX yxxxx xxx xxxxx xxx xxxxxxx xxxxxx.'],
				['<Text>xxxxx xxx </Text>', '<Text>yxxxx xxx </Text>']
			],
			[
				'E7 a plain scene heading: its 5 tags and the stored casing stand',
				'finaldraft-sample02.fdx',
				['(D2) #4#', '(D3) #4#'],
				['<Text TagNumber="617">(d2)</Text>', '<Text TagNumber="617">(d3)</Text>']
			]
		] as const)('%s', (_, name, [find, replace], [before, after]) => {
			const xml = fixture(name);
			const saved = savedAfter(xml, find, replace);
			expect(saved.diagnostics.filter((diagnostic) => diagnostic.code !== 'FDX_REWRITE_SCRIPT_NOTE_RANGES_MOVED')).toEqual([]);
			expect(withoutNoteRanges(saved.xml)).toBe(withoutNoteRanges(fileWith(xml, before, after)));
		});

		it.each(FILES)('an edit anywhere in %s changes bytes only inside the runs it falls in', (name) => {
			const xml = fixture(name);
			const source = fountainSource(xml);
			const reading = parseFountain(source, { emphasis: 'runs' });
			const runs = [...xml.matchAll(/\s*<Text\b[^>]*?(?:\/>|>[^<]*<\/Text>)/g)].map((match) => ({
				start: match.index,
				end: match.index + match[0].length
			}));
			const between = [...source.matchAll(/(?<=[xX])(?=[xX])/g)].map((match) => match.index);
			let proven = 0;
			for (let at = 0; at < between.length; at += Math.floor(between.length / 16)) {
				const position = between[at];
				const typed = source[position] === 'X' ? 'QZ' : 'qz';
				const edited = parseFountain(source.slice(0, position) + typed + source.slice(position), { emphasis: 'runs' });
				const changed = edited.elements.filter((element, index) => element.text !== reading.elements[index]?.text);
				if (edited.elements.length !== reading.elements.length || changed.length !== 1) continue;
				if (edited.elements.some((element, index) => element.type !== reading.elements[index].type)) continue;

				const written = openFdx(xml).rewrite(edited, { unedited: reading });
				// Range values set aside, which their notes' words are proven by; a Range value holds no run.
				const saved = { ...written, xml: withoutNoteRanges(written.xml) };
				const file = withoutNoteRanges(xml);
				let prefix = 0;
				while (prefix < file.length && file[prefix] === saved.xml[prefix]) prefix++;
				let suffix = 0;
				while (suffix < file.length - prefix && file[file.length - 1 - suffix] === saved.xml[saved.xml.length - 1 - suffix]) suffix++;
				const from = prefix;
				const to = Math.max(file.length - suffix, prefix + 1);
				const touched = runs.filter((run) => run.start < to && run.end > from);
				expect(saved.diagnostics.filter((diagnostic) => diagnostic.code !== 'FDX_REWRITE_SCRIPT_NOTE_RANGES_MOVED')).toEqual([]);
				expect(touched.length).toBeGreaterThanOrEqual(1);
				expect(touched.length).toBeLessThanOrEqual(2);
				if (touched.length === 2) expect(touched[1].start).toBe(touched[0].end);
				expect(saved.xml.slice(prefix, saved.xml.length - suffix)).toContain(typed);
				expect(tags(saved.xml)).toBeGreaterThanOrEqual(tags(xml));
				proven += 1;
			}
			expect(proven).toBeGreaterThanOrEqual(10);
		});

		const lab = (paragraphs: string) => `<FinalDraft><Content>\n${paragraphs}\n</Content></FinalDraft>`;
		const labSaved = (xml: string, find: string, replace: string) => {
			const source = fountainSource(xml);
			expect(source.split(find)).toHaveLength(2);
			return openFdx(xml).rewrite(parseFountain(source.replace(find, () => replace), { emphasis: 'runs' }), {
				unedited: parseFountain(source, { emphasis: 'runs' })
			});
		};

		it("typed text takes its run's tags, font, adornment and AllCaps — never its revision mark", () => {
			const xml = lab(
				'<Paragraph Type="Action"><Text AdornmentStyle="-1" Font="Courier Prime" RevisionID="3" Style="AllCaps" TagNumber="12">she waits</Text><Text>.</Text></Paragraph>'
			);
			expect(labSaved(xml, 'SHE WAITS.', 'SHE STILL WAITS.').xml).toBe(
				lab(
					'<Paragraph Type="Action"><Text AdornmentStyle="-1" Font="Courier Prime" RevisionID="3" Style="AllCaps" TagNumber="12">she </Text><Text AdornmentStyle="-1" Font="Courier Prime" Style="AllCaps" TagNumber="12">STILL </Text><Text AdornmentStyle="-1" Font="Courier Prime" RevisionID="3" Style="AllCaps" TagNumber="12">waits</Text><Text>.</Text></Paragraph>'
				)
			);
		});

		it('emphasis the writer adds is applied to the file’s own run, which keeps its tag', () => {
			const xml = lab('<Paragraph Type="Action"><Text TagNumber="7">He runs home.</Text></Paragraph>');
			expect(labSaved(xml, 'He runs home.', 'He *runs* home.').xml).toBe(
				lab(
					'<Paragraph Type="Action"><Text TagNumber="7">He </Text><Text Style="Italic" TagNumber="7">runs</Text><Text TagNumber="7"> home.</Text></Paragraph>'
				)
			);
		});

		it('a paragraph whose kind the writer changed is retyped, its runs and attributes kept', () => {
			const xml = lab(
				'<Paragraph Type="Scene Heading"><Text TagNumber="1">INT. LAB - DAY</Text></Paragraph>\n<Paragraph Alignment="Left" Type="Action"><Text TagNumber="2">SHE WAITS</Text></Paragraph>'
			);
			expect(labSaved(xml, '!SHE WAITS', '> SHE WAITS').xml).toBe(
				lab(
					'<Paragraph Type="Scene Heading"><Text TagNumber="1">INT. LAB - DAY</Text></Paragraph>\n<Paragraph Alignment="Left" Type="Transition"><Text TagNumber="2">SHE WAITS</Text></Paragraph>'
				)
			);
		});

		it('a split paragraph with one line edited stays one paragraph, its line break and tag kept', () => {
			const xml = lab('<Paragraph Type="Action"><Text TagNumber="3">Lands her point:\nThey must work together.</Text></Paragraph>');
			expect(labSaved(xml, 'They must work together.', 'They must work as one.').xml).toBe(
				lab('<Paragraph Type="Action"><Text TagNumber="3">Lands her point:\nThey must work as one.</Text></Paragraph>')
			);
		});

		it('a character outside the BMP retyped in a marked run is typed whole, without the mark', () => {
			const xml = lab('<Paragraph Type="Action"><Text RevisionID="1">Key 🔑.</Text></Paragraph>');
			expect(labSaved(xml, 'Key 🔑.', 'Key 🔒.').xml).toBe(
				lab('<Paragraph Type="Action"><Text RevisionID="1">Key </Text><Text>🔒</Text><Text RevisionID="1">.</Text></Paragraph>')
			);
		});

		it('an edit only to what Fountain added is not guessed: that paragraph takes the old path and is reported', () => {
			const xml = lab(
				'<Paragraph Number="2" Type="Scene Heading"><Text Style="Bold+Italic" TagNumber="601">INT. KITCHEN - NIGHT</Text></Paragraph>\n<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>'
			);
			const saved = labSaved(xml, '#2#', '#3#');
			expect(saved.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['FDX_REWRITE_EDIT_UNPLACED']);
			expect(saved.xml).toContain('<Paragraph Type="Action"><Text Style="Bold+Italic">INT. KITCHEN - NIGHT</Text><Text> #3#</Text></Paragraph>');
			expect(saved.xml).toContain('<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>');
		});
	});
});

describe('openFdx · a Note paragraph that ends in ] (IL-0038)', () => {
	/* ScreenplayFile.open carries an .fdx through Fountain, so a Note ending in
	   `]` went to the editor as `]]]` and came back cut short, with a stray `]`
	   Action paragraph that the next save — edited or not — wrote into the
	   Final Draft file. */
	const file = (note: string) => `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft DocumentType="Script" Template="No" Version="5">
  <Content>
    <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
    <Paragraph Type="Note"><Text>${note}</Text></Paragraph>
    <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
  </Content>
</FinalDraft>`;
	/** The app's path: shouted into Fountain, read back with runs. */
	const reading = (xml: string): Screenplay => {
		const imported = parseFdx(xml).script;
		return parseFountain(
			serialiseFountain({
				...imported,
				elements: imported.elements.map((element) => ({
					...element,
					text: canonicalCasing(element.type as ElementType, element.text)
				}))
			}),
			{ emphasis: 'runs' }
		);
	};
	const NOTES = ['Dana: see [scene 4]', 'see [[4]] later', '[eDraft thread:t4k9qz status:open]'];

	it.each(NOTES)('a save with no edit returns the file byte for byte: %s', (note) => {
		const xml = file(note);
		const unedited = reading(xml);
		expect(openFdx(xml).rewrite(unedited, { unedited }).xml).toBe(xml);
	});

	it.each(NOTES)('an edit elsewhere leaves the note alone and adds no paragraph: %s', (note) => {
		const xml = file(note);
		const unedited = reading(xml);
		const edited = {
			...unedited,
			elements: unedited.elements.map((element) =>
				element.text === 'The kettle screams.' ? { ...element, text: 'The kettle screams again.' } : element
			)
		};
		const saved = openFdx(xml).rewrite(edited, { unedited }).xml;
		expect(saved).toBe(xml.replace('The kettle screams.', 'The kettle screams again.'));
	});
});

describe('openFdx · a note added inside a dialogue block (IL-0040)', () => {
	/* The editor puts a note in front of the line it is about, and hands the
	   save its Fountain. A note on a speech line broke the block in that
	   Fountain, and the save wrote the cue and the speech back as Action. */
	const xml = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft DocumentType="Script" Template="No" Version="5">
  <Content>
    <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
    <Paragraph Type="Character"><Text>BOB</Text></Paragraph>
    <Paragraph Type="Parenthetical"><Text>(beat)</Text></Paragraph>
    <Paragraph Type="Dialogue"><Text>Hello.</Text></Paragraph>
    <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
  </Content>
</FinalDraft>`;
	/** The app's path: shouted into Fountain, read back with runs. */
	const throughFountain = (script: Screenplay): Screenplay =>
		parseFountain(
			serialiseFountain({
				...script,
				elements: script.elements.map((element) => ({
					...element,
					text: canonicalCasing(element.type as ElementType, element.text)
				}))
			}),
			{ emphasis: 'runs' }
		);

	it.each(['Dialogue', 'Parenthetical'])('a note left on the %s line keeps every line of the block as it was', (kind) => {
		const unedited = throughFountain(parseFdx(xml).script);
		const at = unedited.elements.findIndex((element) => element.type === kind.toLowerCase());
		const withNote: Screenplay = {
			...unedited,
			elements: [...unedited.elements.slice(0, at), { type: 'note', text: 'Too flat?' }, ...unedited.elements.slice(at)]
		};
		const saved = openFdx(xml).rewrite(throughFountain(withNote), { unedited }).xml;
		for (const line of [
			'<Paragraph Type="Character"><Text>BOB</Text></Paragraph>',
			'<Paragraph Type="Parenthetical"><Text>(beat)</Text></Paragraph>',
			'<Paragraph Type="Dialogue"><Text>Hello.</Text></Paragraph>'
		]) {
			expect(saved).toContain(line);
		}
		expect(saved).not.toMatch(/Type="Action"><Text>(BOB|\(beat\)|Hello\.)</);
	});
});
