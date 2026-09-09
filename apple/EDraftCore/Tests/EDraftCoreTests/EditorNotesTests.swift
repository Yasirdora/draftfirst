import XCTest
@testable import EDraftCore

/// A note is in the document and not on the page.
///
/// Both halves matter: the writer must not read their own private aside as a
/// stage direction, and they must not lose it by saving.
@MainActor
final class EditorNotesTests: XCTestCase {

    private func editor(_ source: String) -> EditorState {
        EditorState(source: source)
    }

    func testANoteInTheSourceIsLiftedOffThePage() {
        let editor = editor("INT. LAB - DAY\n\n[[Same lab as scene 4?]]\n\nShe waits.")

        XCTAssertEqual(editor.screenplay.elements.map(\.type), [.scene, .action])
        XCTAssertEqual(editor.notes.map(\.text), ["Same lab as scene 4?"])
        XCTAssertEqual(
            editor.notes.first?.anchor,
            editor.screenplay.elements.last?.id,
            "the note belongs to the line under it"
        )
    }

    /// The page is what gets measured. A note that paginated would push the
    /// script a line down and lie about the running time.
    func testANoteDoesNotOccupyALineOfThePage() {
        let withNote = editor("INT. LAB - DAY\n\n[[A long note about the lighting here.]]\n\nShe waits.")
        let without = editor("INT. LAB - DAY\n\nShe waits.")
        XCTAssertEqual(withNote.screenplay.elements.count, without.screenplay.elements.count)
    }

    func testANoteGoesBackIntoTheSavedSource() {
        let source = "INT. LAB - DAY\n\n[[Same lab as scene 4?]]\n\nShe waits."
        let editor = editor(source)
        var published: String?
        editor.onSourceChange = { published = $0 }
        editor.flushPendingWork()

        let saved = try? XCTUnwrap(published)
        XCTAssertNotNil(saved)
        XCTAssertTrue(saved?.contains("[[Same lab as scene 4?]]") == true, "the note was not saved")
    }

    func testAddingANoteAnchorsItToTheCaretsElement() {
        let editor = editor("INT. LAB - DAY\n\nShe waits.")
        let action = editor.screenplay.elements[1]
        editor.activeElementID = action.id

        let note = editor.addNote("Is she waiting for him or for it?")

        XCTAssertEqual(note?.anchor, action.id)
        XCTAssertEqual(editor.notes.count, 1)
        XCTAssertEqual(editor.screenplay.elements.count, 2, "the note landed on the page")
    }

    func testEditingANoteKeepsItsPlaceAndItsIdentity() {
        let editor = editor("INT. LAB - DAY\n\nShe waits.")
        editor.activeElementID = editor.screenplay.elements[1].id
        let note = editor.addNote("First thought.")

        editor.updateNote(id: try! XCTUnwrap(note).id, text: "Second thought.")

        XCTAssertEqual(editor.notes.map(\.text), ["Second thought."])
        XCTAssertEqual(editor.notes.first?.id, note?.id, "editing a note replaced it")
        XCTAssertEqual(editor.notes.first?.anchor, note?.anchor)
    }

    func testDeletingANoteRemovesItFromTheDocument() {
        let editor = editor("INT. LAB - DAY\n\n[[Delete me.]]\n\nShe waits.")
        let note = try! XCTUnwrap(editor.notes.first)

        editor.deleteNote(id: note.id)

        XCTAssertTrue(editor.notes.isEmpty)
        var published: String?
        editor.onSourceChange = { published = $0 }
        editor.flushPendingWork()
        XCTAssertFalse(published?.contains("Delete me.") == true)
    }

    func testUndoBringsADeletedNoteBack() {
        let editor = editor("INT. LAB - DAY\n\n[[Keep me.]]\n\nShe waits.")
        editor.deleteNote(id: try! XCTUnwrap(editor.notes.first).id)
        XCTAssertTrue(editor.notes.isEmpty)

        editor.undo()

        XCTAssertEqual(editor.notes.map(\.text), ["Keep me."])
    }

    /// Two notes on the same line read top to bottom in the order they were
    /// left, which is the order the source has them in.
    func testASecondNoteOnTheSameLineFollowsTheFirst() {
        let editor = editor("INT. LAB - DAY\n\nShe waits.")
        editor.activeElementID = editor.screenplay.elements[1].id
        editor.addNote("First.")
        editor.addNote("Second.")

        XCTAssertEqual(editor.notes.map(\.text), ["First.", "Second."])
        var published: String?
        editor.onSourceChange = { published = $0 }
        editor.flushPendingWork()
        let saved = published ?? ""
        XCTAssertTrue(
            saved.range(of: "[[First.]]")!.lowerBound < saved.range(of: "[[Second.]]")!.lowerBound
        )
    }

    /// A note nobody wrote in is not a note. Pages drops a comment left
    /// blank; an empty `[[]]` in a Fountain file is litter for whoever opens
    /// it next.
    func testANoteLeftBlankIsDiscardedWhenTheWriterIsDoneWithIt() {
        let editor = editor("INT. LAB - DAY\n\nShe waits.")
        editor.activeElementID = editor.screenplay.elements[1].id
        let note = try! XCTUnwrap(editor.addNote())
        XCTAssertEqual(editor.notes.count, 1, "the note has to exist to be typed into")

        editor.finishNote(id: note.id, text: nil)

        XCTAssertTrue(editor.notes.isEmpty, "an untouched empty note survived")
    }

    func testANoteEmptiedAndFinishedIsDiscarded() {
        let editor = editor("INT. LAB - DAY\n\n[[Delete me by emptying me.]]\n\nShe waits.")
        let note = try! XCTUnwrap(editor.notes.first)

        editor.finishNote(id: note.id, text: "   \n  ")

        XCTAssertTrue(editor.notes.isEmpty)
    }

    func testFinishingANoteWithWordsInItKeepsIt() {
        let editor = editor("INT. LAB - DAY\n\n[[First thought.]]\n\nShe waits.")
        let note = try! XCTUnwrap(editor.notes.first)

        editor.finishNote(id: note.id, text: "Second thought.")

        XCTAssertEqual(editor.notes.map(\.text), ["Second thought."])
        XCTAssertEqual(editor.notes.first?.id, note.id)
    }

    /// Closing a card nobody typed in must not touch what is already there.
    func testFinishingAnUntouchedNoteLeavesItAlone() {
        let editor = editor("INT. LAB - DAY\n\n[[Leave me exactly as I am.]]\n\nShe waits.")
        let note = try! XCTUnwrap(editor.notes.first)

        editor.finishNote(id: note.id, text: nil)

        XCTAssertEqual(editor.notes.map(\.text), ["Leave me exactly as I am."])
    }

    /// A note left before the script's first line, and one after its last.
    func testNotesAtEitherEndSurviveTheRoundTrip() {
        let source = "[[Open colder.]]\n\nINT. LAB - DAY\n\nShe waits.\n\n[[End here?]]"
        let editor = editor(source)
        XCTAssertEqual(editor.notes.map(\.text), ["Open colder.", "End here?"])
        XCTAssertNil(editor.notes.last?.anchor, "a trailing note has nothing under it")

        var published: String?
        editor.onSourceChange = { published = $0 }
        editor.flushPendingWork()
        let saved = published ?? ""
        XCTAssertTrue(saved.contains("[[Open colder.]]"))
        XCTAssertTrue(saved.contains("[[End here?]]"))
    }
}
