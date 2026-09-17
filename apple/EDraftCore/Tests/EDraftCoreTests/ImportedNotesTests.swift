import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// A Final Draft file's notes, beside the writer's own.
///
/// Shown, coloured by who wrote them, and never written: the file already
/// keeps them, and a save that wrote them again would put every one in twice.
@MainActor
final class ImportedNotesTests: XCTestCase {

    // MARK: - Fixtures

    /// A real feature, anonymised — the engine's own fixture — with eleven
    /// notes by two writers.
    private func feature() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/sample0-2.fdx"))
    }

    /// The document as an app opens it: Fountain for the editor, the file kept.
    private func opened(_ data: Data) throws -> (editor: EditorState, source: String, origin: String) {
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let origin = try XCTUnwrap(file.origin)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: origin)
        return (editor, file.source, origin)
    }

    /// A small Final Draft file: body paragraphs, and ScriptNotes written raw.
    private func finalDraft(_ paragraphs: [(type: String, text: String)], notes: [String]) -> Data {
        let body = paragraphs
            .map { "<Paragraph Type=\"\($0.type)\"><Text>\($0.text)</Text></Paragraph>" }
            .joined(separator: "\n")
        return Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        \(body)
        </Content>
        <ScriptNotes>\(notes.joined())</ScriptNotes>
        </FinalDraft>
        """.utf8)
    }

    private func scriptNotesBlock(_ xml: String) -> Substring? {
        guard let start = xml.range(of: "<ScriptNotes>"),
              let end = xml.range(of: "</ScriptNotes>") else { return nil }
        return xml[start.lowerBound..<end.upperBound]
    }

    // MARK: - Arriving

    func testAFinalDraftFilesNotesArriveOnTheLinesTheyAreAbout() throws {
        let (editor, _, origin) = try opened(try feature())
        let notes = editor.importedNotes
        XCTAssertEqual(notes.count, 11)
        XCTAssertEqual(notes.filter { $0.author == "Writer A" }.count, 8)
        XCTAssertEqual(notes.filter { $0.author == "Writer B" }.count, 3)

        // Every note lands, on a line that prints, eight lines in all.
        let page = Set(editor.screenplay.elements.map(\.id))
        let anchors = notes.compactMap(\.anchor)
        XCTAssertEqual(anchors.count, 11, "a note of the feature's lost its line")
        XCTAssertTrue(anchors.allSatisfy(page.contains))
        XCTAssertEqual(Set(anchors).count, 8)

        // And the line is the one the file's Range is about: the same index,
        // the same words.
        let document = ScriptAsides.merge(page: editor.screenplay.elements, asides: editor.asides)
        let file = Fdx.parse(origin)
        for (note, read) in zip(notes, file.scriptNotes) {
            let index = try XCTUnwrap(read.anchor?.start.element)
            XCTAssertEqual(note.anchor, document[index].id)
            XCTAssertEqual(note.text, read.text)
        }
    }

    /// A file Final Draft itself wrote, whose notes' Ranges were measured on
    /// exactly its paragraphs — past six dual dialogues and an omitted scene,
    /// each of which a Range counts as two units. Counted as none, the notes
    /// after them sat on the lines below the ones they are about, and the last
    /// fell past the end of the script and had no line at all.
    func testNotesPastDualDialogueAndAnOmittedSceneLandOnTheirOwnLines() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/finaldraft-sample02.fdx"))
        let (editor, _, _) = try opened(data)
        let document = ScriptAsides.merge(page: editor.screenplay.elements, asides: editor.asides)
        let notes = editor.importedNotes
        XCTAssertEqual(notes.count, 11)
        XCTAssertEqual(notes.compactMap(\.anchor).count, 11, "a note has no line")

        func line(_ note: Int) throws -> ScriptElement {
            let id = try XCTUnwrap(notes[note].anchor, "note \(note) has no line")
            return try XCTUnwrap(document.first { $0.id == id })
        }
        // One whole action line, after five dual dialogues.
        XCTAssertEqual(try line(7).type, .action)
        XCTAssertEqual(try line(7).text.utf16.count, 41)
        // One whole line of dialogue.
        XCTAssertEqual(try line(8).type, .dialogue)
        XCTAssertEqual(try line(8).text.utf16.count, 6)
        // A cue, after the omitted scene too.
        XCTAssertEqual(try line(9).type, .character)
        // The script's last line.
        XCTAssertEqual(try line(10).id, document.last?.id)
    }

    func testANoteKeepsItsTitleCategoryAndDate() throws {
        let (editor, _, _) = try opened(try feature())
        let thread = try XCTUnwrap(editor.importedNotes.first { $0.title == "Re: Re: Xxxx Xxx" })
        XCTAssertEqual(thread.category, "Producer")
        let created = try XCTUnwrap(thread.created)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: created)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2020, 12, 14, 0, 51])
    }

    // MARK: - Never guessed

    func testALineWhoseWordsDisagreeIsNeverGuessed() throws {
        let note = #"<ScriptNote Id="1" Range="15,25" WriterName="Dir"><Paragraph><Text>Why is she waiting?</Text></Paragraph></ScriptNote>"#
        let data = finalDraft([("Scene Heading", "INT. LAB - DAY"), ("Action", "She waits.")], notes: [note])
        let origin = String(decoding: data, as: UTF8.self)

        // The editor holds the file's own lines: the note is on the action.
        let (matching, _, _) = try opened(data)
        XCTAssertEqual(matching.importedNotes.first?.anchor, matching.screenplay.elements[1].id)

        // The editor holds different words at that place: kept, but on no line.
        let drifted = EditorState(source: "INT. LAB - DAY\n\nShe leaves.")
        drifted.attachImportedNotes(from: origin)
        XCTAssertEqual(drifted.importedNotes.map(\.text), ["Why is she waiting?"])
        XCTAssertNil(drifted.importedNotes.first?.anchor, "a note was put on a line it is not about")
    }

    func testANoteOnALineThatDoesNotPrintBelongsToTheNextOneThatDoes() throws {
        // "Check the lab" is a Final Draft Note paragraph — beside the page —
        // and the Range points at it.
        let note = #"<ScriptNote Id="1" Range="15,28" WriterName="Dir"><Paragraph><Text>Which lab?</Text></Paragraph></ScriptNote>"#
        let data = finalDraft(
            [("Scene Heading", "INT. LAB - DAY"), ("Note", "Check the lab"), ("Action", "She waits.")],
            notes: [note]
        )
        let (editor, _, _) = try opened(data)
        XCTAssertEqual(editor.importedNotes.first?.anchor, editor.screenplay.elements[1].id)
        XCTAssertEqual(editor.screenplay.elements[1].text, "She waits.")
    }

    // MARK: - Who wrote it

    func testEveryWriterTheFileNamesIsAnAuthorAtOnce() throws {
        // One note is enough: the two-note rule guards against a TODO, and a
        // WriterName is a person by the file's word.
        let note = #"<ScriptNote Id="1" Range="0,4" WriterName="Dir"><Paragraph><Text>Faster.</Text></Paragraph></ScriptNote>"#
        let (editor, _, _) = try opened(finalDraft([("Action", "She waits.")], notes: [note]))
        XCTAssertEqual(editor.noteRoster, ["Dir"])
    }

    func testOnePersonIsOneNameWhicheverAppTheirNoteWasLeftIn() throws {
        let note = #"<ScriptNote Id="1" Range="0,4" WriterName="Joe Jarvis"><Paragraph><Text>Faster.</Text></Paragraph></ScriptNote>"#
        let (editor, _, _) = try opened(finalDraft([("Action", "She waits."), ("Action", "He leaves.")], notes: [note]))
        editor.addNote("joe jarvis: tighter", to: editor.screenplay.elements[0].id)
        editor.addNote("joe jarvis: and here", to: editor.screenplay.elements[1].id)

        XCTAssertEqual(editor.noteRoster, ["Joe Jarvis"], "the file's spelling is the one shown")
        let slots = NoteAttribution.slots(for: editor.noteRoster)
        let own = try XCTUnwrap(NoteAttribution.author(of: editor.notes[0].text, roster: editor.noteRoster))
        let imported = try XCTUnwrap(ImportedNotes.author(of: editor.importedNotes[0], in: editor.noteRoster))
        XCTAssertEqual(slots[own.name], slots[imported])
    }

    func testANoteNobodySignedStaysUnattributed() throws {
        let note = ##"<ScriptNote Id="1" Range="0,4" Color="#6363A7A7EFEF"><Paragraph><Text>Faster.</Text></Paragraph></ScriptNote>"##
        let (editor, _, _) = try opened(finalDraft([("Action", "She waits.")], notes: [note]))
        XCTAssertNil(editor.importedNotes.first?.author)
        XCTAssertTrue(editor.noteRoster.isEmpty, "a colour in the file is not a person")
    }

    // MARK: - Never written

    func testAnImportedNoteCannotBeEditedOrDeleted() throws {
        let (editor, _, _) = try opened(try feature())
        let before = editor.importedNotes
        let own = editor.notes
        let id = try XCTUnwrap(before.first?.id)

        editor.updateNote(id: id, text: "rewritten")
        editor.finishNote(id: id, text: "")
        editor.deleteNote(id: id)

        XCTAssertEqual(editor.importedNotes, before)
        XCTAssertEqual(editor.notes, own, "an imported note reached the writer's own notes")
    }

    func testSavingNeverWritesAnImportedNote() throws {
        let data = try feature()
        let (editor, source, origin) = try opened(data)
        var published: String?
        editor.onSourceChange = { published = $0 }

        // No edit: the file, to the byte.
        editor.flushPendingWork()
        let unedited = try ScreenplayFile.encode(
            published ?? source, as: .finalDraftScreenplay, origin: origin
        )
        XCTAssertEqual(unedited, data, "a save with the notes attached changed the file")

        // The writer's own notes, added, edited and deleted, and the script
        // edited: the file's notes are untouched, and none of their words
        // reached the source.
        let line = editor.screenplay.elements[40].id
        let kept = try XCTUnwrap(editor.addNote("A note of my own.", to: line))
        let gone = try XCTUnwrap(editor.addNote("Soon gone.", to: line))
        editor.updateNote(id: kept.id, text: "A note of my own, revised.")
        editor.deleteNote(id: gone.id)
        editor.flushPendingWork()
        let saved = try XCTUnwrap(published)
        for note in editor.importedNotes where note.text.count > 40 {
            XCTAssertFalse(saved.contains(note.text), "an imported note reached the source")
        }
        XCTAssertTrue(saved.contains("A note of my own, revised."))

        let edited = saved.replacingOccurrences(
            of: "\n.XXX. XXXXXXXX - XX\n\n= Xx'xx xxxx xxxxx xxx xxxx xx.",
            with: "\n.XXX. XXXXXXXX - XXX\n\n= Xx'xx xxxx xxxxx xxx xxxx xx."
        )
        XCTAssertNotEqual(edited, saved, "the script edit did not apply")
        let written = String(decoding: try ScreenplayFile.encode(
            edited, as: .finalDraftScreenplay, origin: origin
        ), as: UTF8.self)
        XCTAssertEqual(scriptNotesBlock(written), scriptNotesBlock(origin))
        XCTAssertTrue(written.contains("A note of my own, revised."))
    }

    // MARK: - Not from Final Draft

    func testADocumentThatDidNotComeFromFinalDraftCarriesNone() {
        let editor = EditorState(source: "INT. LAB - DAY\n\n[[Dir: too slow]]\n\nShe waits.\n\n[[Dir: again]]\n\nHe leaves.")
        let roster = editor.noteRoster
        editor.attachImportedNotes(from: nil)
        XCTAssertTrue(editor.importedNotes.isEmpty)
        XCTAssertEqual(editor.noteRoster, roster)
        XCTAssertEqual(roster, NoteAttribution.roster(of: editor.notes.map(\.text)))
    }
}
