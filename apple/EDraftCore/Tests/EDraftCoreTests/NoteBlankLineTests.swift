import XCTest
@testable import EDraftCore

/// A blank line inside a note (IL-0111).
///
/// A blank line is Fountain's paragraph break. Written as it was, the reader
/// closed the note there, and the next open put the note's words on the page
/// as script. The writer now spells each interior blank line as two spaces.
@MainActor
final class NoteBlankLineTests: XCTestCase {

    func testANoteInTwoParagraphsSurvivesSaveAndReopenAndPrintsNothing() throws {
        let editor = EditorState(source: "INT. LAB - DAY\n\nShe waits.")
        let line = try XCTUnwrap(editor.screenplay.elements.last)
        var published: String?
        editor.onSourceChange = { published = $0 }

        XCTAssertNotNil(editor.addNote("First thought.\n\nSecond thought.", to: line.id))
        editor.flushPendingWork()

        let saved = try XCTUnwrap(published)
        XCTAssertTrue(saved.contains("[[First thought.\n  \nSecond thought.]]"), "the blank line was not written as two spaces")

        let reopened = EditorState(source: saved)
        XCTAssertEqual(reopened.notes.map(\.text), ["First thought.\n\nSecond thought."])
        XCTAssertEqual(reopened.screenplay.elements.map(\.type), [.scene, .action])
        XCTAssertFalse(
            reopened.screenplay.elements.contains { $0.text.contains("First thought") || $0.text.contains("Second thought") },
            "the note landed on the page"
        )
    }
}
