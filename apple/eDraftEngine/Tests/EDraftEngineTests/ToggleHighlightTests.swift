import XCTest
@testable import EDraftEngine

/// The attention mark's verb — mirrors the TypeScript cases in
/// `style-edits.test.ts`, because both engines must answer identically.
final class ToggleHighlightTests: XCTestCase {

    func testApplySplitsAtTheRangeEdges() {
        let runs = Emphasis.toggleHighlight([], from: 3, to: 9, color: .yellow, textLength: 12)
        XCTAssertEqual(runs, [StyleRun(start: 3, end: 9, styles: [], highlight: .yellow)])
    }

    func testOneColorPerPointApplyClearsThenSets() {
        let marked = Emphasis.toggleHighlight([], from: 0, to: 12, color: .yellow, textLength: 12)
        let over = Emphasis.toggleHighlight(marked, from: 4, to: 8, color: .yellow, textLength: 12)
        XCTAssertEqual(over, [StyleRun(start: 0, end: 12, styles: [], highlight: .yellow)])
    }

    func testFullyCoveredComesOffCleanStylesKeepTheirSpan() {
        let base = [
            StyleRun(start: 0, end: 6, styles: .bold),
            StyleRun(start: 6, end: 12, styles: [], highlight: .yellow),
        ]
        XCTAssertEqual(
            Emphasis.toggleHighlight(base, from: 6, to: 12, color: nil, textLength: 12),
            [StyleRun(start: 0, end: 6, styles: .bold)]
        )
    }

    func testAPartialClearSplitsTheMarkAroundTheGap() {
        let marked = [StyleRun(start: 0, end: 10, styles: [], highlight: .yellow)]
        XCTAssertEqual(
            Emphasis.toggleHighlight(marked, from: 3, to: 7, color: nil, textLength: 10),
            [
                StyleRun(start: 0, end: 3, styles: [], highlight: .yellow),
                StyleRun(start: 7, end: 10, styles: [], highlight: .yellow),
            ]
        )
    }

    func testCoverageAnswersTheBarsOneDecision() {
        let marked = [
            StyleRun(start: 0, end: 5, styles: [], highlight: .yellow),
            StyleRun(start: 5, end: 10, styles: [], highlight: .yellow),
        ]
        XCTAssertTrue(Emphasis.highlightCovered(marked, from: 2, to: 8))
        XCTAssertFalse(Emphasis.highlightCovered(marked, from: 2, to: 11))
        XCTAssertFalse(Emphasis.highlightCovered([], from: 0, to: 1))
    }
}
