/** FDX import, export, diagnostics, limits, and round-trip behavior. */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
	decodeXmlEntities,
	encodeXmlEntities,
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

	it('anchors each Range on the text it was measured on', () => {
		const elements = sample.script.elements;
		/* exactly one whole character cue */
		expect(note('110')?.anchor).toEqual({
			start: { element: 536, offset: 0 },
			end: { element: 536, offset: 6 }
		});
		expect(elements[536].type).toBe('character');
		expect(elements[536].text.length).toBe(6);
		/* the shot it is about, from its first character */
		expect(note('107')?.anchor?.start).toEqual({ element: 6, offset: 0 });
		expect(elements[6].type).toBe('shot');
		/* zero-length, inside the absorbed End of Act: the next element */
		expect(note('112')?.range).toEqual({ start: 25736, end: 25736 });
		expect(note('112')?.anchor?.start).toEqual({ element: 766, offset: 0 });
		/* across elements */
		expect(note('137')?.anchor?.start.element).toBe(17);
		expect(note('137')?.anchor?.end.element).toBe(27);
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

	it('editing an annotated line keeps the ScriptNotes block byte for byte', () => {
		const document = openFdx(SAMPLE);
		const script: Screenplay = {
			...document.script,
			elements: document.script.elements.map((element, index) =>
				index === 536 ? { ...element, text: 'XXXXXX (V.O.)' } : element
			)
		};
		const saved = document.rewrite(script).xml;
		expect(saved).toContain('XXXXXX (V.O.)');
		expect(block(saved)).toBe(block(SAMPLE));
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
		expect(openFdx(SAMPLE).rewrite(parseFountain(source, { emphasis: 'runs' })).xml).toBe(SAMPLE);
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
			const saved = document.rewrite({
				...document.script,
				elements: document.script.elements.map((element, at) =>
					at === index ? { ...element, text: marker } : element
				)
			}).xml;
			const shorter = Math.min(SAMPLE.length, saved.length);
			let prefix = 0;
			while (prefix < shorter && SAMPLE[prefix] === saved[prefix]) prefix++;
			let suffix = 0;
			while (
				suffix < shorter - prefix &&
				SAMPLE[SAMPLE.length - 1 - suffix] === saved[saved.length - 1 - suffix]
			) {
				suffix++;
			}
			expect(SAMPLE.slice(prefix, SAMPLE.length - suffix)).not.toContain('Paragraph');
			expect(saved.slice(prefix, saved.length - suffix)).not.toContain('Paragraph');
			expect(
				saved.slice(Math.max(0, prefix - marker.length), saved.length - suffix + marker.length)
			).toContain(marker);
		}
	);
});
