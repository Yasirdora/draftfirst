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

/// A save that follows the writer's omissions — RFC-DRAFT-PRODUCTION §7.3,
/// IL-0087.
///
/// Before this, the preserving save found an omitted scene only by the
/// file's own structure: a scene the writer omitted in eDraft was written
/// as a live OMITTED heading with the whole scene still live under it, and
/// a scene the writer restored was quietly re-omitted by the next save.
/// `script.omissions` is now the writer's word when it is given; nil keeps
/// the file's structure deciding, as before.
@Suite("Omitted scenes · a save that follows the writer")
struct OmissionRewriteTests {

    /// The lab's three scenes, all live.
    private static let live = [
        "<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"5\">",
        "<Content>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>The kettle screams.</Text></Paragraph>",
        "<Paragraph Number=\"21\" Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text TagNumber=\"213\">Mara</Text><Text> waits.</Text></Paragraph>",
        "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. HALL - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>She waits.</Text></Paragraph>",
        "</Content>",
        "</FinalDraft>"
    ].joined(separator: "\n")

    /// The same file after Final Draft omitted the yard: the card holds the
    /// number, the scene sits inside it.
    private static let omitted = [
        "<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"5\">",
        "<Content>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>The kettle screams.</Text></Paragraph>",
        "<Paragraph Number=\"21\" Type=\"Scene Heading\"><Text>OMITTED</Text><OmittedScene>",
        "<Paragraph Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text TagNumber=\"213\">Mara</Text><Text> waits.</Text></Paragraph>",
        "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
        "</OmittedScene></Paragraph>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. HALL - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>She waits.</Text></Paragraph>",
        "</Content>",
        "</FinalDraft>"
    ].joined(separator: "\n")

    private static let sample02: String = {
        (try? String(
            contentsOf: FixtureStore.directory.appendingPathComponent("finaldraft-sample02.fdx"),
            encoding: .utf8
        )) ?? ""
    }()

    private static func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    /// The script as the app holds it: carried through Fountain and read
    /// back, which is what the app's own save compares against.
    private static func fountainReading(_ xml: String) throws -> Screenplay {
        try Fountain.parse(Fountain.serialise(Fdx.parse(xml).script), emphasis: .runs)
    }

    /// The yard omitted by hand: an OMITTED card carrying its number in front
    /// of its heading, and the span behind it.
    private static func omittingTheYard(_ script: Screenplay) -> Screenplay {
        var script = script
        let heading = script.elements.firstIndex { $0.text == "EXT. THE YARD - DUSK" }!
        script.elements.insert(ScreenplayElement(type: .scene, text: "OMITTED", sceneNumber: "21"), at: heading)
        script.omissions = [Omission(start: heading + 1, end: heading + 4)]
        return script
    }

    @Test("Omit: a scene the writer omitted is written inside its card, not live")
    func omitNestsTheScene() throws {
        let reading = Fdx.parse(Self.live).script
        let saved = Self.omittingTheYard(reading)
        let xml = Fdx.open(Self.live).rewrite(saved, unedited: reading)
        let back = Fdx.parse(xml).script
        #expect(back.omissions == saved.omissions)
        #expect(back.elements.map(\.text) == saved.elements.map(\.text))
        #expect(Self.count("<OmittedScene>", in: xml) == 1)
        // Written once, inside the block — never also as a live paragraph.
        #expect(Self.count("EXT. THE YARD - DUSK", in: xml) == 1)
        guard let open = xml.range(of: "<OmittedScene>"), let close = xml.range(of: "</OmittedScene>"),
              let body = xml.range(of: "EXT. THE YARD - DUSK"), let card = xml.range(of: ">OMITTED<")
        else { Issue.record("no block"); return }
        #expect(card.lowerBound < open.lowerBound)
        #expect(body.lowerBound > open.upperBound && body.upperBound < close.lowerBound)
    }

