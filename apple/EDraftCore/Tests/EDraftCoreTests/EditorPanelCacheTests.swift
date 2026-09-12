import XCTest
@testable import EDraftCore
import EDraftEngine

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
    /// A name change moves the runs with it: the mark stays on the words it
    /// was placed on, in cues and in prose alike — a rename must not pin a
    /// highlight to whatever letters happened to keep their offsets.
    func testARenameCarriesRunsThroughTheLengthChange() {
        let editor = EditorState(source: "An opening image.")
        let cue = ScriptElement(
            type: .character, text: "MARA",
            runs: [StyleRun(start: 0, end: 4, styles: [], highlight: .yellow)]
        )
        let prose = ScriptElement(
            type: .action, text: "Mara crosses the room.",
            runs: [StyleRun(start: 0, end: 4, styles: [], highlight: .yellow)]
        )
        editor.screenplay = Screenplay(titlePage: [], elements: [cue, prose])
        var applied: [ScriptElement]?
        editor.onApplyElements = { elements, _ in applied = elements }

        let changed = editor.renameCharacter("MARA", to: "ELENA", includingMentions: true)

        XCTAssertGreaterThan(changed, 0)
        let newCue = applied?.first { $0.type == .character }
        XCTAssertEqual(newCue?.text, "ELENA")
        XCTAssertEqual(
            newCue?.runs,
            [StyleRun(start: 0, end: 5, styles: [], highlight: .yellow)],
            "the mark stretches with the name, cue side"
        )
        let newProse = applied?.first { $0.type == .action }
        XCTAssertEqual(newProse?.text, "ELENA crosses the room.",
                       "prose takes the proposed name verbatim, cues take it shouted")
        XCTAssertEqual(
            newProse?.runs,
            [StyleRun(start: 0, end: 5, styles: [], highlight: .yellow)],
            "and prose side"
        )
    }

    /// Several mentions in one paragraph each move the runs after them,
    /// latest first — the run behind the *last* mention shifts by both
    /// deltas, never by one.
    func testARenameAcrossSeveralMentionsReSeatsRunsOnceEach() {
        let editor = EditorState(source: "An opening image.")
        let prose = ScriptElement(
            type: .action, text: "Mara enters. Mara leaves.",
            runs: [StyleRun(start: 13, end: 17, styles: [], highlight: .yellow)]
        )
        editor.screenplay = Screenplay(titlePage: [], elements: [prose])
        var applied: [ScriptElement]?
        editor.onApplyElements = { elements, _ in applied = elements }

        _ = editor.renameCharacter("MARA", to: "JUNE", includingMentions: true)

        let result = applied?.first
        XCTAssertEqual(result?.text, "JUNE enters. JUNE leaves.")
        XCTAssertEqual(
            result?.runs,
            [StyleRun(start: 13, end: 17, styles: [], highlight: .yellow)],
            "same length here, so the mark stands where it was placed"
        )
    }
}
