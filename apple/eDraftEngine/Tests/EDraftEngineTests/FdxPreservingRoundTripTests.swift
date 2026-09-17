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

/// End of Act through a save.
///
/// The import absorbs End of Act (RFC-ACT-BREAK D3), so no element stands for
/// it. Left to the alignment, every save deleted the card — and a card with
/// no Alignment, typed General, was paired with the writer's next edit and
/// given their text. The save now keeps each card verbatim in front of the
/// next paragraph it keeps, or after the last element when none is left.
@Suite("FDX preserving round trip · End of Act")
struct FdxEndOfActRoundTripTests {

    private static let corpus: FdxCorpus.Root = {
        do { return try FixtureStore.load("fdx.json") }
        catch {
            Issue.record("Failed to load fdx.json: \(error)")
            return FdxCorpus.Root(importCases: [], exportCases: [])
        }
    }()

    /// A real feature, anonymised, with one End of Act card near its end.
    private static let sample: String = {
        do {
            return try String(
                contentsOf: FixtureStore.directory.appendingPathComponent("sample0-2.fdx"),
                encoding: .utf8
            )
        } catch {
            Issue.record("Failed to load sample0-2.fdx: \(error)")
            return ""
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.rewriteCases.count == 9)
    }

    @Test("rewrite", arguments: Self.corpus.rewriteCases)
    func rewrite(_ case_: FdxCorpus.RewriteCase) {
        #expect(Fdx.open(case_.source).rewrite(case_.screenplay) == case_.expected.xml,
                "\(case_.name): the save differs from the TypeScript engine")
    }

    @Test("A save with no edit returns the feature byte for byte, its End of Act included")
    func featureNoOpIsIdentical() {
        let document = Fdx.open(Self.sample)
        #expect(Self.sample.contains("Type=\"End of Act\" id="))
        #expect(document.rewrite(document.script) == Self.sample)
    }

    @Test("A card with no Alignment never takes the writer's edit")
    func bareCardKeepsItsBytes() throws {
        let card = "<Paragraph Type=\"End of Act\"><Text>END OF ACT ONE</Text></Paragraph>"
        let xml = """
        <FinalDraft><Content>
        <Paragraph Type="New Act"><Text>ACT ONE</Text></Paragraph>
        \(card)
        <Paragraph Type="New Act"><Text>ACT TWO</Text></Paragraph>
        <Paragraph Type="Action" id="a2"><Text>Buzz.</Text></Paragraph>
        </Content></FinalDraft>
        """
        let document = Fdx.open(xml)
        var script = document.script
        let index = try #require(script.elements.firstIndex { $0.text == "Buzz." })
        script.elements[index].text = "Buzz, buzz."
        let saved = document.rewrite(script)

        #expect(saved.contains(card))
        #expect(saved.contains("<Paragraph Type=\"Action\" id=\"a2\"><Text>Buzz, buzz.</Text></Paragraph>"))
        #expect(!saved.contains("Type=\"End of Act\"><Text>Buzz"))
    }

    /// Every byte outside the edited paragraph matches the original — for
    /// lines across the feature, and for both paragraphs beside its card.
    @Test("An edit changes bytes only inside the paragraph that was edited",
          arguments: [0, 6, 9, 17, 298, 536, 764, 765, 766, 767])
    func editIsConfined(_ index: Int) {
        let document = Fdx.open(Self.sample)
        var script = document.script
        let marker = "EDITED \(index)"
        script.elements[index].text = marker
        let original = Array(Self.sample.utf8)
        let saved = Array(document.rewrite(script).utf8)

        let shorter = min(original.count, saved.count)
        var prefix = 0
        while prefix < shorter, original[prefix] == saved[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shorter - prefix,
              original[original.count - 1 - suffix] == saved[saved.count - 1 - suffix] {
            suffix += 1
        }
        let removed = String(decoding: original[prefix..<(original.count - suffix)], as: UTF8.self)
        let added = String(decoding: saved[prefix..<(saved.count - suffix)], as: UTF8.self)
        #expect(!removed.contains("Paragraph") && !added.contains("Paragraph"),
                "element \(index): the save changed bytes outside the edited paragraph")
        let window = saved[max(0, prefix - marker.utf8.count)..<min(saved.count, saved.count - suffix + marker.utf8.count)]
        #expect(String(decoding: window, as: UTF8.self).contains(marker),
                "element \(index): the change is not where the edit is")
    }
}
