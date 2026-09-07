import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// A note is beside the page, not on it.
///
/// The point of every case here is that a writer's private aside must not be
/// set in Courier among the stage directions, must not take a line of a page
/// a production schedules against, and must still be findable — which is what
/// the mark in the margin and the wash on the line are for.
@MainActor
final class ScriptSurfaceNotesTests: XCTestCase {

    private func script() -> [ScriptElement] {
        [
            ScriptElement(type: .scene, text: "INT. LAB - DAY"),
            ScriptElement(type: .action, text: "She waits."),
            ScriptElement(type: .character, text: "MARA"),
            ScriptElement(type: .dialogue, text: "You're late.")
        ]
    }

    func testANoteIsNotOnThePage() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("Is this the same lab as scene 4?")
        surface.renderIfNeeded(editor)

        XCTAssertFalse(
            surface.textView.string.contains("Is this the same lab as scene 4?"),
            "the note was set into the script"
        )
        XCTAssertFalse(surface.textView.string.contains("[["), "the note's Fountain marks reached the page")
        XCTAssertTrue(surface.textView.string.contains("She waits."))
    }

    /// The mark is what says a note is there at all.
    func testEachNoteGetsAMarkInTheMargin() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("First.")
        editor.activeElementID = elements[3].id
        editor.addNote("Second.")
        surface.renderIfNeeded(editor)

        XCTAssertEqual(surface.canvas.noteMarkerFrames.count, 2)
    }

    func testAScriptWithNoNotesHasNoMarks() {
        let (editor, surface) = ScriptSurfaceHarness.bound(script())
        surface.renderIfNeeded(editor)
        XCTAssertTrue(surface.canvas.noteMarkerFrames.isEmpty)
    }

    /// The right margin: nothing printed reaches it, so the mark never lands
    /// on a word.
    func testTheMarkSitsBeyondTheLastColumnOfType() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("A note.")
        surface.renderIfNeeded(editor)

        let mark = try? XCTUnwrap(surface.canvas.noteMarkerFrames.first)
        let format = PageFormat.current
        let pageLeft = ((surface.canvas.frame.width - format.pageRect.width) / 2).rounded(.down)
        let textRight = pageLeft
            + ScreenplayPageLayout.textLeft
            + ScreenplayPageLayout.textBlockWidth(format)

        XCTAssertNotNil(mark)
        XCTAssertGreaterThanOrEqual(mark?.minX ?? 0, textRight, "the mark overlaps the text block")
        XCTAssertLessThanOrEqual(
            mark?.maxX ?? .greatestFiniteMagnitude,
            pageLeft + format.pageRect.width,
            "the mark fell off the page"
        )
    }

    /// The mark belongs beside the line it is about, not at the top of the
    /// document — this is the whole affordance.
    func testTheMarkIsLevelWithTheLineItIsAbout() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[3].id
        editor.addNote("About the dialogue.")
        surface.renderIfNeeded(editor)

        let mark = try? XCTUnwrap(surface.canvas.noteMarkerFrames.first)
        let line = ScriptLayout.boundingRect(
            of: ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
                .first { $0.id == elements[3].id }.map {
                    NSRange(location: $0.range.location, length: 1)
                } ?? NSRange(location: 0, length: 1),
            in: surface.textView
        )
        let inCanvas = line.map { surface.canvas.convert($0, from: surface.textView) }

        XCTAssertNotNil(mark)
        XCTAssertNotNil(inCanvas)
        XCTAssertEqual(
            mark?.midY ?? 0, inCanvas?.midY ?? -1, accuracy: 2,
            "the mark is not level with its line"
        )
    }

    /// The wash is how a reader tells which line a mark belongs to.
    func testTheNotedLineIsWashedAndTheRestIsNot() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("About the action.")
        surface.renderIfNeeded(editor)

        let layoutManager = try? XCTUnwrap(surface.textView.layoutManager)
        let ranges = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
        let action = try? XCTUnwrap(ranges.first { $0.id == elements[1].id })
        let heading = try? XCTUnwrap(ranges.first { $0.id == elements[0].id })

        let onAction = layoutManager?.temporaryAttribute(
            .backgroundColor, atCharacterIndex: action?.range.location ?? 0, effectiveRange: nil
        )
        let onHeading = layoutManager?.temporaryAttribute(
            .backgroundColor, atCharacterIndex: heading?.range.location ?? 0, effectiveRange: nil
        )

        XCTAssertNotNil(onAction, "the noted line was not marked")
        XCTAssertNil(onHeading, "a line with no note on it was marked")
    }

    /// A colour written into the text storage would follow the writer's words
    /// into a copy, a paste and the PDF. It has to be the layout manager's.
    func testTheWashIsNotInTheDocumentsOwnAttributes() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("About the action.")
        surface.renderIfNeeded(editor)

        let action = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == elements[1].id }
        let stored = surface.textView.textStorage?.attribute(
            .backgroundColor, at: action?.range.location ?? 0, effectiveRange: nil
        )
        XCTAssertNil(stored, "the wash was written into the script itself")
    }

    /// Deleting the note takes the mark and the wash with it.
    func testRemovingTheNoteRemovesTheMarkAndTheWash() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        let note = editor.addNote("Going away.")
        surface.renderIfNeeded(editor)
        XCTAssertEqual(surface.canvas.noteMarkerFrames.count, 1)

        editor.deleteNote(id: try! XCTUnwrap(note).id)
        surface.renderIfNeeded(editor)

        XCTAssertTrue(surface.canvas.noteMarkerFrames.isEmpty)
        let action = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == elements[1].id }
        XCTAssertNil(
            surface.textView.layoutManager?.temporaryAttribute(
                .backgroundColor, atCharacterIndex: action?.range.location ?? 0, effectiveRange: nil
            ),
            "the wash outlived the note"
        )
    }
}