    /// The bytes both ports write — the same literal is asserted in
    /// `fdx.test.ts`, so the two engines cannot drift apart on either verb.
    static let omittedByTheWriter = [
        "<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"5\">",
        "<Content>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>The kettle screams.</Text></Paragraph>",
        "<Paragraph Type=\"Scene Heading\" Number=\"21\"><Text>OMITTED</Text><OmittedScene>",
        "<Paragraph Number=\"21\" Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text TagNumber=\"213\">Mara</Text><Text> waits.</Text></Paragraph>",
        "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
        "</OmittedScene></Paragraph>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. HALL - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>She waits.</Text></Paragraph>",
        "</Content>",
        "</FinalDraft>"
    ].joined(separator: "\n")

    static let restoredByTheWriter = [
        "<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"5\">",
        "<Content>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>The kettle screams.</Text></Paragraph>",
        "<Paragraph Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text TagNumber=\"213\">Mara</Text><Text> waits.</Text></Paragraph>",
        "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
        "<Paragraph Type=\"Scene Heading\"><Text>INT. HALL - NIGHT</Text></Paragraph>",
        "<Paragraph Type=\"Action\"><Text>She waits.</Text></Paragraph>",
        "</Content>",
        "</FinalDraft>"
    ].joined(separator: "\n")

    @Test("Both ports write the same bytes for an omit and for a restore")
    func crossPortBytes() {
        let live = Fdx.parse(Self.live).script
        #expect(Fdx.open(Self.live).rewrite(Self.omittingTheYard(live), unedited: live) == Self.omittedByTheWriter)
        let omitted = Fdx.parse(Self.omitted).script
        var restored = omitted
        restored.elements.remove(at: restored.elements.firstIndex { $0.text == "OMITTED" }!)
        restored.omissions = []
        #expect(Fdx.open(Self.omitted).rewrite(restored, unedited: omitted) == Self.restoredByTheWriter)
    }

    @Test("Omit: each line of the omitted scene keeps the bytes it had live")
    func omitKeepsTheBytes() {
        let reading = Fdx.parse(Self.live).script
        let xml = Fdx.open(Self.live).rewrite(Self.omittingTheYard(reading), unedited: reading)
        for line in [
            "<Paragraph Number=\"21\" Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>",
            "<Paragraph Type=\"Action\"><Text TagNumber=\"213\">Mara</Text><Text> waits.</Text></Paragraph>",
            "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
            // And the scenes around it are untouched.
            "<Paragraph Type=\"Scene Heading\"><Text>INT. HALL - NIGHT</Text></Paragraph>",
            "<Paragraph Type=\"Action\"><Text>The kettle screams.</Text></Paragraph>"
        ] {
            #expect(xml.contains(line), "lost: \(line)")
        }
    }

    @Test("Restore: a scene the writer restored comes out of its card, bytes and tags kept")
    func restoreUnwrapsTheScene() {
        let reading = Fdx.parse(Self.omitted).script
        var saved = reading
        let card = saved.elements.firstIndex { $0.text == "OMITTED" }!
        saved.elements.remove(at: card)
        saved.omissions = []
        let xml = Fdx.open(Self.omitted).rewrite(saved, unedited: reading)
        let back = Fdx.parse(xml).script
        #expect(back.omissions == nil)
        #expect(back.elements.map(\.text) == saved.elements.map(\.text))
        #expect(!xml.contains("<OmittedScene"))
        #expect(!xml.contains("OMITTED"))
        #expect(xml.contains("<Paragraph Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>"))
        #expect(xml.contains("<Paragraph Type=\"Action\"><Text TagNumber=\"213\">Mara</Text><Text> waits.</Text></Paragraph>"))
    }

    @Test("Restore: a heading given its card's number gains Number and keeps its tags")
    func restoreCarriesTheNumber() {
        let reading = Fdx.parse(Self.omitted).script
        var saved = reading
        saved.elements.remove(at: saved.elements.firstIndex { $0.text == "OMITTED" }!)
        saved.omissions = []
        let heading = saved.elements.firstIndex { $0.text == "EXT. THE YARD - DUSK" }!
        saved.elements[heading].sceneNumber = "21"
        let xml = Fdx.open(Self.omitted).rewrite(saved, unedited: reading)
        #expect(xml.contains("<Paragraph Number=\"21\" Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>"))
        #expect(Fdx.parse(xml).script.elements[heading].sceneNumber == "21")
    }

