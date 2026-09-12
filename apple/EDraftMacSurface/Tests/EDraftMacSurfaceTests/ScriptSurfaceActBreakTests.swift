import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The element menu's Act Break and the delete half of the renumber rule
/// (RFC-ACT-BREAK §4, §6), driven through the page the way a writer drives
/// it: the menu's verb, the keyboard's deletions, and undo.
@MainActor
final class ScriptSurfaceActBreakTests: XCTestCase {

    private func element(_ type: ScreenplayKind, _ text: String) -> ScriptElement {
        ScriptElement(type: type, text: text)
    }

    private func cards(in editor: EditorState) -> [String] {
        editor.screenplay.elements.filter { $0.type == .actbreak }.map(\.text)
    }

    // MARK: - Insert

    func testInsertingLandsTheCardAfterTheCaretsElementAndTheCaretAfterTheCard() {
        let scene = element(.scene, "INT. ROOM - DAY")
        let action = element(.action, "Quiet.")
        let (editor, _) = ScriptSurfaceHarness.bound([scene, action], active: 0)

        editor.onInsertActBreak?()

        let elements = editor.screenplay.elements
        XCTAssertEqual(elements.map(\.type), [.scene, .actbreak, .action, .action])
        XCTAssertEqual(elements[1].text, "ACT ONE", "the first card starts canonical")
        XCTAssertEqual(editor.activeElementID, elements[2].id, "the caret is past the card")
        XCTAssertEqual(editor.selectionOffset, 0)
        XCTAssertEqual(elements[3].text, "Quiet.", "what was there is pushed down, not eaten")
    }

    func testInsertingBetweenActsRenumbersWhatFollows() {
        let (editor, _) = ScriptSurfaceHarness.bound([
            element(.actbreak, "ACT ONE"),
            element(.action, "First."),
            element(.actbreak, "ACT TWO"),
            element(.action, "Second.")
        ], active: 1)

        editor.onInsertActBreak?()

        XCTAssertEqual(cards(in: editor), ["ACT ONE", "ACT TWO", "ACT THREE"])
    }

    /// The insert and the renumber it causes are one gesture, so they are
    /// one undo step: undoing removes the new card *and* restores the
    /// numbers the insert shifted.
    func testTheInsertAndItsRenumberUndoAsOneStep() {
        let before = [
            element(.actbreak, "ACT ONE"),
            element(.action, "First."),
            element(.actbreak, "ACT TWO"),
            element(.action, "Second.")
        ]
        let (editor, _) = ScriptSurfaceHarness.bound(before, active: 1)

        editor.onInsertActBreak?()
        XCTAssertEqual(cards(in: editor), ["ACT ONE", "ACT TWO", "ACT THREE"])

        XCTAssertTrue(editor.onNativeUndo?() ?? false, "the insert registered an undo step")
        XCTAssertEqual(
            editor.screenplay.elements.map { "\($0.type):\($0.text)" },
            before.map { "\($0.type):\($0.text)" }
        )
    }

    // MARK: - Delete

    func testDeletingAnActBreakRenumbersTheCardsThatFollowed() {
        let (editor, surface) = ScriptSurfaceHarness.bound([
            element(.actbreak, "ACT ONE"),
            element(.action, "First."),
            element(.actbreak, "ACT TWO"),
            element(.action, "Second.")
        ], active: 2)

        // Select the first card's whole line, newline included — what a
        // shift-arrow delete of the paragraph looks like to the text view.
        let storage = surface.textView.string as NSString
        let doomed = storage.range(of: "ACT ONE\n")
        XCTAssertLessThan(doomed.location, storage.length)
        ScriptSurfaceHarness.type("", into: surface, at: doomed)

        XCTAssertEqual(
            editor.screenplay.elements.map(\.type), [.action, .actbreak, .action]
        )
        XCTAssertEqual(cards(in: editor), ["ACT ONE"], "ACT TWO moved up to fill the gap")
    }

    func testAnOrdinaryKeystrokeNeverRenumbers() {
        // Two cards out of order on purpose: if typing fired the rule, the
        // second would "correct" to ACT ONE and this test would catch it.
        let (editor, surface) = ScriptSurfaceHarness.bound([
            element(.actbreak, "ACT TWO"),
            element(.action, "Middle."),
            element(.actbreak, "ACT TWO")
        ], active: 1)

        ScriptSurfaceHarness.type("More.", into: surface)

        XCTAssertEqual(cards(in: editor), ["ACT TWO", "ACT TWO"])
    }

    /// The tracker learns the count from the page's first render, so the
    /// first keystroke after an open must not mistake "has acts" for
    /// "gained acts" and renumber a document nobody edited.
    func testTheFirstKeystrokeAfterOpenDoesNotRenumber() {
        let (editor, surface) = ScriptSurfaceHarness.bound([
            element(.scene, "INT. ROOM - DAY"),
            element(.actbreak, "ACT TWO"),
            element(.action, "Middle."),
            element(.actbreak, "ACT FOUR")
        ], active: 2)

        ScriptSurfaceHarness.type("x", into: surface)

        XCTAssertEqual(cards(in: editor), ["ACT TWO", "ACT FOUR"])
    }
}
