import XCTest
import UniformTypeIdentifiers
@testable import EDraftCore

/// Saving a Final Draft file must not cost the writer what it carries.
///
/// `.fdx` is a writable type by design — an .fdx opened in place writes back
/// as FDX, never a read-only trap. That promise is only safe if the save edits
/// the file instead of rebuilding it from a screenplay, which cannot hold
/// revisions, locked pages, tags, or the arc beats nested in a scene heading.
@MainActor
final class FdxSaveBackTests: XCTestCase {

    private static let production = """
    <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
    <FinalDraft DocumentType="Script" Template="No" Version="6">
      <Content>
        <Paragraph Type="Scene Heading" Number="1">
          <SceneProperties Length="4/8" Page="1" Title="Set up Gold Key">
            <SceneArcBeats>
              <CharacterArcBeat Name="TANGLE">
                <Paragraph><Text>Tangle is obsessed with the treasure.</Text></Paragraph>
              </CharacterArcBeat>
            </SceneArcBeats>
          </SceneProperties>
          <Text>INT. HOME LIBRARY - DAY</Text>
        </Paragraph>
        <Paragraph Type="Action"><Text>Majestic.</Text></Paragraph>
        <Paragraph Type="Note"><Text>Is this the same library as scene 9?</Text></Paragraph>
      </Content>
      <LockedPages><LockedPage Number="1"/></LockedPages>
      <Revisions><Revision Color="Blue" Mark="*" Name="First Revision" Number="1"/></Revisions>
      <TagData><TagDefinition Id="t1" Label="Spanish moss"/></TagData>
    </FinalDraft>
    """

    private func opened() throws -> (source: String, origin: String?) {
        try ScreenplayFile.open(
            Data(Self.production.utf8), as: .finalDraftScreenplay
        )
    }

    func testOpeningKeepsTheOriginal() throws {
        let file = try opened()
        XCTAssertEqual(file.origin, Self.production)
        XCTAssertTrue(file.source.contains("INT. HOME LIBRARY - DAY"))
    }

    /// Opened and saved with no edit: the same file, to the byte.
    func testSavingWithoutEditingReturnsTheIdenticalFile() throws {
        let file = try opened()
        let written = try ScreenplayFile.encode(
            file.source, as: .finalDraftScreenplay, origin: file.origin
        )
        XCTAssertEqual(String(data: written, encoding: .utf8), Self.production)
    }

    /// The case that matters: a typo fixed on a locked script.
    func testEditingKeepsRevisionsLockedPagesAndTags() throws {
        let file = try opened()
        let edited = file.source.replacingOccurrences(of: "Majestic.", with: "Majestic, and lit.")
        let written = try ScreenplayFile.encode(
            edited, as: .finalDraftScreenplay, origin: file.origin
        )
        let xml = try XCTUnwrap(String(data: written, encoding: .utf8))

        XCTAssertTrue(xml.contains("Majestic, and lit."))
        XCTAssertTrue(xml.contains("<LockedPage"), "the locked pages were lost")
        XCTAssertTrue(xml.contains("<Revision"), "the revision history was lost")
        XCTAssertTrue(xml.contains("<TagDefinition"), "the production tags were lost")
        XCTAssertTrue(xml.contains("<CharacterArcBeat"), "the arc beats were lost")
    }

    /// A Final Draft Note is a line in the script that does not print, which
    /// is what Fountain's [[ ]] is — so it reaches the writer as a note rather
    /// than as a stage direction printed on the page, and goes home as one.
    func testANoteArrivesAsANoteAndGoesHomeAsOne() throws {
        let file = try opened()
        XCTAssertTrue(
            file.source.contains("[[Is this the same library as scene 9?]]"),
            "a Final Draft note did not survive the trip into the editor"
        )

        let edited = file.source.replacingOccurrences(
            of: "same library as scene 9", with: "same library as scene 12"
        )
        let written = try ScreenplayFile.encode(
            edited, as: .finalDraftScreenplay, origin: file.origin
        )
        let xml = try XCTUnwrap(String(data: written, encoding: .utf8))

        XCTAssertTrue(xml.contains("Type=\"Note\""), "the note stopped being a note")
        XCTAssertTrue(xml.contains("same library as scene 12"), "the edit was lost")
        XCTAssertFalse(xml.contains("Type=\"General\""), "the note was printed as General")
    }