    /// The scene-number half of the fix, on its own — no omission in sight.
    /// Before it, a renumbered heading saved with the file's old number,
    /// and through Fountain lost its tags as well.
    @Test("A renumbered heading's new Number is written, and its tags are kept")
    func renumberedHeadingKeepsItsTags() throws {
        let reading = try Self.fountainReading(Self.live)
        var edited = reading
        let heading = edited.elements.firstIndex { $0.text == "EXT. THE YARD - DUSK" }!
        edited.elements[heading].sceneNumber = "21A"
        let xml = Fdx.open(Self.live).rewrite(edited, unedited: reading)
        #expect(xml.contains("<Paragraph Number=\"21A\" Type=\"Scene Heading\"><Text TagNumber=\"317\">EXT. THE YARD - DUSK</Text></Paragraph>"))
        #expect(Fdx.parse(xml).script.elements[heading].sceneNumber == "21A")
    }

    @Test("Nil omissions leave the file's structure deciding, exactly as before")
    func nilIsTheFilesWord() throws {
        let reading = Fdx.parse(Self.omitted).script
        var carried = reading
        carried.omissions = nil
        #expect(Fdx.open(Self.omitted).rewrite(carried, unedited: reading) == Self.omitted)
        // Said explicitly, the same omissions write the same bytes.
        #expect(Fdx.open(Self.omitted).rewrite(reading, unedited: reading) == Self.omitted)
    }

    /// Final Draft's dual dialogue: a paragraph with no text of its own
    /// holding a <DualDialogue> of two speeches.
    private static let dual = "<Paragraph Type=\"General\"><DualDialogue>"
        + "<Paragraph Type=\"Character\"><Text>MARA</Text></Paragraph>"
        + "<Paragraph Type=\"Dialogue\"><Text TagNumber=\"5\">Now.</Text></Paragraph>"
        + "<Paragraph Type=\"Character\"><Text>TOM</Text></Paragraph>"
        + "<Paragraph Type=\"Dialogue\"><Text>Not yet.</Text></Paragraph>"
        + "</DualDialogue></Paragraph>"

    private static let omittedWithDual = omitted.replacingOccurrences(
        of: "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
        with: dual + "\n<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>"
    )
    private static let liveWithDual = live.replacingOccurrences(
        of: "<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>",
        with: dual + "\n<Paragraph Type=\"Transition\"><Text>Cut to:</Text></Paragraph>"
    )

    @Test("An omitted scene's dual dialogue is read as its lines, not lost")
    func dualInsideAnOmissionIsRead() {
        let script = Fdx.parse(Self.omittedWithDual).script
        let omission = try? #require(script.omissions?.first)
        let body = omission.map { Array(script.elements[$0.start..<$0.end]) } ?? []
        #expect(body.map(\.text) == ["EXT. THE YARD - DUSK", "Mara waits.", "MARA", "Now.", "TOM", "Not yet.", "Cut to:"])
        #expect(body.first { $0.text == "TOM" }?.dual == true)
        #expect(body.first { $0.text == "Now." }?.runs?.first?.tagNumbers == [5])
        // And a save that changes nothing still writes the file's own bytes.
        #expect(Fdx.open(Self.omittedWithDual).rewrite(script, unedited: script) == Self.omittedWithDual)
    }

    @Test("Restore: a dual dialogue comes out of the card whole — its frame and its bytes")
    func restoreKeepsDualDialogue() {
        let reading = Fdx.parse(Self.omittedWithDual).script
        var saved = reading
        saved.elements.remove(at: saved.elements.firstIndex { $0.text == "OMITTED" }!)
        saved.omissions = []
        let xml = Fdx.open(Self.omittedWithDual).rewrite(saved, unedited: reading)
        #expect(!xml.contains("<OmittedScene"))
        #expect(xml.contains(Self.dual), "the block, byte for byte")
        #expect(Fdx.parse(xml).script.elements.map(\.text) == saved.elements.map(\.text))
    }

