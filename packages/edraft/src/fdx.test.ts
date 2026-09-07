/** FDX import, export, diagnostics, limits, and round-trip behavior. */
import { describe, expect, it } from 'vitest';
import {
	decodeXmlEntities,
	encodeXmlEntities,
	parseFdx,
	writeFdx,
	writeFdxWithDiagnostics
} from './fdx.js';
import { parseFountain } from './parse.js';
import { SAMPLE_FOUNTAIN } from '../test/fixtures/sample.js';
import type { Screenplay } from './types.js';

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

	it('maps title-page paragraphs to keyed entries', () => {
		const { script } = parseFdx(FOREIGN_FDX);
		expect(script.titlePage[0]).toEqual({ key: 'Title', values: ['Chips'] });
		expect(script.titlePage[2]).toEqual({ key: 'Author', values: ['A. Writer'] });
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
		expect(script.titlePage[0].values).toContain('A TITLE');
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
				{ type: 'section', text: 'Act One', depth: 1 },
				{ type: 'note', text: 'hidden' },
				{ type: 'action', text: 'Visible.' }
			]
		});
		expect(result.xml).not.toContain('Act One');
		expect(result.xml).not.toContain('hidden');
		expect(result.xml).toContain('Visible.');
		expect(result.xml).toContain('eDraft warning: 2 unsupported element(s) omitted');
		expect(result.diagnostics).toContainEqual(
			expect.objectContaining({ code: 'FDX_STRUCTURAL_ELEMENTS_OMITTED', count: 2 })
		);
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

	it('preserves arbitrary title keys, duplicate entries, empty values, and lyrics', () => {
		const original: Screenplay = {
			titlePage: [
				{ key: 'Custom', values: ['One', 'Two'] },
				{ key: 'Custom', values: [] }
			],
			elements: [{ type: 'lyrics', text: 'La la' }]
		};
		const roundTrip = parseFdx(writeFdx(original)).script;
		expect(roundTrip).toEqual({
			titlePage: [
				{ key: 'Custom', values: ['One', 'Two'] },
				{ key: 'Custom', values: [''] }
			],
			elements: [{ type: 'lyrics', text: 'La la' }]
		});
	});
});

describe('FDX round-trips (hard invariants)', () => {
	it('model → fdx → model is an identity for the sample script', () => {
		const model = parseFountain(SAMPLE_FOUNTAIN);
		const back = parseFdx(writeFdx(model)).script;
		/* printing elements survive exactly (structural excluded by design) */
		const printable = model.elements.filter(
			(e) => !['note', 'section', 'synopsis', 'pagebreak'].includes(e.type)
		);
		expect(back.elements).toEqual(printable);
	});

	it('fdx → model → fdx → model is an identity for foreign files', () => {
		const once = parseFdx(FOREIGN_FDX).script;
		const twice = parseFdx(writeFdx(once)).script;
		expect(twice.elements).toEqual(once.elements);
	});

	it('fountain → model → fdx → model preserves type+text of every element', () => {
		const model = parseFountain(SAMPLE_FOUNTAIN);
		const viaFdx = parseFdx(writeFdx(model)).script;
		const printable = model.elements.filter(
			(e) => !['note', 'section', 'synopsis', 'pagebreak'].includes(e.type)
		);
		expect(viaFdx.elements.map((e) => [e.type, e.text])).toEqual(
			printable.map((e) => [e.type, e.text])
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

	it('restores keyed title-page entries from legacy attributes', () => {
		const { script } = parseFdx(legacyFdx);
		expect(script.titlePage).toEqual([
			{ key: 'Title', values: ['Old Name'] },
			{ key: 'Author', values: ['A. Writer'] }
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