    // MARK: - A Note that ends in ] (IL-0038)

    /// `open` carries an .fdx through Fountain, so a Note ending in `]` went
    /// to the editor as `]]]` and came back cut short, with a stray `]` Action
    /// paragraph that the next save — edited or not — wrote into the file.
    private static func withNote(_ note: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Template="No" Version="5">
          <Content>
            <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
            <Paragraph Type="Note"><Text>\(note)</Text></Paragraph>
            <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
          </Content>
        </FinalDraft>
        """
    }

    private static let bracketNotes = [
        "Dana: see [scene 4]", "see [[4]] later", "[eDraft thread:t4k9qz status:open]"
    ]

    /// Opened, published by the editor, and saved with no edit: the same file.
    func testANoteEndingInABracketSavesWithoutEditingToTheIdenticalFile() throws {
        for note in Self.bracketNotes {
            let original = Self.withNote(note)
            let file = try ScreenplayFile.open(Data(original.utf8), as: .finalDraftScreenplay)
            let editor = EditorState(source: file.source)
            var published: String?
            editor.onSourceChange = { published = $0 }
            editor.flushPendingWork()
            let written = try ScreenplayFile.encode(
                published ?? file.source, as: .finalDraftScreenplay, origin: file.origin
            )
            XCTAssertEqual(String(data: written, encoding: .utf8), original, "\(note)")
        }
    }

    /// An edit elsewhere changes its own line and leaves the note alone, with
    /// no paragraph added.
    func testAnEditBesideANoteEndingInABracketLeavesTheNoteAlone() throws {
        for note in Self.bracketNotes {
            let original = Self.withNote(note)
            let file = try ScreenplayFile.open(Data(original.utf8), as: .finalDraftScreenplay)
            let edited = file.source.replacingOccurrences(
                of: "The kettle screams.", with: "The kettle screams again."
            )
            let written = try ScreenplayFile.encode(
                edited, as: .finalDraftScreenplay, origin: file.origin
            )
            XCTAssertEqual(
                String(data: written, encoding: .utf8),
                original.replacingOccurrences(of: "The kettle screams.", with: "The kettle screams again."),
                "\(note)"
            )
        }
    }

    // MARK: - End of Act

    /// A real feature, anonymised — the engine's own fixture — with one End of
    /// Act card near its end. eDraft never shows an End of Act, so a save must
    /// never be what removes one: every save used to.
    private static func feature() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/sample0-2.fdx"))
    }

    /// Into the editor as Fountain and home again, with no edit: the feature
    /// to the byte, its End of Act card included.
    func testAFeatureSavedWithoutEditingKeepsItsEndOfAct() throws {
        let data = try Self.feature()
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Type=\"End of Act\" id="))
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let written = try ScreenplayFile.encode(
            file.source, as: .finalDraftScreenplay, origin: file.origin
        )
        XCTAssertEqual(written, data, "a save with no edit changed the file")
    }

    /// Editing the scene right after the card changes that line and nothing
    /// else — the card stays where it was, byte for byte.
    func testEditingBesideTheEndOfActChangesOnlyThatLine() throws {
        let data = try Self.feature()
        let original = String(decoding: data, as: UTF8.self)
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let heading = "\n.XXX. XXXXXXXX - XX\n\n= Xx'xx xxxx xxxxx xxx xxxx xx."
        XCTAssertEqual(file.source.components(separatedBy: heading).count, 2,
                       "the heading after the card must be found exactly once")

        let edited = file.source.replacingOccurrences(
            of: heading, with: "\n.XXX. XXXXXXXX - XXX\n\n= Xx'xx xxxx xxxxx xxx xxxx xx."
        )
        let written = try ScreenplayFile.encode(
            edited, as: .finalDraftScreenplay, origin: file.origin
        )
        XCTAssertEqual(
            String(decoding: written, as: UTF8.self),
            original.replacingOccurrences(
                of: "<Text>XXX. XXXXXXXX - XX</Text>", with: "<Text>XXX. XXXXXXXX - XXX</Text>"
            ),
            "the save changed more than the edited line"
        )
    }

    /// A card with no Alignment, typed General on the way in, was paired with
    /// the writer's next edit and given their words. Through the app's path:
    /// the edit stays an Action, and the card stays a card.
    func testACardNeverTakesTheWritersEdit() throws {
        let card = "<Paragraph Type=\"End of Act\"><Text>END OF ACT ONE</Text></Paragraph>"
        let xml = """
        <FinalDraft DocumentType="Script" Version="6"><Content>
        <Paragraph Type="New Act"><Text>ACT ONE</Text></Paragraph>
        \(card)
        <Paragraph Type="New Act"><Text>ACT TWO</Text></Paragraph>
        <Paragraph Type="Action" id="a2"><Text>Buzz.</Text></Paragraph>
        </Content></FinalDraft>
        """
        let file = try ScreenplayFile.open(Data(xml.utf8), as: .finalDraftScreenplay)
        let written = try ScreenplayFile.encode(
            file.source.replacingOccurrences(of: "Buzz.", with: "Buzz, buzz."),
            as: .finalDraftScreenplay, origin: file.origin
        )
        let saved = try XCTUnwrap(String(data: written, encoding: .utf8))

        XCTAssertTrue(saved.contains(card), "the End of Act card was lost")
        XCTAssertTrue(saved.contains("<Paragraph Type=\"Action\" id=\"a2\"><Text>Buzz, buzz.</Text></Paragraph>"))
        XCTAssertFalse(saved.contains("Type=\"End of Act\"><Text>Buzz"), "the writer's edit became an act card")
    }

    /// Without an original there is nothing to preserve, and a whole file is
    /// the right answer — exporting a screenplay that began life here.
    func testExportingWithoutAnOriginalWritesAWholeFile() throws {
        let written = try ScreenplayFile.encode(
            "INT. LAB - DAY\n\nShe waits.", as: .finalDraftScreenplay
        )
        let xml = try XCTUnwrap(String(data: written, encoding: .utf8))
        XCTAssertTrue(xml.contains("<FinalDraft"))
        XCTAssertTrue(xml.contains("INT. LAB - DAY"))
    }

    // MARK: - Files Final Draft wrote

    /// An anonymised copy of a file Final Draft itself wrote — still carrying
    /// its production tags, revision marks and Final Draft's own run splits,
    /// which is what a save through Fountain used to lose. The End of Act
    /// fixture above could not show it: an old eDraft save had stripped its
    /// tags before it ever became a fixture.
    private static func finalDraftWritten(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/\(name)"))
    }

    /// A file with every ScriptNote Range value emptied. A save rewrites the
    /// Range of each note whose words moved (IL-0033); a comparison of the
    /// script sets those values aside, and the notes' words are proven on
    /// their own (ImportedNotesTests).
    private static func withoutNoteRanges(_ xml: String) -> String {
        xml.replacingOccurrences(of: #"(<ScriptNote\b[^>]*?\sRange=")[^"]*(")"#, with: "$1$2", options: .regularExpression)
    }

    private static func tags(_ data: Data) -> Int {
        String(decoding: data, as: UTF8.self).components(separatedBy: "TagNumber=\"").count - 1
    }

    /// Opened, carried into the editor as Fountain, and saved with no edit:
    /// the file Final Draft wrote, to the byte, every tag still on it.
    func testFilesFinalDraftWroteSaveWithoutEditingToTheIdenticalFile() throws {
        for name in ["finaldraft-sample02.fdx", "finaldraft-sample01.fdx"] {
            let data = try Self.finalDraftWritten(name)
            let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
            let written = try ScreenplayFile.encode(file.source, as: .finalDraftScreenplay, origin: file.origin)
            XCTAssertEqual(written, data, "\(name): a save with no edit changed the file")
            XCTAssertEqual(Self.tags(written), Self.tags(data), "\(name): production tags were lost")
        }
    }

    /// The same through the editor the app actually uses: what it publishes
    /// for an unedited document saves back to the identical file.
    func testTheEditorsUneditedSourceSavesToTheIdenticalFile() throws {
        for name in ["finaldraft-sample02.fdx", "finaldraft-sample01.fdx"] {
            let data = try Self.finalDraftWritten(name)
            let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
            let editor = EditorState(source: file.source)
            var published: String?
            editor.onSourceChange = { published = $0 }
            editor.flushPendingWork()
            let written = try ScreenplayFile.encode(
                published ?? file.source, as: .finalDraftScreenplay, origin: file.origin
            )
            XCTAssertEqual(written, data, "\(name): the editor's unedited save changed the file")
        }
    }

    /// A line edited in the editor's Fountain changes that paragraph and
    /// nothing else; the 407 tags on the lines around it all survive.
    func testAnEditChangesOnlyItsParagraphAndEveryOtherTagSurvives() throws {
        let data = try Self.finalDraftWritten("finaldraft-sample02.fdx")
        let original = String(decoding: data, as: UTF8.self)
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let line = "Xxxxxxxx, xxxxx xxxxxxxx xxx xx."
        XCTAssertEqual(file.source.components(separatedBy: line).count, 2, "the edited line must be unique")

        let written = try ScreenplayFile.encode(
            file.source.replacingOccurrences(of: line, with: "Xxxxxxxx, xxxxx xxxxxxxx xxx xx, EDITED."),
            as: .finalDraftScreenplay, origin: file.origin
        )
        XCTAssertEqual(
            Self.withoutNoteRanges(String(decoding: written, as: UTF8.self)),
            Self.withoutNoteRanges(original).replacingOccurrences(of: "<Text>\(line)</Text>", with: "<Text>Xxxxxxxx, xxxxx xxxxxxxx xxx xx, EDITED.</Text>"),
            "the save changed more than the edited line"
        )
        XCTAssertEqual(Self.tags(written), Self.tags(data))
    }

    // MARK: - Edited paragraphs

    /// The file with its one `before` replaced.
    private static func file(_ data: Data, with before: String, as after: String) -> String {
        let original = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(original.components(separatedBy: before).count, 2, "\(before) must occur once")
        return original.replacingOccurrences(of: before, with: after)
    }

    /// Each measured edit, typed into the source the app opened: the save
    /// changes only the writer's characters. Before, each lost what Fountain
    /// cannot carry — tags, a heading's Type and scene data, the (beat)'s
    /// Parenthetical, a Summary's line break, a trailing space, an AllCaps
    /// word's stored letters.
    func testEachMeasuredEditChangesOnlyTheWritersCharacters() throws {
        let cases: [(name: String, file: String, find: String, replace: String, before: String, after: String)] = [
            ("E1", "finaldraft-sample02.fdx", "Xxxx XXXXXX, 12,", "Xyxx XXXXXX, 12,",
             "31a77a253272\">\n      <Text>Xxxx </Text>", "31a77a253272\">\n      <Text>Xyxx </Text>"),
            ("E2", "finaldraft-sample02.fdx", "***(X1)*** #2#", "***(X2)*** #2#",
             "TagNumber=\"603\">(X1)</Text>", "TagNumber=\"603\">(X2)</Text>"),
            ("E3", "finaldraft-sample02.fdx", "(*xx. xxxxx, xxx*)", "(*xx. xxxxx, xxx, xxxxx*)",
             "<Text Style=\"Italic\">xx. xxxxx, xxx</Text>", "<Text Style=\"Italic\">xx. xxxxx, xxx, xxxxx</Text>"),
            ("E3b", "finaldraft-sample02.fdx", "*...Xxx xxxxxxxx.*\n*(beat)*", "*...Xxx xxxxxxxx.*\n*(beat, xxxxx)*",
             "<Text Style=\"Italic\">(beat)</Text>", "<Text Style=\"Italic\">(beat, xxxxx)</Text>"),
            ("E4", "finaldraft-sample01.fdx", "\nX & X xxxx xxxx xxxxxxxx.\n", "\nX & X yxxx xxxx xxxxxxxx.\n",
             "xxxxx:\nX &amp; X xxxx xxxx xxxxxxxx.</Text>", "xxxxx:\nX &amp; X yxxx xxxx xxxxxxxx.</Text>"),
            ("E5", "finaldraft-sample01.fdx", "Xx xxx. Xxx... ", "Yx xxx. Xxx... ",
             "<Text>Xx xxx. Xxx... </Text>", "<Text>Yx xxx. Xxx... </Text>"),
            ("E6", "finaldraft-sample02.fdx", "XXXXXX xxxxx xxx xxxxx xxx xxxxxxx xxxxxx.", "XXXXXX yxxxx xxx xxxxx xxx xxxxxxx xxxxxx.",
             "<Text>xxxxx xxx </Text>", "<Text>yxxxx xxx </Text>"),
            ("E7", "finaldraft-sample02.fdx", "(D2) #4#", "(D3) #4#",
             "<Text TagNumber=\"617\">(d2)</Text>", "<Text TagNumber=\"617\">(d3)</Text>")
        ]
        for edit in cases {
            let data = try Self.finalDraftWritten(edit.file)
            let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
            XCTAssertEqual(file.source.components(separatedBy: edit.find).count, 2, "\(edit.name): the edit must occur once")
            let written = try ScreenplayFile.encode(
                file.source.replacingOccurrences(of: edit.find, with: edit.replace),
                as: .finalDraftScreenplay, origin: file.origin
            )
            XCTAssertEqual(Self.withoutNoteRanges(String(decoding: written, as: UTF8.self)), Self.withoutNoteRanges(Self.file(data, with: edit.before, as: edit.after)),
                           "\(edit.name): the save changed more than the writer's characters")
        }
    }

    /// The same through the editor itself: text replaced in an element, its
    /// emphasis carried by the editor's own rule, published and saved.
    func testAnEditInTheEditorChangesOnlyTheWritersCharacters() throws {
        let data = try Self.finalDraftWritten("finaldraft-sample02.fdx")
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        var published: String?
        editor.onSourceChange = { published = $0 }

        let beat = try XCTUnwrap(editor.screenplay.elements.first { $0.type == .dialogue && $0.text == "(beat)" })
        editor.replaceElementText(id: beat.id, text: "(beat, xxxxx)")
        let typo = try XCTUnwrap(editor.screenplay.elements.first { $0.text.hasPrefix("Xxxx XXXXXX, 12,") })
        editor.replaceElementText(id: typo.id, text: "Xyxx" + typo.text.dropFirst(4))
        editor.flushPendingWork()

        let written = try ScreenplayFile.encode(try XCTUnwrap(published), as: .finalDraftScreenplay, origin: file.origin)
        let expected = Self.file(
            Data(Self.file(data, with: "<Text Style=\"Italic\">(beat)</Text>", as: "<Text Style=\"Italic\">(beat, xxxxx)</Text>").utf8),
            with: "31a77a253272\">\n      <Text>Xxxx </Text>", as: "31a77a253272\">\n      <Text>Xyxx </Text>"
        )
        XCTAssertEqual(Self.withoutNoteRanges(String(decoding: written, as: UTF8.self)), Self.withoutNoteRanges(expected))
        XCTAssertEqual(Self.tags(written), Self.tags(data))
    }

    // MARK: - Dual dialogue

    /// Final Draft keeps dual dialogue as a paragraph with no text of its own
    /// holding a <DualDialogue>. Read as metadata, its speeches never reached
    /// the editor: each block was an empty line.
    func testDualDialogueFromFinalDraftIsInTheEditor() throws {
        let data = try Self.finalDraftWritten("finaldraft-sample02.fdx")
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        let elements = editor.screenplay.elements
        let dualCues = elements.indices.filter { elements[$0].dual == true }
        XCTAssertEqual(dualCues.count, 6)
        let first = try XCTUnwrap(dualCues.first)
        XCTAssertEqual(elements[(first - 2)...(first + 1)].map(\.type), [.character, .dialogue, .character, .dialogue])
        XCTAssertEqual(elements[(first - 2)...(first + 1)].map(\.text), ["XXXXX", "Xxx?", "XXXXXX", "Xxx."])
    }

    /// A line of a dual dialogue edited in the editor saves as that character,
    /// inside Final Draft's block; the block and every tag stay.
    func testADualDialogueLineEditedInTheEditorSavesAsThatCharacter() throws {
        let data = try Self.finalDraftWritten("finaldraft-sample02.fdx")
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        var published: String?
        editor.onSourceChange = { published = $0 }

        let cue = try XCTUnwrap(editor.screenplay.elements.firstIndex { $0.dual == true })
        let line = editor.screenplay.elements[cue + 1]
        XCTAssertEqual(line.text, "Xxx.")
        editor.replaceElementText(id: line.id, text: "Qxx.")
        editor.flushPendingWork()

        let written = try ScreenplayFile.encode(try XCTUnwrap(published), as: .finalDraftScreenplay, origin: file.origin)
        XCTAssertEqual(
            String(decoding: written, as: UTF8.self),
            Self.file(
                data,
                with: "id=\"2220856b-967a-4a2f-85da-74f9df596dbb\">\n          <Text>Xxx.</Text>",
                as: "id=\"2220856b-967a-4a2f-85da-74f9df596dbb\">\n          <Text>Qxx.</Text>"
            )
        )
        XCTAssertEqual(Self.tags(written), Self.tags(data))
    }
}