    @Test("Omit: a scene holding dual dialogue is nested whole and reads back whole")
    func omitKeepsDualDialogue() {
        let reading = Fdx.parse(Self.liveWithDual).script
        let heading = reading.elements.firstIndex { $0.text == "EXT. THE YARD - DUSK" }!
        var saved = reading
        saved.elements.insert(ScreenplayElement(type: .scene, text: "OMITTED", sceneNumber: "21"), at: heading)
        let end = saved.elements.firstIndex { $0.text == "INT. HALL - NIGHT" }!
        saved.omissions = [Omission(start: heading + 1, end: end)]
        let xml = Fdx.open(Self.liveWithDual).rewrite(saved, unedited: reading)
        #expect(xml.contains(Self.dual))
        let back = Fdx.parse(xml).script
        #expect(back.omissions == saved.omissions)
        #expect(back.elements.map(\.text) == saved.elements.map(\.text))
        #expect(back.elements.first { $0.text == "TOM" }?.dual == true)
    }

    @Test("The real file: the file's own omission, said explicitly through Fountain, saves byte for byte")
    func realFileExplicitIsIdentical() throws {
        let parsed = Fdx.parse(Self.sample02).script
        var reading = try Self.fountainReading(Self.sample02)
        #expect(reading.elements.count == parsed.elements.count)
        reading.omissions = parsed.omissions
        #expect(Fdx.open(Self.sample02).rewrite(reading, unedited: reading) == Self.sample02)
    }

    @Test("The real file: restore → save → omit again → save — the same scene omitted, every tag kept")
    func realFileRestoreAndBack() throws {
        let parsed = Fdx.parse(Self.sample02).script
        let omission = try #require(parsed.omissions?.first)
        let reading = try Self.fountainReading(Self.sample02)
        let tags = Self.count("TagNumber=", in: Self.sample02)

        var restored = reading
        let card = restored.elements.remove(at: omission.start - 1)
        restored.omissions = []
        let saved = Fdx.open(Self.sample02).rewrite(restored, unedited: reading)
        #expect(!saved.contains("<OmittedScene"))
        #expect(Fdx.parse(saved).script.omissions == nil)
        #expect(Self.count("TagNumber=", in: saved) == tags)
        #expect(Fdx.parse(saved).script.elements.count == parsed.elements.count - 1)

        // And the writer changes their mind: the same card, the same span.
        var again = try Self.fountainReading(saved)
        again.elements.insert(card, at: omission.start - 1)
        again.omissions = [omission]
        let back = Fdx.open(saved).rewrite(again, unedited: try Self.fountainReading(saved))
        #expect(Fdx.parse(back).script.omissions == [omission])
        #expect(Self.count("TagNumber=", in: back) == tags)
        /* The file's own words throughout; the card, written fresh, in the
           capitals a scene heading takes on the way through Fountain. */
        var expected = parsed.elements.map(\.text)
        expected[omission.start - 1] = expected[omission.start - 1].uppercased()
        #expect(Fdx.parse(back).script.elements.map(\.text) == expected)
    }

    @Test("The real file: omitting a live scene nests it, every tag kept, the rest untouched")
    func realFileOmitALiveScene() throws {
        let parsed = Fdx.parse(Self.sample02).script
        let existing = try #require(parsed.omissions?.first)
        var reading = try Self.fountainReading(Self.sample02)
        /* The first live scene after the file's own omission. */
        let heading = try #require(reading.elements.indices.first { $0 > existing.end && reading.elements[$0].type == .scene })
        let next = reading.elements.indices.first { $0 > heading && reading.elements[$0].type == .scene } ?? reading.elements.count
        let unedited = reading
        reading.elements.insert(
            ScreenplayElement(type: .scene, text: "OMITTED", sceneNumber: reading.elements[heading].sceneNumber),
            at: heading
        )
        reading.omissions = [existing, Omission(start: heading + 1, end: next + 1)]
        let xml = Fdx.open(Self.sample02).rewrite(reading, unedited: unedited)
        let back = Fdx.parse(xml).script
        #expect(back.omissions == reading.omissions)
        /* Every line the writer did not touch comes back in the file's own
           words — not the Fountain reading's canonical casing — and the one
           new line is the card. */
        var expected = parsed.elements.map(\.text)
        expected.insert("OMITTED", at: heading)
        #expect(back.elements.map(\.text) == expected)
        #expect(Self.count("<OmittedScene>", in: xml) == 2)
        #expect(Self.count("TagNumber=", in: xml) == Self.count("TagNumber=", in: Self.sample02))
    }
}
