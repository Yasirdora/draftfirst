import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Typing into a line the page shouts — a scene heading, a cue, a transition,
/// a shot.
///
/// Every hand pass this project has run typed at the *end* of such a line, and
/// so never found that typing anywhere else in one puts the letters in the
/// wrong order. `int` at the head of `LOCATION` produced `ILOCATIONNT`.
@MainActor
final class ShoutedTypingTests: XCTestCase {

    // MARK: - What the writer sees

    func testTypingAtTheHeadOfASceneHeadingKeepsTheLettersInOrder() {
        let heading = ScriptElement(type: .scene, text: "LOCATION")
        let (editor, surface) = ScriptSurfaceHarness.bound([heading])
        surface.textView.setSelectedRange(NSRange(location: 0, length: 0))
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )

        for letter in "int" {
            ScriptSurfaceHarness.type(String(letter), into: surface)
        }

        XCTAssertEqual(
            editor.screenplay.elements[0].text,
            "INTLOCATION",
            "the letters were reordered; the caret is not staying where it was typed"
        )
        XCTAssertEqual(surface.textView.string, "INTLOCATION")
    }

    func testTheCaretStaysWhereItWasTypedInAShoutedLine() {
        let cue = ScriptElement(type: .character, text: "MARA")
        let (_, surface) = ScriptSurfaceHarness.bound([cue])
        surface.textView.setSelectedRange(NSRange(location: 0, length: 0))
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )

        ScriptSurfaceHarness.type("u", into: surface)

        XCTAssertEqual(
            surface.textView.selectedRange().location, 1,
            "one letter typed at the head should leave the caret after it, not at the end"
        )
    }

    /// A kind that does not shout has never had this problem, and must not
    /// acquire one from the fix.
    func testTypingIntoTheMiddleOfActionIsUnaffected() {
        let action = ScriptElement(type: .action, text: "she waits")
        let (editor, surface) = ScriptSurfaceHarness.bound([action])
        surface.textView.setSelectedRange(NSRange(location: 4, length: 0))
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )

        ScriptSurfaceHarness.type("X", into: surface)

        XCTAssertEqual(editor.screenplay.elements[0].text, "she Xwaits")
        XCTAssertEqual(surface.textView.selectedRange().location, 5)
    }

    // MARK: - The AppKit facts the fix rests on

    /// The root cause, measured rather than reasoned about: replacing a range
    /// of an `NSTextView`'s storage moves the insertion point to the end of
    /// what was replaced. Repairing the text after the fact therefore cannot
    /// leave the caret alone.
    func testReplacingAStorageRangeMovesTheInsertionPoint() {
        let (_, surface) = ScriptSurfaceHarness.bound(
            [ScriptElement(type: .action, text: "abcdefgh")]
        )
        surface.textView.setSelectedRange(NSRange(location: 2, length: 0))

        surface.textView.textStorage?.replaceCharacters(
            in: NSRange(location: 0, length: 8), with: "ABCDEFGH"
        )

        XCTAssertNotEqual(
            surface.textView.selectedRange().location, 2,
            "if AppKit left the caret alone, the shouting bug would not exist and "
                + "this measurement is stale"
        )
    }
}

/// The page must not move under a writer who is editing a script that already
/// fits on the screen.
///
/// A structural edit — Return, Tab, a scene-heading dash — rebuilds the storage
/// and then settles the viewport against where the caret is. It was settling
/// *before* the caret was restored, so it followed a position nobody was ever
/// going to see, and the line being edited scrolled off the top.
@MainActor
final class PageStillnessTests: XCTestCase {

    private func shortScript() -> (EditorState, ScriptSurface) {
        ScriptSurfaceHarness.bound([
            ScriptElement(type: .scene, text: "INT. KITCHEN"),
            ScriptElement(type: .action, text: "She waits."),
            ScriptElement(type: .character, text: "MARA"),
            ScriptElement(type: .dialogue, text: "We are late.")
        ])
    }

    func testADashInAHeadingDoesNotMoveThePage() {
        let (editor, surface) = shortScript()
        let heading = editor.screenplay.elements[0]
        ScriptSurfaceHarness.placeCaret(editor, surface, on: heading)
        let before = surface.scrollView.contentView.bounds.origin.y

        ScriptSurfaceHarness.type("-", into: surface)

        XCTAssertEqual(
            surface.scrollView.contentView.bounds.origin.y, before, accuracy: 0.5,
            "the page scrolled while the writer was typing into a line that was "
                + "already on screen"
        )
    }

    func testReturnDoesNotMoveThePage() {
        let (editor, surface) = shortScript()
        ScriptSurfaceHarness.placeCaret(editor, surface, on: editor.screenplay.elements[1])
        let before = surface.scrollView.contentView.bounds.origin.y

        ScriptSurfaceHarness.type("\n", into: surface)

        XCTAssertEqual(
            surface.scrollView.contentView.bounds.origin.y, before, accuracy: 0.5,
            "Return moved the page on a script that fits"
        )
    }
}
