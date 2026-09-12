import XCTest
@testable import EDraftCore
@testable import EDraftEngine

/// A paste carries the writer's formatting as data: Fountain's centred
/// line becomes the element's type, and `**`/`_` markers become style
/// runs — the same parse the file boundary applies, so a paste and an
/// import agree. Literal characters that are not markers stay literal.
@MainActor
final class PasteFormattingTests: XCTestCase {

    private func paste(_ source: String) -> ScreenplayEditPlanner.Plan? {
        ScreenplayEditPlanner.plan(
            elements: [ScriptElement(type: .action, text: "")],
            replacing: NSRange(location: 0, length: 0),
            with: source,
            intent: .multilinePaste,
            kindForNewElement: { previous, text, depth in
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth
                )
            }
        )
    }

    func testPastedEmphasisMarkersBecomeRuns() {
        let plan = paste("The **bold** and _underlined_ words stand.")

        let element = plan?.elements.first
        XCTAssertEqual(element?.text, "The bold and underlined words stand.",
                       "no marker characters enter the text")
        XCTAssertEqual(
            element?.runs,
            [StyleRun(start: 4, end: 8, styles: .bold),
             StyleRun(start: 13, end: 23, styles: .underline)]
        )
    }

    func testACentredLinePasteBecomesTheType() {
        let plan = paste("INT. LAB - DAY\n\nDust hangs.\n\n> THE END <")

        let last = plan?.elements.last
        XCTAssertEqual(last?.type, .centered)
        XCTAssertEqual(last?.text, "THE END",
                       "the markers are the boundary's, not the text's")
    }

    func testAMarkedCueStaysACueAndKeepsItsStyle() {
        let plan = paste("**MARA**\nWe go.")

        XCTAssertEqual(plan?.elements.first?.type, .character,
                       "the tell reads the words, not the markers")
        XCTAssertEqual(plan?.elements.first?.text, "MARA")
        XCTAssertEqual(plan?.elements.first?.runs, [StyleRun(start: 0, end: 4, styles: .bold)])
        XCTAssertEqual(plan?.elements.last?.type, .dialogue)
    }

    func testALiteralAsteriskIsNobodyFormatting() {
        let plan = paste("The answer is 2 * 3 = 6, and the * stays.")

        let element = plan?.elements.first
        XCTAssertEqual(element?.text, "The answer is 2 * 3 = 6, and the * stays.")
        XCTAssertNil(element?.runs)
    }

    func testMarkersSurviveAHardWrappedJoin() {
        // An unindented, blankless, hard-wrapped paste whose bold spans the
        // wrap: one element, one run, markers gone.
        let lines = (1...4).map { _ in "The road holds its breath for a line and" }
            + ["then **turns, and the turn", "holds** for a moment more here."]
        let source = lines.joined(separator: "\n") + "\nMARK\nIt is."
        let plan = paste(source)

        let action = plan?.elements.first(where: { $0.type == .action })
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.runs?.first?.styles, .bold)
        XCTAssertNil(action?.text.range(of: "**"), "no marker survives the join")
        XCTAssertEqual(plan?.elements.dropLast().last?.type, .character)
        XCTAssertEqual(plan?.elements.dropLast().last?.text, "MARK")
        XCTAssertEqual(plan?.elements.last?.type, .dialogue)
        XCTAssertEqual(plan?.elements.last?.text, "It is.")
    }

    /// The donor rule gives inserted text the *whole* property set (§4) —
    /// mark included. Inserting at the end of a highlighted word must not
    /// drop the highlight on what follows it.
    func testInsertionIntoAMarkedSpanKeepsTheMark() {
        let element = ScriptElement(
            type: .action, text: "The word",
            runs: [StyleRun(start: 4, end: 8, styles: [], highlight: .yellow)]
        )
        let plan = ScreenplayEditPlanner.plan(
            elements: [element],
            replacing: NSRange(location: 8, length: 0),
            with: " and more",
            intent: .replacement,
            kindForNewElement: { previous, text, depth in
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth
                )
            }
        )

        let runs = plan?.elements.first?.runs ?? []
        XCTAssertEqual(
            runs.filter { $0.highlight != nil }.map { "\($0.start)-\($0.end)" },
            ["4-17"],
            "the mark covers the original word and what the donor passed on"
        )
    }
}
