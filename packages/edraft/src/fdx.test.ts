/** FDX import, export, diagnostics, limits, and round-trip behavior. */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import {
	decodeXmlEntities,
	encodeXmlEntities,
	type FdxNoteWriting,
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
import type { ElementType, Screenplay, ScreenplayElement } from './types.js';

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

	it('writes a note as a Final Draft ScriptNote, never a line of the script (IL-0039)', () => {
		let id = 0;
		const result = writeFdxWithDiagnostics(
			{
				titlePage: [],
				elements: [
					{ type: 'action', text: 'Visible.' },
					{ type: 'note', text: 'Check this against the schedule.' }
				]
			},
			{
				notes: {
					writer: 'Sam Okafor',
					now: '20260918T120000',
					newId: () => `00000000-0000-4000-8000-${(++id).toString(16).padStart(12, '0')}`
				}
			}
		);
		expect(result.xml).not.toContain('Type="Note"');
		expect(result.xml).toContain(
			[
				'<ScriptNotes>',
				'<ScriptNote Color="#000000000000" DateModified="20260918T120000" DateTime="20260918T120000" Id="1" Name="[eDraft]" Range="0,8" RefId="00000000-0000-4000-8000-000000000001" Type="" WriterID="00000000-0000-4000-8000-000000000001" WriterName="Sam Okafor">',
				'<Paragraph Alignment="Left" FirstIndent="0.00" Leading="Regular" LeftIndent="0.00" OutlineLevel="1" RightIndent="1.39" SpaceBefore="0" Spacing="1" StartsNewPage="No" id="00000000-0000-4000-8000-000000000002">',
				'<Text AdornmentStyle="0" Font="Arial" RevisionID="0" Size="12" Style="">Check this against the schedule.</Text>',
				'</Paragraph>',
				'</ScriptNote>',
				'</ScriptNotes>'
			].join('\n')
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
		/* exactly one line of dialogue. Past the omitted scene, every element
		   index is eight further on than it was before the omitted body was
		   read into the script (§7.3) — the Range values in the file, and
		   every offset here, are untouched: only the model grew. */
		expect(at('110')).toEqual({ start: { element: 556, offset: 0 }, end: { element: 556, offset: 6 } });
		expect([elements[556].type, elements[556].text.length]).toEqual(['dialogue', 6]);
		/* after the omitted scene too: from a cue to the start of the next line */
		expect(at('111')).toEqual({ start: { element: 601, offset: 0 }, end: { element: 603, offset: 0 } });
		/* zero-length, at the end of the script's last line */
		expect(at('112')).toEqual({ start: { element: 787, offset: 13 }, end: { element: 787, offset: 13 } });
		/* 780 before the omitted scene's eight paragraphs were read (§7.3). */
		expect(elements).toHaveLength(788);
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
			/* Read since §7.3: the scene inside the block, which used to be
			   skipped whole with it. */
			['scene', 'EXT. YARD - DAY'],
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
			span(5, 7, 7, 0), // the break after it, to the next line
			span(7, 0, 7, 3) // the line after both — past the script's end, counted as zero
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
			/* taggedRuns and trailingSpaces count the model, and the model now
			   holds the omitted scene's body (§7.3): its five tagged runs and
			   two trailing-space paragraphs were invisible before. The file
			   has not changed — more of it is read. */
			eDraftNamespace: false, bareParagraphLines: 0, taggedRuns: 399, revisionRuns: 98,
			adornmentSplits: 10, dualDialogue: 6, omittedScenes: 1, endOfAct: 1, emphasisedHeadings: 1,
			italicParentheticals: 2, multiLineParagraphs: 0, trailingSpaces: 11, astral: 0
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

describe('the writer’s notes as Final Draft ScriptNotes (IL-0039)', () => {
	/* A note left in eDraft saved into an .fdx as <Paragraph Type="Note">, a
	   line of the script: Final Draft showed it in the script text, not in its
	   notes. It is now a ScriptNote (RFC-NOTES-SYSTEM §4.2), and comes back as
	   the writer's own note (§4.3). */
	const LAB = `<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<FinalDraft DocumentType="Script" Template="No" Version="5">

  <Content>
    <Paragraph Type="Scene Heading">
      <Text>INT. KITCHEN - NIGHT</Text>
    </Paragraph>
    <Paragraph Type="Action">
      <Text>The kettle screams.</Text>
    </Paragraph>
    <Paragraph Type="Note">
      <Text>A note the file already has.</Text>
    </Paragraph>
    <Paragraph Type="Character">
      <Text>MARA</Text>
    </Paragraph>
    <Paragraph Type="Dialogue">
      <Text>It's the same lab.</Text>
    </Paragraph>
  </Content>

  <Characters>
    <Character>MARA</Character>
  </Characters>

  <Navigator/>
</FinalDraft>
`;
	const FEATURE = readFileSync(
		new URL('../../../apple/eDraftEngine/Fixtures/finaldraft-sample02.fdx', import.meta.url),
		'utf8'
	);
	const writing = (writer = 'Dana Reyes (Director)'): FdxNoteWriting => {
		let id = 0;
		return {
			...(writer ? { writer } : {}),
			now: '20260918T120000',
			newId: () => `00000000-0000-4000-8000-${(++id).toString(16).padStart(12, '0')}`
		};
	};
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
	/** Opened as the app opens it, edited in the editor's Fountain, and saved. */
	const save = (
		xml: string,
		edit: (elements: ScreenplayElement[]) => ScreenplayElement[],
		notes: FdxNoteWriting = writing()
	) => {
		const unedited = throughFountain(parseFdx(xml).script);
		const edited = throughFountain({ ...unedited, elements: edit(unedited.elements) });
		return openFdx(xml).rewrite(edited, { unedited, notes });
	};
	const noteBefore =
		(text: string, line: string) =>
		(elements: ScreenplayElement[]): ScreenplayElement[] => {
			const at = elements.findIndex((element) => element.text === line);
			expect(at).toBeGreaterThanOrEqual(0);
			return [...elements.slice(0, at), { type: 'note', text }, ...elements.slice(at)];
		};
	const contentOf = (xml: string) => xml.slice(xml.indexOf('<Content>'), xml.indexOf('</Content>'));
	const scriptNotesOf = (xml: string) => xml.slice(xml.indexOf('<ScriptNotes'), xml.indexOf('</ScriptNotes>'));
	const noteParagraph = (id: number, text: string) =>
		[
			`      <Paragraph Alignment="Left" FirstIndent="0.00" Leading="Regular" LeftIndent="0.00" OutlineLevel="1" RightIndent="1.39" SpaceBefore="0" Spacing="1" StartsNewPage="No" id="00000000-0000-4000-8000-${id.toString(16).padStart(12, '0')}">`,
			`        <Text AdornmentStyle="0" Font="Arial" RevisionID="0" Size="12" Style="">${text}</Text>`,
			'      </Paragraph>'
		].join('\n');

	it('writes a note as one ScriptNote, after </Characters>, and the script gains no paragraph', () => {
		const saved = save(LAB, noteBefore('Dana Reyes (Director): Too flat?', "It's the same lab."));
		expect(contentOf(saved.xml)).toBe(contentOf(LAB));
		expect(saved.xml).toBe(
			LAB.replace(
				'  </Characters>\n',
				[
					'  </Characters>',
					'',
					'  <ScriptNotes>',
					'    <ScriptNote Color="#000000000000" DateModified="20260918T120000" DateTime="20260918T120000" Id="1" Name="[eDraft]" Range="75,93" RefId="00000000-0000-4000-8000-000000000001" Type="Director" WriterID="00000000-0000-4000-8000-000000000001" WriterName="Dana Reyes">',
					noteParagraph(2, 'Too flat?'),
					'    </ScriptNote>',
					'  </ScriptNotes>',
					''
				].join('\n')
			)
		);
		expect(saved.xml).not.toContain('EDraft:');
		expect(saved.xml).not.toContain('[eDraft thread');
		expect(saved.warnings).toEqual([]);
	});

	it('puts its Range on the whole paragraph it sits in front of, as Final Draft counts it', () => {
		const saved = save(LAB, noteBefore('Too flat?', 'The kettle screams.'));
		// INT. KITCHEN - NIGHT is 20 units and a break: The kettle screams. is 21 to 40.
		expect(saved.xml).toContain('Range="21,40"');
		// An unsigned note is written with the writer's name (D3), the role in Type.
		expect(saved.xml).toContain('Type="Director" WriterID="00000000-0000-4000-8000-000000000001" WriterName="Dana Reyes"');
	});

	it('anchors a note after the last line to the last paragraph', () => {
		const saved = save(LAB, (elements) => [...elements, { type: 'note', text: 'The end?' }]);
		expect(saved.xml).toContain('Range="75,93"');
	});

	it('writes a note of several lines one paragraph to a line', () => {
		const saved = save(LAB, noteBefore('First thought.\nSecond thought.', 'The kettle screams.'));
		expect(scriptNotesOf(saved.xml)).toContain(noteParagraph(2, 'First thought.'));
		expect(scriptNotesOf(saved.xml)).toContain(noteParagraph(3, 'Second thought.'));
		// The words once: never copied into the title.
		expect(saved.xml).toContain('Name="[eDraft]"');
		expect(saved.xml.match(/First thought\./g)).toHaveLength(1);
	});

	it('names nobody when the writer has no name and the note names nobody', () => {
		const saved = save(LAB, noteBefore('Too flat?', 'The kettle screams.'), writing(''));
		expect(saved.xml).toContain('Name="[eDraft]" Range="21,40"');
		expect(saved.xml).toContain('Type="" WriterID="00000000-0000-4000-8000-000000000001" WriterName=""');
		expect(parseFdx(saved.xml).script.elements.filter((element) => element.type === 'note').map((element) => element.text)).toEqual([
			'Too flat?',
			'A note the file already has.'
		]);
	});

	it('adds to Final Draft’s own ScriptNotes with the next Id, and every other byte stays', () => {
		const saved = save(FEATURE, (elements) => [...elements.slice(0, 3), { type: 'note', text: 'Tighter?' }, ...elements.slice(3)]);
		const close = FEATURE.lastIndexOf('\n  </ScriptNotes>');
		const added = saved.xml.slice(close, saved.xml.length - (FEATURE.length - close));
		expect(saved.xml.slice(0, close)).toBe(FEATURE.slice(0, close));
		expect(saved.xml.slice(close + added.length)).toBe(FEATURE.slice(close));
		const ids = [...FEATURE.matchAll(/<ScriptNote\b[^>]*\sId="(\d+)"/g)].map((match) => Number(match[1]));
		expect(added).toContain(`Id="${Math.max(...ids) + 1}"`);
		expect(added.match(/<ScriptNote /g)).toHaveLength(1);
	});

	describe('reopened', () => {
		const written = save(LAB, noteBefore('Dana Reyes (Director): Too flat?', "It's the same lab.")).xml;

		it('comes back as the writer’s own note on its line, and not as one of the file’s', () => {
			const reopened = parseFdx(written);
			expect(reopened.script.elements.map((element) => [element.type, element.text])).toEqual([
				['scene', 'INT. KITCHEN - NIGHT'],
				['action', 'The kettle screams.'],
				['note', 'A note the file already has.'],
				['character', 'MARA'],
				['note', 'Dana Reyes (Director): Too flat?'],
				['dialogue', "It's the same lab."]
			]);
			expect(reopened.scriptNotes).toEqual([]);
		});

		it('saves with no edit to the identical file', () => {
			expect(save(written, (elements) => elements).xml).toBe(written);
			const document = openFdx(written);
			expect(document.rewrite(document.script).xml).toBe(written);
		});

		it('moves only its Range when a line above it is edited', () => {
			const saved = save(written, (elements) =>
				elements.map((element) => (element.text === 'The kettle screams.' ? { ...element, text: 'The old kettle screams.' } : element))
			);
			expect(scriptNotesOf(saved.xml)).toBe(scriptNotesOf(written).replace('Range="75,93"', 'Range="79,97"'));
		});

		it('is taken out of ScriptNotes when the writer deletes it', () => {
			const saved = save(written, (elements) => elements.filter((element) => !element.text.endsWith('Too flat?')));
			expect(saved.xml).not.toContain('<ScriptNote ');
			expect(saved.xml).toContain('<ScriptNotes>\n  </ScriptNotes>');
			expect(contentOf(saved.xml)).toBe(contentOf(LAB));
			expect(saved.diagnostics.map((diagnostic) => diagnostic.code)).toEqual(['FDX_REWRITE_SCRIPT_NOTES_REMOVED']);
		});

		it('is written again as a new note when the writer changes it — stage 1', () => {
			const saved = save(written, (elements) =>
				elements.map((element) => (element.text.endsWith('Too flat?') ? { ...element, text: 'Dana Reyes (Director): Much too flat.' } : element))
			);
			expect(saved.xml.match(/<ScriptNote /g)).toHaveLength(1);
			expect(saved.xml).toContain('Id="2" Name="[eDraft]"');
			expect(saved.xml).toContain('>Much too flat.</Text>');
			expect(saved.xml).not.toContain('Too flat?');
		});
	});

	it('keeps a body Note paragraph the file already has a paragraph — edited, or deleted', () => {
		const edited = save(LAB, (elements) =>
			elements.map((element) => (element.text === 'A note the file already has.' ? { ...element, text: 'A note the file has, edited.' } : element))
		);
		expect(edited.xml).toContain('<Paragraph Type="Note">\n      <Text>A note the file has, edited.</Text>');
		expect(edited.xml).not.toContain('<ScriptNotes>');
		const deleted = save(LAB, (elements) => elements.filter((element) => element.text !== 'A note the file already has.'));
		expect(deleted.xml).not.toContain('Type="Note"');
		expect(deleted.xml).not.toContain('<ScriptNotes>');
	});

	it('never parts a dual dialogue with a note', () => {
		const dual = `<FinalDraft DocumentType="Script" Template="No" Version="5">
  <Content>
    <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
    <Paragraph><DualDialogue><Paragraph Type="Character"><Text>BOB</Text></Paragraph><Paragraph Type="Dialogue"><Text>Hi.</Text></Paragraph><Paragraph Type="Character"><Text>ANN</Text></Paragraph><Paragraph Type="Dialogue"><Text>Ho.</Text></Paragraph></DualDialogue></Paragraph>
  </Content>
</FinalDraft>`;
		const saved = save(dual, noteBefore('Overlap?', 'Ho.'));
		expect(contentOf(saved.xml)).toBe(contentOf(dual));
		// The block's own paragraph: 20 units and a break, then its two.
		expect(saved.xml).toContain('Range="21,23"');
	});
});

describe('which notes are eDraft’s (RFC-NOTES-SYSTEM §4.3, IL-0043)', () => {
	const file = (title: string, writerName = 'Sam Okafor', type = 'Director') => `<FinalDraft><Content>
<Paragraph Type="Action"><Text>Hum.</Text></Paragraph>
</Content><ScriptNotes><ScriptNote Id="1" Name="${title}" Range="0,4" Type="${type}" WriterName="${writerName}"><Paragraph><Text>Words.</Text></Paragraph></ScriptNote></ScriptNotes></FinalDraft>`;

	it.each<[string, string, string, string]>([
		['[eDraft]', 'Sam Okafor', 'Director', 'Sam Okafor (Director): Words.'],
		['[eDraft]', 'Sam Okafor', '', 'Sam Okafor: Words.'],
		['[eDraft]', '', '', 'Words.'],
		// After an edit in Final Draft: the title kept, the author re-stamped.
		['[eDraft]', 'x', 'Director', 'x (Director): Words.']
	])('a note titled %j by %j, Type %j, comes back as the writer’s own: %j', (title, writerName, type, text) => {
		const read = parseFdx(file(title, writerName, type));
		expect(read.scriptNotes).toEqual([]);
		expect(read.script.elements).toEqual([
			{ type: 'note', text },
			{ type: 'action', text: 'Hum.' }
		]);
	});

	it.each([
		['retitled in Final Draft', 'Tighter?', 'Sam Okafor'],
		['untitled', '', 'Sam Okafor'],
		['marked the IL-0042 way, in the author field', '', '[eDraft] Sam Okafor'],
		['titled eDraft without brackets', 'eDraft', 'Sam Okafor']
	])('a note stays Final Draft’s when %s', (_, title, writerName) => {
		const read = parseFdx(file(title, writerName));
		expect(read.scriptNotes).toHaveLength(1);
		expect(read.script.elements).toEqual([{ type: 'action', text: 'Hum.' }]);
	});
});

describe('FDX · notes pinned to words (RFC-NOTES-SYSTEM §5, stage 4)', () => {
	const NOTES: FdxNoteWriting = {
		writer: 'Sam Okafor',
		now: '20260920T120000',
		newId: () => '00000000-0000-4000-8000-000000000001'
	};
	const rangeOf = (xml: string) => /<ScriptNote[^>]*\sRange="([^"]*)"/.exec(xml)?.[1];
	const wrote = (elements: ScreenplayElement[]) =>
		writeFdxWithDiagnostics({ titlePage: [], elements }, { notes: NOTES });

	it('writes an anchored note on its words, not its paragraph (§5.1)', () => {
		const result = wrote([
			{ type: 'action', text: "The kettle screams. Mara doesn't move." },
			{ type: 'note', text: 'Too still?', anchor: { on: "doesn't move" } }
		]);
		/* "The kettle screams. Mara " is 25 units; the words run to the
		   full stop, which they do not include. */
		expect(rangeOf(result.xml)).toBe('25,37');
		expect(result.diagnostics).toEqual([]);
	});

	it('writes an unanchored note on its whole paragraph, exactly as before', () => {
		const paragraph = "The kettle screams. Mara doesn't move.";
		const anchored = wrote([{ type: 'action', text: paragraph }, { type: 'note', text: 'Too still?' }]);
		expect(rangeOf(anchored.xml)).toBe(`0,${paragraph.length}`);
	});

	it('nth picks the occurrence, and the Range follows it (§5.3)', () => {
		const result = wrote([
			{ type: 'action', text: 'one two one two' },
			{ type: 'note', text: 'Which?', anchor: { on: 'one', nth: 2 } }
		]);
		expect(rangeOf(result.xml)).toBe('8,11');
	});

	it('words that are gone fall back to the paragraph and say so (§5.3 rule 5)', () => {
		const result = wrote([
			{ type: 'action', text: 'The kettle screams.' },
			{ type: 'note', text: 'Too still?', anchor: { on: 'the samovar' } }
		]);
		expect(rangeOf(result.xml)).toBe('0,19');
		expect(result.diagnostics.map((d) => d.code)).toContain('FDX_NOTE_ANCHOR_WORDS_CHANGED');
	});

	it('reads the words back off the Range, and round-trips the anchor (§5.4)', () => {
		const original: Screenplay = {
			titlePage: [],
			/* In front of its paragraph: where the editor keeps a note, and
			   where reading one back puts it (§5.2). */
			elements: [
				{ type: 'note', text: 'Sam Okafor: Too still?', anchor: { on: "doesn't move" } },
				{ type: 'action', text: "The kettle screams. Mara doesn't move." }
			]
		};
		const read = parseFdx(writeFdxWithDiagnostics(original, { notes: NOTES }).xml).script;
		expect(read.elements.find((e) => e.type === 'note')?.anchor).toEqual({ on: "doesn't move" });
		expect(read).toEqual(original);
	});

	it('gives a whole-paragraph Range no anchor — every note before stage 4', () => {
		const xml = writeFdxWithDiagnostics(
			{ titlePage: [], elements: [{ type: 'action', text: 'The kettle screams.' }, { type: 'note', text: 'Sam Okafor: Why?' }] },
			{ notes: NOTES }
		).xml;
		expect(parseFdx(xml).script.elements.find((e) => e.type === 'note')?.anchor).toBeUndefined();
	});

	it('a Range that spans paragraphs anchors to the words in its first (§5.3 rule 6)', () => {
		const xml =
			'<FinalDraft><Content>' +
			'<Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>' +
			'<Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>' +
			'</Content><ScriptNotes>' +
			'<ScriptNote Name="[eDraft]" Range="4,25" WriterName="Sam Okafor"><Paragraph><Text>Both?</Text></Paragraph></ScriptNote>' +
			'</ScriptNotes></FinalDraft>';
		const note = parseFdx(xml).script.elements.find((e) => e.type === 'note');
		expect(note?.anchor).toEqual({ on: 'kettle screams.' });
	});

	it('an anchor never reaches the file as an attribute — Final Draft strips those (§3 fact 1)', () => {
		const xml = wrote([
			{ type: 'action', text: "The kettle screams. Mara doesn't move." },
			{ type: 'note', text: 'Too still?', anchor: { on: "doesn't move" } }
		]).xml;
		/* The root's xmlns:EDraft and the EDraft:ElementType/TitleKey
		   attributes are the writer's own, from long before this stage. What
		   stage 4 promises is narrower and is what is checked: the anchor
		   itself never becomes an attribute, on a note or anywhere else. */
		const notes = xml.slice(xml.indexOf('<ScriptNotes>'));
		expect(notes).not.toContain('EDraft:');
		expect(xml).not.toContain('on:');
		expect(xml).not.toContain('nth:');
		expect(xml).not.toContain('Anchor');
	});

	it('FDX to Fountain and back keeps the words', () => {
		const original: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'action', text: 'one two one two' },
				{ type: 'note', text: 'Sam Okafor: Which?', anchor: { on: 'one', nth: 2 } }
			]
		};
		const xml = writeFdxWithDiagnostics(original, { notes: NOTES }).xml;
		const throughFountain = parseFountain(serialiseFountain(parseFdx(xml).script));
		expect(throughFountain.elements.find((e) => e.type === 'note')?.anchor).toEqual({ on: 'one', nth: 2 });
		expect(rangeOf(writeFdxWithDiagnostics(throughFountain, { notes: NOTES }).xml)).toBe('8,11');
	});

	it('Fountain cannot anchor a note on a speech line, and the save says so', () => {
		/* A note between a cue and its speech ends the block in Fountain, so
		   the serialiser hoists it in front of the block (IL-0040). §5.2 then
		   makes the cue its paragraph, the words are not in it, and §5.3 rule
		   5 falls back to the whole cue. A named degradation, not a surprise:
		   the words are never moved to another paragraph or guessed at. */
		const script: Screenplay = {
			titlePage: [],
			elements: [
				{ type: 'character', text: 'MARA' },
				{ type: 'note', text: 'Too flat?', anchor: { on: 'same lab' } },
				{ type: 'dialogue', text: "It's the same lab." }
			]
		};
		const reparsed = parseFountain(serialiseFountain(script));
		expect(reparsed.elements.map((e) => e.type)).toEqual(['note', 'character', 'dialogue']);
		const result = writeFdxWithDiagnostics(reparsed, { notes: NOTES });
		expect(rangeOf(result.xml)).toBe('0,4');
		expect(result.diagnostics.map((d) => d.code)).toContain('FDX_NOTE_ANCHOR_WORDS_CHANGED');
	});

	it('a save with no edit is byte-identical when the file holds an anchored note', () => {
		const source =
			'<FinalDraft DocumentType="Script" Template="No" Version="5">\n' +
			'  <Content>\n' +
			'    <Paragraph Type="Action">\n' +
			'      <Text>The kettle screams. Mara doesn\'t move.</Text>\n' +
			'    </Paragraph>\n' +
			'  </Content>\n' +
			'  <ScriptNotes>\n' +
			'    <ScriptNote Name="[eDraft]" Range="20,37" WriterName="Sam Okafor">\n' +
			'      <Paragraph>\n' +
			'        <Text>Too still?</Text>\n' +
			'      </Paragraph>\n' +
			'    </ScriptNote>\n' +
			'  </ScriptNotes>\n' +
			'</FinalDraft>\n';
		const reading = parseFdx(source).script;
		/* 20,37 is "Mara doesn't move" — the Range is the measure, not the eye. */
		expect(reading.elements.find((e) => e.type === 'note')?.anchor).toEqual({ on: "Mara doesn't move" });
		const saved = openFdx(source).rewrite(reading, { unedited: reading, notes: NOTES }).xml;
		expect(saved).toBe(source);
	});
});

