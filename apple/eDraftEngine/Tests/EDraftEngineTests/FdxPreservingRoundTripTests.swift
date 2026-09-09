import Testing
import Foundation
@testable import EDraftEngine

/// A Final Draft file is edited, not rebuilt.
///
/// Reading an .fdx into a screenplay and writing a new one from that
/// screenplay throws away everything the screenplay cannot hold — on a real
/// production draft, 19 revisions, 171 revised runs, 25 locked pages, 73
/// deleted-text marks, 248 production tags, 6 dual-dialogue blocks, 136
/// emphasis runs and 3 script notes, all from changing one word and saving.
@Suite("FDX preserving round trip")
struct FdxPreservingRoundTripTests {

    /// A production draft in miniature: the constructs a screenplay model
    /// cannot hold, and a scene heading with its arc beats nested inside.
    static let production = """
    <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
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
    </FinalDraft>
    """

    /// The invariant everything rests on.
    @Test("A save with no edit returns the identical file")
    func noOpIsIdentical() {
        let document = Fdx.open(Self.production)
        #expect(document.rewrite(document.script) == Self.production)
    }

    @Test("An edit rewrites that paragraph and touches nothing else")
    func editKeepsTheRest() {
        let document = Fdx.open(Self.production)
        var script = document.script
        script.elements = script.elements.map { element in
            guard element.text == "Majestic." else { return element }
            var edited = element
            edited.text = "Majestic, and lit."
            return edited
        }
        let xml = document.rewrite(script)

        #expect(xml.contains("Majestic, and lit."))
        #expect(!xml.contains(">Majestic.<"))
        // Everything the screenplay cannot hold survived the edit.
        #expect(xml.contains("<Revision"))
        #expect(xml.contains("<LockedPage"))
        #expect(xml.contains("<TagDefinition"))
        #expect(xml.contains("Style=\"Italic\""))
        #expect(xml.contains("<SceneProperties"))
    }

    /// A scene heading carries its arc beats. Editing its words must not cost
    /// the writer their beats.
    @Test("A scene heading keeps its nested blocks when its text changes")
    func headingKeepsItsBeats() {
        let document = Fdx.open(Self.production)
        var script = document.script
        script.elements = script.elements.map { element in
            guard element.type == .scene else { return element }
            var edited = element
            edited.text = "INT. SOMEWHERE ELSE - NIGHT"
            return edited
        }
        let xml = document.rewrite(script)

        #expect(xml.contains("INT. SOMEWHERE ELSE - NIGHT"))
        #expect(xml.contains("<CharacterArcBeat Name=\"TANGLE\">"))
        #expect(xml.contains("Tangle is obsessed"))
        #expect(xml.contains("Number=\"1\""))
    }

    /// Fountain has no `Shot` and no `General`, so both come back as action.
    /// Rewriting them as Action would be a loss the writer never asked for —
    /// and it is what dropped all twelve `<DualDialogue>` wrappers on a real
    /// production draft, since those live in the whitespace between the
    /// paragraphs being replaced.
    @Test("A kind Fountain cannot carry survives an edit")
    func keepsAFlattenedKind() {
        let xml = """
        <FinalDraft><Content>
        <Paragraph Type="Shot"><Text>CLOSE ON: A GOLD KEY</Text></Paragraph>
        </Content></FinalDraft>
        """
        let document = Fdx.open(xml)
        #expect(document.script.elements.first?.type == .shot)

        // What the editor gives back after a Fountain round trip: action.
        let out = document.rewrite(Screenplay(titlePage: [], elements: [
            ScreenplayElement(type: .action, text: "CLOSE ON: A SILVER KEY")
        ]))
        #expect(out.contains("Type=\"Shot\""))
        #expect(out.contains("CLOSE ON: A SILVER KEY"))
    }

    /// A kind Fountain *can* carry is the writer's to change.
    @Test("A kind the writer really did change is written")
    func writesARealKindChange() {
        let xml = """
        <FinalDraft><Content>
        <Paragraph Type="Action" id="k1"><Text>MARA</Text></Paragraph>
        </Content></FinalDraft>
        """
        let document = Fdx.open(xml)
        let out = document.rewrite(Screenplay(titlePage: [], elements: [
            ScreenplayElement(type: .character, text: "MARA")
        ]))
        #expect(out.contains("Type=\"Character\""))
        #expect(out.contains("id=\"k1\""))
    }

    @Test("A file with nothing to preserve is written whole")
    func nothingToPreserve() {
        let document = Fdx.open("not xml at all")
        let xml = document.rewrite(
            Screenplay(titlePage: [], elements: [
                ScreenplayElement(type: .action, text: "A fresh start.")
            ])
        )
        #expect(xml.contains("<FinalDraft"))
        #expect(xml.contains("A fresh start."))
    }
}
