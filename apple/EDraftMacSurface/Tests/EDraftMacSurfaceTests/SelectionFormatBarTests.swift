import EDraftEngine
import XCTest
import EDraftCore
@testable import EDraftMacSurface

/// Bold, italic, underline and strikethrough are style runs in the model
/// now (RFC v2.1): the bar adjusts the runs directly, no marker character
/// ever enters the text, and one undo step lifts the whole change. Centre
/// still rewrites the line through the input path.
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

    func testBoldPaintsARunAndAgainLiftsIt() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)

        surface.applyMark(.bold)
        XCTAssertTrue(surface.textView.string.contains("Dust hangs in"))
        XCTAssertFalse(
            surface.textView.string.contains("**"),
            "no marker characters enter the text"
        )
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 5, end: 10, styles: .bold)],
            "the model carries the style as data"
        )
        XCTAssertEqual(
            surface.textView.selectedRange().length, ("hangs" as NSString).length,
            "the word stays selected, so a second press takes it off"
        )

        surface.applyMark(.bold)
        XCTAssertNil(editor.screenplay.elements.last?.runs)
        XCTAssertTrue(surface.textView.string.contains("Dust hangs in"))
    }

    func testTheToggleIsOneNamedUndoStep() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.bold)
        XCTAssertNotNil(editor.screenplay.elements.last?.runs)

        editor.undo()
        XCTAssertNil(
            editor.screenplay.elements.last?.runs,
            "one undo lifts the whole toggle"
        )
        editor.redo()
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 5, end: 10, styles: .bold)]
        )
    }

    func testAMixedSelectionOnlyAdds() {
        // One paragraph already bold, one plain; selecting across both and
        // pressing Bold must not strip the bold one — the global decision is
        // "not all covered, so add".
        let (editor, surface) = surface("plain\n\nworn")
        select("worn", in: surface)
        surface.applyMark(.bold)
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 0, end: 4, styles: .bold)]
        )

        let whole = surface.textView.string as NSString
        surface.textView.setSelectedRange(NSRange(location: 0, length: whole.length))
        surface.applyMark(.bold)
        XCTAssertEqual(
            editor.screenplay.elements.first?.runs,
            [StyleRun(start: 0, end: 5, styles: .bold)],
            "the plain paragraph gains the style"
        )
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 0, end: 4, styles: .bold)],
            "the styled paragraph keeps it — a mixed selection adds, never strips"
        )

        surface.applyMark(.bold)
        XCTAssertNil(editor.screenplay.elements.first?.runs)
        XCTAssertNil(editor.screenplay.elements.last?.runs)
    }

    func testTheBarReadsWhatTheSelectionWears() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.bold)

        select("hangs", in: surface)
        XCTAssertEqual(
            surface.styleCoverage(at: surface.textView.selectedRange()),
            [.bold],
            "a covered selection lights its mark"
        )
        select("Dust", in: surface)
        XCTAssertEqual(
            surface.styleCoverage(at: surface.textView.selectedRange()),
            [],
            "a bare selection lights nothing"
        )
        _ = editor
    }

    func testACaretReadsTheNextKeystrokesStyle() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.bold)

        // Caret inside the bold word: the donor rule says the next keystroke
        // is bold, and the bar agrees.
        let word = (surface.textView.string as NSString).range(of: "hangs")
        surface.textView.setSelectedRange(NSRange(location: word.location + 2, length: 0))
        XCTAssertEqual(surface.styleCoverage(at: surface.textView.selectedRange()), [.bold])

        // Caret in the plain word beside it: nothing lights.
        let plain = (surface.textView.string as NSString).range(of: "Dust")
        surface.textView.setSelectedRange(NSRange(location: plain.location + 2, length: 0))
        XCTAssertEqual(surface.styleCoverage(at: surface.textView.selectedRange()), [])
        _ = editor
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

    func testAStyleMarkNeedsASelection() {
        let (editor, surface) = surface("INT. LAB - DAY")
        surface.textView.setSelectedRange(NSRange(location: 0, length: 0))
        surface.applyMark(.italic)
        XCTAssertNil(editor.screenplay.elements.last?.runs)
        XCTAssertFalse(surface.textView.string.contains("*"))
    }
}