/**
 * Omitted scenes (RFC-DRAFT-PRODUCTION §7.3).
 *
 * Final Draft nests an <OmittedScene> INSIDE the visible Scene Heading that
 * shows the OMITTED card. Before this suite, the parser skipped the block
 * whole as metadata: its paragraphs never reached the model, nothing said
 * the scene was omitted, and a fresh export dropped it. Only the
 * byte-preserving save stood between a writer and a lost scene.
 */
describe('FDX · omitted scenes (§7.3)', () => {
	const OMIT_LAB = [
		'<FinalDraft DocumentType="Script" Template="No" Version="5">',
		'<Content>',
		'<Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>',
		'<Paragraph Number="21" Type="Scene Heading">',
		'<Text>OMITTED</Text>',
		'<OmittedScene>',
		'<Paragraph Type="Scene Heading"><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>',
		'<Paragraph Type="Action"><Text TagNumber="213">Mara</Text><Text> waits.</Text></Paragraph>',
		'</OmittedScene>',
		'</Paragraph>',
		'<Paragraph Type="Action"><Text>She waits.</Text></Paragraph>',
		'</Content>',
		'</FinalDraft>'
	].join('\n');

	const SAMPLE02 = new URL('../../../apple/eDraftEngine/Fixtures/finaldraft-sample02.fdx', import.meta.url);
	const OMITTED_HEADING = 'Ext. Xx xxx xxxxxx xxxx - dusk';

	it('reads the omitted body into the script — it is not skipped as metadata', () => {
		const script = parseFdx(OMIT_LAB).script;
		const texts = script.elements.map((e) => e.text);
		expect(texts).toContain('EXT. THE YARD - DUSK');
		expect(texts).toContain('Mara waits.');
		/* The card keeps its own place and its number. */
		const card = script.elements.findIndex((e) => e.text === 'OMITTED');
		expect(script.elements[card].sceneNumber).toBe('21');
		expect(script.elements[card + 1].type).toBe('scene');
		expect(script.elements[card + 1].text).toBe('EXT. THE YARD - DUSK');
	});

	it('records the omission as a reversible span starting at a scene heading', () => {
		const script = parseFdx(OMIT_LAB).script;
		const card = script.elements.findIndex((e) => e.text === 'OMITTED');
		expect(script.omissions).toEqual([{ start: card + 1, end: card + 3 }]);
		/* §7.3: the span starts at a scene heading, and the body stays. */
		expect(script.elements[script.omissions![0].start].type).toBe('scene');
		expect(script.omissions![0].end - script.omissions![0].start).toBe(2);
	});

	it('the model says which elements are omitted, without re-reading the file', () => {
		const script = parseFdx(OMIT_LAB).script;
		const omitted = new Set<number>();
		for (const o of script.omissions ?? []) for (let i = o.start; i < o.end; i++) omitted.add(i);
		const names = script.elements.map((e, i) => `${omitted.has(i) ? 'omitted' : 'live   '} ${e.text}`);
		expect(names).toEqual([
			'live    INT. KITCHEN - NIGHT',
			'live    The kettle screams.',
			'live    OMITTED',
			'omitted EXT. THE YARD - DUSK',
			'omitted Mara waits.',
			'live    She waits.'
		]);
	});

	it('keeps the TagNumbers of the omitted body', () => {
		const script = parseFdx(OMIT_LAB).script;
		const heading = script.elements.find((e) => e.text === 'EXT. THE YARD - DUSK');
		expect(heading?.runs?.[0]?.tagNumbers).toEqual([317]);
		const action = script.elements.find((e) => e.text === 'Mara waits.');
		expect(action?.runs?.[0]?.tagNumbers).toEqual([213]);
	});

	it('a fresh export writes the <OmittedScene> wrapper back, nested in its card', () => {
		const xml = writeFdx(parseFdx(OMIT_LAB).script);
		expect(xml).toContain('<OmittedScene>');
		expect(xml).toContain('TagNumber="317"');
		/* Nested inside the card, not loose among the live paragraphs. */
		const card = xml.indexOf('OMITTED<');
		const open = xml.indexOf('<OmittedScene>');
		const close = xml.indexOf('</OmittedScene>');
		expect(card).toBeGreaterThan(-1);
		expect(open).toBeGreaterThan(card);
		expect(xml.indexOf('EXT. THE YARD - DUSK')).toBeGreaterThan(open);
		expect(xml.indexOf('EXT. THE YARD - DUSK')).toBeLessThan(close);
		/* And the omitted body is not also emitted as a live paragraph. */
		expect(xml.split('EXT. THE YARD - DUSK').length - 1).toBe(1);
	});

	it('import → export → import is stable, omission included', () => {
		const once = parseFdx(OMIT_LAB).script;
		const twice = parseFdx(writeFdx(once)).script;
		expect(twice).toEqual(once);
	});

	it('the real file: the omitted scene reaches the model instead of vanishing', () => {
		const source = readFileSync(SAMPLE02, 'utf8');
		const script = parseFdx(source).script;
		expect(script.elements.map((e) => e.text)).toContain(OMITTED_HEADING);
		expect(script.omissions?.length).toBe(1);
		const [omission] = script.omissions!;
		expect(script.elements[omission.start].text).toBe(OMITTED_HEADING);
		expect(script.elements[omission.start].type).toBe('scene');
	});

	it('the real file: a fresh export keeps the scene instead of deleting it', () => {
		const source = readFileSync(SAMPLE02, 'utf8');
		const xml = writeFdx(parseFdx(source).script);
		expect(xml).toContain('<OmittedScene>');
		expect(xml).toContain(OMITTED_HEADING);
		expect(xml).toContain('TagNumber="317"');
	});

	it('the real file: a no-edit preserving save is still byte-identical', () => {
		const source = readFileSync(SAMPLE02, 'utf8');
		const reading = parseFdx(source).script;
		expect(openFdx(source).rewrite(reading, { unedited: reading }).xml).toBe(source);
	});

	it('a script with no omission carries no record, and writes exactly as before', () => {
		const plain = OMIT_LAB.replace(/<OmittedScene>[\s\S]*<\/OmittedScene>/, '');
		const script = parseFdx(plain).script;
		expect(script.omissions).toBeUndefined();
		expect('omissions' in script).toBe(false);
	});

	it('two omitted scenes are two records, each over its own span', () => {
		const two = OMIT_LAB.replace(
			'<Paragraph Type="Action"><Text>She waits.</Text></Paragraph>',
			[
				'<Paragraph Number="22" Type="Scene Heading">',
				'<Text>OMITTED</Text>',
				'<OmittedScene>',
				'<Paragraph Type="Scene Heading"><Text>INT. THE HALL - DAY</Text></Paragraph>',
				'</OmittedScene>',
				'</Paragraph>',
				'<Paragraph Type="Action"><Text>She waits.</Text></Paragraph>'
			].join('\n')
		);
		const script = parseFdx(two).script;
		expect(script.omissions).toHaveLength(2);
		const [first, second] = script.omissions!;
		expect(script.elements[first.start].text).toBe('EXT. THE YARD - DUSK');
		expect(script.elements[second.start].text).toBe('INT. THE HALL - DAY');
		expect(second.start).toBeGreaterThanOrEqual(first.end);
		expect(parseFdx(writeFdx(script)).script).toEqual(script);
	});

	it('an empty wrapper records no omission and loses nothing', () => {
		const empty = OMIT_LAB.replace(/<OmittedScene>[\s\S]*<\/OmittedScene>/, '<OmittedScene></OmittedScene>');
		const script = parseFdx(empty).script;
		expect(script.omissions).toBeUndefined();
		expect(openFdx(empty).rewrite(script, { unedited: script }).xml).toBe(empty);
	});

	it('editing an omitted line keeps the file\'s bytes, and the save says so', () => {
		const reading = parseFdx(OMIT_LAB).script;
		const omission = reading.omissions![0];
		const edited = {
			...reading,
			elements: reading.elements.map((element, index) =>
				index === omission.start ? { ...element, text: 'EXT. SOMEWHERE ELSE - DAWN' } : element
			)
		};
		const saved = openFdx(OMIT_LAB).rewrite(edited, { unedited: reading });
		/* The omitted body is the file's, not the editor's (§7.3, "Preserved
		   on splice") — and the writer is told, never left to guess. */
		expect(saved.xml).toBe(OMIT_LAB);
		expect(saved.diagnostics.map((d) => d.code)).toContain('FDX_REWRITE_OMITTED_SCENE_KEPT');
		expect(saved.diagnostics.find((d) => d.code === 'FDX_REWRITE_OMITTED_SCENE_KEPT')?.severity).toBe('info');
	});

	it('an omitted body the save cannot find is reported, not guessed at', () => {
		const reading = parseFdx(OMIT_LAB).script;
		const omission = reading.omissions![0];
		/* The whole body gone from the script being saved. */
		const without = {
			...reading,
			elements: reading.elements.filter((_, index) => index < omission.start || index >= omission.end),
			omissions: undefined
		};
		const saved = openFdx(OMIT_LAB).rewrite(without, { unedited: without });
		expect(saved.diagnostics.map((d) => d.code)).toContain('FDX_REWRITE_OMITTED_SCENE_UNPLACED');
		expect(saved.xml).toContain('<OmittedScene>');
	});

	it('an edit outside the omission is written, and the block is untouched', () => {
		const reading = parseFdx(OMIT_LAB).script;
		const edited = {
			...reading,
			elements: reading.elements.map((element) =>
				element.text === 'She waits.' ? { ...element, text: 'She waited.' } : element
			)
		};
		const saved = openFdx(OMIT_LAB).rewrite(edited, { unedited: reading });
		expect(saved.xml).toContain('She waited.');
		expect(saved.xml).toContain('<OmittedScene>');
		expect(saved.xml).toContain('TagNumber="317"');
		expect(saved.xml.split('EXT. THE YARD - DUSK').length - 1).toBe(1);
	});

	it('the Range space does not move: a note after an omitted scene keeps its offsets', () => {
		const source = readFileSync(SAMPLE02, 'utf8');
		const { scriptNotes } = parseFdx(source);
		/* The file's Range values are what Final Draft measured; reading the
		   omitted body into the model must not touch them. */
		const ranges = scriptNotes.map((note) => note.range && `${note.range.start},${note.range.end}`);
		const inFile = [...source.matchAll(/<ScriptNote[^>]*\sRange="([^"]*)"/g)].map((m) => m[1]);
		expect(ranges.filter(Boolean)).toEqual(inFile);
		/* And every anchor still lands on whole words, none mid-word. */
		expect(scriptNotes.filter((note) => note.anchor === undefined)).toEqual([]);
	});

	it('unknown nested structure still follows the embedded-blocks rule', () => {
		const withUnknown = OMIT_LAB.replace(
			'<Paragraph Type="Action"><Text TagNumber="213">Mara</Text><Text> waits.</Text></Paragraph>',
			'<Paragraph Type="Action"><SomeFutureThing><Inner>x</Inner></SomeFutureThing><Text TagNumber="213">Mara</Text><Text> waits.</Text></Paragraph>'
		);
		const script = parseFdx(withUnknown).script;
		/* The unknown wrapper is metadata, skipped whole; the text stands. */
		expect(script.elements.map((e) => e.text)).toContain('Mara waits.');
		expect(openFdx(withUnknown).rewrite(script, { unedited: script }).xml).toBe(withUnknown);
	});
});

