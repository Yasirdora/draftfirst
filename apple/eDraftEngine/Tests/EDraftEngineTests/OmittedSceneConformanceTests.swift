import Foundation
import Testing
import EDraftEngine

/// Omitted scenes — RFC-DRAFT-PRODUCTION §7.3.
///
/// Final Draft nests an <OmittedScene> INSIDE the visible Scene Heading that
/// shows the OMITTED card. Before this suite, the parser skipped the block
/// whole as metadata: its paragraphs never reached the model, nothing said
/// the scene was omitted, and a fresh export dropped it. Only the
/// byte-preserving save stood between a writer and a lost scene.
///
/// The cross-port cases live in `Fixtures/fdx.json`; this suite is the
/// reading of them in this port's own terms.
@Suite("Omitted scenes")
struct OmittedSceneConformanceTests {

    private static let lab = [
        "<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"5\">",
        "<Content>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>The kettle screams.</Text></Paragraph>",
        "<Paragraph Number=\"21\" Type=\"Scene Heading\">",
        "<Text>OMITTED</Text>",
        "<OmittedScene>",
        "<Paragraph Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text TagNumber=\"213\">Mara</Text><Text> waits.</Text></Paragraph>",
        "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
        "</OmittedScene>",
        "</Paragraph>",
        "<Paragraph Type=\"Action\"><Text>She waits.</Text></Paragraph>",
        "</Content>",
        "</FinalDraft>"
    ].joined(separator: "\n")

    private static let sample02: String = {
        do {
            return try String(
                contentsOf: FixtureStore.directory.appendingPathComponent("finaldraft-sample02.fdx"),
                encoding: .utf8
            )
        } catch {
            Issue.record("Failed to load finaldraft-sample02.fdx: \(error)")
            return ""
        }
    }()

    @Test("The omitted body is read into the script, not skipped as metadata")
    func bodyIsRead() {
        let script = Fdx.parse(Self.lab).script
        let texts = script.elements.map(\.text)
        #expect(texts.contains("EXT. THE YARD - DUSK"))
        #expect(texts.contains("Mara waits."))
        // The card keeps its own place and its number.
        let card = script.elements.firstIndex { $0.text == "OMITTED" }
        #expect(card != nil)
        #expect(script.elements[card!].sceneNumber == "21")
        #expect(script.elements[card! + 1].type == .scene)
        #expect(script.elements[card! + 1].text == "EXT. THE YARD - DUSK")
    }

    @Test("§7.3 · the omission is a reversible span starting at a scene heading")
    func omissionIsASpan() {
        let script = Fdx.parse(Self.lab).script
        let card = script.elements.firstIndex { $0.text == "OMITTED" } ?? -1
        #expect(script.omissions == [Omission(start: card + 1, end: card + 4)])
        #expect(script.elements[card + 1].type == .scene)
    }

    @Test("The model says which elements are omitted, without re-reading the file")
    func modelSaysWhichAreOmitted() {
        let script = Fdx.parse(Self.lab).script
        var omitted = Set<Int>()
        for omission in script.omissions ?? [] {
            for at in omission.start..<omission.end { omitted.insert(at) }
        }
        let named = script.elements.enumerated().map { "\($0.offset == 0 || !omitted.contains($0.offset) ? "live" : "omitted") \($0.element.text)" }
        #expect(named == [
            "live INT. KITCHEN - NIGHT",
            "live The kettle screams.",
            "live OMITTED",
            "omitted EXT. THE YARD - DUSK",
            "omitted Mara waits.",
            "omitted Cut to:",
            "live She waits."
        ])
    }

    @Test("The omitted body keeps its TagNumbers")
    func tagNumbersKept() {
        let script = Fdx.parse(Self.lab).script
        let heading = script.elements.first { $0.text == "EXT. THE YARD - DUSK" }
        #expect(heading?.runs?.first?.tagNumbers == [317])
        let action = script.elements.first { $0.text == "Mara waits." }
        #expect(action?.runs?.first?.tagNumbers == [213])
    }

    @Test("A fresh export writes the wrapper back, nested in its card")
    func exportWrapsItBack() {
        let xml = Fdx.write(Fdx.parse(Self.lab).script).xml
        #expect(xml.contains("<OmittedScene>"))
        #expect(xml.contains("TagNumber=\"317\""))
        guard let card = xml.range(of: "OMITTED<"),
              let open = xml.range(of: "<OmittedScene>"),
              let close = xml.range(of: "</OmittedScene>"),
              let body = xml.range(of: "EXT. THE YARD - DUSK")
        else {
            Issue.record("the wrapper is not in the export")
            return
        }
        #expect(open.lowerBound > card.lowerBound)
        #expect(body.lowerBound > open.lowerBound && body.upperBound < close.lowerBound)
        // And the body is not also written as a live paragraph.
        #expect(xml.components(separatedBy: "EXT. THE YARD - DUSK").count - 1 == 1)
    }

    @Test("Import → export → import is stable, omission included")
    func stableRoundTrip() {
        let once = Fdx.parse(Self.lab).script
        let twice = Fdx.parse(Fdx.write(once).xml).script
        #expect(twice == once)
    }

    @Test("The real file: the omitted scene reaches the model instead of vanishing")
    func realFileIsRead() {
        let script = Fdx.parse(Self.sample02).script
        #expect(script.elements.map(\.text).contains("Ext. Xx xxx xxxxxx xxxx - dusk"))
        #expect(script.omissions?.count == 1)
        guard let omission = script.omissions?.first else { return }
        #expect(script.elements[omission.start].text == "Ext. Xx xxx xxxxxx xxxx - dusk")
        #expect(script.elements[omission.start].type == .scene)
    }

    @Test("The real file: a fresh export keeps the scene instead of deleting it")
    func realFileExportKeepsIt() {
        let xml = Fdx.write(Fdx.parse(Self.sample02).script).xml
        #expect(xml.contains("<OmittedScene>"))
        #expect(xml.contains("Ext. Xx xxx xxxxxx xxxx - dusk"))
        #expect(xml.contains("TagNumber=\"317\""))
    }

    @Test("The real file: a no-edit preserving save is still byte-identical")
    func realFilePreservingSave() {
        let reading = Fdx.parse(Self.sample02).script
        #expect(Fdx.open(Self.sample02).rewrite(reading, unedited: reading) == Self.sample02)
    }

    @Test("Unknown nested structure still follows the embedded-blocks rule")
    func unknownNestedStructure() {
        let withUnknown = Self.lab.replacingOccurrences(
            of: "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
            with: "<Paragraph Type=\"Transition\"><SomeFutureThing><Inner>x</Inner></SomeFutureThing><Text>Cut to:</Text></Paragraph>"
        )
        let script = Fdx.parse(withUnknown).script
        #expect(script.elements.map(\.text).contains("Cut to:"))
        #expect(Fdx.open(withUnknown).rewrite(script, unedited: script) == withUnknown)
    }
}
