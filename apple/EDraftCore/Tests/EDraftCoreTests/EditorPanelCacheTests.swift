import XCTest
@testable import EDraftCore

/// The cast and scene lists the panel reads. Both walk the whole document,
/// and a SwiftUI body asks on every invalidation — so they are cached by
/// revision (and by the debounced stats, whose scene page numbers ride
/// along). These pin the cache's honesty: fresh after real edits, the same
/// answer object between reads, and the name rule by hand rather than by
/// regex.
@MainActor
final class EditorPanelCacheTests: XCTestCase {

    private func editor() -> EditorState {
        EditorState(source: "INT. LAB - DAY\n\nDust hangs.\n\nMARA\nWe go.\n\nMARA (V.O.)\nStill going.")
    }

    func testCastGroupsExtensionsAndReadsTheSameBetweenReads() {
        let editor = editor()

        let first = editor.cast
        XCTAssertEqual(first.map(\.name), ["MARA"])
        XCTAssertEqual(first.first?.cues, 2, "(V.O.) is how a line is heard, not who says it")

        let second = editor.cast
        XCTAssertEqual(second, first)
        XCTAssertTrue(
            first.first?.firstCueID == second.first?.firstCueID,
            "a re-read rebuilds nothing"
        )
    }

    func testAnEditInvalidatesTheCast() {
        let editor = editor()
        XCTAssertEqual(editor.cast.map(\.name), ["MARA"])

        let cue = editor.screenplay.elements.last(where: { $0.type == .character })!
        editor.replaceElementText(id: cue.id, text: "DAVID", structural: true)

        XCTAssertEqual(editor.cast.map(\.name), ["DAVID", "MARA"])
    }

    func testAnEditInvalidatesTheScenes() {
        let editor = editor()
        XCTAssertEqual(editor.scenes.map(\.title), ["INT. LAB - DAY"])

        let scene = editor.screenplay.elements.first(where: { $0.type == .scene })!
        editor.replaceElementText(id: scene.id, text: "INT. KITCHEN - NIGHT", structural: true)

        XCTAssertEqual(editor.scenes.map(\.title), ["INT. KITCHEN - NIGHT"])
    }

    func testTheNameRuleMatchesTheOldRegex() {
        let cases: [(String, String)] = [
            ("MARA", "MARA"),
            ("MARA (V.O.)", "MARA"),
            ("MARA (WHISPERING) (O.S.)", "MARA"),
            ("  MARA (CONT'D)  ", "MARA"),
            ("TYLER)", "TYLER)"),           // unbalanced: the regex stripped nothing
            ("NAME (A) B)", "NAME (A) B)"), // stray close inside the tail: no strip
            ("mara", "MARA"),               // case folds up
            ("", ""),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(EditorState.canonicalCharacterName(input), expected, input)
        }
    }
}