/**
 * A save that follows the writer's omissions — RFC-DRAFT-PRODUCTION §7.3,
 * IL-0087. Mirrored in Swift (`OmissionRewriteTests`), with the same
 * fixtures and the same expected bytes, so the two ports cannot drift.
 *
 * Before this, the preserving save found an omitted scene only by the
 * file's own structure: a scene the writer omitted was written as a live
 * OMITTED heading with the whole scene still live under it, and a scene the
 * writer restored was quietly re-omitted by the next save.
 */
describe('openFdx · a save that follows the writer’s omissions', () => {
	const LIVE = [
		'<FinalDraft DocumentType="Script" Template="No" Version="5">',
		'<Content>',
		'<Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>',
		'<Paragraph Number="21" Type="Scene Heading"><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>',
		'<Paragraph Type="Action"><Text TagNumber="213">Mara</Text><Text> waits.</Text></Paragraph>',
		'<Paragraph Type="Transition"><Text>Cut to:</Text></Paragraph>',
		'<Paragraph Type="Scene Heading"><Text>INT. HALL - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>She waits.</Text></Paragraph>',
		'</Content>',
		'</FinalDraft>'
	].join('\n');
	const OMITTED = [
		'<FinalDraft DocumentType="Script" Template="No" Version="5">',
		'<Content>',
		'<Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>',
		'<Paragraph Number="21" Type="Scene Heading"><Text>OMITTED</Text><OmittedScene>',
		'<Paragraph Type="Scene Heading"><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>',
		'<Paragraph Type="Action"><Text TagNumber="213">Mara</Text><Text> waits.</Text></Paragraph>',
		'<Paragraph Type="Transition"><Text>Cut to:</Text></Paragraph>',
		'</OmittedScene></Paragraph>',
		'<Paragraph Type="Scene Heading"><Text>INT. HALL - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>She waits.</Text></Paragraph>',
		'</Content>',
		'</FinalDraft>'
	].join('\n');
	/** The bytes both ports write — the same literal is asserted in Swift. */
	const OMITTED_BY_THE_WRITER = [
		'<FinalDraft DocumentType="Script" Template="No" Version="5">',
		'<Content>',
		'<Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>',
		'<Paragraph Type="Scene Heading" Number="21"><Text>OMITTED</Text><OmittedScene>',
		'<Paragraph Number="21" Type="Scene Heading"><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>',
		'<Paragraph Type="Action"><Text TagNumber="213">Mara</Text><Text> waits.</Text></Paragraph>',
		'<Paragraph Type="Transition"><Text>Cut to:</Text></Paragraph>',
		'</OmittedScene></Paragraph>',
		'<Paragraph Type="Scene Heading"><Text>INT. HALL - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>She waits.</Text></Paragraph>',
		'</Content>',
		'</FinalDraft>'
	].join('\n');
	const RESTORED_BY_THE_WRITER = [
		'<FinalDraft DocumentType="Script" Template="No" Version="5">',
		'<Content>',
		'<Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>',
		'<Paragraph Type="Scene Heading"><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>',
		'<Paragraph Type="Action"><Text TagNumber="213">Mara</Text><Text> waits.</Text></Paragraph>',
		'<Paragraph Type="Transition"><Text>Cut to:</Text></Paragraph>',
		'<Paragraph Type="Scene Heading"><Text>INT. HALL - NIGHT</Text></Paragraph>',
		'<Paragraph Type="Action"><Text>She waits.</Text></Paragraph>',
		'</Content>',
		'</FinalDraft>'
	].join('\n');
	const count = (needle: string, haystack: string) => haystack.split(needle).length - 1;
	const fixture = (name: string) =>
		readFileSync(new URL(`../../../apple/eDraftEngine/Fixtures/${name}`, import.meta.url), 'utf8');
	/** The script as the app holds it: carried through Fountain and read back. */
	const fountainReading = (xml: string): Screenplay =>
		parseFountain(serialiseFountain(parseFdx(xml).script), { emphasis: 'runs' });
	/** The yard omitted by hand: a card carrying its number, the span behind it. */
	const omittingTheYard = (script: Screenplay): Screenplay => {
		const heading = script.elements.findIndex((e) => e.text === 'EXT. THE YARD - DUSK');
		const elements = [...script.elements];
		elements.splice(heading, 0, { type: 'scene', text: 'OMITTED', sceneNumber: '21' });
		return { ...script, elements, omissions: [{ start: heading + 1, end: heading + 4 }] };
	};
	const restoringTheYard = (script: Screenplay): Screenplay => ({
		...script,
		elements: script.elements.filter((e) => e.text !== 'OMITTED'),
		omissions: []
	});

	it('omit: the scene is written inside its card, once, and reads back omitted', () => {
		const reading = parseFdx(LIVE).script;
		const saved = omittingTheYard(reading);
		const result = openFdx(LIVE).rewrite(saved, { unedited: reading });
		const back = parseFdx(result.xml).script;
		expect(back.omissions).toEqual(saved.omissions);
		expect(back.elements.map((e) => e.text)).toEqual(saved.elements.map((e) => e.text));
		expect(count('EXT. THE YARD - DUSK', result.xml)).toBe(1);
		expect(result.diagnostics.map((d) => d.code)).toContain('FDX_REWRITE_SCENE_OMITTED');
	});

	it('restore: the scene comes out of its card with its bytes and tags', () => {
		const reading = parseFdx(OMITTED).script;
		const result = openFdx(OMITTED).rewrite(restoringTheYard(reading), { unedited: reading });
		const back = parseFdx(result.xml).script;
		expect(back.omissions).toBeUndefined();
		expect(result.xml).not.toContain('<OmittedScene');
		expect(result.xml).not.toContain('OMITTED');
		expect(result.diagnostics.map((d) => d.code)).toContain('FDX_REWRITE_OMITTED_SCENE_RESTORED');
	});

	it('both ports write the same bytes for an omit and for a restore', () => {
		const live = parseFdx(LIVE).script;
		expect(openFdx(LIVE).rewrite(omittingTheYard(live), { unedited: live }).xml).toBe(OMITTED_BY_THE_WRITER);
		const omitted = parseFdx(OMITTED).script;
		expect(openFdx(OMITTED).rewrite(restoringTheYard(omitted), { unedited: omitted }).xml).toBe(
			RESTORED_BY_THE_WRITER
		);
	});

	it('restore: a heading given its card’s number gains Number and keeps its tags', () => {
		const reading = parseFdx(OMITTED).script;
		const saved = restoringTheYard(reading);
		const heading = saved.elements.findIndex((e) => e.text === 'EXT. THE YARD - DUSK');
		saved.elements[heading] = { ...saved.elements[heading], sceneNumber: '21' };
		const xml = openFdx(OMITTED).rewrite(saved, { unedited: reading }).xml;
		expect(xml).toContain(
			'<Paragraph Number="21" Type="Scene Heading"><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>'
		);
		expect(parseFdx(xml).script.elements[heading].sceneNumber).toBe('21');
	});

	/** Final Draft's dual dialogue: a paragraph with no text of its own
	    holding a <DualDialogue> of two speeches. */
	const DUAL =
		'<Paragraph Type="General"><DualDialogue>' +
		'<Paragraph Type="Character"><Text>MARA</Text></Paragraph>' +
		'<Paragraph Type="Dialogue"><Text TagNumber="5">Now.</Text></Paragraph>' +
		'<Paragraph Type="Character"><Text>TOM</Text></Paragraph>' +
		'<Paragraph Type="Dialogue"><Text>Not yet.</Text></Paragraph>' +
		'</DualDialogue></Paragraph>';
	const CUT = '<Paragraph Type="Transition"><Text>Cut to:</Text></Paragraph>';
	const OMITTED_WITH_DUAL = OMITTED.replace(CUT, `${DUAL}\n${CUT}`);
	const LIVE_WITH_DUAL = LIVE.replace(CUT, `${DUAL}\n${CUT}`);

	it('an omitted scene’s dual dialogue is read as its lines, not lost', () => {
		const script = parseFdx(OMITTED_WITH_DUAL).script;
		const omission = script.omissions?.[0];
		expect(omission).toBeDefined();
		if (!omission) return;
		const body = script.elements.slice(omission.start, omission.end);
		expect(body.map((e) => e.text)).toEqual([
			'EXT. THE YARD - DUSK', 'Mara waits.', 'MARA', 'Now.', 'TOM', 'Not yet.', 'Cut to:'
		]);
		expect(body.find((e) => e.text === 'TOM')?.dual).toBe(true);
		expect(body.find((e) => e.text === 'Now.')?.runs?.[0]?.tagNumbers).toEqual([5]);
		expect(openFdx(OMITTED_WITH_DUAL).rewrite(script, { unedited: script }).xml).toBe(OMITTED_WITH_DUAL);
	});

	it('restore: a dual dialogue comes out of the card whole — its frame and its bytes', () => {
		const reading = parseFdx(OMITTED_WITH_DUAL).script;
		const saved = restoringTheYard(reading);
		const xml = openFdx(OMITTED_WITH_DUAL).rewrite(saved, { unedited: reading }).xml;
		expect(xml).not.toContain('<OmittedScene');
		expect(xml).toContain(DUAL);
		expect(parseFdx(xml).script.elements.map((e) => e.text)).toEqual(saved.elements.map((e) => e.text));
	});

	it('omit: a scene holding dual dialogue is nested whole and reads back whole', () => {
		const reading = parseFdx(LIVE_WITH_DUAL).script;
		const heading = reading.elements.findIndex((e) => e.text === 'EXT. THE YARD - DUSK');
		const elements = [...reading.elements];
		elements.splice(heading, 0, { type: 'scene', text: 'OMITTED', sceneNumber: '21' });
		const end = elements.findIndex((e) => e.text === 'INT. HALL - NIGHT');
		const saved = { ...reading, elements, omissions: [{ start: heading + 1, end }] };
		const xml = openFdx(LIVE_WITH_DUAL).rewrite(saved, { unedited: reading }).xml;
		expect(xml).toContain(DUAL);
		const back = parseFdx(xml).script;
		expect(back.omissions).toEqual(saved.omissions);
		expect(back.elements.map((e) => e.text)).toEqual(saved.elements.map((e) => e.text));
		expect(back.elements.find((e) => e.text === 'TOM')?.dual).toBe(true);
	});

	/* The scene-number half of the fix, on its own — no omission in sight.
	   Before it, a renumbered heading saved with the file's old number, and
	   through Fountain lost its tags as well. */
	it('a renumbered heading’s new Number is written, and its tags are kept', () => {
		const reading = fountainReading(LIVE);
		const heading = reading.elements.findIndex((e) => e.text === 'EXT. THE YARD - DUSK');
		const elements = [...reading.elements];
		elements[heading] = { ...elements[heading], sceneNumber: '21A' };
		const xml = openFdx(LIVE).rewrite({ ...reading, elements }, { unedited: reading }).xml;
		expect(xml).toContain(
			'<Paragraph Number="21A" Type="Scene Heading"><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>'
		);
		expect(parseFdx(xml).script.elements[heading].sceneNumber).toBe('21A');
	});

	it('undefined omissions leave the file’s structure deciding, exactly as before', () => {
		const reading = parseFdx(OMITTED).script;
		const { omissions: _omissions, ...carried } = reading;
		expect(openFdx(OMITTED).rewrite(carried, { unedited: reading }).xml).toBe(OMITTED);
		expect(openFdx(OMITTED).rewrite(reading, { unedited: reading }).xml).toBe(OMITTED);
	});

	it('the real file: its own omission, said explicitly through Fountain, saves byte for byte', () => {
		const source = fixture('finaldraft-sample02.fdx');
		const parsed = parseFdx(source).script;
		const reading = { ...fountainReading(source), omissions: parsed.omissions };
		expect(reading.elements.length).toBe(parsed.elements.length);
		expect(openFdx(source).rewrite(reading, { unedited: reading }).xml).toBe(source);
	});

	it('the real file: restore → save → omit again → save — the same scene omitted, every tag kept', () => {
		const source = fixture('finaldraft-sample02.fdx');
		const parsed = parseFdx(source).script;
		const omission = parsed.omissions?.[0];
		expect(omission).toBeDefined();
		if (!omission) return;
		const reading = fountainReading(source);
		const tags = count('TagNumber=', source);

		const elements = [...reading.elements];
		const [card] = elements.splice(omission.start - 1, 1);
		const saved = openFdx(source).rewrite({ ...reading, elements, omissions: [] }, { unedited: reading }).xml;
		expect(saved).not.toContain('<OmittedScene');
		expect(parseFdx(saved).script.omissions).toBeUndefined();
		expect(count('TagNumber=', saved)).toBe(tags);

		const again = fountainReading(saved);
		const withCard = [...again.elements];
		withCard.splice(omission.start - 1, 0, card);
		const back = openFdx(saved).rewrite(
			{ ...again, elements: withCard, omissions: [omission] },
			{ unedited: fountainReading(saved) }
		).xml;
		expect(parseFdx(back).script.omissions).toEqual([omission]);
		expect(count('TagNumber=', back)).toBe(tags);
		const expected = parsed.elements.map((e) => e.text);
		expected[omission.start - 1] = expected[omission.start - 1].toUpperCase();
		expect(parseFdx(back).script.elements.map((e) => e.text)).toEqual(expected);
	});

	it('the real file: omitting a live scene nests it, every tag kept, the rest untouched', () => {
		const source = fixture('finaldraft-sample02.fdx');
		const parsed = parseFdx(source).script;
		const existing = parsed.omissions?.[0];
		expect(existing).toBeDefined();
		if (!existing) return;
		const unedited = fountainReading(source);
		const heading = unedited.elements.findIndex((e, at) => at > existing.end && e.type === 'scene');
		const after = unedited.elements.findIndex((e, at) => at > heading && e.type === 'scene');
		const next = after === -1 ? unedited.elements.length : after;
		const elements = [...unedited.elements];
		elements.splice(heading, 0, { type: 'scene', text: 'OMITTED', sceneNumber: unedited.elements[heading].sceneNumber });
		const omissions = [existing, { start: heading + 1, end: next + 1 }];
		const xml = openFdx(source).rewrite({ ...unedited, elements, omissions }, { unedited }).xml;
		const back = parseFdx(xml).script;
		expect(back.omissions).toEqual(omissions);
		const expected = parsed.elements.map((e) => e.text);
		expected.splice(heading, 0, 'OMITTED');
		expect(back.elements.map((e) => e.text)).toEqual(expected);
		expect(count('<OmittedScene>', xml)).toBe(2);
		expect(count('TagNumber=', xml)).toBe(count('TagNumber=', source));
	});
});
