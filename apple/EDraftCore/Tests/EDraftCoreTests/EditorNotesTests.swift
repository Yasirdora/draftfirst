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

    /// A note left on a speech line sits in front of it, inside the dialogue
    /// block. Written as its own paragraph there, it ended the block, and the
    /// next open read the cue and the speech as Action (IL-0040).
    func testANoteOnASpeechLineLeavesTheCueAndTheSpeechAsTheyWere() throws {
        for kind in [ScreenplayKind.dialogue, .parenthetical] {
            let editor = editor("INT. LAB - DAY\n\nMARA\n(quietly)\nIt's the same lab.\n\nShe waits.")
            let line = try XCTUnwrap(editor.screenplay.elements.first { $0.type == kind })
            var published: String?
            editor.onSourceChange = { published = $0 }

            XCTAssertNotNil(editor.addNote("Same lab as scene 4?", to: line.id))
            editor.flushPendingWork()

            let reopened = EditorState(source: try XCTUnwrap(published))
            XCTAssertEqual(
                reopened.screenplay.elements.map(\.type),
                [.scene, .character, .parenthetical, .dialogue, .action],
                "a note on the \(kind) line broke the block"
            )
            XCTAssertEqual(reopened.notes.map(\.text), ["Same lab as scene 4?"])
            XCTAssertEqual(
                reopened.notes.first?.anchor,
                reopened.screenplay.elements.first { $0.type == kind }?.id,
                "the note left its line"
            )
        }
    }

    // MARK: - The name for notes (RFC-NOTES-SYSTEM §8, IL-0039)

    /// Runs `body` with no name for notes on this device, and puts back
    /// whatever was there.
    private func withNoName(_ body: () throws -> Void) rethrows {
        let keys = ["noteSignature", "noteRole", "signsNotes"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        try body()
    }

    /// No name is ever taken from the system — not the account's, not the
    /// computer's. A writer who has given none has none, and is asked.
    func testTheNameForNotesStartsEmptyAndNeverFromTheSystem() {
        withNoName {
            let editor = editor("INT. LAB - DAY\n\nShe waits.")
            XCTAssertEqual(editor.noteSignature, "")
            XCTAssertEqual(editor.signature, "")
            XCTAssertTrue(editor.needsNoteName)
            XCTAssertEqual(NoteIdentity.signature, "")
        }
    }

    func testTheNameGivenOnceSignsEveryNoteAfterIt() {
        withNoName {
            let editor = editor("INT. LAB - DAY\n\nShe waits.")
            editor.activeElementID = editor.screenplay.elements[1].id
            editor.setNoteIdentity(name: " Dana Reyes ", role: "Director")

            XCTAssertFalse(editor.needsNoteName)
            XCTAssertEqual(NoteIdentity.signature, "Dana Reyes (Director)")
            XCTAssertEqual(editor.addNote("Too flat?")?.text, "Dana Reyes (Director): Too flat?")
            XCTAssertEqual(editor.addNote("And this.")?.text, "Dana Reyes (Director): And this.")
            // Kept on this device: the next document knows it.
            XCTAssertFalse(EditorState(source: "INT. LAB - DAY").needsNoteName)
        }
    }

    /// `Name (Role)` is an author (D4), and the person is the name: their
    /// colour does not change when their role does.
    func testARoleSignsANoteButTheNameIsThePerson() {
        XCTAssertEqual(NoteAttribution.candidate(in: "Dana Reyes (Director): Too flat?")?.name, "Dana Reyes (Director)")
        XCTAssertEqual(NoteAttribution.person(of: "Dana Reyes (Director)"), "Dana Reyes")
        XCTAssertNil(NoteAttribution.candidate(in: "Dana (: nothing"))
        let roster = NoteAttribution.roster(
            of: ["Dana Reyes (Director): One.", "Dana Reyes (Producer): Two."], signature: nil
        )
        XCTAssertEqual(roster.count, 1, "one person, two roles, became two people")
        XCTAssertEqual(NoteAttribution.author(of: "Dana Reyes (Producer): Two.", roster: roster)?.body, "Two.")
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
