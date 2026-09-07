import XCTest
@testable import EDraftCore

/// A note is in the document but not on the page, and the trip out and back
/// must not move it, duplicate it, or lose it.
final class ScriptNotesTests: XCTestCase {

    private func element(_ type: ScreenplayKind, _ text: String) -> ScriptElement {
        ScriptElement(type: type, text: text)
    }

    func testANoteComesOffThePageAnchoredToTheLineBelowIt() {
        let heading = element(.scene, "INT. LAB - DAY")
        let note = element(.note, "Same lab as scene 4?")
        let action = element(.action, "She waits.")
        let split = ScriptNotes.split([heading, note, action])

        XCTAssertEqual(split.page, [heading, action], "the note was left on the page")
        XCTAssertEqual(split.notes.count, 1)
        XCTAssertEqual(split.notes.first?.text, "Same lab as scene 4?")
        XCTAssertEqual(split.notes.first?.anchor, action.id, "the note belongs to the line under it")
    }

    /// Fountain writes `[[…]]` before the line it is about, and a writer who
    /// types two of them means both.
    func testTwoNotesOnTheSameLineKeepTheirOrder() {
        let action = element(.action, "She waits.")
        let first = element(.note, "First.")
        let second = element(.note, "Second.")
        let split = ScriptNotes.split([first, second, action])

        XCTAssertEqual(split.notes.map(\.text), ["First.", "Second."])
        XCTAssertEqual(split.notes.map(\.anchor), [action.id, action.id])
        XCTAssertEqual(ScriptNotes.merge(page: split.page, notes: split.notes), [first, second, action])
    }

    func testANoteAfterTheLastLineTrailsTheScript() {
        let action = element(.action, "She waits.")
        let note = element(.note, "End on this.")
        let split = ScriptNotes.split([action, note])

        XCTAssertNil(split.notes.first?.anchor, "a note with nothing under it has nothing to anchor to")
        XCTAssertEqual(ScriptNotes.merge(page: split.page, notes: split.notes), [action, note])
    }

    /// Sections and synopses are non-printing too. They stay on the page
    /// until they have somewhere of their own to be — see `ScriptNotes`.
    func testOnlyNotesComeOff() {
        let section = element(.section, "Act One")
        let synopsis = element(.synopsis, "They meet.")
        let note = element(.note, "A note.")
        let action = element(.action, "She waits.")
        let split = ScriptNotes.split([section, synopsis, note, action])

        XCTAssertEqual(split.page, [section, synopsis, action])
        XCTAssertEqual(split.notes.count, 1)
    }

    func testSplitAndMergeIsTheIdentityOnAWholeScript() {
        let elements = [
            element(.note, "Open colder."),
            element(.scene, "INT. LAB - DAY"),
            element(.action, "She waits."),
            element(.note, "Is she waiting for him or for it?"),
            element(.character, "MARA"),
            element(.dialogue, "You're late."),
            element(.note, "Trailing.")
        ]
        let split = ScriptNotes.split(elements)
        XCTAssertEqual(ScriptNotes.merge(page: split.page, notes: split.notes), elements)
    }

    /// The case the whole design turns on: the writer edits the page, and
    /// the notes have to find their way home to elements that moved.
    func testNotesSurviveAnEditThatReordersThePage() {
        let heading = element(.scene, "INT. LAB - DAY")
        let action = element(.action, "She waits.")
        let note = element(.note, "About the action.")
        var split = ScriptNotes.split([heading, note, action])

        // The writer retypes the heading and moves the action above it. The
        // note is about the action, and follows it.
        split.page = [
            ScriptElement(id: action.id, type: .action, text: "She waits, badly."),
            ScriptElement(id: heading.id, type: .scene, text: "INT. LAB - NIGHT")
        ]
        let merged = ScriptNotes.merge(page: split.page, notes: split.notes)

        XCTAssertEqual(merged.map(\.type), [.note, .action, .scene])
        XCTAssertEqual(merged.first?.text, "About the action.")
    }

    /// Deleting the line a note is about must not delete the note. It goes
    /// where the writer can see it and decide.
    func testANoteWhoseLineIsGoneSurvivesAtTheEnd() {
        let heading = element(.scene, "INT. LAB - DAY")
        let note = element(.note, "Keep me.")
        let action = element(.action, "She waits.")
        var split = ScriptNotes.split([heading, note, action])

        split.page = [heading]
        let merged = ScriptNotes.merge(page: split.page, notes: split.notes)

        XCTAssertEqual(merged.map(\.type), [.scene, .note])
        XCTAssertEqual(merged.last?.text, "Keep me.")
    }

    func testAScriptWithNoNotesIsUntouched() {
        let elements = [element(.scene, "INT. LAB - DAY"), element(.action, "She waits.")]
        let split = ScriptNotes.split(elements)
        XCTAssertTrue(split.notes.isEmpty)
        XCTAssertEqual(ScriptNotes.merge(page: split.page, notes: split.notes), elements)
    }
}
