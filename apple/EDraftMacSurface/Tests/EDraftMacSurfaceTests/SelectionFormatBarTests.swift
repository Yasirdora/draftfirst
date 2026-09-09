import XCTest
import EDraftCore
@testable import EDraftMacSurface

/// Bold, italic, underline and centre go in through the input path, so the
/// planner sees them exactly as it sees typing.
@MainActor
final class SelectionFormatBarTests: XCTestCase {

    private func surface(_ source: String) -> (EditorState, ScriptSurface) {
        let editor = EditorState(source: source)
        let surface = ScriptSurface()
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    private func select(_ text: String, in surface: ScriptSurface) {
        surface.textView.setSelectedRange((surface.textView.string as NSString).range(of: text))
    }

    func testBoldWrapsAndAgainUnwraps() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)

        surface.applyMark(.bold)
        XCTAssertTrue(surface.textView.string.contains("Dust **hangs** in"))
        XCTAssertTrue(
            editor.screenplay.elements.contains { $0.text.contains("**hangs**") },
            "the planner saw the edit"
        )
        XCTAssertEqual(
            surface.textView.selectedRange().length, ("**hangs**" as NSString).length,
            "the mark stays selected, so a second press takes it off"
        )

        surface.applyMark(.bold)
        XCTAssertTrue(surface.textView.string.contains("Dust hangs in"))
        XCTAssertFalse(surface.textView.string.contains("**"))
    }

    func testCentreMarksTheWholeLineAndAgainUnmarksIt() {
        let (_, surface) = surface("INT. LAB - DAY\n\nThe end.")
        select("end", in: surface)

        surface.applyMark(.centered)
        XCTAssertTrue(surface.textView.string.contains("> The end. <"))

        surface.applyMark(.centered)
        XCTAssertTrue(surface.textView.string.contains("The end."))
        XCTAssertFalse(surface.textView.string.contains("> The end. <"))
    }

    func testAWrappingMarkNeedsASelection() {
        let (_, surface) = surface("INT. LAB - DAY")
        surface.textView.setSelectedRange(NSRange(location: 0, length: 0))
        surface.applyMark(.italic)
        XCTAssertFalse(surface.textView.string.contains("*"))
    }
}
