import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// What a double-click leaves behind.
///
/// A double-click does not only select a word — it sets the text view's
/// `selectionGranularity` to `.selectByWord`, and AppKit keeps that until
/// something sets it back. While it holds, a range the app sets programmatically
/// can be widened to word boundaries, so the caret the surface asks for comes
/// back as a selection. A selection is not a caret: the ghost requires
/// `selectedRange().length == 0`, and `refreshPredictions` requires the offset
/// to be at the element's end. Both refuse, and the writer sees the engine go
/// quiet for the rest of the line.
///
/// Reported on both surfaces. Driven from the keyboard everything works, which
/// is why this took a real double-click to find.
@MainActor
final class WordGranularityTests: XCTestCase {

    func testACaretSetAfterADoubleClickIsStillACaret() {
        let heading = ScriptElement(type: .scene, text: "INT. LAB - DAY")
        let (editor, surface) = ScriptSurfaceHarness.bound([heading])
        ScriptSurfaceHarness.placeCaret(editor, surface, on: heading)

        // What the double-click did: select DAY, by word.
        surface.textView.selectionGranularity = .selectByWord
        surface.textView.setSelectedRange(NSRange(location: 11, length: 3))
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )

        // Delete it, then type the first letter of the new time.
        ScriptSurfaceHarness.type("", into: surface, at: NSRange(location: 11, length: 3))
        ScriptSurfaceHarness.type("d", into: surface)

        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. LAB - D")
        XCTAssertEqual(
            surface.textView.selectedRange().length, 0,
            "the caret came back as a selection; word granularity outlived the "
                + "double-click and widened it"
        )
        XCTAssertEqual(
            editor.selectionOffset, 12,
            "a widened selection also moves the model's caret off the end, which "
                + "is what silences the engine"
        )
        XCTAssertTrue(
            ScriptSurfaceHarness.wait { editor.currentSuggestionSuffix?.isEmpty == false },
            "the engine went quiet after a double-click edit"
        )
    }
}
