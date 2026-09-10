import EDraftEngine
import XCTest
import EDraftCore
@testable import EDraftMacSurface

/// §3.3, D6: a typed `*`, `_` or `~` that completes a marker pair collapses
/// the markers into a style run — an input transformation, so the markers
/// cease to exist the moment the pair completes. These drive the real
/// delegate path: `shouldChangeTextIn`, the storage, the model.
@MainActor
final class LiveCollapseTests: XCTestCase {

    private func surface() -> (EditorState, ScriptSurface) {
        ScriptSurfaceHarness.bound([ScriptElement(type: .action, text: "")])
    }

    private func type(_ text: String, into surface: ScriptSurface) {
        ScriptSurfaceHarness.type(text, into: surface)
    }

    func testTypingACompletePairCollapsesToBold() {
        let (editor, surface) = surface()
        for character in ["*", "*", "w", "o", "r", "l", "d", "*"] {
            type(character, into: surface)
        }
        XCTAssertEqual(
            editor.screenplay.elements[0].text, "**world*",
            "the first closer key changes nothing — a `**` pair waits whole"
        )
        XCTAssertNil(editor.screenplay.elements[0].runs)

        type("*", into: surface)
        XCTAssertEqual(editor.screenplay.elements[0].text, "world")
        XCTAssertEqual(
            editor.screenplay.elements[0].runs,
            [StyleRun(start: 0, end: 5, styles: .bold)]
        )
        XCTAssertFalse(surface.textView.string.contains("*"),
            "the markers cease to exist — never displayed, never stored")
    }

    func testTypingContinuesInsideTheNewRun() {
        let (editor, surface) = surface()
        for character in ["*", "*", "b", "o", "l", "d", "*", "*", "!"] {
            type(character, into: surface)
        }
        XCTAssertEqual(editor.screenplay.elements[0].text, "bold!")
        XCTAssertEqual(
            editor.screenplay.elements[0].runs,
            [StyleRun(start: 0, end: 5, styles: .bold)],
            "the caret lands at the run's end and the donor rule keeps typing bold"
        )
    }

    func testSingleStarsCollapseToItalic() {
        let (editor, surface) = surface()
        for character in ["*", "a", "*"] {
            type(character, into: surface)
        }
        XCTAssertEqual(editor.screenplay.elements[0].text, "a")
        XCTAssertEqual(
            editor.screenplay.elements[0].runs,
            [StyleRun(start: 0, end: 1, styles: .italic)]
        )
    }

    func testABackslashEscapesTheMarker() {
        let (editor, surface) = surface()
        type("\\", into: surface)
        type("*", into: surface)
        XCTAssertEqual(
            editor.screenplay.elements[0].text, "*",
            "the backslash is consumed and the star arrives literal"
        )
        XCTAssertNil(editor.screenplay.elements[0].runs)
    }

    func testAnUnpairedMarkerStaysLiteral() {
        let (editor, surface) = surface()
        type("a", into: surface)
        type("*", into: surface)
        XCTAssertEqual(editor.screenplay.elements[0].text, "a*")
        XCTAssertNil(editor.screenplay.elements[0].runs)
    }

    func testPreExistingRunsSurviveACollapse() {
        // "it" italic already; typing a bold pair after it must leave the
        // italic run exactly where it was.
        let (editor, surface) = ScriptSurfaceHarness.bound([ScriptElement(
            type: .action, text: "it ",
            runs: [StyleRun(start: 0, end: 2, styles: .italic)]
        )])
        for character in ["*", "*", "n", "o", "*", "*"] {
            type(character, into: surface)
        }
        XCTAssertEqual(editor.screenplay.elements[0].text, "it no")
        XCTAssertEqual(editor.screenplay.elements[0].runs, [
            StyleRun(start: 0, end: 2, styles: .italic),
            StyleRun(start: 3, end: 5, styles: .bold)
        ])
    }
}
